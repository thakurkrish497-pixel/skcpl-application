import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/cash_transaction_model.dart';
import '../../models/stock_transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_provider.dart';
import '../../providers/stock_provider.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/offline_indicator.dart';
import '../../widgets/photo_thumbnail_strip.dart';
import '../../widgets/cache_manager_dialog.dart';
import '../../services/excel_service.dart';
import '../../providers/sla_alert_provider.dart';
import 'expense_form_screen.dart';

/// Cash book history for the active site
class CashHistoryScreen extends ConsumerStatefulWidget {
  const CashHistoryScreen({super.key});

  @override
  ConsumerState<CashHistoryScreen> createState() => _CashHistoryScreenState();
}

class _CashHistoryScreenState extends ConsumerState<CashHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final siteId = ref.read(authProvider).activeSite?.id;
      if (siteId != null) {
        ref.read(cashProvider.notifier).loadTransactions(siteId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cashState = ref.watch(cashProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: const Text('Cash Book History'),
        actions: [
          if (ref.watch(authProvider).isAdmin || ref.watch(authProvider).isAccounts)
            IconButton(
              icon: const Icon(Icons.table_view_rounded, color: Color(0xFF107C41)),
              tooltip: 'Export Excel Workbook (.xlsx)',
              onPressed: () async {
                final activeSite = ref.read(authProvider).activeSite;
                if (activeSite == null) return;
                try {
                  // Ensure latest stock transactions are also loaded for this site
                  var stockList = ref.read(stockProvider).transactions;
                  if (stockList.isEmpty) {
                    await ref.read(stockProvider.notifier).loadTransactions(activeSite.id);
                    stockList = ref.read(stockProvider).transactions;
                  }
                  await ExcelService.exportAndShareComprehensiveExcel(
                    siteName: activeSite.name,
                    siteId: activeSite.id,
                    cashTransactions: cashState.transactions,
                    stockTransactions: stockList,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Comprehensive Excel (Cash & Stock) exported!'),
                        backgroundColor: Color(0xFF107C41),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Export failed: $e'),
                        backgroundColor: AppColors.rejected,
                      ),
                    );
                  }
                }
              },
            ),
          const CacheActionButton(),
          const OfflineSyncButton(),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (cashState.isLoading) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          final missedDates = ref.watch(missedCashbookForWorkerProvider);

          Widget? missedBanner;
          if (missedDates.isNotEmpty) {
            final formattedDates = missedDates
                .map((d) => DateFormat('dd MMM yyyy').format(d))
                .join(', ');
            missedBanner = Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309), size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '⚠️ Action Required: Missed Cashbook Entry',
                          style: TextStyle(
                            color: Color(0xFF92400E),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'No cash entries were recorded on $formattedDates. Please record daily cashbook entries.',
                          style: const TextStyle(
                            color: Color(0xFF78350F),
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD97706),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          label: const Text('Record Cashbook Entry Now'),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ExpenseFormScreen()),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          if (cashState.transactions.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (missedBanner != null) missedBanner,
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.account_balance_wallet_outlined,
                              color: AppColors.textTertiary, size: 64),
                          const SizedBox(height: 16),
                          Text('No Entries Yet',
                              style: AppTextStyles.h3
                                  .copyWith(color: AppColors.textPrimary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: cashState.transactions.length + (missedBanner != null ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (missedBanner != null && index == 0) {
                return missedBanner;
              }
              final txIndex = missedBanner != null ? index - 1 : index;
              final tx = cashState.transactions[txIndex];
              final isAdmin = ref.watch(authProvider).isAdmin;
              final canEdit = tx.isEditable || isAdmin;

              return InkWell(
                onTap: () {
                  if (canEdit) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ExpenseFormScreen(existingTransaction: tx),
                    )).then((didUpdate) {
                      if (didUpdate == true) {
                        final siteId = ref.read(authProvider).activeSite?.id ?? tx.siteId;
                        ref.invalidate(siteCashSummaryProvider(siteId));
                        ref.read(cashProvider.notifier).loadTransactions(siteId);
                      }
                    });
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('This submission has been reviewed and is locked.')),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(14),
                child: _CashTile(
                  transaction: tx,
                  onEdit: canEdit
                      ? () {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ExpenseFormScreen(existingTransaction: tx),
                          )).then((didUpdate) {
                            if (didUpdate == true) {
                              final siteId = ref.read(authProvider).activeSite?.id ?? tx.siteId;
                              ref.invalidate(siteCashSummaryProvider(siteId));
                              ref.read(cashProvider.notifier).loadTransactions(siteId);
                            }
                          });
                        }
                      : null,
                  onDelete: isAdmin ? () => _confirmDeleteCash(tx) : null,
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () {
          final activeSite = ref.read(authProvider).activeSite;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ExpenseFormScreen()),
          ).then((_) {
            if (activeSite != null) {
              ref.invalidate(siteCashSummaryProvider(activeSite.id));
              ref.read(cashProvider.notifier).loadTransactions(activeSite.id);
            }
          });
        },
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Entry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Future<void> _confirmDeleteCash(CashTransactionModel tx) async {
    final isExpense = tx.expenseAmount > 0;
    final amtStr = isExpense ? '₹${tx.expenseAmount}' : '₹${tx.amountReceived}';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Cash Entry?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to permanently delete this ${isExpense ? "expense" : "cash received"} entry ($amtStr - ${tx.displayExpenseTypeName})?\n\n'
          'Site cash in hand and total summary will be recalculated automatically.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rejected),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final siteId = ref.read(authProvider).activeSite?.id ?? tx.siteId;
      final success = await ref.read(cashProvider.notifier).deleteTransaction(tx);
      ref.invalidate(siteCashSummaryProvider(siteId));
      ref.read(cashProvider.notifier).loadTransactions(siteId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Cash entry deleted & balance updated.' : 'Failed to delete cash entry.'),
            backgroundColor: success ? AppColors.approved : AppColors.rejected,
          ),
        );
      }
    }
  }
}

