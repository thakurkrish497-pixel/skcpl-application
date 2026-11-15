import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../providers/site_provider.dart';
import '../../providers/cash_provider.dart';
import '../../models/site_model.dart';
import '../../widgets/universal_sync_button.dart';

class AdminCashflowScreen extends ConsumerStatefulWidget {
  const AdminCashflowScreen({super.key});
  @override
  ConsumerState<AdminCashflowScreen> createState() =>
      _AdminCashflowScreenState();
}

class _AdminCashflowScreenState extends ConsumerState<AdminCashflowScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      if (mounted) await ref.read(cashProvider.notifier).loadAllTransactions();
    });
  }

  Future<void> _refresh() async {
    final cash = ref.read(cashProvider.notifier).loadAllTransactions();
    try {
      await ref.refresh(activeSitesProvider.future).then<void>((_) {});
    } catch (_) {
      // The site provider exposes its own error; retain any cached cash figures.
    }
    await cash;
  }

  @override
  Widget build(BuildContext context) {
    final sitesAsync = ref.watch(activeSitesProvider);
    final cash = ref.watch(cashProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
          title: const Text('Cashflow Management'),
          actions: const [UniversalSyncButton()]),
      body: Column(children: [
        if (cash.isLoading) const LinearProgressIndicator(),
        if (cash.error != null)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Text(cash.transactions.isEmpty
                    ? 'Cashflow is unavailable: ${cash.error}'
                    : 'Could not refresh cashflow. Showing the last loaded figures. ${cash.error}'),
                TextButton(
                    onPressed: _refresh, child: const Text('Retry cashflow')),
              ])),
        Expanded(
            child: cash.transactions.isEmpty && cash.isLoading
                ? const Center(child: CircularProgressIndicator())
                : cash.transactions.isEmpty && cash.error != null
                    ? const Center(
                        child: Text('Refresh to load cashflow figures.'))
                    : sitesAsync.when(
                        data: (sites) => Center(
                            child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1000),
                          child: RefreshIndicator(
                              onRefresh: _refresh,
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(16),
                                itemCount: sites.isEmpty ? 1 : sites.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 16),
                                itemBuilder: (context, index) => sites.isEmpty
                                    ? const Text('No active sites found.')
                                    : _SiteCashflowCard(site: sites[index])
                                        .animate()
                                        .fadeIn(
                                            delay: Duration(
                                                milliseconds: 50 * index)),
                              )),
                        )),
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, _) => Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              Text('Error: $error'),
                              TextButton(
                                  onPressed: _refresh,
                                  child: const Text('Retry sites'))
                            ])),
                      )),
      ]),
    );
  }
}

class _SiteCashflowCard extends ConsumerWidget {
  final SiteModel site;

  const _SiteCashflowCard({required this.site});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(siteOperationalCashSummaryProvider(site.id));
    final currencyFormatter =
        NumberFormat.currency(symbol: '₹', decimalDigits: 2, locale: 'en_IN');

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
              border: Border(
                  bottom: BorderSide(color: AppColors.divider, width: 0.5)),
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
                        style: AppTextStyles.h4
                            .copyWith(color: AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Allocated Budget: ${currencyFormatter.format(site.allocatedBudget)}',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textSecondary),
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
                  child: const Icon(Icons.account_balance_wallet,
                      color: AppColors.primary),
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Builder(builder: (context) {
              final totalExpense = summary['total_expense']!;
              final approvedExpense = summary['approved_expense']!;
              final remainingBudget = site.allocatedBudget - approvedExpense;
              final budgetProgress = site.allocatedBudget > 0
                  ? (approvedExpense / site.allocatedBudget).clamp(0.0, 1.0)
                  : 0.0;
              final progressColor = budgetProgress > 0.9
                  ? AppColors.rejected
                  : budgetProgress > 0.7
                      ? Colors.orange
                      : AppColors.approved;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Live operational cash • includes pending entries; excludes rejected entries'),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (context, constraints) {
                      final columns = constraints.maxWidth < 600 ? 2 : 3;
                      final width =
                          (constraints.maxWidth - 16 * (columns - 1)) / columns;
                      return Wrap(spacing: 16, runSpacing: 16, children: [
                        for (final stat in [
                          (
                            'Cash Received',
                            summary['total_received']!,
                            AppColors.approved
                          ),
                          ('Total Expenses', totalExpense, AppColors.rejected),
                          (
                            'Cash in Hand',
                            summary['balance']!,
                            AppColors.primary
                          ),
                          (
                            'Approved Cash Balance',
                            summary['approved_balance']!,
                            AppColors.textSecondary
                          ),
                          (
                            'Approved Expenses',
                            approvedExpense,
                            AppColors.textSecondary
                          ),
                          ('Remaining Budget', remainingBudget, progressColor),
                        ])
                          SizedBox(
                              width: width,
                              child: _StatItem(
                                  label: stat.$1,
                                  value: currencyFormatter.format(stat.$2),
                                  color: stat.$3)),
                      ]);
                    }),
                    const SizedBox(height: 12),
                    Text(
                        '${summary['pending_count']!.toInt()} pending entries'),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                        value: budgetProgress,
                        minHeight: 8,
                        backgroundColor: AppColors.divider,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(progressColor)),
                    const SizedBox(height: 8),
                    Text(
                        '${(budgetProgress * 100).toStringAsFixed(1)}% of budget used by approved expenses',
                        style: AppTextStyles.caption),
                  ]);
            }),
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

  const _StatItem(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                AppTextStyles.caption.copyWith(color: AppColors.textTertiary)),
        const SizedBox(height: 4),
        FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: AppTextStyles.h4.copyWith(color: color))),
      ],
    );
  }
}
