import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/site_model.dart';
import '../../providers/stock_provider.dart';
import '../../providers/cash_provider.dart';
import '../../providers/auth_provider.dart';
import 'site_customization_screen.dart';
import 'manage_site_staff_screen.dart';
import 'site_history_screen.dart';
import '../../services/excel_service.dart';
import 'daily_site_reports_screen.dart';
import '../../widgets/cache_manager_dialog.dart';
import 'package:intl/intl.dart';

class SiteDetailsScreen extends ConsumerWidget {
  final SiteModel site;

  const SiteDetailsScreen({super.key, required this.site});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fetch Stock and Cash for this site
    final currentStockAsync = ref.watch(stockOverviewProvider(site.id));
    final currentCashAsync = ref.watch(siteCashSummaryProvider(site.id));
    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Text(site.name),
        actions: [
          const CacheActionButton(),
          IconButton(
            icon: const Icon(Icons.record_voice_over_rounded, color: AppColors.primary),
            tooltip: 'Daily Site Reports',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DailySiteReportsScreen(initialSiteId: site.id),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Site Info Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Site Information',
                    style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                _buildInfoRow('Login ID', site.siteLoginId),
                if (site.address != null && site.address!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildInfoRow('Address', site.address!),
                ],
                const SizedBox(height: 8),
                _buildInfoRow('Status', site.isActive ? 'Active' : 'Inactive',
                    valueColor: site.isActive ? AppColors.approved : AppColors.rejected),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Management Options
          Text('Site Management',
              style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          
          if (ref.read(authProvider).isAdmin) ...[
            ListTile(
              tileColor: AppColors.cardDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tune_rounded, color: AppColors.primary),
              ),
              title: Text('Customize Site & Dropdowns', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary)),
              subtitle: Text('Vendors, materials, units, credentials & budget', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SiteCustomizationScreen(
                      site: site,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              tileColor: AppColors.cardDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.people_alt_rounded, color: AppColors.secondary),
              ),
              title: Text('Manage Staff & Roles', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary)),
              subtitle: Text('Configure site team members, module permissions & login PINs', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ManageSiteStaffScreen(
                      site: site,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          
          ListTile(
            tileColor: AppColors.cardDark,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.history, color: AppColors.secondary),
            ),
            title: Text('Transaction History', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary)),
            subtitle: Text('View past stock and cash transactions', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SiteHistoryScreen(
                    siteId: site.id,
                    siteName: site.name,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          ListTile(
            tileColor: AppColors.cardDark,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.record_voice_over_rounded, color: AppColors.primary),
            ),
            title: Text('Daily Site Reports', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary)),
            subtitle: Text('Voice-to-Text notes & site photos submitted by site team', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DailySiteReportsScreen(initialSiteId: site.id),
                ),
              );
            },
          ),
          if (ref.read(authProvider).isAdmin || ref.read(authProvider).isAccounts) ...[
            const SizedBox(height: 12),
            ListTile(
              tileColor: AppColors.cardDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF107C41).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.table_view_rounded, color: Color(0xFF107C41)),
              ),
              title: Text('Export Excel Workbook', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary)),
              subtitle: Text('Cashbook, deliveries & usage register (.xlsx)', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
              trailing: const Icon(Icons.download_rounded, color: Color(0xFF107C41)),
              onTap: () async {
                final stockService = ref.read(stockServiceProvider);
                final cashService = ref.read(cashServiceProvider);
                final stockTx = await stockService.getTransactionsForSite(site.id);
                final cashTx = await cashService.getTransactionsForSite(site.id);
                try {
                  await ExcelService.exportAndShareComprehensiveExcel(
                    siteName: site.name,
                    siteId: site.id,
                    cashTransactions: cashTx,
                    stockTransactions: stockTx,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Comprehensive Excel exported successfully!'),
                        backgroundColor: Color(0xFF107C41),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.rejected),
                    );
                  }
                }
              },
            ),
          ],
          
          const SizedBox(height: 24),
          
          // Dashboard Cards
          Text('Dashboard', style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          
          Row(
            children: [
              Expanded(
                child: currentCashAsync.when(
                  loading: () => _buildShimmerCard(),
                  error: (e, _) => _buildErrorCard('Cash Error'),
                  data: (summary) => _buildStatCard(
                    'Cash Balance',
                    '₹${NumberFormat('#,##0.00').format(summary['balance'])}',
                    Icons.account_balance_wallet,
                    AppColors.approved,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Stock Overview List
          Text('Current Stock', style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          currentStockAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (stockList) {
              if (stockList.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No stock data available.'),
                );
              }
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: stockList.length,
                  separatorBuilder: (_, __) => const Divider(color: AppColors.divider),
                  itemBuilder: (context, index) {
                    final item = stockList[index];
                    return ListTile(
                      title: Text(item['product_name'] ?? 'Unknown', style: AppTextStyles.bodyMedium),
                      trailing: Text(
                        '${item['current_stock']} ${item['metric_unit'] ?? ''}',
                        style: AppTextStyles.h4.copyWith(color: AppColors.primary),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerCard() {
    return Container(
      height: 100,
      decoration: BoxDecoration(color: AppColors.cardDark, borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildErrorCard(String title) {
    return Container(
      height: 100,
      decoration: BoxDecoration(color: AppColors.cardDark, borderRadius: BorderRadius.circular(12)),
      alignment: Alignment.center,
      child: Text(title, style: TextStyle(color: AppColors.rejected)),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color iconColor) {
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
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(width: 8),
              Text(title, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(color: valueColor ?? AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}