class _CashTile extends StatelessWidget {
  final CashTransactionModel transaction;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _CashTile({
    required this.transaction,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
              Text(
                DateFormat('dd MMM yyyy').format(transaction.date),
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(),
              if (transaction.status == TransactionStatus.approved && transaction.approvedAt != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'Approved ${DateFormat('dd MMM hh:mm a').format(transaction.approvedAt!)}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.approved),
                  ),
                ),
              StatusBadge(
                status: transaction.status,
                compact: true,
                isOffline: transaction.id?.startsWith('offline_') ?? false,
              ),
              if (transaction.isEditable) ...[
                const SizedBox(width: 8),
                const Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            transaction.amountReceived > 0 && transaction.expenseAmount == 0
                ? (transaction.customExpenseType ?? (transaction.partyName != null && transaction.partyName!.isNotEmpty ? 'Cash from ${transaction.partyName}' : 'Cash Received / Top-up'))
                : transaction.displayExpenseTypeName,
            style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
          ),
          if (transaction.partyName != null || transaction.billNo != null) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (transaction.partyName != null && transaction.partyName!.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_outline_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Party: ${transaction.partyName!}',
                        style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                if (transaction.billNo != null && transaction.billNo!.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.receipt_outlined, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'Bill: #${transaction.billNo!}',
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _MiniStat(
                label: 'Expense',
                value: '₹${NumberFormat('#,##,###').format(transaction.expenseAmount)}',
                color: AppColors.rejected,
              ),
              const SizedBox(width: 16),
              _MiniStat(
                label: 'Received',
                value: '₹${NumberFormat('#,##,###').format(transaction.amountReceived)}',
                color: AppColors.approved,
              ),
              const SizedBox(width: 16),
              _MiniStat(
                label: 'Cash in Hand',
                value: '₹${NumberFormat('#,##,###').format(transaction.cashInHand)}',
                color: AppColors.primary,
              ),
            ],
          ),
          if (transaction.submitterName != null || transaction.supervisorReviewNote != null) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (transaction.submitterName != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_outline, size: 11, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          'By: ${transaction.submitterName}',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (transaction.supervisorReviewNote != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified_outlined, size: 11, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          transaction.supervisorReviewNote!,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 10,
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
          if (transaction.cleanRemarks != null &&
              transaction.cleanRemarks!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              transaction.cleanRemarks!,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textTertiary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (transaction.status == TransactionStatus.rejected && 
              transaction.rejectionNote != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.rejectedSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 16, color: AppColors.rejected),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rejected: ${transaction.rejectionNote!}',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.rejected),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (transaction.photoUrls.isNotEmpty)
            PhotoThumbnailStrip(photoUrls: transaction.photoUrls),
          if (onEdit != null || onDelete != null) ...[
            const Divider(color: AppColors.divider, height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onEdit != null)
                  TextButton.icon(
                    icon: const Icon(Icons.edit_note_rounded, size: 18, color: AppColors.primary),
                    label: const Text('Edit Entry', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold)),
                    onPressed: onEdit,
                  ),
                if (onDelete != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.rejected),
                    label: const Text('Delete', style: TextStyle(color: AppColors.rejected, fontSize: 13, fontWeight: FontWeight.bold)),
                    onPressed: onDelete,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  AppTextStyles.caption.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: 2),
          Text(value,
              style: AppTextStyles.labelLarge.copyWith(color: color)),
        ],
      ),
    );
  }
}
