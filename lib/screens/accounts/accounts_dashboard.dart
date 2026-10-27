import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/stock_transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/cash_provider.dart';
import '../../providers/site_provider.dart';
import '../../providers/role_access_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/sla_notification_bar.dart';
import '../../widgets/skcpl_announcement_bar.dart';
import '../../widgets/notice_board_dialog.dart';
import '../../widgets/notification_bell_button.dart';
import '../home/home_screen.dart';
import '../admin/site_details_screen.dart';
import '../stock/add_product_screen.dart';
import '../stock/use_product_screen.dart';
import '../cashbook/expense_form_screen.dart';
import 'transaction_review_screen.dart';

/// Accounts Dashboard — Review and approve/reject worker submissions
class AccountsDashboard extends ConsumerWidget {
  const AccountsDashboard({super.key});

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
    final pendingStockAsync = ref.watch(pendingStockAccountsProvider);
    final pendingCashAsync = ref.watch(pendingCashAccountsProvider);
    final allSitesAsync = ref.watch(activeSitesProvider);
    final authState = ref.watch(authProvider);
    final roleAccess = ref.watch(roleAccessProvider);
    final canApproveStock = roleAccess.accountsCanApproveStock;
    final canApproveCash = roleAccess.accountsCanApproveCash;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldDark,
        drawer: AppDrawer(
          user: authState.user,
          onSignOut: () async {
            await ref.read(authProvider.notifier).signOut();
            if (context.mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
            }
          },
        ),
        appBar: AppBar(
          title: const Text('Accounts Dashboard'),
          actions: [
            const NotificationBellButton(),
            IconButton(
              icon: const Icon(Icons.campaign_rounded, color: AppColors.waveCyan),
              tooltip: 'Notice Board & Broadcast Announcements',
              onPressed: () => NoticeBoardDialog.show(context),
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Sign Out',
              onPressed: () async {
                await ref.read(authProvider.notifier).signOut();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  );
                }
              },
            ),
          ],
          bottom: TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textTertiary,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inventory_2, size: 18),
                    const SizedBox(width: 6),
                    const Text('Stock'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_balance_wallet, size: 18),
                    const SizedBox(width: 6),
                    const Text('Cash'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, size: 18),
                    const SizedBox(width: 6),
                    const Text('Sites'),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: ResponsiveContainer(
          maxWidth: 1100,
          child: Column(
            children: [
              // ── Birthday & Corporate Announcement Bar ──
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SkcplAnnouncementBar(margin: EdgeInsets.zero),
              ),
              // ── In-App SLA Overdue Notification Bar (>36h) ──
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SlaNotificationBar(),
              ),
              Expanded(
                child: TabBarView(
                  children: [
            // ── Tab 1: Pending Stock ──
            if (!canApproveStock)
              _buildExtractedPowerBanner(
                title: 'Stock Approval Extracted by Admin',
                message:
                    'Per Admin policy, stock verification is bypassed for Accounts and flows directly from Project Head to Admin.',
              )
            else
              pendingStockAsync.when(
              loading: () => const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (transactions) {
                final sortedStock = [...transactions]
                  ..sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));
                return sortedStock.isEmpty
                  ? _emptyState('No Pending Stock', Icons.check_circle_outline)
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: sortedStock.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final tx = sortedStock[index];
                        return _ReviewableTile(
                          title:
                              '${tx.type.displayName}: ${tx.displayProductName} (${tx.quantity} ${tx.displayMetricUnitName})',
                          subtitle:
                              'Date: ${DateFormat('dd MMM yyyy').format(tx.date)}${tx.displayVendorName != null ? ' • ${tx.displayVendorName}' : ''}${tx.billNo != null ? ' • Bill: #${tx.billNo}' : ''}${tx.cleanRemarks != null ? ' • ${tx.cleanRemarks}' : ''}',
                          amount: tx.finalAmount,
                          submitter: tx.submitterName,
                          supervisorNote: tx.supervisorReviewNote,
                          status: tx.status,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TransactionReviewScreen(
                                  stockTransaction: tx,
                                ),
                              ),
                            );
                            ref.invalidate(pendingStockAccountsProvider);
                            ref.invalidate(pendingCashAccountsProvider);
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
                              ref.invalidate(pendingStockAccountsProvider);
                              ref.invalidate(pendingCashAccountsProvider);
                            }
                          },
                          onApprove: () async {
                            final userId = ref.read(authProvider).user?.id ?? 
                                           ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';
                            final success = await ref.read(stockProvider.notifier).approveByAccounts(tx.id!, userId);
                            ref.invalidate(pendingStockAccountsProvider);
                            ref.invalidate(pendingCashAccountsProvider);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(success ? 'Approved & forwarded to Admin!' : 'Approval failed. Please try again.'),
                                  backgroundColor: success ? AppColors.approved : AppColors.rejected,
                                ),
                              );
                            }
                          },
                          onReject: () async {
                            final note = await _showRejectionDialog(context);
                            if (note != null && note.isNotEmpty) {
                              final userId = ref.read(authProvider).user?.id ?? 
                                             ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';
                              final success = await ref.read(stockProvider.notifier).rejectTransaction(tx.id!, userId, note);
                              ref.invalidate(pendingStockAccountsProvider);
                              ref.invalidate(pendingCashAccountsProvider);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(success ? 'Transaction rejected' : 'Rejection failed. Please try again.'),
                                    backgroundColor: AppColors.rejected,
                                  ),
                                );
                              }
                            }
                          },
                        ).animate().fadeIn(
                              delay: Duration(milliseconds: 50 * index),
                            );
                      },
                    );
              },
            ),

            // ── Tab 2: Pending Cash ──
            if (!canApproveCash)
              _buildExtractedPowerBanner(
                title: 'Cashbook Approval Extracted by Admin',
                message:
                    'Per Admin policy, cash expense verification is bypassed for Accounts and flows directly from Project Head to Admin.',
              )
            else
              pendingCashAsync.when(
              loading: () => const Center(
                  child:
                       CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (transactions) {
                final sortedCash = [...transactions]
                  ..sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));
                return sortedCash.isEmpty
                  ? _emptyState('No Pending Cash', Icons.check_circle_outline)
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: sortedCash.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final tx = sortedCash[index];
                        final isCashReceived = tx.amountReceived > 0 && tx.expenseAmount == 0;
                        return _ReviewableTile(
                          title: isCashReceived
                              ? 'CASH RECEIVED (Top-up): ₹${NumberFormat('#,##,###').format(tx.amountReceived)}'
                              : '${tx.displayExpenseTypeName} — ₹${NumberFormat('#,##,###').format(tx.expenseAmount)}',
                          subtitle: isCashReceived
                              ? 'From: ${tx.customExpenseType ?? (tx.partyName ?? "Office")} • Date: ${DateFormat('dd MMM yyyy').format(tx.date)}${tx.billNo != null ? ' • Ref: #${tx.billNo}' : ''}${tx.cleanRemarks != null ? ' • ${tx.cleanRemarks}' : ''}'
                              : 'Date: ${DateFormat('dd MMM yyyy').format(tx.date)}${tx.partyName != null ? ' • ${tx.partyName}' : ''}${tx.billNo != null ? ' • Bill: #${tx.billNo}' : ''}${tx.cleanRemarks != null ? ' • ${tx.cleanRemarks}' : ''}',
                          amount: isCashReceived ? tx.amountReceived : tx.expenseAmount,
                          submitter: tx.submitterName,
                          supervisorNote: tx.supervisorReviewNote,
                          status: tx.status,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TransactionReviewScreen(
                                  cashTransaction: tx,
                                ),
                              ),
                            );
                            ref.invalidate(pendingCashAccountsProvider);
                            ref.invalidate(pendingStockAccountsProvider);
                            ref.invalidate(siteCashSummaryProvider(tx.siteId));
                          },
                          onEdit: () async {
                            final didUpdate = await Navigator.push<bool>(context, MaterialPageRoute(
                              builder: (_) => ExpenseFormScreen(existingTransaction: tx),
                            ));
                            if (didUpdate == true) {
                              ref.invalidate(pendingCashAccountsProvider);
                              ref.invalidate(pendingStockAccountsProvider);
                              ref.invalidate(siteCashSummaryProvider(tx.siteId));
                            }
                          },
                          onApprove: () async {
                            final userId = ref.read(authProvider).user?.id ?? 
                                           ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';
                            final success = await ref.read(cashProvider.notifier).approveByAccounts(tx.id!, userId);
                            ref.invalidate(pendingCashAccountsProvider);
                            ref.invalidate(pendingStockAccountsProvider);
                            ref.invalidate(siteCashSummaryProvider(tx.siteId));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(success ? 'Approved & forwarded to Admin!' : 'Approval failed. Please try again.'),
                                  backgroundColor: success ? AppColors.approved : AppColors.rejected,
                                ),
                              );
                            }
                          },
                          onReject: () async {
                            final note = await _showRejectionDialog(context);
                            if (note != null && note.isNotEmpty) {
                              final userId = ref.read(authProvider).user?.id ?? 
                                             ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';
                              final success = await ref.read(cashProvider.notifier).rejectTransaction(tx.id!, userId, note);
                              ref.invalidate(pendingCashAccountsProvider);
                              ref.invalidate(pendingStockAccountsProvider);
                              ref.invalidate(siteCashSummaryProvider(tx.siteId));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(success ? 'Transaction rejected' : 'Rejection failed. Please try again.'),
                                    backgroundColor: AppColors.rejected,
                                  ),
                                );
                              }
                            }
                          },
                        ).animate().fadeIn(
                              delay: Duration(milliseconds: 50 * index),
                            );
                      },
                    );
              },
            ),

            // ── Tab 3: Sites Overview ──
            allSitesAsync.when(
              loading: () => const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (sitesList) => sitesList.isEmpty
                  ? _emptyState('No Sites Found', Icons.location_on_outlined)
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select Site for Details',
                            style: AppTextStyles.h4
                                .copyWith(color: AppColors.textPrimary),
                          ).animate().fadeIn(),
                          const SizedBox(height: 16),
                          Expanded(
                            child: ListView.separated(
                              itemCount: sitesList.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final site = sitesList[index];
                                return ListTile(
                                  tileColor: AppColors.cardDark,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      side: const BorderSide(
                                          color: AppColors.divider, width: 0.5)),
                                  title: Text(
                                    site.name,
                                    style: AppTextStyles.labelLarge
                                        .copyWith(color: AppColors.textPrimary),
                                  ),
                                  subtitle: Text(
                                    site.address ?? 'No address provided',
                                    style: AppTextStyles.bodySmall
                                        .copyWith(color: AppColors.textSecondary),
                                  ),
                                  trailing: const Icon(Icons.chevron_right,
                                      color: AppColors.textTertiary),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => SiteDetailsScreen(site: site),
                                      ),
                                    );
                                  },
                                ).animate().fadeIn(
                                      delay: Duration(
                                          milliseconds: 50 * index),
                                    );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    ],
  ),
),
      ),
    );
  }

  Widget _emptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.approved, size: 64),
          const SizedBox(height: 16),
          Text(message,
              style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text('All caught up!',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildExtractedPowerBanner({required String title, required String message}) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.goldAccent.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.goldAccent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_rounded, color: AppColors.goldAccent, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.approved.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.approved.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.alt_route_rounded, color: AppColors.approved, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Active Policy: Project Head ➔ Admin Direct',
                    style: TextStyle(
                      color: AppColors.approved,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewableTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? submitter;
  final String? supervisorNote;
  final double? amount;
  final TransactionStatus status;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _ReviewableTile({
    required this.title,
    required this.subtitle,
    this.submitter,
    this.supervisorNote,
    this.amount,
    required this.status,
    required this.onTap,
    this.onEdit,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: AppTextStyles.labelLarge
                                  .copyWith(color: AppColors.textPrimary)),
                          const SizedBox(height: 4),
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
                    const SizedBox(width: 8),
                    StatusBadge(status: status, compact: true),
                  ],
                ),
                if (onEdit != null || onApprove != null || onReject != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 38,
                          child: OutlinedButton.icon(
                            onPressed: onTap,
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
                      if (onEdit != null) ...[
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: OutlinedButton.icon(
                              onPressed: onEdit,
                              icon: const Icon(Icons.edit_note_rounded, size: 18),
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
                      if (onReject != null) ...[
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: OutlinedButton.icon(
                              onPressed: onReject,
                              icon: const Icon(Icons.cancel_outlined, size: 18),
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
                      ],
                      if (onApprove != null)
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: ElevatedButton.icon(
                              onPressed: onApprove,
                              icon: const Icon(Icons.check_circle_outline, size: 18),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
