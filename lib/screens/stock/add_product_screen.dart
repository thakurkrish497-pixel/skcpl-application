import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/validators.dart';
import '../../models/dropdown_item_model.dart';
import '../../models/stock_transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dropdown_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/storage_provider.dart';
import '../../widgets/locked_form_banner.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/photo_picker.dart';
import 'dart:io';

/// Add Product (Inbound) form with real-time tax calculation
/// and conditional locking based on approval status
class AddProductScreen extends ConsumerStatefulWidget {
  final StockTransactionModel? existingTransaction; // null = new entry

  const AddProductScreen({super.key, this.existingTransaction});

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _quantityController = TextEditingController();
  final _rateController = TextEditingController();
  final _sgstController = TextEditingController();
  final _igstController = TextEditingController();
  final _remarksController = TextEditingController();
  final _unregisteredVendorController = TextEditingController();

  // Selected dropdown values
  String? _selectedVendorId;
  String? _selectedProductId;
  String? _selectedMetricUnitId;
  DateTime _selectedDate = DateTime.now();

  // Photos
  List<File> _selectedPhotos = [];

  // Calculated
  double _finalAmount = 0.0;

  bool get _isEditMode => widget.existingTransaction != null;
  StockTransactionModel? get _transaction => widget.existingTransaction;

  /// Whether the form should be locked (read-only)
  bool get isLocked {
    if (widget.existingTransaction == null) return false;
    final user = ref.read(authProvider);
    if (user.isAdmin) return false;
    if (user.isAccounts && widget.existingTransaction!.status == TransactionStatus.pendingAccounts) return false;
    return !widget.existingTransaction!.isEditable;
  }

  @override
  void initState() {
    super.initState();
    // Attach listeners for real-time tax calculation
    _quantityController.addListener(_calculateFinalAmount);
    _rateController.addListener(_calculateFinalAmount);
    _sgstController.addListener(_calculateFinalAmount);
    _igstController.addListener(_calculateFinalAmount);

    // Pre-fill values if editing an existing transaction
    final tx = widget.existingTransaction;
    if (tx != null) {
      _selectedVendorId = tx.vendorId;
      _selectedProductId = tx.productId;
      _selectedMetricUnitId = tx.metricUnitId;
      _selectedDate = tx.date;
      _quantityController.text = tx.quantity.toString();
      _rateController.text = tx.rate?.toString() ?? '';
      _sgstController.text = tx.sgst.toString();
      _igstController.text = tx.igst.toString();
      _remarksController.text = tx.remarks ?? '';
      if (tx.unregisteredVendor != null) {
        _selectedVendorId = 'OTHER';
        _unregisteredVendorController.text = tx.unregisteredVendor!;
      }
      _calculateFinalAmount();
    }
  }

  void _calculateFinalAmount() {
    final qty = double.tryParse(_quantityController.text) ?? 0;
    final rate = double.tryParse(_rateController.text) ?? 0;
    final sgst = double.tryParse(_sgstController.text) ?? 0;
    final igst = double.tryParse(_igstController.text) ?? 0;

    final baseAmount = qty * rate;
    final taxAmount = baseAmount * ((sgst + igst) / 100);

    setState(() {
      _finalAmount = baseAmount + taxAmount;
    });
  }

