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

/// Staged draft for multi-material Inward challans
class StockInwardDraft {
  final String id;
  final String productId;
  final String? customProduct;
  final String productName;
  final String metricUnitId;
  final String? customMetricUnit;
  final String metricUnitName;
  final double quantity;
  final double? rate;
  final double sgst;
  final double igst;
  final double? finalAmount;
  final String? remarks;

  StockInwardDraft({
    required this.id,
    required this.productId,
    this.customProduct,
    required this.productName,
    required this.metricUnitId,
    this.customMetricUnit,
    required this.metricUnitName,
    required this.quantity,
    this.rate,
    this.sgst = 0,
    this.igst = 0,
    this.finalAmount,
    this.remarks,
  });
}

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

  // Staged multi-material batch
  final List<StockInwardDraft> _stagedMaterials = [];
  Key _photoPickerKey = UniqueKey();

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final siteId = widget.existingTransaction?.siteId ?? ref.read(authProvider).activeSite?.id;
      if (siteId != null) {
        ref.read(stockProvider.notifier).loadCurrentStock(siteId);
      }
    });

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

  bool get _hasCurrentMaterialData {
    final qty = double.tryParse(_quantityController.text) ?? 0;
    return qty > 0;
  }

  String _getProductName(String? id, List<DropdownItemModel> products) {
    if (id == 'OTHER') {
      return _customProductController.text.trim().isNotEmpty
          ? _customProductController.text.trim()
          : 'Manual Material';
    }
    final match = products.where((p) => p.id == id).firstOrNull;
    return match?.value ?? 'Material';
  }

  String _getUnitName(String? id, List<DropdownItemModel> units) {
    if (id == 'OTHER') {
      return _customUnitController.text.trim().isNotEmpty
          ? _customUnitController.text.trim()
          : 'units';
    }
    final match = units.where((u) => u.id == id).firstOrNull;
    return match?.value ?? 'units';
  }

  bool _stageCurrentMaterial({
    bool silent = false,
    List<DropdownItemModel> products = const [],
    List<DropdownItemModel> units = const [],
  }) {
    final qty = double.tryParse(_quantityController.text) ?? 0;
    if (qty <= 0) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid quantity greater than 0'),
            backgroundColor: AppColors.rejected,
          ),
        );
      }
      return false;
    }

    if (_selectedProductId == null) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a Material / Product'),
            backgroundColor: AppColors.rejected,
          ),
        );
      }
      return false;
    }

    if (_selectedProductId == 'OTHER' && _customProductController.text.trim().isEmpty) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter custom material name'),
            backgroundColor: AppColors.rejected,
          ),
        );
      }
      return false;
    }

    if (_selectedMetricUnitId == null) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a Metric Unit'),
            backgroundColor: AppColors.rejected,
          ),
        );
      }
      return false;
    }

    if (_selectedMetricUnitId == 'OTHER' && _customUnitController.text.trim().isEmpty) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter custom unit name'),
            backgroundColor: AppColors.rejected,
          ),
        );
      }
      return false;
    }

    final pName = _getProductName(_selectedProductId, products);
    final uName = _getUnitName(_selectedMetricUnitId, units);

    final draft = StockInwardDraft(
      id: 'DRAFT-IN-${DateTime.now().microsecondsSinceEpoch}',
      productId: _selectedProductId!,
      customProduct: _customProductController.text.trim().isNotEmpty ? _customProductController.text.trim() : null,
      productName: pName,
      metricUnitId: _selectedMetricUnitId!,
      customMetricUnit: _customUnitController.text.trim().isNotEmpty ? _customUnitController.text.trim() : null,
      metricUnitName: uName,
      quantity: qty,
      rate: double.tryParse(_rateController.text),
      sgst: double.tryParse(_sgstController.text) ?? 0,
      igst: double.tryParse(_igstController.text) ?? 0,
      finalAmount: _finalAmount > 0 ? _finalAmount : null,
      remarks: _remarksController.text.trim().isNotEmpty ? _remarksController.text.trim() : null,
    );

    setState(() {
      _stagedMaterials.add(draft);
      _quantityController.clear();
      _rateController.clear();
      _sgstController.clear();
      _igstController.clear();
      _remarksController.clear();
      _customProductController.clear();
      _customUnitController.clear();
      _selectedProductId = null;
      _selectedMetricUnitId = null;
      _finalAmount = 0.0;
    });

    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added to Challan! (${_stagedMaterials.length} materials staged)'),
          backgroundColor: AppColors.approved,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    return true;
  }

  void _showBatchSuccessDialog(int count, double totalValue) {
    final currencyFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.approved.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: AppColors.approved, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                'Inward Batch Recorded!',
                style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                '$count ${count == 1 ? "material" : "materials"} inwarded'
                '${totalValue > 0 ? " • Total: ${currencyFmt.format(totalValue)}" : ""}',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: const Text('View History'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.divider),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pushNamed(context, '/stock-history');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('+ Receive More'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        // Clears bill/vendor inputs ready for next challan without re-login!
                        setState(() {
                          _billNoController.clear();
                          _unregisteredVendorController.clear();
                          _selectedVendorId = null;
                          _selectedPhotos = [];
                          _photoPickerKey = UniqueKey();
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context, true);
                  }
                },
                child: const Text('Done & Return to Menu', style: TextStyle(color: AppColors.textTertiary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSubmit({
    List<DropdownItemModel> products = const [],
    List<DropdownItemModel> units = const [],
  }) async {
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

    final roleAccess = ref.read(roleAccessProvider);
    final phCanApproveStock = roleAccess.projectHeadCanApproveStock;
    final accountsCanApproveStock = roleAccess.accountsCanApproveStock;

    TransactionStatus initialStatus = TransactionStatus.pendingAccounts;
    if (!phCanApproveStock && !accountsCanApproveStock) {
      initialStatus = TransactionStatus.pendingAdmin;
    }

    // ── Single Edit Mode ──
    if (_isEditMode) {
      if (!_formKey.currentState!.validate()) return;
      if (_selectedVendorId == null || _selectedProductId == null || _selectedMetricUnitId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select all required dropdowns')),
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
        if (activeStaff != null) {
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
        final effectiveVendorId = _selectedVendorId == 'OTHER' ? null : _selectedVendorId;
        final effectiveUnregisteredVendor = _selectedVendorId == 'OTHER' ? _unregisteredVendorController.text.trim() : null;

        var submission = StockTransactionModel(
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

        final success = await ref.read(stockProvider.notifier).updateTransaction(submission);
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Changes saved successfully!'), backgroundColor: AppColors.approved),
          );
          Navigator.pop(context, true);
        }
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
      return;
    }

    // ── Multi-Material Batch Mode ──
    if (_selectedVendorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or specify a Vendor for this challan.')),
      );
      return;
    }

    // If current inputs have material info, auto-stage it
    if (_hasCurrentMaterialData) {
      final staged = _stageCurrentMaterial(silent: true, products: products, units: units);
      if (!staged) return; // Validation error
    }

    if (_stagedMaterials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter at least one material with quantity.'),
          backgroundColor: AppColors.rejected,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final batchId = 'BATCH-${DateTime.now().millisecondsSinceEpoch}';
      final storageService = ref.read(storageServiceProvider);

      // Upload shared challan photos
      List<String> uploadedUrls = [];
      if (_selectedPhotos.isNotEmpty) {
        for (var photo in _selectedPhotos) {
          try {
            final url = await storageService.uploadPhotoBytes(photo.bytes, fileName: photo.name);
            uploadedUrls.add(url);
          } catch (uploadError) {
            debugPrint('Challan photo upload failed: $uploadError');
          }
        }
      }

      final bill = _billNoController.text.trim();
      final effectiveVendorId = _selectedVendorId == 'OTHER' ? null : _selectedVendorId;
      final effectiveUnregisteredVendor = _selectedVendorId == 'OTHER' ? _unregisteredVendorController.text.trim() : null;

      int successCount = 0;
      double totalBatchValue = 0.0;

      for (final draft in _stagedMaterials) {
        String? encodedRemarks = draft.remarks;
        encodedRemarks = '[Batch: $batchId] ${encodedRemarks ?? ''}'.trim();

        if (draft.productId == 'OTHER' || draft.customProduct != null) {
          final tag = '[Material: ${draft.customProduct ?? "Material"}]';
          encodedRemarks = '$tag $encodedRemarks';
        }
        if (draft.metricUnitId == 'OTHER' || draft.customMetricUnit != null) {
          final tag = '[Unit: ${draft.customMetricUnit ?? "units"}]';
          encodedRemarks = '$tag $encodedRemarks';
        }
        if (activeStaff != null) {
          final staffTag = '[By: ${activeStaff.name} (${activeStaff.designation ?? activeStaff.role.displayName})]';
          encodedRemarks = '$staffTag $encodedRemarks';
        }
        if (phCanApproveStock) {
          const supTag = '[Project Head Review: Pending] [Supervisor Review: Pending]';
          encodedRemarks = '$encodedRemarks $supTag';
        } else {
          const supTag = '[Project Head Review: Bypassed by Admin Policy]';
          encodedRemarks = '$encodedRemarks $supTag';
        }
        if (bill.isNotEmpty) {
          final tag = '[Bill: $bill]';
          encodedRemarks = '$tag $encodedRemarks';
        }

        final effectiveProductId = draft.productId == 'OTHER'
            ? DropdownService.otherProductPlaceholderId
            : draft.productId;
        final effectiveMetricUnitId = draft.metricUnitId == 'OTHER'
            ? DropdownService.otherUnitPlaceholderId
            : draft.metricUnitId;

        final submission = StockTransactionModel(
          siteId: siteId,
          submittedBy: userId,
          type: TransactionType.inbound,
          date: _selectedDate,
          vendorId: effectiveVendorId,
          productId: effectiveProductId,
          metricUnitId: effectiveMetricUnitId,
          quantity: draft.quantity,
          rate: draft.rate,
          sgst: draft.sgst,
          igst: draft.igst,
          finalAmount: draft.finalAmount,
          remarks: encodedRemarks.trim(),
          unregisteredVendor: effectiveUnregisteredVendor,
          status: initialStatus,
          photoUrls: uploadedUrls,
        );

        final success = await ref.read(stockProvider.notifier).submitTransaction(submission);
        if (success) {
          successCount++;
          totalBatchValue += (draft.finalAmount ?? 0);
        }
      }

      if (mounted) {
        if (successCount > 0) {
          setState(() {
            _stagedMaterials.clear();
          });
          _showBatchSuccessDialog(successCount, totalBatchValue);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ref.read(stockProvider).error ?? 'Submission failed'),
              backgroundColor: AppColors.rejected,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.rejected),
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
    final isLight = AppColors.isLight;

    final stockItem = (_selectedProductId != null && _selectedProductId != 'OTHER')
        ? stockState.currentStock.where((s) => s['product_id'] == _selectedProductId).firstOrNull
        : null;
    final currentInHand = (stockItem?['current_stock'] as num?)?.toDouble() ?? 0.0;
    final unitName = stockItem?['metric_unit'] ?? '';
    final enteredQty = double.tryParse(_quantityController.text) ?? 0.0;

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
                      decoration: InputDecoration(
                        labelText: 'Enter Vendor / Party Name',
                        prefixIcon: const Icon(Icons.edit_note, color: AppColors.textTertiary, size: 20),
                        suffixIcon: isLocked
                            ? null
                            : VoiceInputIconButton(
                                controller: _unregisteredVendorController,
                                fieldLabel: 'Vendor Name',
                              ),
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
                  if (stockItem != null) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isLight ? const Color(0xFFF0FDF4) : const Color(0xFF064E3B).withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF10B981),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2_rounded, color: Color(0xFF10B981), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Already in Hand at Site:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isLight ? AppColors.textPrimaryLight : AppColors.textPrimaryDark,
                                  ),
                                ),
                                Text(
                                  '$currentInHand $unitName',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: isLight ? const Color(0xFF047857) : const Color(0xFF34D399),
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
                    labelText: 'Quantity',
                    prefixIcon: const Icon(Icons.production_quantity_limits_rounded,
                        color: AppColors.textTertiary, size: 20),
                    suffixText: unitName.isNotEmpty ? unitName : null,
                  ),
                ),
                if (stockItem != null && enteredQty > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      'New total stock on site: ${(currentInHand + enteredQty).toStringAsFixed(1)} $unitName (+${enteredQty})',
                      style: TextStyle(
                        fontSize: 11,
                        color: isLight ? const Color(0xFF047857) : const Color(0xFF34D399),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
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
            ).animate().fadeIn(delay: 600.ms),

            const SizedBox(height: 18),

            // ── Attachments ──
            PhotoPickerWidget(
              key: _photoPickerKey,
              initialPhotoUrls: _isEditMode ? _transaction!.photoUrls : [],
              isReadOnly: isLocked,
              onPhotosChanged: (photos) {
                setState(() {
                  _selectedPhotos = photos;
                });
              },
            ).animate().fadeIn(delay: 650.ms),

            const SizedBox(height: 24),

            // ── Staged Materials Tray (Multi-Material Challan) ──
            if (!_isEditMode)
              _buildStagedMaterialsTray(),

            // ── Action Buttons ──
            if (!isLocked) ...[
              if (_isEditMode)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: (_isSubmitting || stockState.isLoading)
                        ? null
                        : () => _handleSubmit(
                              products: productsAsync.valueOrNull ?? [],
                              units: unitsAsync.valueOrNull ?? [],
                            ),
                    icon: (_isSubmitting || stockState.isLoading)
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_rounded),
                    label: Text(
                      (_isSubmitting || stockState.isLoading) ? 'Saving Changes...' : 'Save Changes',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.1)
              else
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: (_isSubmitting || isLocked)
                              ? null
                              : () => _stageCurrentMaterial(
                                    products: productsAsync.valueOrNull ?? [],
                                    units: unitsAsync.valueOrNull ?? [],
                                  ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.primary, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.add_rounded, color: AppColors.primary, size: 20),
                          label: const Text(
                            '+ Add Item',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: (_isSubmitting || stockState.isLoading || isLocked)
                              ? null
                              : () => _handleSubmit(
                                    products: productsAsync.valueOrNull ?? [],
                                    units: unitsAsync.valueOrNull ?? [],
                                  ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: (_isSubmitting || stockState.isLoading)
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send_rounded, size: 20),
                          label: Text(
                            (_isSubmitting || stockState.isLoading)
                                ? 'Submitting Challan...'
                                : (_stagedMaterials.isNotEmpty
                                    ? 'Submit Challan (${_stagedMaterials.length + (_hasCurrentMaterialData ? 1 : 0)})'
                                    : 'Submit Inward'),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.1),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildStagedMaterialsTray() {
    if (_stagedMaterials.isEmpty) return const SizedBox.shrink();

    final currencyFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    final totalValue = _stagedMaterials.fold<double>(0.0, (sum, m) => sum + (m.finalAmount ?? 0.0));

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.inventory_2_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Materials in this Challan (${_stagedMaterials.length})',
                    style: AppTextStyles.h4.copyWith(fontSize: 15, color: AppColors.textPrimary),
                  ),
                ],
              ),
              if (totalValue > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    currencyFmt.format(totalValue),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 8),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _stagedMaterials.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final item = _stagedMaterials[idx];
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#${idx + 1}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productName,
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${item.quantity} ${item.metricUnitName}'
                            '${item.rate != null ? " @ ₹${item.rate}" : ""}'
                            '${item.finalAmount != null ? " • Total: ${currencyFmt.format(item.finalAmount)}" : ""}',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.rejected, size: 20),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() {
                          _stagedMaterials.removeAt(idx);
                        });
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
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
