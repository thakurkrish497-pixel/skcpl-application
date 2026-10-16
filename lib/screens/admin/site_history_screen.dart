import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../providers/stock_provider.dart';
import '../../providers/dropdown_provider.dart';
import '../../services/pdf_service.dart';
import '../../models/dropdown_item_model.dart';

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

class _SiteHistoryScreenState extends ConsumerState<SiteHistoryScreen> {
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(stockProvider.notifier).loadTransactions(widget.siteId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final stockState = ref.watch(stockProvider);
    final productsAsync = ref.watch(allDropdownsProvider((category: DropdownCategory.product, siteId: widget.siteId)));
    final unitsAsync = ref.watch(allDropdownsProvider((category: DropdownCategory.metricUnit, siteId: widget.siteId)));

    // Filter transactions
    var transactions = stockState.transactions.where((t) => t.status.name == 'approved').toList();
    if (_selectedDate != null) {
      transactions = transactions.where((t) {
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
            icon: Icon(_selectedDate == null ? Icons.calendar_today : Icons.filter_alt_off),
            onPressed: () async {
              if (_selectedDate != null) {
                setState(() => _selectedDate = null);
                return;
              }
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() => _selectedDate = picked);
              }
            },
          ),
        ],
      ),
      body: stockState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : transactions.isEmpty
              ? const Center(child: Text('No historical transactions found.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: transactions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final tx = transactions[index];
                    final isAdd = tx.type.name == 'inbound';
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isAdd ? Icons.add_circle : Icons.remove_circle,
                            color: isAdd ? AppColors.approved : AppColors.rejected,
                            size: 32,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isAdd ? 'Product Added' : 'Product Used',
                                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Date: ${DateFormat('dd MMM yyyy').format(tx.date)}',
                                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                                ),
                                if (tx.remarks != null)
                                  Text(
                                    'Remarks: ${tx.remarks}',
                                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            '${tx.quantity}',
                            style: AppTextStyles.h4.copyWith(color: AppColors.primary),
                          ),
                          IconButton(
                            icon: const Icon(Icons.picture_as_pdf, color: AppColors.textSecondary),
                            onPressed: () {
                              final productName = productsAsync.value?.where((p) => p.id == tx.productId).firstOrNull?.value ?? 'Unknown';
                              final unitName = unitsAsync.value?.where((u) => u.id == tx.metricUnitId).firstOrNull?.value ?? '';
                              PdfService.generateAndPrintStockReceipt(tx, widget.siteName, productName, unitName);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
