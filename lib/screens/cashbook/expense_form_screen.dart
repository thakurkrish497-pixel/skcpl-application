import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/validators.dart';
import '../../models/cash_transaction_model.dart';
import '../../models/stock_transaction_model.dart';
import '../../models/dropdown_item_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_provider.dart';
import '../../providers/dropdown_provider.dart';
import '../../providers/storage_provider.dart';
import '../../widgets/locked_form_banner.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/photo_picker.dart';
import 'dart:io';

/// Cash Book — Expense entry form
class ExpenseFormScreen extends ConsumerStatefulWidget {
  final CashTransactionModel? existingTransaction;

  const ExpenseFormScreen({super.key, this.existingTransaction});

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _expenseAmountController = TextEditingController();
  final _amountReceivedController = TextEditingController();
  final _cashInHandController = TextEditingController();
  final _remarksController = TextEditingController();

  String? _selectedExpenseTypeId;
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
    _expenseAmountController.addListener(_calculateCashInHand);
    _amountReceivedController.addListener(_calculateCashInHand);

    final tx = widget.existingTransaction;
    if (tx != null) {
      _selectedExpenseTypeId = tx.expenseTypeId;
      _selectedDate = tx.date;
      _expenseAmountController.text = tx.expenseAmount.toString();
      _amountReceivedController.text = tx.amountReceived.toString();
      _cashInHandController.text = tx.cashInHand.toString();
      _remarksController.text = tx.remarks ?? '';
    }
  }

  void _calculateCashInHand() {
    final received = double.tryParse(_amountReceivedController.text) ?? 0;
    final expense = double.tryParse(_expenseAmountController.text) ?? 0;
    _cashInHandController.text = (received - expense).toStringAsFixed(2);
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
    if (_selectedExpenseTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an expense type')),
      );
      return;
    }

    final authState = ref.read(authProvider);
    final siteId = authState.activeSite?.id;
    final userId = authState.user?.id;

    if (siteId == null) return;

    CashTransactionModel transaction;

    if (widget.existingTransaction == null) {
      transaction = CashTransactionModel(
        siteId: siteId,
        submittedBy: userId,
        date: _selectedDate,
        expenseTypeId: _selectedExpenseTypeId!,
        expenseAmount: double.tryParse(_expenseAmountController.text) ?? 0,
        amountReceived: double.tryParse(_amountReceivedController.text) ?? 0,
        cashInHand: double.parse(_cashInHandController.text),
        remarks: _remarksController.text.isEmpty ? null : _remarksController.text,
      );
    } else {
      transaction = CashTransactionModel(
        id: widget.existingTransaction!.id,
        siteId: widget.existingTransaction!.siteId,
        submittedBy: widget.existingTransaction!.submittedBy,
        date: widget.existingTransaction!.date,
        expenseTypeId: _selectedExpenseTypeId!,
        expenseAmount: double.tryParse(_expenseAmountController.text) ?? 0,
        amountReceived: double.tryParse(_amountReceivedController.text) ?? 0,
        cashInHand: double.parse(_cashInHandController.text),
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
        ? await ref.read(cashProvider.notifier).submitTransaction(transaction)
        : await ref.read(cashProvider.notifier).updateTransaction(transaction);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.existingTransaction != null ? 'Transaction updated successfully!' : 'Expense recorded! Sent to Accounts.'),
          backgroundColor: AppColors.approved,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    _expenseAmountController.dispose();
    _amountReceivedController.dispose();
    _cashInHandController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final siteId = ref.watch(authProvider).activeSite?.id;
    final expenseTypesAsync = ref.watch(dropdownProvider((category: DropdownCategory.expenseType, siteId: siteId)));
    final cashState = ref.watch(cashProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: const Text('Record Expense'),
        actions: [
          if (isLocked)
            const Padding(
              padding: EdgeInsets.all(16),
              child:
                  Icon(Icons.lock_rounded, color: AppColors.pending, size: 20),
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
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    prefixIcon: Icon(Icons.calendar_today_rounded,
                        color: AppColors.textTertiary, size: 20),
                  ),
                ),
              ),
            ).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 18),

            // Expense Type
            expenseTypesAsync.when(
              loading: () => _placeholder('Loading expense types...'),
              error: (_, __) => _placeholder('Failed to load'),
              data: (types) => DropdownButtonFormField<String>(
                value: _selectedExpenseTypeId,
                decoration: const InputDecoration(
                  labelText: 'Expense Type',
                  prefixIcon: Icon(Icons.receipt_long_rounded,
                      color: AppColors.textTertiary, size: 20),
                ),
                dropdownColor: AppColors.cardDark,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textPrimary),
                items: types
                    .map((t) => DropdownMenuItem(
                          value: t.id,
                          child: Text(t.value),
                        ))
                    .toList(),
                onChanged: isLocked
                    ? null
                    : (val) => setState(() => _selectedExpenseTypeId = val),
                validator: (v) =>
                    Validators.dropdownRequired(v, 'Expense Type'),
              ),
            ).animate().fadeIn(delay: 200.ms),

            const SizedBox(height: 18),

            // Amount Received
            TextFormField(
              controller: _amountReceivedController,
              readOnly: isLocked,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => Validators.nonNegativeNumber(v, 'Amount'),
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Amount Received',
                prefixIcon: Icon(Icons.account_balance_wallet_rounded,
                    color: AppColors.textTertiary, size: 20),
              ),
            ).animate().fadeIn(delay: 300.ms),

            const SizedBox(height: 18),

            // Expense Amount
            TextFormField(
              controller: _expenseAmountController,
              readOnly: isLocked,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => Validators.positiveNumber(v, 'Expense Amount'),
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Expense Amount',
                prefixIcon: Icon(Icons.money_off_rounded,
                    color: AppColors.textTertiary, size: 20),
              ),
            ).animate().fadeIn(delay: 400.ms),

            const SizedBox(height: 18),

            // Cash in Hand (auto-calculated)
            TextFormField(
              controller: _cashInHandController,
              readOnly: true,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                labelText: 'Cash in Hand (Auto-calculated)',
                prefixIcon: const Icon(Icons.account_balance_rounded,
                    color: AppColors.secondary, size: 20),
                filled: true,
                fillColor: AppColors.secondarySurface,
              ),
            ).animate().fadeIn(delay: 500.ms),

            const SizedBox(height: 18),

            // Remarks
            TextFormField(
              controller: _remarksController,
              readOnly: isLocked,
              maxLines: 3,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Remarks (Optional)',
                alignLabelWithHint: true,
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

            if (!isLocked)
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: cashState.isLoading ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                  ),
                  icon: cashState.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(cashState.isLoading
                      ? 'Submitting...'
                      : 'Submit to Accounts'),
                ),
              ).animate().fadeIn(delay: 700.ms),

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
          style:
              AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary)),
    );
  }
}
