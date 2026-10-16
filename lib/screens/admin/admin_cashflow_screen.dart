import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../providers/site_provider.dart';
import '../../providers/cash_provider.dart';
import '../../models/site_model.dart';

class AdminCashflowScreen extends ConsumerWidget {
  const AdminCashflowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sitesAsync = ref.watch(activeSitesProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: const Text('Cashflow Management'),
      ),
      body: sitesAsync.when(
        data: (sites) {
          if (sites.isEmpty) {
            return const Center(child: Text('No active sites found.'));
          }
          
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sites.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final site = sites[index];
              return _SiteCashflowCard(site: site).animate().fadeIn(delay: Duration(milliseconds: 50 * index));
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
    );
  }
}

class _SiteCashflowCard extends ConsumerWidget {
  final SiteModel site;

  const _SiteCashflowCard({required this.site});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashSummaryAsync = ref.watch(siteCashSummaryProvider(site.id));
    final currencyFormatter = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        site.name,
                        style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Allocated Budget: ${currencyFormatter.format(site.allocatedBudget)}',
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.account_balance_wallet, color: AppColors.primary),
                ),
              ],
            ),
          ),
          
          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: cashSummaryAsync.when(
              data: (summary) {
                final double totalExpense = summary['total_expense'] ?? 0.0;
                final double totalReceived = summary['total_received'] ?? 0.0;
                // Cash balance logic: Usually received - expenses, but budget is allocated
                // Total available = allocatedBudget + totalReceived (if external)
                // Let's just show Budget vs Expenses
                final double remainingBudget = site.allocatedBudget - totalExpense;
                
                final budgetProgress = site.allocatedBudget > 0 
                    ? (totalExpense / site.allocatedBudget).clamp(0.0, 1.0) 
                    : 0.0;
                
                final progressColor = budgetProgress > 0.9 ? AppColors.rejected 
                                      : budgetProgress > 0.7 ? Colors.orange 
                                      : AppColors.approved;

                return Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _StatItem(label: 'Total Expenses', value: currencyFormatter.format(totalExpense), color: AppColors.rejected),
                        _StatItem(label: 'Remaining Budget', value: currencyFormatter.format(remainingBudget), color: progressColor),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: budgetProgress,
                        minHeight: 8,
                        backgroundColor: AppColors.divider,
                        valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${(budgetProgress * 100).toStringAsFixed(1)}% Used', style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary)),
                        Text(currencyFormatter.format(site.allocatedBudget), style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary)),
                      ],
                    ),
                  ],
                );
              },
              loading: () => const Center(child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              )),
              error: (e, _) => Text('Failed to load cashflow data: $e', style: const TextStyle(color: Colors.red)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatItem({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary)),
        const SizedBox(height: 4),
        Text(value, style: AppTextStyles.h4.copyWith(color: color)),
      ],
    );
  }
}
