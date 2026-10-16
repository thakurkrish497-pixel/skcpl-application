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

  String? _selectedProductId;
  String? _selectedMetricUnitId;
  DateTime _selectedDate = DateTime.now();
  List<File> _selectedPhotos = [];

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final siteId = ref.read(authProvider).activeSite?.id;
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
      _remarksController.text = tx.remarks ?? '';
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
    final siteId = authState.activeSite?.id;
    final userId = authState.user?.id;

    if (siteId == null) return;

    final quantity = double.parse(_quantityController.text);

    // Stock Validation
    if (widget.existingTransaction == null) {
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

    StockTransactionModel transaction;

    if (widget.existingTransaction == null) {
      transaction = StockTransactionModel(
        siteId: siteId,
        submittedBy: userId,
        type: TransactionType.outbound,
        date: _selectedDate,
        productId: _selectedProductId!,
        metricUnitId: _selectedMetricUnitId!,
        quantity: double.parse(_quantityController.text),
        remarks: _remarksController.text.isEmpty ? null : _remarksController.text,
      );
    } else {
      transaction = StockTransactionModel(
        id: widget.existingTransaction!.id,
        siteId: widget.existingTransaction!.siteId,
        submittedBy: widget.existingTransaction!.submittedBy,
        type: TransactionType.outbound,
        date: widget.existingTransaction!.date,
        productId: _selectedProductId!,
        metricUnitId: _selectedMetricUnitId!,
        quantity: double.parse(_quantityController.text),
        remarks: _remarksController.text.isEmpty ? null : _remarksController.text,
        status: widget.existingTransaction!.status,
        photoUrls: widget.existingTransaction!.photoUrls,
      );
    }

    List<String> uploadedUrls = List.from(transaction.photoUrls);
    if (_selectedPhotos.isNotEmpty) {
      final storageService = ref.read(storageServiceProvider);
      for (var file in _selectedPhotos) {
        final url = await storageService.uploadPhoto(file);
        uploadedUrls.add(url);
      }
      transaction = transaction.copyWith(photoUrls: uploadedUrls);
    }

    final success = widget.existingTransaction == null
        ? await ref.read(stockProvider.notifier).submitTransaction(transaction)
        : await ref.read(stockProvider.notifier).updateTransaction(transaction);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.existingTransaction != null ? 'Transaction updated successfully!' : 'Usage recorded! Sent to Accounts.'),
          backgroundColor: AppColors.approved,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final siteId = ref.watch(authProvider).activeSite?.id;
    final productsAsync = ref.watch(dropdownProvider((category: DropdownCategory.product, siteId: siteId)));
    final unitsAsync = ref.watch(dropdownProvider((category: DropdownCategory.metricUnit, siteId: siteId)));
    final stockState = ref.watch(stockProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: const Text('Use Product'),
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
            if (isLocked)
              const LockedFormBanner().animate().fadeIn(),

            // Date
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

            // Product
            productsAsync.when(
              loading: () => _placeholder('Loading products...'),
              error: (_, __) => _placeholder('Failed to load products'),
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
            ).animate().fadeIn(delay: 200.ms),

            const SizedBox(height: 18),

            // Metric Unit
            unitsAsync.when(
              loading: () => _placeholder('Loading units...'),
              error: (_, __) => _placeholder('Failed to load units'),
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
            ).animate().fadeIn(delay: 300.ms),

            const SizedBox(height: 18),

            // Quantity
            TextFormField(
              controller: _quantityController,
              readOnly: isLocked,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => Validators.positiveNumber(v, 'Quantity'),
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Quantity Used',
                prefixIcon: Icon(Icons.remove_circle_outline_rounded,
                    color: AppColors.textTertiary, size: 20),
              ),
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
              decoration: const InputDecoration(
                labelText: 'Remarks (Optional)',
                alignLabelWithHint: true,
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 48),
                  child: Icon(Icons.notes_rounded,
                      color: AppColors.textTertiary, size: 20),
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
                  onPressed: stockState.isLoading ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                  ),
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
                      : 'Submit Usage to Accounts'),
                ),
              ).animate().fadeIn(delay: 600.ms),

            const SizedBox(height: 24),
          ],
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
