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
import '../../widgets/app_drawer.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/status_badge.dart';
import '../admin/site_details_screen.dart';
import 'transaction_review_screen.dart';

/// Accounts Dashboard — Review and approve/reject worker submissions
class AccountsDashboard extends ConsumerWidget {
  const AccountsDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingStockAsync = ref.watch(pendingStockAccountsProvider);
    final pendingCashAsync = ref.watch(pendingCashAccountsProvider);
    final allSitesAsync = ref.watch(activeSitesProvider);
    final authState = ref.watch(authProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldDark,
        drawer: AppDrawer(
          user: authState.user,
          onSignOut: () => ref.read(authProvider.notifier).signOut(),
        ),
        appBar: AppBar(
          title: const Text('Accounts Dashboard'),
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
        body: TabBarView(
          children: [
            // ── Tab 1: Pending Stock ──
            pendingStockAsync.when(
              loading: () => const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (transactions) => transactions.isEmpty
                  ? _emptyState('No Pending Stock', Icons.check_circle_outline)
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: transactions.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final tx = transactions[index];
                        return _ReviewableTile(
                          title:
                              '${tx.type.displayName} — ${tx.quantity} units',
                          subtitle:
                              'Date: ${DateFormat('dd MMM').format(tx.date)}',
                          amount: tx.finalAmount,
                          status: tx.status,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TransactionReviewScreen(
                                  stockTransaction: tx,
                                ),
                              ),
                            );
                          },
                        ).animate().fadeIn(
                              delay: Duration(milliseconds: 50 * index),
                            );
                      },
                    ),
            ),

            // ── Tab 2: Pending Cash ──
            pendingCashAsync.when(
              loading: () => const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (transactions) => transactions.isEmpty
                  ? _emptyState('No Pending Cash', Icons.check_circle_outline)
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: transactions.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final tx = transactions[index];
                        return _ReviewableTile(
                          title:
                              'Expense: ₹${NumberFormat('#,##,###').format(tx.expenseAmount)}',
                          subtitle:
                              'Date: ${DateFormat('dd MMM').format(tx.date)}',
                          amount: tx.expenseAmount,
                          status: tx.status,
                          onTap: () {
                            // Navigate to cash review
                          },
                        ).animate().fadeIn(
                              delay: Duration(milliseconds: 50 * index),
                            );
                      },
                    ),
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
}

class _ReviewableTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final double? amount;
  final TransactionStatus status;
  final VoidCallback onTap;

  const _ReviewableTile({
    required this.title,
    required this.subtitle,
    this.amount,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Row(
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
                ],
              ),
            ),
            StatusBadge(status: status, compact: true),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right,
                color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}
