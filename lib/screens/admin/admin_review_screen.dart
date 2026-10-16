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
import '../stock/add_product_screen.dart';
import '../stock/use_product_screen.dart';
import '../cashbook/expense_form_screen.dart';

/// Admin approval screen — Final approval for pending_admin transactions
class AdminReviewScreen extends ConsumerWidget {
  const AdminReviewScreen({super.key});

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
              data: (transactions) => transactions.isEmpty
                  ? _emptyState('All Stock Approved')
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: transactions.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final tx = transactions[index];
                        return _AdminReviewTile(
                          title:
                              '${tx.type.displayName} — ${tx.quantity} units',
                          subtitle:
                              DateFormat('dd MMM yyyy').format(tx.date),
                          amount: tx.finalAmount,
                          onApprove: () async {
                            final userId =
                                ref.read(authProvider).user?.id ?? '';
                            await ref
                                .read(stockProvider.notifier)
                                .approveByAdmin(tx, userId);
                            ref.refresh(pendingStockAdminProvider);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                    'Approved! Record permanently locked.'),
                                backgroundColor: AppColors.approved,
                              ),
                            );
                          },
                          onReject: () async {
                            final userId =
                                ref.read(authProvider).user?.id ?? '';
                            await ref
                                .read(stockProvider.notifier)
                                .rejectTransaction(
                                    tx.id!, userId, 'Rejected by Admin');
                            ref.refresh(pendingStockAdminProvider);
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
                              ref.refresh(pendingStockAdminProvider);
                            }
                          },
                        );
                      },
                    ),
            ),

            // Cash tab
            pendingCashAsync.when(
              loading: () => const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (transactions) => transactions.isEmpty
                  ? _emptyState('All Cash Approved')
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: transactions.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final tx = transactions[index];
                        return _AdminReviewTile(
                          title:
                              'Expense: ₹${NumberFormat('#,##,###').format(tx.expenseAmount)}',
                          subtitle:
                              DateFormat('dd MMM yyyy').format(tx.date),
                          amount: tx.expenseAmount,
                          onApprove: () async {
                            final userId =
                                ref.read(authProvider).user?.id ?? '';
                            await ref
                                .read(cashProvider.notifier)
                                .approveByAdmin(tx.id!, userId);
                            ref.refresh(pendingCashAdminProvider);
                          },
                          onReject: () async {
                            final userId =
                                ref.read(authProvider).user?.id ?? '';
                            await ref
                                .read(cashProvider.notifier)
                                .rejectTransaction(
                                    tx.id!, userId, 'Rejected by Admin');
                            ref.refresh(pendingCashAdminProvider);
                          },
                          onEdit: () async {
                            final didUpdate = await Navigator.push<bool>(context, MaterialPageRoute(
                              builder: (_) => ExpenseFormScreen(existingTransaction: tx),
                            ));
                            if (didUpdate == true) {
                              ref.refresh(pendingCashAdminProvider);
                            }
                          },
                        );
                      },
                    ),
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
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback? onEdit;

  const _AdminReviewTile({
    required this.title,
    required this.subtitle,
    this.amount,
    required this.onApprove,
    required this.onReject,
    this.onEdit,
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
                  ],
                ),
              ),
              const StatusBadge(
                  status: TransactionStatus.pendingAdmin, compact: true),
              if (onEdit != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20, color: AppColors.primary),
                  onPressed: onEdit,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.rejected,
                      side: const BorderSide(color: AppColors.rejected),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text('Reject'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: onApprove,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.approved,
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text('Approve'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
