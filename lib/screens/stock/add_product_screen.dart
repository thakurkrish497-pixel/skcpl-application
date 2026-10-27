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
import '../../widgets/offline_indicator.dart';
import '../../widgets/responsive_layout.dart';
import '../../providers/site_staff_provider.dart';
import '../../providers/role_access_provider.dart';
import '../../services/dropdown_service.dart';
import '../../models/site_staff_model.dart';

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
  final _customProductController = TextEditingController();
  final _customUnitController = TextEditingController();
  final _billNoController = TextEditingController();

  // Selected dropdown values
  String? _selectedVendorId;
  String? _selectedProductId;
  String? _selectedMetricUnitId;
  DateTime _selectedDate = DateTime.now();

  // Photos
  List<PickedPhoto> _selectedPhotos = [];
  bool _isSubmitting = false;

  // Calculated
  double _finalAmount = 0.0;

  bool get _isEditMode => widget.existingTransaction != null;
  StockTransactionModel? get _transaction => widget.existingTransaction;

  /// Whether the form should be locked (read-only)
  bool get isLocked {
    final activeStaff = ref.read(activeStaffProvider);
    if (activeStaff != null && !activeStaff.hasModule(StaffModule.stock)) return true;
    if (widget.existingTransaction == null) return false;
    if (widget.existingTransaction!.status == TransactionStatus.approved) return true;
    final user = ref.read(authProvider);
    if (user.isAdmin || user.isAccounts) return false;
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
      _remarksController.text = tx.cleanRemarks ?? '';
      _billNoController.text = tx.billNo ?? '';

      if (tx.unregisteredVendor != null && tx.unregisteredVendor!.isNotEmpty) {
        _selectedVendorId = 'OTHER';
        _unregisteredVendorController.text = tx.unregisteredVendor!;
      }
      if (tx.customProduct != null || tx.productId == DropdownService.otherProductPlaceholderId) {
        _selectedProductId = 'OTHER';
        _customProductController.text = tx.customProduct ?? '';
      }
      if (tx.customMetricUnit != null || tx.metricUnitId == DropdownService.otherUnitPlaceholderId) {
        _selectedMetricUnitId = 'OTHER';
        _customUnitController.text = tx.customMetricUnit ?? '';
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
    final siteId = widget.existingTransaction?.siteId ?? authState.activeSite?.id;
    final userId = authState.user?.id;

    if (siteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: No site associated with this transaction')),
      );
      return;
    }

    final activeStaff = ref.read(activeStaffProvider);
    if (activeStaff != null && !activeStaff.hasModule(StaffModule.stock)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Access Denied: Stock management is turned off for ${activeStaff.name}.'),
          backgroundColor: AppColors.rejected,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      String? encodedRemarks = _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim();
      if (_selectedProductId == 'OTHER' && _customProductController.text.trim().isNotEmpty) {
        final tag = '[Material: ${_customProductController.text.trim()}]';
        encodedRemarks = encodedRemarks == null ? tag : '$tag $encodedRemarks';
      }
      if (_selectedMetricUnitId == 'OTHER' && _customUnitController.text.trim().isNotEmpty) {
        final tag = '[Unit: ${_customUnitController.text.trim()}]';
        encodedRemarks = encodedRemarks == null ? tag : '$tag $encodedRemarks';
      }

      final bill = _billNoController.text.trim();
      final activeStaff = ref.read(activeStaffProvider);
      final roleAccess = ref.read(roleAccessProvider);
      final phCanApproveStock = roleAccess.projectHeadCanApproveStock;
      final accountsCanApproveStock = roleAccess.accountsCanApproveStock;

      if (!_isEditMode) {
        if (activeStaff != null) {
          final staffTag = '[By: ${activeStaff.name} (${activeStaff.designation ?? activeStaff.role.displayName})]';
          encodedRemarks = encodedRemarks == null ? staffTag : '$staffTag $encodedRemarks';
        }
        if (phCanApproveStock) {
          const supTag = '[Project Head Review: Pending] [Supervisor Review: Pending]';
          encodedRemarks = encodedRemarks == null ? supTag : '$encodedRemarks $supTag';
        } else {
          const supTag = '[Project Head Review: Bypassed by Admin Policy]';
          encodedRemarks = encodedRemarks == null ? supTag : '$encodedRemarks $supTag';
        }
      } else if (activeStaff != null) {
        final staffTag = '[By: ${activeStaff.name} (${activeStaff.designation ?? activeStaff.role.displayName})]';
        encodedRemarks = encodedRemarks == null ? staffTag : '$staffTag $encodedRemarks';
      }
      if (bill.isNotEmpty) {
        final tag = '[Bill: $bill]';
        encodedRemarks = encodedRemarks == null ? tag : '$tag $encodedRemarks';
      }

      final effectiveProductId = _selectedProductId == 'OTHER'
          ? DropdownService.otherProductPlaceholderId
          : _selectedProductId!;

      final effectiveMetricUnitId = _selectedMetricUnitId == 'OTHER'
          ? DropdownService.otherUnitPlaceholderId
          : _selectedMetricUnitId!;

      final effectiveVendorId = _selectedVendorId == 'OTHER'
          ? null
          : _selectedVendorId;

      final effectiveUnregisteredVendor = _selectedVendorId == 'OTHER'
          ? _unregisteredVendorController.text.trim()
          : null;

      TransactionStatus initialStatus = TransactionStatus.pendingAccounts;
      if (!phCanApproveStock && !accountsCanApproveStock) {
        // Both Project Head & Accounts bypassed -> direct to Admin
        initialStatus = TransactionStatus.pendingAdmin;
      }

      StockTransactionModel submission;

      if (_isEditMode) {
        submission = StockTransactionModel(
          id: _transaction!.id,
          siteId: _transaction!.siteId,
          submittedBy: _transaction!.submittedBy,
          type: TransactionType.inbound,
          date: _selectedDate,
          vendorId: effectiveVendorId,
          productId: effectiveProductId,
          metricUnitId: effectiveMetricUnitId,
          quantity: double.parse(_quantityController.text),
          rate: double.tryParse(_rateController.text),
          sgst: double.tryParse(_sgstController.text) ?? 0,
          igst: double.tryParse(_igstController.text) ?? 0,
          finalAmount: _finalAmount,
          remarks: encodedRemarks,
          unregisteredVendor: effectiveUnregisteredVendor,
          status: _transaction!.status,
          photoUrls: _transaction!.photoUrls,
        );
      } else {
        submission = StockTransactionModel(
          siteId: siteId,
          submittedBy: userId,
          type: TransactionType.inbound,
          date: _selectedDate,
          vendorId: effectiveVendorId,
          productId: effectiveProductId,
          metricUnitId: effectiveMetricUnitId,
          quantity: double.parse(_quantityController.text),
          rate: double.tryParse(_rateController.text),
          sgst: double.tryParse(_sgstController.text) ?? 0,
          igst: double.tryParse(_igstController.text) ?? 0,
          finalAmount: _finalAmount,
          remarks: encodedRemarks,
          unregisteredVendor: effectiveUnregisteredVendor,
          status: initialStatus,
          photoUrls: [],
        );
      }

      List<String> uploadedUrls = List.from(submission.photoUrls);
      if (_selectedPhotos.isNotEmpty) {
        final storageService = ref.read(storageServiceProvider);
        for (var photo in _selectedPhotos) {
          try {
            final url = await storageService.uploadPhotoBytes(photo.bytes, fileName: photo.name);
            uploadedUrls.add(url);
          } catch (uploadError) {
            debugPrint('Photo upload failed: $uploadError');
          }
        }
        submission = submission.copyWith(photoUrls: uploadedUrls);
      }

      final success = _isEditMode
          ? await ref.read(stockProvider.notifier).updateTransaction(submission)
          : await ref.read(stockProvider.notifier).submitTransaction(submission);

      final stockError = ref.read(stockProvider).error;

      if (success && mounted) {
        final isOffline = stockError == 'OFFLINE_SAVED';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isOffline
                  ? 'Saved offline! Will sync automatically when internet is back.'
                  : (_isEditMode
                      ? 'Changes saved successfully!'
                      : 'Submitted successfully!'),
            ),
            backgroundColor: isOffline ? AppColors.pending : AppColors.approved,
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Submission error: $e'),
            backgroundColor: AppColors.rejected,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _rateController.dispose();
    _sgstController.dispose();
    _igstController.dispose();
    _remarksController.dispose();
    _unregisteredVendorController.dispose();
    _customProductController.dispose();
    _customUnitController.dispose();
    _billNoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final siteId = widget.existingTransaction?.siteId ?? ref.watch(authProvider).activeSite?.id;
    final vendorsAsync = ref.watch(dropdownProvider((category: DropdownCategory.vendor, siteId: siteId)));
    final productsAsync = ref.watch(dropdownProvider((category: DropdownCategory.product, siteId: siteId)));
    final unitsAsync = ref.watch(dropdownProvider((category: DropdownCategory.metricUnit, siteId: siteId)));
    final stockState = ref.watch(stockProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: const Text('Add Product'),
        actions: [
          const OfflineSyncButton(),
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
      body: ResponsiveContainer(
        maxWidth: 720,
        child: Form(
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
                    text: DateFormat('dd MMM yyyy (EEEE)').format(_selectedDate),
                  ),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Date (Optional / Defaults to today)',
                    prefixIcon: const Icon(Icons.calendar_today_rounded,
                        color: AppColors.primary, size: 20),
                    suffixIcon: isLocked
                        ? null
                        : const Icon(Icons.arrow_drop_down,
                            color: AppColors.textTertiary),
                  ),
                ),
              ),
            ).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 18),

            // ── Vendor / Party Dropdown ──
            vendorsAsync.when(
              loading: () => _shimmerField('Loading vendors...'),
              error: (_, __) => _errorField('Failed to load vendors'),
              data: (vendors) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedVendorId,
                    decoration: const InputDecoration(
                      labelText: 'Vendor / Party Name',
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
                        child: Text('Other (Unregistered Party / Vendor)', style: TextStyle(fontStyle: FontStyle.italic)),
                      ),
                    ],
                    onChanged: isLocked ? null : (val) => setState(() => _selectedVendorId = val),
                    validator: (v) => Validators.dropdownRequired(v, 'Vendor / Party'),
                  ),
                  if (_selectedVendorId == 'OTHER') ...[
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _unregisteredVendorController,
                      readOnly: isLocked,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Enter vendor / party name' : null,
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Enter Vendor / Party Name',
                        prefixIcon: Icon(Icons.edit_note, color: AppColors.textTertiary, size: 20),
                      ),
                    ).animate().fadeIn(),
                  ],
                ],
              ),
            ).animate().fadeIn(delay: 200.ms),

            const SizedBox(height: 18),

            // ── Bill / Challan No. (Optional) ──
            TextFormField(
              controller: _billNoController,
              readOnly: isLocked,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Bill / Challan No. (Optional)',
                hintText: 'e.g. INV-2024-89 / Challan #12',
                prefixIcon: Icon(Icons.receipt_long_rounded, color: AppColors.textTertiary, size: 20),
              ),
            ).animate().fadeIn(delay: 220.ms),

            const SizedBox(height: 18),

            // ── Product Dropdown ──
            productsAsync.when(
              loading: () => _shimmerField('Loading products...'),
              error: (_, __) => _errorField('Failed to load products'),
              data: (products) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedProductId,
                    decoration: const InputDecoration(
                      labelText: 'Product / Material Name',
                      prefixIcon: Icon(Icons.category_rounded,
                          color: AppColors.textTertiary, size: 20),
                    ),
                    dropdownColor: AppColors.cardDark,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    items: [
                      ...products.map((p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(p.value),
                          )),
                      const DropdownMenuItem(
                        value: 'OTHER',
                        child: Text(
                          '+ Other / Enter Manually',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                    onChanged: isLocked ? null : (val) => setState(() => _selectedProductId = val),
                    validator: (v) => Validators.dropdownRequired(v, 'Product'),
                  ),
                  if (_selectedProductId == 'OTHER') ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _customProductController,
                      readOnly: isLocked,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Please enter product name'
                          : null,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Enter Product / Material Name',
                        hintText: 'e.g. Birla White Cement, PVC Pipe 4"',
                        prefixIcon: Icon(Icons.edit_note_rounded,
                            color: AppColors.primary, size: 20),
                      ),
                    ).animate().fadeIn(),
                  ],
                ],
              ),
            ).animate().fadeIn(delay: 300.ms),

            const SizedBox(height: 18),

            // ── Metric Unit Dropdown ──
            unitsAsync.when(
              loading: () => _shimmerField('Loading units...'),
              error: (_, __) => _errorField('Failed to load units'),
              data: (units) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
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
                    items: [
                      ...units.map((u) => DropdownMenuItem(
                            value: u.id,
                            child: Text(u.value),
                          )),
                      const DropdownMenuItem(
                        value: 'OTHER',
                        child: Text(
                          '+ Other / Enter Manually',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                    onChanged: isLocked ? null : (val) => setState(() => _selectedMetricUnitId = val),
                    validator: (v) => Validators.dropdownRequired(v, 'Unit'),
                  ),
                  if (_selectedMetricUnitId == 'OTHER') ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _customUnitController,
                      readOnly: isLocked,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Please enter metric unit'
                          : null,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Enter Metric Unit',
                        hintText: 'e.g. Brass, Bundles, Coil, Sq.ft',
                        prefixIcon: Icon(Icons.edit_note_rounded,
                            color: AppColors.primary, size: 20),
                      ),
                    ).animate().fadeIn(),
                  ],
                ],
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
                  onPressed: (_isSubmitting || stockState.isLoading) ? null : _handleSubmit,
                  icon: (_isSubmitting || stockState.isLoading)
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text((_isSubmitting || stockState.isLoading)
                      ? (_isEditMode ? 'Saving Changes...' : 'Submitting...')
                      : (_isEditMode ? 'Save Changes' : 'Submit')),
                ),
              ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.1),

            const SizedBox(height: 24),
          ],
        ),
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
