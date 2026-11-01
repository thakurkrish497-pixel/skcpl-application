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
import '../../widgets/voice_input_field.dart';

/// Use Product (Outbound) form — simplified, no vendor/rate/tax
class UseProductScreen extends ConsumerStatefulWidget {
  final StockTransactionModel? existingTransaction;

  const UseProductScreen({super.key, this.existingTransaction});

  @override
  ConsumerState<UseProductScreen> createState() => _UseProductScreenState();
}

class _UseProductScreenState extends ConsumerState<UseProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _remarksController = TextEditingController();
  final _customProductController = TextEditingController();
  final _customUnitController = TextEditingController();
  final _billNoController = TextEditingController();

  String? _selectedProductId;
  String? _selectedMetricUnitId;
  DateTime _selectedDate = DateTime.now();
  List<PickedPhoto> _selectedPhotos = [];
  bool _isSubmitting = false;

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
    _quantityController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final siteId = widget.existingTransaction?.siteId ?? ref.read(authProvider).activeSite?.id;
      if (siteId != null) {
        ref.read(stockProvider.notifier).loadCurrentStock(siteId);
      }
    });
    final tx = widget.existingTransaction;
    if (tx != null) {
      _selectedProductId = tx.productId;
      _selectedMetricUnitId = tx.metricUnitId;
      _selectedDate = tx.date;
      _quantityController.text = tx.quantity.toString();
      _remarksController.text = tx.cleanRemarks ?? '';
      _billNoController.text = tx.billNo ?? '';

      if (tx.customProduct != null || tx.productId == DropdownService.otherProductPlaceholderId) {
        _selectedProductId = 'OTHER';
        _customProductController.text = tx.customProduct ?? '';
      }
      if (tx.customMetricUnit != null || tx.metricUnitId == DropdownService.otherUnitPlaceholderId) {
        _selectedMetricUnitId = 'OTHER';
        _customUnitController.text = tx.customMetricUnit ?? '';
      }
    }
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
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProductId == null || _selectedMetricUnitId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select all required fields')),
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
          content: Text('Access Denied: Stock usage is turned off for ${activeStaff.name}.'),
          backgroundColor: AppColors.rejected,
        ),
      );
      return;
    }

    final quantity = double.parse(_quantityController.text);

    // Stock Validation
    if (widget.existingTransaction == null && _selectedProductId != 'OTHER') {
      final stockState = ref.read(stockProvider);
      final stockItem = stockState.currentStock.where((s) => s['product_id'] == _selectedProductId).firstOrNull;
      final currentStock = stockItem?['current_stock'] ?? 0;
      if (quantity > currentStock) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Not enough stock! Available: $currentStock'),
            backgroundColor: AppColors.rejected,
          ),
        );
        return;
      }
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

      if (widget.existingTransaction == null) {
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

      TransactionStatus initialStatus = TransactionStatus.pendingAccounts;
      if (!phCanApproveStock && !accountsCanApproveStock) {
        // Both Project Head & Accounts bypassed -> direct to Admin
        initialStatus = TransactionStatus.pendingAdmin;
      }

      StockTransactionModel transaction;

      if (widget.existingTransaction == null) {
        transaction = StockTransactionModel(
          siteId: siteId,
          submittedBy: userId,
          type: TransactionType.outbound,
          date: _selectedDate,
          productId: effectiveProductId,
          metricUnitId: effectiveMetricUnitId,
          quantity: double.parse(_quantityController.text),
          remarks: encodedRemarks,
          status: initialStatus,
        );
      } else {
        transaction = StockTransactionModel(
          id: widget.existingTransaction!.id,
          siteId: widget.existingTransaction!.siteId,
          submittedBy: widget.existingTransaction!.submittedBy,
          type: TransactionType.outbound,
          date: _selectedDate,
          productId: effectiveProductId,
          metricUnitId: effectiveMetricUnitId,
          quantity: double.parse(_quantityController.text),
          remarks: encodedRemarks,
          status: widget.existingTransaction!.status,
          photoUrls: widget.existingTransaction!.photoUrls,
        );
      }

      List<String> uploadedUrls = List.from(transaction.photoUrls);
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
        transaction = transaction.copyWith(photoUrls: uploadedUrls);
      }

      final success = widget.existingTransaction == null
          ? await ref.read(stockProvider.notifier).submitTransaction(transaction)
          : await ref.read(stockProvider.notifier).updateTransaction(transaction);

      final stockError = ref.read(stockProvider).error;

      if (success && mounted) {
        final isOffline = stockError == 'OFFLINE_SAVED';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isOffline
                  ? 'Saved offline! Will sync automatically when internet is back.'
                  : (widget.existingTransaction != null
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
            content: Text('Error: $e'),
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
    _remarksController.dispose();
    _customProductController.dispose();
    _customUnitController.dispose();
    _billNoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final siteId = widget.existingTransaction?.siteId ?? ref.watch(authProvider).activeSite?.id;
    final productsAsync = ref.watch(dropdownProvider((category: DropdownCategory.product, siteId: siteId)));
    final unitsAsync = ref.watch(dropdownProvider((category: DropdownCategory.metricUnit, siteId: siteId)));
    final stockState = ref.watch(stockProvider);
    final isLight = AppColors.isLight;

    final stockItem = (_selectedProductId != null && _selectedProductId != 'OTHER')
        ? stockState.currentStock.where((s) => s['product_id'] == _selectedProductId).firstOrNull
        : null;
    final availableStock = (stockItem?['current_stock'] as num?)?.toDouble() ?? 0.0;
    final totalInbound = (stockItem?['total_inbound'] as num?)?.toDouble() ?? 0.0;
    final totalOutbound = (stockItem?['total_outbound'] as num?)?.toDouble() ?? 0.0;
    final unitName = stockItem?['metric_unit'] ?? '';
    final enteredQty = double.tryParse(_quantityController.text) ?? 0.0;

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Text(widget.existingTransaction != null ? 'Edit Used Product' : 'Use Product'),
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
            if (isLocked)
              const LockedFormBanner().animate().fadeIn(),

            // Date
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

            // ── Issue Slip / Ref No. (Optional) ──
            TextFormField(
              controller: _billNoController,
              readOnly: isLocked,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Issue Slip / Reference No. (Optional)',
                hintText: 'e.g. SLIP-102 / Work Order #4',
                prefixIcon: Icon(Icons.receipt_long_rounded, color: AppColors.textTertiary, size: 20),
              ),
            ).animate().fadeIn(delay: 150.ms),

            const SizedBox(height: 18),

            // Product
            productsAsync.when(
              loading: () => _placeholder('Loading products...'),
              error: (_, __) => _placeholder('Failed to load products'),
              data: (products) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
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
                  if (stockItem != null) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: availableStock > 0
                            ? (isLight ? const Color(0xFFDCFCE7) : const Color(0xFF064E3B).withValues(alpha: 0.4))
                            : (isLight ? const Color(0xFFFEE2E2) : const Color(0xFF7F1D1D).withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: availableStock > 0 ? const Color(0xFF10B981) : AppColors.rejected,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            availableStock > 0 ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                            color: availableStock > 0 ? const Color(0xFF10B981) : AppColors.rejected,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Current Stock in Hand:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isLight ? AppColors.textPrimaryLight : AppColors.textPrimaryDark,
                                      ),
                                    ),
                                    Text(
                                      '$availableStock $unitName',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: availableStock > 0
                                            ? (isLight ? const Color(0xFF047857) : const Color(0xFF34D399))
                                            : AppColors.rejected,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Received on site: $totalInbound $unitName • Previously used: $totalOutbound $unitName',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isLight ? AppColors.textSecondaryLight : Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(),
                  ],
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
                      decoration: InputDecoration(
                        labelText: 'Enter Product / Material Name',
                        hintText: 'e.g. Birla White Cement, PVC Pipe 4"',
                        prefixIcon: const Icon(Icons.edit_note_rounded,
                            color: AppColors.primary, size: 20),
                        suffixIcon: isLocked
                            ? null
                            : VoiceInputIconButton(
                                controller: _customProductController,
                                fieldLabel: 'Product Name',
                              ),
                      ),
                    ).animate().fadeIn(),
                  ],
                ],
              ),
            ).animate().fadeIn(delay: 200.ms),

            const SizedBox(height: 18),

            // Metric Unit
            unitsAsync.when(
              loading: () => _placeholder('Loading units...'),
              error: (_, __) => _placeholder('Failed to load units'),
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
                        hintText: 'e.g. Bags, Quintal, Meter, Nos',
                        prefixIcon: Icon(Icons.straighten_rounded,
                            color: AppColors.primary, size: 20),
                      ),
                    ).animate().fadeIn(),
                  ],
                ],
              ),
            ).animate().fadeIn(delay: 300.ms),

            const SizedBox(height: 18),

            // Quantity
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _quantityController,
                  readOnly: isLocked,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) => Validators.positiveNumber(v, 'Quantity'),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Quantity Used',
                    prefixIcon: const Icon(Icons.remove_circle_outline_rounded,
                        color: AppColors.textTertiary, size: 20),
                    suffixText: unitName.isNotEmpty ? unitName : null,
                  ),
                ),
                if (stockItem != null && enteredQty > availableStock) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.rejected.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.rejected),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.rejected, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Warning: Entered quantity ($enteredQty) exceeds current stock in hand ($availableStock $unitName)!',
                            style: const TextStyle(color: AppColors.rejected, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (stockItem != null && enteredQty > 0) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      'Remaining stock after this use: ${(availableStock - enteredQty).toStringAsFixed(1)} $unitName',
                      style: TextStyle(
                        fontSize: 11,
                        color: isLight ? const Color(0xFF047857) : const Color(0xFF34D399),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ).animate().fadeIn(delay: 400.ms),

            const SizedBox(height: 18),

            // Remarks
            TextFormField(
              controller: _remarksController,
              readOnly: isLocked,
              maxLines: 3,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: 'Remarks (Optional)',
                alignLabelWithHint: true,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 48),
                  child: Icon(Icons.notes_rounded,
                      color: AppColors.textTertiary, size: 20),
                ),
                suffixIcon: isLocked
                    ? null
                    : VoiceInputIconButton(
                        controller: _remarksController,
                        fieldLabel: 'Remarks',
                      ),
              ),
            ).animate().fadeIn(delay: 500.ms),

            const SizedBox(height: 18),

            PhotoPickerWidget(
              initialPhotoUrls: widget.existingTransaction?.photoUrls ?? [],
              isReadOnly: isLocked,
              onPhotosChanged: (photos) {
                setState(() {
                  _selectedPhotos = photos;
                });
              },
            ).animate().fadeIn(delay: 550.ms),

            const SizedBox(height: 32),

            // Submit
            if (!isLocked)
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: (_isSubmitting || stockState.isLoading) ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                  ),
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
                      ? (widget.existingTransaction != null ? 'Saving Changes...' : 'Submitting...')
                      : (widget.existingTransaction != null ? 'Save Changes' : 'Submit')),
                ),
              ).animate().fadeIn(delay: 600.ms),

            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
    );
  }

  Widget _placeholder(String text) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.cardDarkAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 16),
      child: Text(text,
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary)),
    );
  }
}
