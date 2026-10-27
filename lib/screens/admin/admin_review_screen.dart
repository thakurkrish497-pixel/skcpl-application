import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/stock_transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/cash_provider.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/photo_thumbnail_strip.dart';
import '../../widgets/cache_manager_dialog.dart';
import '../../widgets/entry_detail_dialog.dart';
import '../../widgets/responsive_layout.dart';
import '../stock/add_product_screen.dart';
import '../stock/use_product_screen.dart';
import '../cashbook/expense_form_screen.dart';

/// Admin approval screen — Final approval for pending_admin transactions
class AdminReviewScreen extends ConsumerWidget {
  const AdminReviewScreen({super.key});

  Future<String?> _showRejectionDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Transaction', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Rejection Reason (Required)',
            hintText: 'Enter reason why this transaction is rejected...',
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rejected),
            child: const Text('Confirm Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingStockAsync = ref.watch(pendingStockAdminProvider);
    final pendingCashAsync = ref.watch(pendingCashAdminProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldDark,
        appBar: AppBar(
          title: const Text('Final Approval'),
          actions: const [
            CacheActionButton(),
          ],
          bottom: const TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textTertiary,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(text: 'Stock'),
              Tab(text: 'Cash Book'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Stock tab
            pendingStockAsync.when(
              loading: () => const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (transactions) {
                final sortedStock = [...transactions]
                  ..sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));
                return sortedStock.isEmpty
                  ? _emptyState('All Stock Approved')
                  : ResponsiveContainer(
                      maxWidth: 1000,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: sortedStock.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final tx = sortedStock[index];
                        return _AdminReviewTile(
                          title:
                              '${tx.type.displayName}: ${tx.displayProductName} (${tx.quantity} ${tx.displayMetricUnitName})',
                          subtitle:
                              '${DateFormat('dd MMM yyyy').format(tx.date)}${tx.displayVendorName != 'None' ? ' • Party: ${tx.displayVendorName}' : ''}${tx.billNo != null ? ' • Bill: #${tx.billNo}' : ''}${tx.cleanRemarks != null ? ' • ${tx.cleanRemarks}' : ''}',
                          amount: tx.finalAmount,
                          photoUrls: tx.photoUrls,
                          submitter: tx.submitterName,
                          supervisorNote: tx.supervisorReviewNote,
                          onView: () => EntryDetailDialog.show(
                            context,
                            stockTransaction: tx,
                            onEdit: () async {
                              bool? didUpdate = false;
                              if (tx.type == TransactionType.inbound) {
                                didUpdate = await Navigator.push<bool>(context, MaterialPageRoute(
                                  builder: (_) => AddProductScreen(existingTransaction: tx),
                                ));
                              } else {
                                didUpdate = await Navigator.push<bool>(context, MaterialPageRoute(
                                  builder: (_) => UseProductScreen(existingTransaction: tx),
                                ));
                              }
                              if (didUpdate == true) {
                                ref.invalidate(pendingStockAdminProvider);
                                ref.invalidate(stockOverviewProvider(tx.siteId));
                                ref.invalidate(allSitesStockProvider);
                              }
                            },
                          ),
                          onApprove: () async {
                            final userId =
                                ref.read(authProvider).user?.id ?? '';
                            final success = await ref
                                .read(stockProvider.notifier)
                                .approveByAdmin(tx, userId);
                            ref.invalidate(pendingStockAdminProvider);
                            ref.invalidate(stockOverviewProvider(tx.siteId));
                            ref.invalidate(allSitesStockProvider);
                            if (!context.mounted) return;
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Approved! Record permanently locked.'),
                                  backgroundColor: AppColors.approved,
                                ),
                              );
                            } else {
                              final err = ref.read(stockProvider).error;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Approval failed: ${err ?? "Please try again."}'),
                                  backgroundColor: AppColors.rejected,
                                ),
                              );
                            }
                          },
                          onReject: () async {
                            final note = await _showRejectionDialog(context);
                            if (note == null || note.isEmpty) return;
                            final userId =
                                ref.read(authProvider).user?.id ?? '';
                            final success = await ref
                                .read(stockProvider.notifier)
                                .rejectTransaction(
                                    tx.id!, userId, note);
                            ref.invalidate(pendingStockAdminProvider);
                            ref.invalidate(stockOverviewProvider(tx.siteId));
                            ref.invalidate(allSitesStockProvider);
                            if (!context.mounted) return;
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Stock entry rejected.'),
                                  backgroundColor: AppColors.rejected,
                                ),
                              );
                            } else {
                              final err = ref.read(stockProvider).error;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Rejection failed: ${err ?? "Please try again."}'),
                                  backgroundColor: AppColors.rejected,
                                ),
                              );
                            }
                          },
                          onEdit: () async {
                            bool? didUpdate = false;
                            if (tx.type == TransactionType.inbound) {
                              didUpdate = await Navigator.push<bool>(context, MaterialPageRoute(
                                builder: (_) => AddProductScreen(existingTransaction: tx),
                              ));
                            } else {
                              didUpdate = await Navigator.push<bool>(context, MaterialPageRoute(
                                builder: (_) => UseProductScreen(existingTransaction: tx),
                              ));
                            }
                            if (didUpdate == true) {
                              ref.invalidate(pendingStockAdminProvider);
                              ref.invalidate(stockOverviewProvider(tx.siteId));
                              ref.invalidate(allSitesStockProvider);
                            }
                          },
                        );
                      },
                    ),
                  );
              },
            ),

            // Cash tab
            pendingCashAsync.when(
              loading: () => const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (transactions) {
                final sortedCash = [...transactions]
                  ..sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));
                return sortedCash.isEmpty
                  ? _emptyState('All Cash Approved')
                  : ResponsiveContainer(
                      maxWidth: 1000,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: sortedCash.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                        final tx = sortedCash[index];
                        final isCashReceived = tx.amountReceived > 0 && tx.expenseAmount == 0;
                        return _AdminReviewTile(
                          title: isCashReceived
                              ? 'CASH RECEIVED (Top-up): ₹${NumberFormat('#,##,###').format(tx.amountReceived)}'
                              : '${tx.displayExpenseTypeName}: ₹${NumberFormat('#,##,###').format(tx.expenseAmount)}',
                          subtitle: isCashReceived
                              ? 'From: ${tx.customExpenseType ?? (tx.partyName ?? "Office")} • ${DateFormat('dd MMM yyyy').format(tx.date)}${tx.billNo != null ? ' • Ref: #${tx.billNo}' : ''}${tx.cleanRemarks != null ? ' • ${tx.cleanRemarks}' : ''}'
                              : '${DateFormat('dd MMM yyyy').format(tx.date)}${tx.partyName != null ? ' • Party: ${tx.partyName}' : ''}${tx.billNo != null ? ' • Bill: #${tx.billNo}' : ''}${tx.cleanRemarks != null ? ' • ${tx.cleanRemarks}' : ''}',
                          amount: isCashReceived ? tx.amountReceived : tx.expenseAmount,
                          photoUrls: tx.photoUrls,
                          submitter: tx.submitterName,
                          supervisorNote: tx.supervisorReviewNote,
                          onView: () => EntryDetailDialog.show(
                            context,
                            cashTransaction: tx,
                            onEdit: () async {
                              final didUpdate = await Navigator.push<bool>(context, MaterialPageRoute(
                                builder: (_) => ExpenseFormScreen(existingTransaction: tx),
                              ));
                              if (didUpdate == true) {
                                ref.invalidate(pendingCashAdminProvider);
                                ref.invalidate(siteCashSummaryProvider(tx.siteId));
                              }
                            },
                          ),
                          onApprove: () async {
                            final userId =
                                ref.read(authProvider).user?.id ?? '';
                            final success = await ref
                                .read(cashProvider.notifier)
                                .approveByAdmin(tx.id!, userId);
                            ref.invalidate(pendingCashAdminProvider);
                            ref.invalidate(siteCashSummaryProvider(tx.siteId));
                            if (!context.mounted) return;
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Approved! Record permanently locked.'),
                                  backgroundColor: AppColors.approved,
                                ),
                              );
                            } else {
                              final err = ref.read(cashProvider).error;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Approval failed: ${err ?? "Please try again."}'),
                                  backgroundColor: AppColors.rejected,
                                ),
                              );
                            }
                          },
                          onReject: () async {
                            final note = await _showRejectionDialog(context);
                            if (note == null || note.isEmpty) return;
                            final userId =
                                ref.read(authProvider).user?.id ?? '';
                            final success = await ref
                                .read(cashProvider.notifier)
                                .rejectTransaction(
                                    tx.id!, userId, note);
                            ref.invalidate(pendingCashAdminProvider);
                            ref.invalidate(siteCashSummaryProvider(tx.siteId));
                            if (!context.mounted) return;
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cash transaction rejected.'),
                                  backgroundColor: AppColors.rejected,
                                ),
                              );
                            } else {
                              final err = ref.read(cashProvider).error;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Rejection failed: ${err ?? "Please try again."}'),
                                  backgroundColor: AppColors.rejected,
                                ),
                              );
                            }
                          },
                          onEdit: () async {
                            final didUpdate = await Navigator.push<bool>(context, MaterialPageRoute(
                              builder: (_) => ExpenseFormScreen(existingTransaction: tx),
                            ));
                            if (didUpdate == true) {
                              ref.invalidate(pendingCashAdminProvider);
                              ref.invalidate(siteCashSummaryProvider(tx.siteId));
                            }
                          },
                        );
                      },
                    ),
                  );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.verified, color: AppColors.approved, size: 64),
          const SizedBox(height: 16),
          Text(msg,
              style:
                  AppTextStyles.h4.copyWith(color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _AdminReviewTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final double? amount;
  final List<String> photoUrls;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final String? submitter;
  final String? supervisorNote;
  final VoidCallback? onEdit;
  final VoidCallback? onView;

  const _AdminReviewTile({
    required this.title,
    required this.subtitle,
    this.amount,
    this.photoUrls = const [],
    this.submitter,
    this.supervisorNote,
    required this.onApprove,
    required this.onReject,
    this.onEdit,
    this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onView,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: AppTextStyles.labelLarge
                              .copyWith(color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textTertiary)),
                      if (submitter != null || supervisorNote != null) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (submitter != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceDark,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.divider),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.person_outline,
                                        size: 11, color: AppColors.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Entered by: $submitter',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (supervisorNote != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: AppColors.primary.withOpacity(0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.verified_outlined,
                                        size: 11, color: AppColors.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Supervisor: $supervisorNote',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const StatusBadge(
                    status: TransactionStatus.pendingAdmin, compact: true),
              ],
            ),
            if (photoUrls.isNotEmpty)
              PhotoThumbnailStrip(photoUrls: photoUrls),
            const SizedBox(height: 14),
            Row(
              children: [
                if (onView != null) ...[
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: OutlinedButton.icon(
                        onPressed: onView,
                        icon: const Icon(Icons.visibility_outlined, size: 16),
                        label: const Text('View'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.cardBorder),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (onEdit != null) ...[
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_note_rounded, size: 16),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.rejected,
                        side: const BorderSide(color: AppColors.rejected),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: ElevatedButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.approved,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