  Future<void> _pickDate() async {
    if (isLocked) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              surface: AppColors.surfaceDark,
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

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVendorId == null ||
        _selectedProductId == null ||
        _selectedMetricUnitId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select all required dropdowns')),
      );
      return;
    }

    final authState = ref.read(authProvider);
    final siteId = authState.activeSite?.id;
    final userId = authState.user?.id;

    if (siteId == null) return;

    StockTransactionModel submission;

    if (_isEditMode) {
      submission = StockTransactionModel(
        id: _transaction!.id,
        siteId: _transaction!.siteId,
        submittedBy: _transaction!.submittedBy,
        type: TransactionType.inbound,
        date: _transaction!.date,
        vendorId: _selectedVendorId == 'OTHER' ? null : _selectedVendorId,
        productId: _selectedProductId!,
        metricUnitId: _selectedMetricUnitId!,
        quantity: double.parse(_quantityController.text),
        rate: double.tryParse(_rateController.text),
        sgst: double.tryParse(_sgstController.text) ?? 0,
        igst: double.tryParse(_igstController.text) ?? 0,
        finalAmount: _finalAmount,
        remarks: _remarksController.text.isEmpty ? null : _remarksController.text,
        unregisteredVendor: _selectedVendorId == 'OTHER' ? _unregisteredVendorController.text : null,
        status: _transaction!.status,
        photoUrls: _transaction!.photoUrls,
      );
    } else {
      submission = StockTransactionModel(
        siteId: siteId,
        submittedBy: userId,
        type: TransactionType.inbound,
        date: _selectedDate,
        vendorId: _selectedVendorId == 'OTHER' ? null : _selectedVendorId,
        productId: _selectedProductId!,
        metricUnitId: _selectedMetricUnitId!,
        quantity: double.parse(_quantityController.text),
        rate: double.tryParse(_rateController.text),
        sgst: double.tryParse(_sgstController.text) ?? 0,
        igst: double.tryParse(_igstController.text) ?? 0,
        finalAmount: _finalAmount,
        remarks: _remarksController.text.isEmpty ? null : _remarksController.text,
        unregisteredVendor: _selectedVendorId == 'OTHER' ? _unregisteredVendorController.text : null,
        photoUrls: [],
      );
    }

    List<String> uploadedUrls = List.from(submission.photoUrls);
    if (_selectedPhotos.isNotEmpty) {
      final storageService = ref.read(storageServiceProvider);
      for (var file in _selectedPhotos) {
        final url = await storageService.uploadPhoto(file);
        uploadedUrls.add(url);
      }
      submission = submission.copyWith(photoUrls: uploadedUrls);
    }

    final success = _isEditMode
        ? await ref.read(stockProvider.notifier).updateTransaction(submission)
        : await ref.read(stockProvider.notifier).submitTransaction(submission);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditMode ? 'Transaction updated successfully!' : 'Product added successfully! Sent to Accounts.'),
          backgroundColor: AppColors.approved,
        ),
      );
      Navigator.pop(context, true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ref.read(stockProvider).error ?? 'Submission failed'),
          backgroundColor: AppColors.rejected,
        ),
      );
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _rateController.dispose();
    _sgstController.dispose();
    _igstController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final siteId = ref.watch(authProvider).activeSite?.id;
    final vendorsAsync = ref.watch(dropdownProvider((category: DropdownCategory.vendor, siteId: siteId)));
    final productsAsync = ref.watch(dropdownProvider((category: DropdownCategory.product, siteId: siteId)));
    final unitsAsync = ref.watch(dropdownProvider((category: DropdownCategory.metricUnit, siteId: siteId)));
    final stockState = ref.watch(stockProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: const Text('Add Product'),
        actions: [
          if (isLocked)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Icon(Icons.lock_rounded, color: AppColors.pending, size: 20),
            ),
          if (widget.existingTransaction != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: StatusBadge(
                status: widget.existingTransaction!.status,
                compact: true,
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Locked banner
            if (isLocked)
              const LockedFormBanner()
                  .animate()
                  .fadeIn()
                  .slideY(begin: -0.1),

            // ── Date Picker ──
            GestureDetector(
              onTap: _pickDate,
              child: AbsorbPointer(
                child: TextFormField(
                  readOnly: true,
                  controller: TextEditingController(
                    text: DateFormat('dd MMM yyyy').format(_selectedDate),
                  ),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Date',
                    prefixIcon: const Icon(Icons.calendar_today_rounded,
                        color: AppColors.textTertiary, size: 20),
                    suffixIcon: isLocked
                        ? null
                        : const Icon(Icons.arrow_drop_down,
                            color: AppColors.textTertiary),
                  ),
                ),
              ),
            ).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 18),

            // ── Vendor Dropdown ──
            vendorsAsync.when(
              loading: () => _shimmerField('Loading vendors...'),
              error: (_, __) => _errorField('Failed to load vendors'),
              data: (vendors) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedVendorId,
                    decoration: const InputDecoration(
                      labelText: 'Vendor Name',
                      prefixIcon: Icon(Icons.store_rounded,
                          color: AppColors.textTertiary, size: 20),
                    ),
                    dropdownColor: AppColors.cardDark,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    items: [
                      ...vendors.map((v) => DropdownMenuItem(
                            value: v.id,
                            child: Text(v.value),
                          )),
                      const DropdownMenuItem(
                        value: 'OTHER',
                        child: Text('Other (Unregistered Vendor)', style: TextStyle(fontStyle: FontStyle.italic)),
                      ),
                    ],
                    onChanged: isLocked ? null : (val) => setState(() => _selectedVendorId = val),
                    validator: (v) => Validators.dropdownRequired(v, 'Vendor'),
                  ),
                  if (_selectedVendorId == 'OTHER') ...[
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _unregisteredVendorController,
                      readOnly: isLocked,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Enter vendor name' : null,
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Enter Vendor Name',
                        prefixIcon: Icon(Icons.edit_note, color: AppColors.textTertiary, size: 20),
                      ),
                    ).animate().fadeIn(),
                  ],
                ],
              ),
            ).animate().fadeIn(delay: 200.ms),

            const SizedBox(height: 18),

            // ── Product Dropdown ──
            productsAsync.when(
              loading: () => _shimmerField('Loading products...'),
              error: (_, __) => _errorField('Failed to load products'),
              data: (products) => DropdownButtonFormField<String>(
                value: _selectedProductId,
                decoration: const InputDecoration(
                  labelText: 'Product Name',
                  prefixIcon: Icon(Icons.category_rounded,
                      color: AppColors.textTertiary, size: 20),
                ),
                dropdownColor: AppColors.cardDark,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
                items: products
                    .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(p.value),
                        ))
                    .toList(),
                onChanged: isLocked ? null : (val) => setState(() => _selectedProductId = val),
                validator: (v) => Validators.dropdownRequired(v, 'Product'),
              ),
            ).animate().fadeIn(delay: 300.ms),

            const SizedBox(height: 18),

            // ── Metric Unit Dropdown ──
            unitsAsync.when(
              loading: () => _shimmerField('Loading units...'),
              error: (_, __) => _errorField('Failed to load units'),
              data: (units) => DropdownButtonFormField<String>(
                value: _selectedMetricUnitId,
                decoration: const InputDecoration(
                  labelText: 'Metric Unit',
                  prefixIcon: Icon(Icons.straighten_rounded,
                      color: AppColors.textTertiary, size: 20),
                ),
                dropdownColor: AppColors.cardDark,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
                items: units
                    .map((u) => DropdownMenuItem(
                          value: u.id,
                          child: Text(u.value),
                        ))
                    .toList(),
                onChanged: isLocked ? null : (val) => setState(() => _selectedMetricUnitId = val),
                validator: (v) => Validators.dropdownRequired(v, 'Unit'),
              ),
            ).animate().fadeIn(delay: 350.ms),

            const SizedBox(height: 18),

            // ── Quantity ──
            TextFormField(
              controller: _quantityController,
              readOnly: isLocked,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => Validators.positiveNumber(v, 'Quantity'),
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Quantity',
                prefixIcon: Icon(Icons.production_quantity_limits_rounded,
                    color: AppColors.textTertiary, size: 20),
              ),
            ).animate().fadeIn(delay: 400.ms),

            const SizedBox(height: 18),

            // ── Rate ──
            TextFormField(
              controller: _rateController,
              readOnly: isLocked,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => Validators.positiveNumber(v, 'Rate'),
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Rate (per unit)',
                prefixIcon: Icon(Icons.currency_rupee_rounded,
                    color: AppColors.textTertiary, size: 20),
              ),
            ).animate().fadeIn(delay: 450.ms),

            const SizedBox(height: 18),

            // ── SGST & IGST Row ──
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _sgstController,
                    readOnly: isLocked,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) => Validators.nonNegativeNumber(v, 'SGST'),
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'SGST (%)',
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextFormField(
                    controller: _igstController,
                    readOnly: isLocked,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) => Validators.nonNegativeNumber(v, 'IGST'),
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'IGST (%)',
                    ),
                  ),
                ),
              ],
            ).animate().fadeIn(delay: 500.ms),

            const SizedBox(height: 24),

            // ── Final Amount Display ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.12),
                    AppColors.secondary.withOpacity(0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Final Amount',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '₹ ${NumberFormat('#,##,###.##').format(_finalAmount)}',
                    style: AppTextStyles.h2.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 550.ms),

            const SizedBox(height: 18),

            // ── Remarks ──
            TextFormField(
              controller: _remarksController,
              readOnly: isLocked,
              maxLines: 3,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Remarks (Optional)',
                alignLabelWithHint: true,
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 48),
                  child: Icon(Icons.notes_rounded,
                      color: AppColors.textTertiary, size: 20),
                ),
              ),
            ).animate().fadeIn(delay: 600.ms),

            const SizedBox(height: 18),

            // ── Attachments ──
            PhotoPickerWidget(
              initialPhotoUrls: _isEditMode ? _transaction!.photoUrls : [],
              isReadOnly: isLocked,
              onPhotosChanged: (photos) {
                setState(() {
                  _selectedPhotos = photos;
                });
              },
            ).animate().fadeIn(delay: 650.ms),

            const SizedBox(height: 32),

            // ── Submit Button ──
            if (!isLocked)
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: stockState.isLoading ? null : _handleSubmit,
                  icon: stockState.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(stockState.isLoading
                      ? 'Submitting...'
                      : 'Submit to Accounts'),
                ),
              ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.1),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _shimmerField(String label) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.cardDarkAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 16),
      child: Text(label,
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary)),
    );
  }

  Widget _errorField(String label) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.rejectedSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 16),
      child: Text(label,
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.rejected)),
    );
  }
}
