import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/stock_transaction_model.dart';
import '../../models/cash_transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/cash_provider.dart';
import '../../widgets/status_badge.dart';
import '../../providers/dropdown_provider.dart';
import '../../models/dropdown_item_model.dart';
import '../stock/add_product_screen.dart';
import '../stock/use_product_screen.dart';
import '../cashbook/expense_form_screen.dart';
/// Detail view for a single transaction — Accounts can approve or reject
class TransactionReviewScreen extends ConsumerStatefulWidget {
  final StockTransactionModel? stockTransaction;
  final CashTransactionModel? cashTransaction;

  const TransactionReviewScreen({
    super.key,
    this.stockTransaction,
    this.cashTransaction,
  });

  @override
  ConsumerState<TransactionReviewScreen> createState() =>
      _TransactionReviewScreenState();
}

class _TransactionReviewScreenState
    extends ConsumerState<TransactionReviewScreen> {
  final _rejectionNoteController = TextEditingController();
  bool _isProcessing = false;

  bool get isStockReview => widget.stockTransaction != null;

  TransactionStatus get status => isStockReview
      ? widget.stockTransaction!.status
      : widget.cashTransaction!.status;

  bool get canReview => status == TransactionStatus.pendingAccounts;

  Future<void> _approve() async {
    setState(() => _isProcessing = true);
    final userId = ref.read(authProvider).user?.id ?? '';

    bool success;
    if (isStockReview) {
      success = await ref
          .read(stockProvider.notifier)
          .approveByAccounts(widget.stockTransaction!.id!, userId);
    } else {
      success = await ref
          .read(cashProvider.notifier)
          .approveByAccounts(widget.cashTransaction!.id!, userId);
    }

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (success) {
      ref.invalidate(pendingStockAccountsProvider);
      ref.invalidate(pendingCashAccountsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Approved! Forwarded to Admin.'),
          backgroundColor: AppColors.approved,
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _reject() async {
    if (_rejectionNoteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a rejection reason')),
      );
      return;
    }

    setState(() => _isProcessing = true);
    final userId = ref.read(authProvider).user?.id ?? '';

    bool success;
    if (isStockReview) {
      success = await ref.read(stockProvider.notifier).rejectTransaction(
            widget.stockTransaction!.id!,
            userId,
            _rejectionNoteController.text,
          );
    } else {
      success = await ref.read(cashProvider.notifier).rejectTransaction(
            widget.cashTransaction!.id!,
            userId,
            _rejectionNoteController.text,
          );
    }

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (success) {
      ref.invalidate(pendingStockAccountsProvider);
      ref.invalidate(pendingCashAccountsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Transaction rejected.'),
          backgroundColor: AppColors.rejected,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _rejectionNoteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stockTx = widget.stockTransaction;
    final cashTx = widget.cashTransaction;
    final siteId = stockTx?.siteId ?? cashTx?.siteId ?? '';
    
    final vendorsAsync = ref.watch(allDropdownsProvider((category: DropdownCategory.vendor, siteId: siteId)));
    final productsAsync = ref.watch(allDropdownsProvider((category: DropdownCategory.product, siteId: siteId)));
    final unitsAsync = ref.watch(allDropdownsProvider((category: DropdownCategory.metricUnit, siteId: siteId)));
    final expenseTypesAsync = ref.watch(allDropdownsProvider((category: DropdownCategory.expenseType, siteId: siteId)));

    final isLoading = vendorsAsync.isLoading || productsAsync.isLoading || unitsAsync.isLoading || expenseTypesAsync.isLoading;
    
    if (isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.scaffoldDark,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final vendors = vendorsAsync.valueOrNull ?? [];
    final products = productsAsync.valueOrNull ?? [];
    final units = unitsAsync.valueOrNull ?? [];
    final expenseTypes = expenseTypesAsync.valueOrNull ?? [];

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Text(isStockReview ? 'Review Stock Entry' : 'Review Expense'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: StatusBadge(status: status),
          ),
          if (ref.watch(authProvider).isAdmin || 
             (ref.watch(authProvider).isAccounts && 
              (isStockReview ? widget.stockTransaction!.status == TransactionStatus.pendingAccounts : widget.cashTransaction!.status == TransactionStatus.pendingAccounts)))
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                bool? didUpdate = false;
                if (isStockReview) {
                  if (widget.stockTransaction!.type == TransactionType.inbound) {
                    didUpdate = await Navigator.push<bool>(context, MaterialPageRoute(
                      builder: (_) => AddProductScreen(existingTransaction: widget.stockTransaction),
                    ));
                  } else {
                    didUpdate = await Navigator.push<bool>(context, MaterialPageRoute(
                      builder: (_) => UseProductScreen(existingTransaction: widget.stockTransaction),
                    ));
                  }
                } else {
                  didUpdate = await Navigator.push<bool>(context, MaterialPageRoute(
                    builder: (_) => ExpenseFormScreen(existingTransaction: widget.cashTransaction),
                  ));
                }

                if (didUpdate == true && mounted) {
                  ref.invalidate(pendingStockAccountsProvider);
                  ref.invalidate(pendingCashAccountsProvider);
                  Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Transaction Details ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider, width: 0.5),
            ),
            child: isStockReview
                ? _buildStockDetails(widget.stockTransaction!, vendors, products, units)
                : _buildCashDetails(widget.cashTransaction!, expenseTypes),
          ),

          if (canReview) ...[
            const SizedBox(height: 24),

            // ── Rejection Note ──
            TextFormField(
              controller: _rejectionNoteController,
              maxLines: 3,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Rejection Note (required to reject)',
                alignLabelWithHint: true,
              ),
            ),

            const SizedBox(height: 24),

            // ── Action Buttons ──
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _reject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.rejected,
                        side: const BorderSide(color: AppColors.rejected),
                      ),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Reject'),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _approve,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.approved,
                      ),
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: const Text('Approve'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStockDetails(StockTransactionModel tx, List<DropdownItemModel> vendors, List<DropdownItemModel> products, List<DropdownItemModel> units) {
    final productName = products.where((p) => p.id == tx.productId).firstOrNull?.value ?? 'Unknown Product';
    final vendorName = tx.vendorId != null 
        ? vendors.where((v) => v.id == tx.vendorId).firstOrNull?.value ?? 'Unknown Vendor'
        : tx.unregisteredVendor ?? 'None';
    final unitName = units.where((u) => u.id == tx.metricUnitId).firstOrNull?.value ?? '';
    
    final baseAmount = (tx.rate ?? 0) * tx.quantity;
    final sgstAmount = baseAmount * (tx.sgst / 100);
    final igstAmount = baseAmount * (tx.igst / 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailRow('Type', tx.type.displayName),
        _DetailRow('Date', DateFormat('dd MMM yyyy').format(tx.date)),
        if (tx.type == TransactionType.inbound) _DetailRow('Vendor', vendorName),
        _DetailRow('Product', productName),
        _DetailRow('Quantity', '${tx.quantity} $unitName'),
        if (tx.rate != null && tx.type == TransactionType.inbound) _DetailRow('Rate', '₹${tx.rate}'),
        if (tx.type == TransactionType.inbound) _DetailRow('Base Amount', '₹${NumberFormat('#,##,###.##').format(baseAmount)}'),
        if (tx.sgst > 0) _DetailRow('SGST', '${tx.sgst}% (₹${NumberFormat('#,##,###.##').format(sgstAmount)})'),
        if (tx.igst > 0) _DetailRow('IGST', '${tx.igst}% (₹${NumberFormat('#,##,###.##').format(igstAmount)})'),
        if (tx.finalAmount != null && tx.type == TransactionType.inbound)
          _DetailRow('Final Amount',
              '₹${NumberFormat('#,##,###.##').format(tx.finalAmount)}'),
        if (tx.remarks != null) _DetailRow('Remarks', tx.remarks!),
        if (tx.photoUrls.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Attached Photos', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tx.photoUrls.map((url) => _PhotoThumbnail(url: url)).toList(),
          ),
        ]
      ],
    );
  }

  Widget _buildCashDetails(CashTransactionModel tx, List<DropdownItemModel> expenseTypes) {
    final expenseName = expenseTypes.where((e) => e.id == tx.expenseTypeId).firstOrNull?.value ?? 'Unknown Expense';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailRow('Date', DateFormat('dd MMM yyyy').format(tx.date)),
        _DetailRow('Expense Type', expenseName),
        _DetailRow('Expense Amount',
            '₹${NumberFormat('#,##,###').format(tx.expenseAmount)}'),
        _DetailRow('Amount Received',
            '₹${NumberFormat('#,##,###').format(tx.amountReceived)}'),
        _DetailRow('Cash in Hand',
            '₹${NumberFormat('#,##,###').format(tx.cashInHand)}'),
        if (tx.remarks != null) _DetailRow('Remarks', tx.remarks!),
        if (tx.photoUrls.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Attached Photos', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tx.photoUrls.map((url) => _PhotoThumbnail(url: url)).toList(),
          ),
        ]
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textTertiary)),
          ),
          Expanded(
            child: Text(value,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _PhotoThumbnail extends StatelessWidget {
  final String url;
  const _PhotoThumbnail({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 80,
        height: 80,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 80, height: 80,
          color: AppColors.surfaceDark,
          child: const Icon(Icons.broken_image, color: AppColors.textTertiary),
        ),
      ),
    );
  }
}
