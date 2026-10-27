import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../models/stock_transaction_model.dart';
import '../models/cash_transaction_model.dart';
import '../services/summary_service.dart';
import '../services/excel_service.dart';
import '../providers/auth_provider.dart';

/// Modal bottom sheet for viewing, customizing, and sharing the Daily Site Summary
class DailySummaryDialog extends ConsumerStatefulWidget {
  final String siteId;
  final String siteName;
  final String? siteLoginId;
  final List<StockTransactionModel> stockTransactions;
  final List<CashTransactionModel> cashTransactions;

  const DailySummaryDialog({
    super.key,
    required this.siteId,
    required this.siteName,
    this.siteLoginId,
    required this.stockTransactions,
    required this.cashTransactions,
  });

  static Future<void> show(
    BuildContext context, {
    required String siteId,
    required String siteName,
    String? siteLoginId,
    required List<StockTransactionModel> stockTransactions,
    required List<CashTransactionModel> cashTransactions,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DailySummaryDialog(
        siteId: siteId,
        siteName: siteName,
        siteLoginId: siteLoginId,
        stockTransactions: stockTransactions,
        cashTransactions: cashTransactions,
      ),
    );
  }

  @override
  ConsumerState<DailySummaryDialog> createState() => _DailySummaryDialogState();
}

class _DailySummaryDialogState extends ConsumerState<DailySummaryDialog> {
  late DateTime _selectedDate;
  bool _isExportingPdf = false;
  bool _isExportingExcel = false;
  bool _isSharingWhatsApp = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.cardDark,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final currencyFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    // Calculate day metrics
    final dayCash = widget.cashTransactions
        .where((c) => DateFormat('yyyy-MM-dd').format(c.date) == dateKey)
        .toList();
    final dayStock = widget.stockTransactions
        .where((s) => DateFormat('yyyy-MM-dd').format(s.date) == dateKey)
        .toList();

    double totalInboundCash = 0;
    double totalOutboundCash = 0;
    for (final c in dayCash) {
      totalInboundCash += c.amountReceived;
      totalOutboundCash += c.expenseAmount;
    }

    final inboundStockCount = dayStock.where((s) => s.type == TransactionType.inbound).length;
    final outboundStockCount = dayStock.where((s) => s.type == TransactionType.outbound).length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Daily Site Summary',
                      style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.siteName,
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              // Date picker button
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    border: Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('dd MMM yyyy').format(_selectedDate),
                        style: AppTextStyles.labelMedium.copyWith(color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Quick Day Overview Cards ──
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Today Expenses',
                  value: currencyFmt.format(totalOutboundCash),
                  color: AppColors.rejected,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.savings_rounded,
                  label: 'Cash Received',
                  value: currencyFmt.format(totalInboundCash),
                  color: AppColors.approved,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.move_to_inbox_rounded,
                  label: 'Deliveries In',
                  value: '$inboundStockCount materials',
                  color: const Color(0xFF06B6D4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.outbox_rounded,
                  label: 'Material Used',
                  value: '$outboundStockCount entries',
                  color: const Color(0xFFF97316),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 20),

          // ── Action Buttons ──

          // 1. WhatsApp Button
          ElevatedButton.icon(
            onPressed: _isSharingWhatsApp
                ? null
                : () async {
                    setState(() => _isSharingWhatsApp = true);
                    final message = SummaryService.buildWhatsAppSummary(
                      siteName: widget.siteName,
                      date: _selectedDate,
                      stockTransactions: widget.stockTransactions,
                      cashTransactions: widget.cashTransactions,
                      siteLoginId: widget.siteLoginId,
                    );
                    await SummaryService.shareToWhatsApp(message);
                    if (!mounted) return;
                    setState(() => _isSharingWhatsApp = false);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Summary copied to clipboard & opening WhatsApp!'),
                          backgroundColor: Color(0xFF25D366),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.chat_rounded, color: Colors.white),
            label: Text(
              _isSharingWhatsApp ? 'Preparing WhatsApp Report...' : 'Share Report on WhatsApp',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),

          const SizedBox(height: 12),

          // 2. PDF Download / Print Button
          OutlinedButton.icon(
            onPressed: _isExportingPdf
                ? null
                : () async {
                    setState(() => _isExportingPdf = true);
                    try {
                      await SummaryService.exportPdfReport(
                        siteName: widget.siteName,
                        date: _selectedDate,
                        stockTransactions: widget.stockTransactions,
                        cashTransactions: widget.cashTransactions,
                        siteLoginId: widget.siteLoginId,
                      );
                    } finally {
                      if (mounted) setState(() => _isExportingPdf = false);
                    }
                  },
            icon: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF38BDF8)),
            label: Text(_isExportingPdf ? 'Generating PDF...' : 'Download / Print PDF Report'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.divider),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),

          // 3. Excel (.xlsx) Export & Share Button (Strictly restricted to Admin and Accounts)
          if (ref.watch(authProvider).isAdmin || ref.watch(authProvider).isAccounts) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isExportingExcel
                  ? null
                  : () async {
                      setState(() => _isExportingExcel = true);
                      try {
                        await ExcelService.exportAndShareComprehensiveExcel(
                          siteName: widget.siteName,
                          siteId: widget.siteId,
                          cashTransactions: widget.cashTransactions,
                          stockTransactions: widget.stockTransactions,
                          filterDate: null, // Full site record with Cash, Stock Deliveries, & Stock Consumption
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
                      } finally {
                        if (mounted) setState(() => _isExportingExcel = false);
                      }
                    },
              icon: const Icon(Icons.table_view_rounded, color: Color(0xFF107C41)),
              label: Text(_isExportingExcel ? 'Generating Excel...' : 'Export Excel: Cashflow & Stock (.xlsx)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: Color(0xFF107C41)),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    ),
    ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
