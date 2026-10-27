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
import '../../widgets/photo_thumbnail_strip.dart';
import '../../widgets/photo_viewer_dialog.dart';
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

  bool get canAccountsReview => status == TransactionStatus.pendingAccounts;
  bool get canAdminReview => status == TransactionStatus.pendingAdmin;
  bool get canReview => canAccountsReview || canAdminReview;
  bool get canEdit => status != TransactionStatus.approved;

  Future<void> _openEditScreen() async {
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
      ref.invalidate(pendingStockAdminProvider);
      ref.invalidate(pendingCashAdminProvider);
      Navigator.pop(context, true);
    }
  }

  Future<void> _approve() async {
    setState(() => _isProcessing = true);
    final userId = ref.read(authProvider).user?.id ?? 
                   ref.read(supabaseClientProvider).auth.currentUser?.id ?? 
                   '';

    bool success;
    if (canAdminReview) {
      if (isStockReview) {
        success = await ref
            .read(stockProvider.notifier)
            .approveByAdmin(widget.stockTransaction!, userId);
      } else {
        success = await ref
            .read(cashProvider.notifier)
            .approveByAdmin(widget.cashTransaction!.id!, userId);
      }
    } else {
      if (isStockReview) {
        success = await ref
            .read(stockProvider.notifier)
            .approveByAccounts(widget.stockTransaction!.id!, userId);
      } else {
        success = await ref
            .read(cashProvider.notifier)
            .approveByAccounts(widget.cashTransaction!.id!, userId);
      }
    }

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (success) {
      ref.invalidate(pendingStockAccountsProvider);
      ref.invalidate(pendingCashAccountsProvider);
      ref.invalidate(pendingStockAdminProvider);
      ref.invalidate(pendingCashAdminProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(canAdminReview
              ? 'Approved! Record permanently locked.'
              : 'Approved! Forwarded to Admin.'),
          backgroundColor: AppColors.approved,
        ),
      );
      Navigator.pop(context, true);
    } else {
      final errorMsg = isStockReview
          ? ref.read(stockProvider).error
          : ref.read(cashProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Approval failed: ${errorMsg ?? "Please try again"}'),
          backgroundColor: AppColors.rejected,
        ),
      );
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
    final userId = ref.read(authProvider).user?.id ?? 
                   ref.read(supabaseClientProvider).auth.currentUser?.id ?? 
                   '';

    bool success;
    if (isStockReview) {
      success = await ref.read(stockProvider.notifier).rejectTransaction(
            widget.stockTransaction!.id!,
            userId,
            _rejectionNoteController.text.trim(),
          );
    } else {
      success = await ref.read(cashProvider.notifier).rejectTransaction(
            widget.cashTransaction!.id!,
            userId,
            _rejectionNoteController.text.trim(),
          );
    }

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (success) {
      ref.invalidate(pendingStockAccountsProvider);
      ref.invalidate(pendingCashAccountsProvider);
      ref.invalidate(pendingStockAdminProvider);
      ref.invalidate(pendingCashAdminProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Transaction rejected.'),
          backgroundColor: AppColors.rejected,
        ),
      );
      Navigator.pop(context, true);
    } else {
      final errorMsg = isStockReview
          ? ref.read(stockProvider).error
          : ref.read(cashProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rejection failed: ${errorMsg ?? "Please try again"}'),
          backgroundColor: AppColors.rejected,
        ),
      );
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

    final isLoading = isStockReview
        ? (vendorsAsync.isLoading || productsAsync.isLoading || unitsAsync.isLoading)
        : expenseTypesAsync.isLoading;
    
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

    final canEdit = status != TransactionStatus.approved;

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Text(isStockReview ? 'Review Stock Entry' : 'Review Expense'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: StatusBadge(status: status),
          ),
          if (canEdit)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _openEditScreen,
                icon: const Icon(Icons.edit_note_rounded, color: AppColors.primary, size: 22),
                label: const Text(
                  'Edit',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
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

          // ── Prominent Edit Button ──
          if (canEdit) ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary, width: 1.5),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _isProcessing ? null : _openEditScreen,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.edit_note_rounded, color: AppColors.primary, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'Edit / Correct Transaction Details',
                          style: AppTextStyles.labelLarge.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],

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
                      label: Text(canAdminReview ? 'Final Approve' : 'Approve'),
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
    final matchedProduct = products.where((p) => p.id == tx.productId).firstOrNull?.value;
    final productName = tx.customProduct ?? (matchedProduct ?? tx.displayProductName);

    final matchedVendor = tx.vendorId != null 
        ? vendors.where((v) => v.id == tx.vendorId).firstOrNull?.value
        : null;
    final vendorName = matchedVendor ?? tx.displayVendorName;

    final matchedUnit = units.where((u) => u.id == tx.metricUnitId).firstOrNull?.value;
    final unitName = tx.customMetricUnit ?? (matchedUnit ?? tx.displayMetricUnitName);
    
    final baseAmount = (tx.rate ?? 0) * tx.quantity;
    final sgstAmount = baseAmount * (tx.sgst / 100);
    final igstAmount = baseAmount * (tx.igst / 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailRow('Type', tx.type.displayName),
        _DetailRow('Date', DateFormat('dd MMM yyyy').format(tx.date)),
        if (tx.type == TransactionType.inbound) _DetailRow('Vendor / Party', vendorName),
        if (tx.billNo != null && tx.billNo!.isNotEmpty) _DetailRow('Bill / Challan No', '#${tx.billNo}'),
        _DetailRow('Product', productName),
        _DetailRow('Quantity', '${tx.quantity} $unitName'),
        if (tx.rate != null && tx.type == TransactionType.inbound) _DetailRow('Rate', '₹${tx.rate}'),
        if (tx.type == TransactionType.inbound) _DetailRow('Base Amount', '₹${NumberFormat('#,##,###.##').format(baseAmount)}'),
        if (tx.sgst > 0) _DetailRow('SGST', '${tx.sgst}% (₹${NumberFormat('#,##,###.##').format(sgstAmount)})'),
        if (tx.igst > 0) _DetailRow('IGST', '${tx.igst}% (₹${NumberFormat('#,##,###.##').format(igstAmount)})'),
        if (tx.finalAmount != null && tx.type == TransactionType.inbound)
          _DetailRow('Final Amount',
              '₹${NumberFormat('#,##,###.##').format(tx.finalAmount)}'),
        if (tx.submitterName != null) _DetailRow('Entered By', tx.submitterName!),
        if (tx.supervisorReviewNote != null) _DetailRow('Project Head Review', tx.supervisorReviewNote!),
        if (tx.cleanRemarks != null && tx.cleanRemarks!.isNotEmpty) _DetailRow('Remarks', tx.cleanRemarks!),
        if (tx.photoUrls.isNotEmpty)
          PhotoThumbnailStrip(
            photoUrls: tx.photoUrls,
            title: 'Attached Bills & Challans (${tx.photoUrls.length}) • Tap to zoom',
            size: 76,
          ),
      ],
    );
  }

  Widget _buildCashDetails(CashTransactionModel tx, List<DropdownItemModel> expenseTypes) {
    final matchedExpense = expenseTypes.where((e) => e.id == tx.expenseTypeId).firstOrNull?.value;
    final expenseName = tx.customExpenseType ?? (matchedExpense ?? tx.displayExpenseTypeName);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailRow('Date', DateFormat('dd MMM yyyy').format(tx.date)),
        _DetailRow('Expense Type', expenseName),
        if (tx.partyName != null && tx.partyName!.isNotEmpty) _DetailRow('Party / Vendor', tx.partyName!),
        if (tx.billNo != null && tx.billNo!.isNotEmpty) _DetailRow('Bill / Voucher No', '#${tx.billNo}'),
        _DetailRow('Expense Amount',
            '₹${NumberFormat('#,##,###').format(tx.expenseAmount)}'),
        _DetailRow('Amount Received',
            '₹${NumberFormat('#,##,###').format(tx.amountReceived)}'),
        _DetailRow('Cash in Hand',
            '₹${NumberFormat('#,##,###').format(tx.cashInHand)}'),
        if (tx.submitterName != null) _DetailRow('Entered By', tx.submitterName!),
        if (tx.supervisorReviewNote != null) _DetailRow('Project Head Review', tx.supervisorReviewNote!),
        if (tx.cleanRemarks != null && tx.cleanRemarks!.isNotEmpty) _DetailRow('Remarks', tx.cleanRemarks!),
        if (tx.photoUrls.isNotEmpty)
          PhotoThumbnailStrip(
            photoUrls: tx.photoUrls,
            title: 'Attached Receipts (${tx.photoUrls.length}) • Tap to zoom',
            size: 76,
          ),
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
