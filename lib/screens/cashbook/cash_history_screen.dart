import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/cash_transaction_model.dart';
import '../../models/stock_transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_provider.dart';
import '../../widgets/status_badge.dart';
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
      appBar: AppBar(title: const Text('Cash Book History')),
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
              StatusBadge(status: transaction.status, compact: true),
              if (transaction.isEditable) ...[
                const SizedBox(width: 8),
                const Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
              ],
            ],
          ),
          const SizedBox(height: 12),
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
          if (transaction.remarks != null &&
              transaction.remarks!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              transaction.remarks!,
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
