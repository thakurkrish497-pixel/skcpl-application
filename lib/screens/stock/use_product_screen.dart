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

/// Staged draft for multi-material Outward / Consumption batches
class StockOutwardDraft {
  final String id;
  final String productId;
  final String? customProduct;
  final String productName;
  final String metricUnitId;
  final String? customMetricUnit;
  final String metricUnitName;
  final double quantity;
  final String? remarks;

  StockOutwardDraft({
    required this.id,
    required this.productId,
    this.customProduct,
    required this.productName,
    required this.metricUnitId,
    this.customMetricUnit,
    required this.metricUnitName,
    required this.quantity,
    this.remarks,
  });
}

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

  // Multi-material staged consumption
  final List<StockOutwardDraft> _stagedOutward = [];
  Key _photoPickerKey = UniqueKey();

  bool get isLocked {
    // Approved records are permanently locked for everyone
    if (widget.existingTransaction?.status == TransactionStatus.approved) return true;

    final user = ref.read(authProvider);
    // Admin and Accounts ALWAYS have full edit privileges for pending and rejected records
    if (user.isAdmin || user.isAccounts) return false;

    // Project Head can edit transactions pending supervisor review or rejected
    if (user.isProjectHead &&
        (widget.existingTransaction == null ||
         widget.existingTransaction!.isPendingSupervisorReview ||
         widget.existingTransaction!.status == TransactionStatus.pendingAccounts ||
         widget.existingTransaction!.status == TransactionStatus.rejected)) {
      return false;
    }

    // Only apply staff module restrictions if the user is a worker/site staff
    final activeStaff = ref.read(activeStaffProvider);
    if (activeStaff != null && !activeStaff.hasModule(StaffModule.stock)) return true;

    if (widget.existingTransaction == null) return false;
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

  bool get _hasCurrentOutwardData {
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

  bool _stageCurrentOutward({
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

    // Stock check
    if (widget.existingTransaction == null && _selectedProductId != 'OTHER') {
      final stockState = ref.read(stockProvider);
      final stockItem = stockState.currentStock.where((s) => s['product_id'] == _selectedProductId).firstOrNull;
      final currentStock = stockItem?['current_stock'] ?? 0;
      if (qty > currentStock) {
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Not enough stock! Available: $currentStock'),
              backgroundColor: AppColors.rejected,
            ),
          );
        }
        return false;
      }
    }

    final pName = _getProductName(_selectedProductId, products);
    final uName = _getUnitName(_selectedMetricUnitId, units);

    final draft = StockOutwardDraft(
      id: 'DRAFT-OUT-${DateTime.now().microsecondsSinceEpoch}',
      productId: _selectedProductId!,
      customProduct: _customProductController.text.trim().isNotEmpty ? _customProductController.text.trim() : null,
      productName: pName,
      metricUnitId: _selectedMetricUnitId!,
      customMetricUnit: _customUnitController.text.trim().isNotEmpty ? _customUnitController.text.trim() : null,
      metricUnitName: uName,
      quantity: qty,
      remarks: _remarksController.text.trim().isNotEmpty ? _remarksController.text.trim() : null,
    );

    setState(() {
      _stagedOutward.add(draft);
      _quantityController.clear();
      _remarksController.clear();
      _customProductController.clear();
      _customUnitController.clear();
      _selectedProductId = null;
      _selectedMetricUnitId = null;
    });

    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added to batch! (${_stagedOutward.length} items staged)'),
          backgroundColor: AppColors.approved,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    return true;
  }

  void _showBatchSuccessDialog(int count) {
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
                  color: const Color(0xFFF59E0B).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFFF59E0B), size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                'Consumption Recorded!',
                style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                '$count ${count == 1 ? "material" : "materials"} consumption submitted successfully',
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
                      label: const Text('+ Record More'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        // Stays right in screen with site & staff session intact!
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

    final isPrivileged = authState.isAdmin || authState.isAccounts;
    final activeStaff = ref.read(activeStaffProvider);
    if (!isPrivileged && activeStaff != null && !activeStaff.hasModule(StaffModule.stock)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Access Denied: Stock usage is turned off for ${activeStaff.name}.'),
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
    if (widget.existingTransaction != null) {
      if (!_formKey.currentState!.validate()) return;
      if (_selectedProductId == null || _selectedMetricUnitId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select all required fields')),
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

        var transaction = StockTransactionModel(
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

        final success = await ref.read(stockProvider.notifier).updateTransaction(transaction);
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

    // ── Multi-Material Outward Batch Mode ──
    if (_hasCurrentOutwardData) {
      final staged = _stageCurrentOutward(silent: true, products: products, units: units);
      if (!staged) return; // Validation error
    }

    if (_stagedOutward.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter at least one consumed material with quantity.'),
          backgroundColor: AppColors.rejected,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final batchId = 'BATCH-${DateTime.now().millisecondsSinceEpoch}';
      final storageService = ref.read(storageServiceProvider);

      // Upload shared photos if any
      List<String> uploadedUrls = [];
      if (_selectedPhotos.isNotEmpty) {
        for (var photo in _selectedPhotos) {
          try {
            final url = await storageService.uploadPhotoBytes(photo.bytes, fileName: photo.name);
            uploadedUrls.add(url);
          } catch (uploadError) {
            debugPrint('Outward photo upload failed: $uploadError');
          }
        }
      }

      final bill = _billNoController.text.trim();
      int successCount = 0;

      for (final draft in _stagedOutward) {
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

        final transaction = StockTransactionModel(
          siteId: siteId,
          submittedBy: userId,
          type: TransactionType.outbound,
          date: _selectedDate,
          productId: effectiveProductId,
          metricUnitId: effectiveMetricUnitId,
          quantity: draft.quantity,
          remarks: encodedRemarks.trim(),
          status: initialStatus,
          photoUrls: uploadedUrls,
        );

        final success = await ref.read(stockProvider.notifier).submitTransaction(transaction);
        if (success) {
          successCount++;
        }
      }

      if (mounted) {
        if (successCount > 0) {
          setState(() {
            _stagedOutward.clear();
          });
          _showBatchSuccessDialog(successCount);
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
                    value: (products.any((p) => p.id == _selectedProductId) || _selectedProductId == 'OTHER')
                        ? _selectedProductId
                        : null,
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
                    value: (units.any((u) => u.id == _selectedMetricUnitId) || _selectedMetricUnitId == 'OTHER')
                        ? _selectedMetricUnitId
                        : null,
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
              key: _photoPickerKey,
              initialPhotoUrls: widget.existingTransaction?.photoUrls ?? [],
              isReadOnly: isLocked,
              onPhotosChanged: (photos) {
                setState(() {
                  _selectedPhotos = photos;
                });
              },
            ).animate().fadeIn(delay: 550.ms),

            const SizedBox(height: 24),

            // ── Staged Outward Tray (Multi-Material Consumption) ──
            if (widget.existingTransaction == null)
              _buildStagedOutwardTray(),

            // ── Action Buttons ──
            if (!isLocked) ...[
              if (widget.existingTransaction != null)
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
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
                ).animate().fadeIn(delay: 600.ms)
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
                              : () => _stageCurrentOutward(
                                    products: productsAsync.valueOrNull ?? [],
                                    units: unitsAsync.valueOrNull ?? [],
                                  ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.add_rounded, color: Color(0xFFF59E0B), size: 20),
                          label: const Text(
                            '+ Add Item',
                            style: TextStyle(
                              color: Color(0xFFF59E0B),
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
                            backgroundColor: const Color(0xFFF59E0B),
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
                                ? 'Submitting Batch...'
                                : (_stagedOutward.isNotEmpty
                                    ? 'Submit Batch (${_stagedOutward.length + (_hasCurrentOutwardData ? 1 : 0)})'
                                    : 'Submit Outward'),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 600.ms),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildStagedOutwardTray() {
    if (_stagedOutward.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.remove_circle_outline_rounded, color: Color(0xFFF59E0B), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Materials Consumed (${_stagedOutward.length} ${_stagedOutward.length == 1 ? "item" : "items"})',
                    style: AppTextStyles.h4.copyWith(fontSize: 15, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 8),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _stagedOutward.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final item = _stagedOutward[idx];
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
                        color: const Color(0xFFF59E0B).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#${idx + 1}',
                        style: const TextStyle(
                          color: Color(0xFFF59E0B),
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
                            '${item.quantity} ${item.metricUnitName}${item.remarks != null ? " • ${item.remarks}" : ""}',
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
                          _stagedOutward.removeAt(idx);
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
