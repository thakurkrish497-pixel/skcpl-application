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
      body: cashState.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : cashState.transactions.isEmpty
              ? Center(
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
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: cashState.transactions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final tx = cashState.transactions[index];
                    return InkWell(
                      onTap: () {
                        if (tx.isEditable || ref.read(authProvider).isAdmin) {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ExpenseFormScreen(existingTransaction: tx),
                          )).then((didUpdate) {
                            if (didUpdate == true) {
                              ref.read(cashProvider.notifier).loadTransactions(ref.read(authProvider).activeSite!.id);
                            }
                          });
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('This submission has been reviewed and is locked.')),
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: _CashTile(transaction: tx),
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
              ref.read(cashProvider.notifier).loadTransactions(activeSite.id);
            }
          });
        },
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Entry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _CashTile extends StatelessWidget {
  final CashTransactionModel transaction;

  const _CashTile({required this.transaction});

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
