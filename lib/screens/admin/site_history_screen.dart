import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/cash_transaction_model.dart';
import '../../models/stock_transaction_model.dart';
import '../../providers/stock_provider.dart';
import '../../providers/cash_provider.dart';
import '../../services/pdf_service.dart';
import '../../services/excel_service.dart';
import '../../widgets/photo_thumbnail_strip.dart';
import '../../widgets/status_badge.dart';
import '../../providers/auth_provider.dart';
import '../stock/add_product_screen.dart';
import '../stock/use_product_screen.dart';
import '../cashbook/expense_form_screen.dart';

class SiteHistoryScreen extends ConsumerStatefulWidget {
  final String siteId;
  final String siteName;

  const SiteHistoryScreen({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  @override
  ConsumerState<SiteHistoryScreen> createState() => _SiteHistoryScreenState();
}

class _SiteHistoryScreenState extends ConsumerState<SiteHistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime? _selectedDate;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(stockProvider.notifier).loadTransactions(widget.siteId);
      ref.read(cashProvider.notifier).loadTransactions(widget.siteId);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _exportExcel() async {
    final cashState = ref.read(cashProvider);
    final stockState = ref.read(stockProvider);
    setState(() => _isExporting = true);
    try {
      await ExcelService.exportAndShareComprehensiveExcel(
        siteName: widget.siteName,
        siteId: widget.siteId,
        cashTransactions: cashState.transactions,
        stockTransactions: stockState.transactions,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comprehensive Excel (Cash & Stock) exported!'),
            backgroundColor: Color(0xFF107C41),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.rejected),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _deleteStockTx(StockTransactionModel tx) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Stock Entry?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to permanently delete this ${tx.type.displayName} entry (${tx.displayProductName} - ${tx.quantity} ${tx.displayMetricUnitName})?\n\n'
          'Current stock balance will be recalculated automatically.',
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
      final success = await ref.read(stockProvider.notifier).deleteTransaction(tx);
      ref.invalidate(stockOverviewProvider(widget.siteId));
      ref.invalidate(allSitesStockProvider);
      ref.read(stockProvider.notifier).loadCurrentStock(widget.siteId);
      ref.read(stockProvider.notifier).loadTransactions(widget.siteId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Stock entry deleted & inventory updated.' : 'Failed to delete stock entry.'),
            backgroundColor: success ? AppColors.approved : AppColors.rejected,
          ),
        );
      }
    }
  }

  Future<void> _deleteCashTx(CashTransactionModel tx) async {
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
          'Site cash in hand and total balance will be recalculated automatically.',
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
      final success = await ref.read(cashProvider.notifier).deleteTransaction(tx);
      ref.invalidate(siteCashSummaryProvider(widget.siteId));
      ref.read(cashProvider.notifier).loadTransactions(widget.siteId);
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

  @override
  Widget build(BuildContext context) {
    final stockState = ref.watch(stockProvider);
    final cashState = ref.watch(cashProvider);

    // Filter stock transactions
    var stockTransactions = stockState.transactions.where((t) => t.status == TransactionStatus.approved).toList();
    if (_selectedDate != null) {
      stockTransactions = stockTransactions.where((t) {
        return t.date.year == _selectedDate!.year &&
            t.date.month == _selectedDate!.month &&
            t.date.day == _selectedDate!.day;
      }).toList();
    }

    // Filter cash transactions
    var cashTransactions = cashState.transactions.where((t) => t.status == TransactionStatus.approved).toList();
    if (_selectedDate != null) {
      cashTransactions = cashTransactions.where((t) {
        return t.date.year == _selectedDate!.year &&
            t.date.month == _selectedDate!.month &&
            t.date.day == _selectedDate!.day;
      }).toList();
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Text('${widget.siteName} History'),
        actions: [
          IconButton(
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.table_view_rounded, color: Color(0xFF107C41)),
            tooltip: 'Export Imprest Excel (.xlsx)',
            onPressed: _isExporting ? null : _exportExcel,
          ),
          IconButton(
            icon: Icon(_selectedDate == null ? Icons.calendar_today : Icons.filter_alt_off),
            tooltip: _selectedDate == null ? 'Filter by date' : 'Clear date filter',
            onPressed: () async {
              if (_selectedDate != null) {
                setState(() => _selectedDate = null);
                return;
              }
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                setState(() => _selectedDate = picked);
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Stock Material'),
            Tab(icon: Icon(Icons.account_balance_wallet_outlined), text: 'Imprest Cashbook'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Tab 1: Stock History ──
          stockState.isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : stockTransactions.isEmpty
                  ? Center(
                      child: Text(
                        _selectedDate != null
                            ? 'No approved stock records on ${DateFormat('dd MMM yyyy').format(_selectedDate!)}'
                            : 'No historical stock transactions found.',
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textTertiary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: stockTransactions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final tx = stockTransactions[index];
                        final isAdd = tx.type == TransactionType.inbound;
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.cardDark,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.divider, width: 0.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isAdd ? Icons.add_circle : Icons.remove_circle,
                                    color: isAdd ? AppColors.approved : AppColors.rejected,
                                    size: 30,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${isAdd ? 'Product In' : 'Product Used'}: ${tx.displayProductName}',
                                          style: AppTextStyles.bodyMedium.copyWith(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'Date: ${DateFormat('dd MMM yyyy').format(tx.date)}',
                                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                                        ),
                                        if (tx.submitterName != null || tx.supervisorReviewNote != null)
                                          Text(
                                            '${tx.submitterName != null ? 'By: ${tx.submitterName}  ' : ''}${tx.supervisorReviewNote != null ? '• ${tx.supervisorReviewNote}' : ''}',
                                            style: AppTextStyles.caption.copyWith(color: AppColors.secondary, fontWeight: FontWeight.w600),
                                          ),
                                        if (tx.billNo != null || (isAdd && tx.displayVendorName != 'None'))
                                          Text(
                                            '${isAdd && tx.displayVendorName != 'None' ? 'Party: ${tx.displayVendorName}  ' : ''}${tx.billNo != null ? 'Bill: #${tx.billNo}' : ''}',
                                            style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
                                          ),
                                        if (tx.cleanRemarks != null && tx.cleanRemarks!.isNotEmpty)
                                          Text(
                                            'Remarks: ${tx.cleanRemarks}',
                                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${tx.quantity} ${tx.displayMetricUnitName}',
                                    style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.picture_as_pdf, color: AppColors.textSecondary, size: 20),
                                    onPressed: () {
                                      PdfService.generateAndPrintStockReceipt(tx, widget.siteName);
                                    },
                                  ),
                                ],
                              ),
                              if (tx.photoUrls.isNotEmpty)
                                PhotoThumbnailStrip(photoUrls: tx.photoUrls),
                              if (ref.read(authProvider).isAdmin) ...[
                                const Divider(color: AppColors.divider, height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      icon: const Icon(Icons.edit_note_rounded, size: 18, color: AppColors.primary),
                                      label: const Text('Edit Entry', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold)),
                                      onPressed: () async {
                                        final didUpdate = await Navigator.push<bool>(context, MaterialPageRoute(
                                          builder: (_) => tx.type == TransactionType.inbound
                                              ? AddProductScreen(existingTransaction: tx)
                                              : UseProductScreen(existingTransaction: tx),
                                        ));
                                        if (didUpdate == true) {
                                          ref.invalidate(stockOverviewProvider(widget.siteId));
                                          ref.invalidate(allSitesStockProvider);
                                          ref.read(stockProvider.notifier).loadCurrentStock(widget.siteId);
                                          ref.read(stockProvider.notifier).loadTransactions(widget.siteId);
                                        }
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.rejected),
                                      label: const Text('Delete Entry', style: TextStyle(color: AppColors.rejected, fontSize: 13, fontWeight: FontWeight.bold)),
                                      onPressed: () => _deleteStockTx(tx),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),

          // ── Tab 2: Imprest Cashbook History ──
          cashState.isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : cashTransactions.isEmpty
                  ? Center(
                      child: Text(
                        _selectedDate != null
                            ? 'No approved cash records on ${DateFormat('dd MMM yyyy').format(_selectedDate!)}'
                            : 'No historical cashbook transactions found.',
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textTertiary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: cashTransactions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final tx = cashTransactions[index];
                        final isExpense = tx.expenseAmount > 0;
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.cardDark,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.divider, width: 0.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isExpense ? Icons.money_off_rounded : Icons.savings_rounded,
                                    color: isExpense ? AppColors.rejected : AppColors.approved,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tx.displayExpenseTypeName,
                                          style: AppTextStyles.bodyMedium.copyWith(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'Date: ${DateFormat('dd MMM yyyy').format(tx.date)}',
                                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                                        ),
                                        if (tx.submitterName != null || tx.supervisorReviewNote != null)
                                          Text(
                                            '${tx.submitterName != null ? 'By: ${tx.submitterName}  ' : ''}${tx.supervisorReviewNote != null ? '• ${tx.supervisorReviewNote}' : ''}',
                                            style: AppTextStyles.caption.copyWith(color: AppColors.secondary, fontWeight: FontWeight.w600),
                                          ),
                                        if (tx.partyName != null || tx.billNo != null)
                                          Text(
                                            '${tx.partyName != null ? 'Party: ${tx.partyName}  ' : ''}${tx.billNo != null ? 'Bill: #${tx.billNo}' : ''}',
                                            style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
                                          ),
                                        if (tx.cleanRemarks != null && tx.cleanRemarks!.isNotEmpty)
                                          Text(
                                            'Desc: ${tx.cleanRemarks}',
                                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        isExpense
                                            ? '-₹${NumberFormat('#,##,###').format(tx.expenseAmount)}'
                                            : '+₹${NumberFormat('#,##,###').format(tx.amountReceived)}',
                                        style: AppTextStyles.h4.copyWith(
                                          color: isExpense ? AppColors.rejected : AppColors.approved,
                                        ),
                                      ),
                                      Text(
                                        'Hand: ₹${NumberFormat('#,##,###').format(tx.cashInHand)}',
                                        style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (tx.photoUrls.isNotEmpty)
                                PhotoThumbnailStrip(photoUrls: tx.photoUrls),
                              if (ref.read(authProvider).isAdmin) ...[
                                const Divider(color: AppColors.divider, height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      icon: const Icon(Icons.edit_note_rounded, size: 18, color: AppColors.primary),
                                      label: const Text('Edit Entry', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold)),
                                      onPressed: () async {
                                        final didUpdate = await Navigator.push<bool>(context, MaterialPageRoute(
                                          builder: (_) => ExpenseFormScreen(existingTransaction: tx),
                                        ));
                                        if (didUpdate == true) {
                                          ref.invalidate(siteCashSummaryProvider(widget.siteId));
                                          ref.read(cashProvider.notifier).loadTransactions(widget.siteId);
                                        }
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.rejected),
                                      label: const Text('Delete Entry', style: TextStyle(color: AppColors.rejected, fontSize: 13, fontWeight: FontWeight.bold)),
                                      onPressed: () => _deleteCashTx(tx),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
        ],
      ),
    );
  }
}
