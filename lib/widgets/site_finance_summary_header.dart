import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../models/stock_transaction_model.dart';
import '../providers/site_provider.dart';
import '../providers/cash_provider.dart';
import '../providers/stock_provider.dart';
import '../services/excel_service.dart';

/// Interactive Site Finance & Live Running Balance + Material Stock Summary Header
class SiteFinanceSummaryHeader extends ConsumerStatefulWidget {
  final String selectedSiteId;
  final ValueChanged<String> onSiteChanged;
  final bool showExportExcel;

  const SiteFinanceSummaryHeader({
    super.key,
    required this.selectedSiteId,
    required this.onSiteChanged,
    this.showExportExcel = true,
  });

  @override
  ConsumerState<SiteFinanceSummaryHeader> createState() =>
      _SiteFinanceSummaryHeaderState();
}

class _SiteFinanceSummaryHeaderState
    extends ConsumerState<SiteFinanceSummaryHeader> {
  bool _showStockSection = false;
  final TextEditingController _stockSearchController = TextEditingController();

  @override
  void dispose() {
    _stockSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sitesAsync = ref.watch(activeSitesProvider);
    final sites = sitesAsync.valueOrNull ?? [];
    final cashState = ref.watch(cashProvider);
    final allStockAsync = ref.watch(allSitesStockProvider);
    final rawStockList = allStockAsync.valueOrNull ?? [];
    final currencyFmt =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    // 1. Filter cash transactions by selected site (or all)
    final filteredCash = widget.selectedSiteId == 'all'
        ? cashState.transactions
        : cashState.transactions
            .where((t) => t.siteId == widget.selectedSiteId)
            .toList();

    double totalReceived = 0.0;
    double totalExpenses = 0.0;
    int pendingCount = 0;

    for (final t in filteredCash) {
      if (t.status != TransactionStatus.rejected) {
        totalReceived += t.amountReceived;
        totalExpenses += t.expenseAmount;
      }
      if (t.status == TransactionStatus.pendingAccounts ||
          t.status == TransactionStatus.pendingAdmin) {
        pendingCount++;
      }
    }

    final netCashInHand = totalReceived - totalExpenses;
    final selectedSiteName = widget.selectedSiteId == 'all'
        ? 'All Sites Overview'
        : (sites
                .where((s) => s.id == widget.selectedSiteId)
                .firstOrNull
                ?.name ??
            'Selected site');

    // 2. Filter stock items by selected site (or all)
    final filteredStock = widget.selectedSiteId == 'all'
        ? rawStockList
        : rawStockList
            .where((s) => s['site_id'] == widget.selectedSiteId)
            .toList();

    // Material filter query
    final stockQuery = _stockSearchController.text.trim().toLowerCase();
    final displayStock = filteredStock.where((item) {
      if (stockQuery.isEmpty) return true;
      final prod = (item['product_name'] ?? '').toString().toLowerCase();
      final site = (item['site_name'] ?? '').toString().toLowerCase();
      return prod.contains(stockQuery) || site.contains(stockQuery);
    }).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: Site Selector Dropdown + Excel Export Button ──
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: widget.selectedSiteId == 'all' ||
                              sites.any((s) => s.id == widget.selectedSiteId)
                          ? widget.selectedSiteId
                          : null,
                      hint: const Text('Select an available site'),
                      isExpanded: true,
                      selectedItemBuilder: (context) => [
                        const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('All Sites',
                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ...sites.map((s) => Align(
                            alignment: Alignment.centerLeft,
                            child: Text(s.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis))),
                      ],
                      dropdownColor: AppColors.surfaceDark,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: AppColors.waveCyan),
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textPrimary),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Row(
                            children: [
                              Icon(Icons.dashboard_customize_rounded,
                                  size: 16, color: AppColors.waveCyan),
                              SizedBox(width: 8),
                              Text('All Sites Overview',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        ...sites.map((s) => DropdownMenuItem(
                              value: s.id,
                              child: Row(
                                children: [
                                  Icon(
                                    s.isHeadOffice
                                        ? Icons.apartment_rounded
                                        : Icons.location_on_rounded,
                                    size: 16,
                                    color: s.isHeadOffice
                                        ? AppColors.waveCyan
                                        : AppColors.goldAccent,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(s.name,
                                          overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            )),
                      ],
                      onChanged: (val) {
                        if (val != null) widget.onSiteChanged(val);
                      },
                    ),
                  ),
                ),
              ),
              if (widget.showExportExcel) ...[
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF107C41),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                  icon: const Icon(Icons.table_view_rounded, size: 16),
                  label: const Text('Export Excel',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Generating Comprehensive Excel Report...'),
                        backgroundColor: Color(0xFF107C41),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    await ExcelService.exportAndShareComprehensiveExcel(
                      siteName: selectedSiteName,
                      siteId: widget.selectedSiteId == 'all'
                          ? null
                          : widget.selectedSiteId,
                      cashTransactions: filteredCash,
                    );
                  },
                ),
              ],
            ],
          ),

          const SizedBox(height: 14),

          // ── Row 2: Live Financial KPI Metrics ──
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;
              final cards = [
                _buildMetricTile(
                  label: 'Operational Cash in Hand',
                  value: cashState.isLoading && filteredCash.isEmpty
                      ? 'Loading…'
                      : (cashState.error != null
                          ? 'Refresh needed'
                          : currencyFmt.format(netCashInHand)),
                  icon: Icons.account_balance_wallet_rounded,
                  color: netCashInHand >= 0
                      ? AppColors.approved
                      : AppColors.rejected,
                  badge: netCashInHand >= 0
                      ? 'Includes pending & local'
                      : 'Deficit',
                ),
                _buildMetricTile(
                  label: 'Total Inflow (Received)',
                  value: currencyFmt.format(totalReceived),
                  icon: Icons.arrow_downward_rounded,
                  color: AppColors.approved,
                ),
                _buildMetricTile(
                  label: 'Total Outflow (Spent)',
                  value: currencyFmt.format(totalExpenses),
                  icon: Icons.arrow_upward_rounded,
                  color: AppColors.pending,
                ),
                _buildMetricTile(
                  label: 'Pending Approvals',
                  value: '$pendingCount vouchers',
                  icon: Icons.pending_actions_rounded,
                  color: pendingCount > 0
                      ? AppColors.goldAccent
                      : AppColors.textTertiary,
                ),
              ];

              if (isNarrow) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 8),
                        Expanded(child: cards[1]),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: cards[2]),
                        const SizedBox(width: 8),
                        Expanded(child: cards[3]),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 8),
                  Expanded(child: cards[1]),
                  const SizedBox(width: 8),
                  Expanded(child: cards[2]),
                  const SizedBox(width: 8),
                  Expanded(child: cards[3]),
                ],
              );
            },
          ),

          const SizedBox(height: 12),

          // ── Row 3: Site Material Stock (IN / OUT / BALANCE) Bar ──
          InkWell(
            onTap: () => setState(() => _showStockSection = !_showStockSection),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _showStockSection
                      ? AppColors.waveCyan
                      : AppColors.cardBorder,
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.waveCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.inventory_2_rounded,
                        size: 16, color: AppColors.waveCyan),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            const Text(
                              'Approved Stock (IN / OUT / BALANCE)',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.waveCyan.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${filteredStock.length} Items',
                                style: const TextStyle(
                                  color: AppColors.waveCyan,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (allStockAsync.hasError
                              ? 'Stock refresh failed — retry'
                              : allStockAsync.isLoading
                                  ? 'Refreshing stock…'
                                  : '${filteredStock.length} material/unit balances • expand for quantities'),
                          style: const TextStyle(
                              color: AppColors.textTertiary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _showStockSection
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.waveCyan,
                  ),
                ],
              ),
            ),
          ),

          // ── Expandable Stock In / Out Breakdown ──
          if (_showStockSection) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.waveCyan.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filter field
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: TextField(
                            controller: _stockSearchController,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'Filter materials or sites...',
                              hintStyle: const TextStyle(
                                  color: AppColors.textTertiary, fontSize: 12),
                              prefixIcon: const Icon(Icons.search,
                                  size: 16, color: AppColors.waveCyan),
                              filled: true,
                              fillColor: AppColors.cardDark,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                      ),
                      if (_stockSearchController.text.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.clear,
                              size: 16, color: AppColors.textTertiary),
                          onPressed: () {
                            _stockSearchController.clear();
                            setState(() {});
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (displayStock.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: Text(
                          'No stock inventory records found for this selection.',
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 12),
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: displayStock.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = displayStock[index];
                          final productName =
                              item['product_name'] ?? 'Material';
                          final siteName = item['site_name'] ?? '';
                          final unit = item['metric_unit'] ?? '';
                          final inQty =
                              (item['total_inbound'] as num?)?.toDouble() ??
                                  0.0;
                          final outQty =
                              (item['total_outbound'] as num?)?.toDouble() ??
                                  0.0;
                          final stockQty =
                              (item['current_stock'] as num?)?.toDouble() ??
                                  0.0;
                          final isLow = stockQty <= 0;

                          return Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.cardDark,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isLow
                                    ? AppColors.rejected.withValues(alpha: 0.35)
                                    : AppColors.cardBorder,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 4,
                                  backgroundColor: isLow
                                      ? AppColors.rejected
                                      : AppColors.approved,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        productName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (siteName.isNotEmpty &&
                                          widget.selectedSiteId == 'all')
                                        Text(
                                          siteName,
                                          style: const TextStyle(
                                            color: AppColors.waveCyan,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // In metric
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.approved
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.arrow_downward_rounded,
                                          size: 10, color: AppColors.approved),
                                      const SizedBox(width: 3),
                                      Text(
                                        'IN: ${NumberFormat('#,##0.##').format(inQty)} $unit',
                                        style: const TextStyle(
                                            color: AppColors.approved,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Out metric
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.pending
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.arrow_upward_rounded,
                                          size: 10, color: AppColors.pending),
                                      const SizedBox(width: 3),
                                      Text(
                                        'OUT: ${NumberFormat('#,##0.##').format(outQty)} $unit',
                                        style: const TextStyle(
                                            color: AppColors.pending,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Balance in hand badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: (isLow
                                            ? AppColors.rejected
                                            : AppColors.waveCyan)
                                        .withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: (isLow
                                              ? AppColors.rejected
                                              : AppColors.waveCyan)
                                          .withValues(alpha: 0.4),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    'BAL: ${NumberFormat('#,##0.##').format(stockQty)} $unit',
                                    style: TextStyle(
                                      color: isLow
                                          ? AppColors.rejected
                                          : AppColors.waveCyan,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    String? badge,
  }) {
    return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textTertiary, fontSize: 11))),
            Icon(icon, size: 14, color: color)
          ]),
          const SizedBox(height: 6),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: 15, fontWeight: FontWeight.bold)),
          if (badge != null)
            Text(badge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 10)),
        ]));
  }
}
