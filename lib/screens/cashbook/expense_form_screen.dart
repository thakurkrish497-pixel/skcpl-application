import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/validators.dart';
import '../../models/cash_transaction_model.dart';
import '../../models/stock_transaction_model.dart';
import '../../models/site_staff_model.dart';
import '../../models/dropdown_item_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_provider.dart';
import '../../providers/dropdown_provider.dart';
import '../../providers/storage_provider.dart';
import '../../providers/stock_provider.dart';
import '../../widgets/locked_form_banner.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/photo_picker.dart';
import '../../widgets/offline_indicator.dart';
import '../../widgets/language_toggle_button.dart';
import '../../widgets/skcpl_brand_logo.dart';
import '../../widgets/responsive_layout.dart';
import '../../providers/site_staff_provider.dart';
import '../../services/dropdown_service.dart';
import '../../services/excel_service.dart';
import '../../providers/role_access_provider.dart';

enum CashEntryMode { expense, received }

/// Cash Book — Imprest cash entry form matching the Excel cashbook structure
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
  final _remarksController = TextEditingController();
  final _customExpenseTypeController = TextEditingController();
  final _billNoController = TextEditingController();
  final _partyNameController = TextEditingController();

  CashEntryMode _entryMode = CashEntryMode.expense;
  String? _selectedExpenseTypeId;
  DateTime _selectedDate = DateTime.now();
  List<PickedPhoto> _selectedPhotos = [];
  bool _isSubmitting = false;

  bool get isLocked {
    final activeStaff = ref.read(activeStaffProvider);
    if (activeStaff != null && !activeStaff.hasModule(StaffModule.cashbook)) return true;
    if (widget.existingTransaction == null) return false;
    if (widget.existingTransaction!.status == TransactionStatus.approved) return true;
    final user = ref.read(authProvider);
    if (user.isAdmin || user.isAccounts) return false;
    return !widget.existingTransaction!.isEditable;
  }

  @override
  void initState() {
    super.initState();
    _expenseAmountController.addListener(() => setState(() {}));
    _amountReceivedController.addListener(() => setState(() {}));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final siteId = widget.existingTransaction?.siteId ?? ref.read(authProvider).activeSite?.id;
      if (siteId != null) {
        ref.read(cashProvider.notifier).loadTransactions(siteId);
      }
    });

    final tx = widget.existingTransaction;
    if (tx != null) {
      if (tx.amountReceived > 0 && tx.expenseAmount == 0) {
        _entryMode = CashEntryMode.received;
      } else {
        _entryMode = CashEntryMode.expense;
      }

      _selectedExpenseTypeId = tx.expenseTypeId;
      _selectedDate = tx.date;
      _expenseAmountController.text = tx.expenseAmount > 0 ? tx.expenseAmount.toString() : '';
      _amountReceivedController.text = tx.amountReceived > 0 ? tx.amountReceived.toString() : '';
      _remarksController.text = tx.cleanRemarks ?? '';
      _billNoController.text = tx.billNo ?? '';
      _partyNameController.text = tx.partyName ?? '';

      if (tx.customExpenseType != null || tx.expenseTypeId == DropdownService.otherExpensePlaceholderId) {
        _selectedExpenseTypeId = 'OTHER';
        _customExpenseTypeController.text = tx.customExpenseType ?? '';
      }
    }
  }

  double _getCurrentSiteBalance([List<CashTransactionModel>? txList, String? targetSiteId]) {
    final transactions = txList ?? ref.read(cashProvider).transactions;
    final currentTxId = widget.existingTransaction?.id;
    final sId = targetSiteId ?? widget.existingTransaction?.siteId ?? ref.read(authProvider).activeSite?.id;
    double balance = 0.0;
    for (final t in transactions) {
      if (sId != null && t.siteId != sId) continue;
      if (t.id != currentTxId && t.status != TransactionStatus.rejected) {
        balance += (t.amountReceived - t.expenseAmount);
      }
    }
    return balance;
  }

  double _getProjectedBalance([double? currentBal]) {
    final current = currentBal ?? _getCurrentSiteBalance();
    if (_entryMode == CashEntryMode.expense) {
      final exp = double.tryParse(_expenseAmountController.text) ?? 0;
      return current - exp;
    } else {
      final rec = double.tryParse(_amountReceivedController.text) ?? 0;
      return current + rec;
    }
  }

  Future<void> _pickDate() async {
    if (isLocked) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
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
    if (activeStaff != null && !activeStaff.hasModule(StaffModule.cashbook)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Access Denied: Cashbook entries are turned off for ${activeStaff.name}.'),
          backgroundColor: AppColors.rejected,
        ),
      );
      return;
    }

    String effectiveExpenseTypeId;
    String? encodedRemarks = _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim();

    if (_entryMode == CashEntryMode.expense) {
      if (_selectedExpenseTypeId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an Expense Type')),
        );
        return;
      }

      if (_selectedExpenseTypeId == 'OTHER') {
        if (_customExpenseTypeController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter custom expense type name')),
          );
          return;
        }
        final tag = '[Expense: ${_customExpenseTypeController.text.trim()}]';
        encodedRemarks = encodedRemarks == null ? tag : '$tag $encodedRemarks';
        effectiveExpenseTypeId = DropdownService.otherExpensePlaceholderId;
      } else {
        effectiveExpenseTypeId = _selectedExpenseTypeId!;
      }
    } else {
      // Cash Received Mode
      if (_selectedExpenseTypeId == null || _selectedExpenseTypeId == 'OTHER') {
        final headName = _customExpenseTypeController.text.trim().isNotEmpty
            ? _customExpenseTypeController.text.trim()
            : 'Indore Office';
        final tag = '[Expense: $headName]';
        encodedRemarks = encodedRemarks == null ? tag : '$tag $encodedRemarks';
        effectiveExpenseTypeId = DropdownService.otherExpensePlaceholderId;
      } else {
        effectiveExpenseTypeId = _selectedExpenseTypeId!;
      }
    }

    final bill = _billNoController.text.trim();
    final party = _partyNameController.text.trim();
    final roleAccess = ref.read(roleAccessProvider);
    final phCanApproveCash = roleAccess.projectHeadCanApproveCash;
    final accountsCanApproveCash = roleAccess.accountsCanApproveCash;

    if (widget.existingTransaction == null) {
      if (activeStaff != null) {
        final staffTag = '[By: ${activeStaff.name} (${activeStaff.designation ?? activeStaff.role.displayName})]';
        encodedRemarks = encodedRemarks == null ? staffTag : '$staffTag $encodedRemarks';
      }
      if (phCanApproveCash) {
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
    if (party.isNotEmpty) {
      final tag = '[Party: $party]';
      encodedRemarks = encodedRemarks == null ? tag : '$tag $encodedRemarks';
    }
    if (bill.isNotEmpty) {
      final tag = '[Bill: $bill]';
      encodedRemarks = encodedRemarks == null ? tag : '$tag $encodedRemarks';
    }

    final double expenseAmt = _entryMode == CashEntryMode.expense
        ? (double.tryParse(_expenseAmountController.text) ?? 0)
        : 0;
    final double receivedAmt = _entryMode == CashEntryMode.received
        ? (double.tryParse(_amountReceivedController.text) ?? 0)
        : 0;

    final currentBal = _getCurrentSiteBalance(ref.read(cashProvider).transactions, siteId);
    final cashInHand = _getProjectedBalance(currentBal);

    TransactionStatus initialStatus = TransactionStatus.pendingAccounts;
    if (!phCanApproveCash && !accountsCanApproveCash) {
      // Both Project Head & Accounts bypassed -> direct to Admin
      initialStatus = TransactionStatus.pendingAdmin;
    }

    CashTransactionModel transaction;

    if (widget.existingTransaction == null) {
      transaction = CashTransactionModel(
        siteId: siteId,
        submittedBy: userId,
        date: _selectedDate,
        expenseTypeId: effectiveExpenseTypeId,
        expenseAmount: expenseAmt,
        amountReceived: receivedAmt,
        cashInHand: cashInHand,
        remarks: encodedRemarks,
        status: initialStatus,
      );
    } else {
      transaction = CashTransactionModel(
        id: widget.existingTransaction!.id,
        siteId: widget.existingTransaction!.siteId,
        submittedBy: widget.existingTransaction!.submittedBy,
        date: _selectedDate,
        expenseTypeId: effectiveExpenseTypeId,
        expenseAmount: expenseAmt,
        amountReceived: receivedAmt,
        cashInHand: cashInHand,
        remarks: encodedRemarks,
        status: widget.existingTransaction!.status,
        photoUrls: widget.existingTransaction!.photoUrls,
      );
    }

    setState(() => _isSubmitting = true);

    try {
      List<String> uploadedUrls = List.from(transaction.photoUrls);
      if (_selectedPhotos.isNotEmpty) {
        final storageService = ref.read(storageServiceProvider);
        for (var photo in _selectedPhotos) {
          try {
            final url = await storageService.uploadPhotoBytes(photo.bytes, fileName: photo.name);
            uploadedUrls.add(url);
          } catch (uploadError) {
            debugPrint('Cash photo upload failed: $uploadError');
          }
        }
        transaction = transaction.copyWith(photoUrls: uploadedUrls);
      }

      final success = widget.existingTransaction == null
          ? await ref.read(cashProvider.notifier).submitTransaction(transaction)
          : await ref.read(cashProvider.notifier).updateTransaction(transaction);

      final cashError = ref.read(cashProvider).error;

      if (success && mounted) {
        ref.invalidate(siteCashSummaryProvider(siteId));
        ref.read(cashProvider.notifier).loadTransactions(siteId);

        final isOffline = cashError == 'OFFLINE_SAVED';
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
            content: Text(ref.read(cashProvider).error ?? 'Submission failed'),
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
    _expenseAmountController.dispose();
    _amountReceivedController.dispose();
    _remarksController.dispose();
    _customExpenseTypeController.dispose();
    _billNoController.dispose();
    _partyNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final siteId = widget.existingTransaction?.siteId ?? ref.watch(authProvider).activeSite?.id;
    final expenseTypesAsync = ref.watch(dropdownProvider((category: DropdownCategory.expenseType, siteId: siteId)));
    final cashState = ref.watch(cashProvider);

    final currentBalance = _getCurrentSiteBalance(cashState.transactions, siteId);
    final projectedBalance = _getProjectedBalance(currentBalance);
    final currencyFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Row(
          children: [
            const SkcplBrandLogo(variant: LogoVariant.compact, customSize: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.existingTransaction != null
                    ? (_entryMode == CashEntryMode.expense ? 'Edit Expense' : 'Edit Cash Receipt')
                    : (_entryMode == CashEntryMode.expense ? 'Record Expense' : 'Record Cash Received'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: LanguageToggleButton(isCompact: true),
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded, color: AppColors.textPrimary),
            tooltip: 'Cash Book History',
            onPressed: () => Navigator.pushNamed(context, '/cash-history'),
          ),
          const OfflineSyncButton(),
          if (ref.watch(authProvider).isAdmin || ref.watch(authProvider).isAccounts)
            IconButton(
              icon: const Icon(Icons.table_view_rounded, color: Color(0xFF107C41)),
              tooltip: 'Export Excel (.xlsx)',
              onPressed: () async {
                final activeSite = ref.read(authProvider).activeSite;
                final targetSiteId = siteId ?? activeSite?.id;
                final targetSiteName = activeSite?.name ?? 'Site';
                if (targetSiteId == null) return;
                await ExcelService.exportAndShareComprehensiveExcel(
                  siteName: targetSiteName,
                  siteId: targetSiteId,
                );
              },
            ),

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

            // ── Segmented Toggle: Expense vs Cash Received ──
            if (!isLocked) ...[
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _entryMode = CashEntryMode.expense),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _entryMode == CashEntryMode.expense
                                ? AppColors.rejected.withOpacity(0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: _entryMode == CashEntryMode.expense
                                ? Border.all(color: AppColors.rejected)
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.money_off_rounded,
                                size: 18,
                                color: _entryMode == CashEntryMode.expense
                                    ? AppColors.rejected
                                    : AppColors.textTertiary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Site Expense',
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: _entryMode == CashEntryMode.expense
                                      ? AppColors.rejected
                                      : AppColors.textSecondary,
                                  fontWeight: _entryMode == CashEntryMode.expense
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _entryMode = CashEntryMode.received),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _entryMode == CashEntryMode.received
                                ? AppColors.approved.withOpacity(0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: _entryMode == CashEntryMode.received
                                ? Border.all(color: AppColors.approved)
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.savings_rounded,
                                size: 18,
                                color: _entryMode == CashEntryMode.received
                                    ? AppColors.approved
                                    : AppColors.textTertiary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Cash Received',
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: _entryMode == CashEntryMode.received
                                      ? AppColors.approved
                                      : AppColors.textSecondary,
                                  fontWeight: _entryMode == CashEntryMode.received
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(),
              const SizedBox(height: 18),
            ],

            // ── 1. Date Field ──
            GestureDetector(
              onTap: _pickDate,
              child: AbsorbPointer(
                child: TextFormField(
                  readOnly: true,
                  controller: TextEditingController(
                    text: DateFormat('dd MMM yyyy (EEEE)').format(_selectedDate),
                  ),
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Date (As per Cashbook)',
                    prefixIcon: Icon(Icons.calendar_today_rounded,
                        color: AppColors.primary, size: 20),
                  ),
                ),
              ),
            ).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 18),

            // ── 2. Expense Type (Dropdown configured by Admin per site) ──
            if (_entryMode == CashEntryMode.expense) ...[
              expenseTypesAsync.when(
                loading: () => _placeholder('Loading expense types...'),
                error: (_, __) => _placeholder('Failed to load'),
                data: (types) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedExpenseTypeId,
                      decoration: const InputDecoration(
                        labelText: 'Expense Type (Account Head) *',
                        prefixIcon: Icon(Icons.receipt_long_rounded,
                            color: AppColors.primary, size: 20),
                        hintText: 'Select category / contractor',
                      ),
                      dropdownColor: AppColors.cardDark,
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                      items: [
                        ...types.map((t) => DropdownMenuItem(
                              value: t.id,
                              child: Text(t.value),
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
                      onChanged: isLocked
                          ? null
                          : (val) => setState(() => _selectedExpenseTypeId = val),
                      validator: (v) => Validators.dropdownRequired(v, 'Expense Type'),
                    ),
                    if (_selectedExpenseTypeId == 'OTHER') ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _customExpenseTypeController,
                        readOnly: isLocked,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Please enter custom expense type'
                            : null,
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Enter Custom Expense Type *',
                          hintText: 'e.g. Indar Civil Cont., Mess Exp, Vehicle Repair',
                          prefixIcon: Icon(Icons.edit_note_rounded,
                              color: AppColors.primary, size: 20),
                        ),
                      ).animate().fadeIn(),
                    ],
                  ],
                ),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 18),

              // ── Optional: Bill / Voucher No & Party Name ──
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _billNoController,
                      readOnly: isLocked,
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Bill / Voucher No. (Optional)',
                        hintText: 'e.g. 1042',
                        prefixIcon: Icon(Icons.receipt_rounded, color: AppColors.textTertiary, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _partyNameController,
                      readOnly: isLocked,
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Party / Vendor (Optional)',
                        hintText: 'e.g. Sharma Hardware',
                        prefixIcon: Icon(Icons.person_outline_rounded, color: AppColors.textTertiary, size: 20),
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 220.ms),

              const SizedBox(height: 18),

              // ── 3. Description of Expenses (Required Narration matching Excel Col B) ──
              TextFormField(
                controller: _remarksController,
                readOnly: isLocked,
                maxLines: 2,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter description of expense'
                    : null,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Description of Expenses *',
                  hintText: 'e.g. Sabji, oil / JCB 5.18 hr / Tractor diesel 30L / Auto rent',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 24),
                    child: Icon(Icons.notes_rounded, color: AppColors.textTertiary, size: 20),
                  ),
                ),
              ).animate().fadeIn(delay: 250.ms),

              const SizedBox(height: 18),

              // ── 4. Expense Amount (₹) ──
              TextFormField(
                controller: _expenseAmountController,
                readOnly: isLocked,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => Validators.positiveNumber(v, 'Expense Amount'),
                style: AppTextStyles.h4.copyWith(color: AppColors.rejected),
                decoration: const InputDecoration(
                  labelText: 'Expense Amount (₹) *',
                  prefixIcon: Icon(Icons.currency_rupee_rounded,
                      color: AppColors.rejected, size: 20),
                ),
              ).animate().fadeIn(delay: 300.ms),
            ] else ...[
              // ── CASH RECEIVED (INFLOW) FIELDS ──
              // 1. Amount Received
              TextFormField(
                controller: _amountReceivedController,
                readOnly: isLocked,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => Validators.positiveNumber(v, 'Amount Received'),
                style: AppTextStyles.h4.copyWith(color: AppColors.approved),
                decoration: const InputDecoration(
                  labelText: 'Amount Received (₹) *',
                  prefixIcon: Icon(Icons.currency_rupee_rounded,
                      color: AppColors.approved, size: 20),
                ),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 18),

              // 2. Source / Account Head (defaults to Indore Office)
              TextFormField(
                controller: _customExpenseTypeController,
                readOnly: isLocked,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Received From / Head',
                  hintText: 'e.g. Indore Office, Bank Transfer, Head Office Advance',
                  prefixIcon: Icon(Icons.account_balance_rounded,
                      color: AppColors.primary, size: 20),
                ),
              ).animate().fadeIn(delay: 250.ms),

              const SizedBox(height: 18),

              // ── Optional: Slip / Ref No & Party / Depositor ──
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _billNoController,
                      readOnly: isLocked,
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Slip / Ref No. (Optional)',
                        hintText: 'e.g. TXN-8901',
                        prefixIcon: Icon(Icons.receipt_rounded, color: AppColors.textTertiary, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _partyNameController,
                      readOnly: isLocked,
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Party / Depositor (Optional)',
                        hintText: 'e.g. Indore Office',
                        prefixIcon: Icon(Icons.person_outline_rounded, color: AppColors.textTertiary, size: 20),
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 280.ms),

              const SizedBox(height: 18),

              // 3. Narration / Remarks
              TextFormField(
                controller: _remarksController,
                readOnly: isLocked,
                maxLines: 2,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Description / Narration (Optional)',
                  hintText: 'e.g. Advance cash received for site kickoff / NEFT Ref #1234',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 24),
                    child: Icon(Icons.notes_rounded, color: AppColors.textTertiary, size: 20),
                  ),
                ),
              ).animate().fadeIn(delay: 300.ms),
            ],

            const SizedBox(height: 20),

            // ── Live Running Balance Preview Card ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Current Site Balance:',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                      Text(
                        cashState.isLoading && cashState.transactions.isEmpty
                            ? 'Syncing live balance...'
                            : currencyFmt.format(currentBalance),
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _entryMode == CashEntryMode.expense ? 'Deduct Expense:' : 'Add Inflow:',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: _entryMode == CashEntryMode.expense ? AppColors.rejected : AppColors.approved,
                        ),
                      ),
                      Text(
                        _entryMode == CashEntryMode.expense
                            ? '-${currencyFmt.format(double.tryParse(_expenseAmountController.text) ?? 0)}'
                            : '+${currencyFmt.format(double.tryParse(_amountReceivedController.text) ?? 0)}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: _entryMode == CashEntryMode.expense ? AppColors.rejected : AppColors.approved,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: AppColors.divider, height: 1),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.account_balance_wallet_rounded,
                              size: 18,
                              color: projectedBalance >= 0 ? AppColors.approved : AppColors.rejected),
                          const SizedBox(width: 8),
                          Text('Estimated Balance in Hand:',
                              style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Text(
                        currencyFmt.format(projectedBalance),
                        style: AppTextStyles.h4.copyWith(
                          color: projectedBalance >= 0 ? AppColors.approved : AppColors.rejected,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 350.ms),

            const SizedBox(height: 20),

            // ── Photo Picker (Voucher / Bill) ──
            PhotoPickerWidget(
              initialPhotoUrls: widget.existingTransaction?.photoUrls ?? [],
              isReadOnly: isLocked,
              onPhotosChanged: (photos) {
                setState(() {
                  _selectedPhotos = photos;
                });
              },
            ).animate().fadeIn(delay: 400.ms),

            const SizedBox(height: 32),

            // ── Submit / Save Button ──
            if (!isLocked)
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: (_isSubmitting || cashState.isLoading) ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _entryMode == CashEntryMode.expense
                        ? AppColors.primary
                        : AppColors.approved,
                  ),
                  icon: (_isSubmitting || cashState.isLoading)
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    (_isSubmitting || cashState.isLoading)
                        ? (widget.existingTransaction != null ? 'Saving Changes...' : 'Submitting...')
                        : (widget.existingTransaction != null ? 'Save Changes' : 'Submit'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ).animate().fadeIn(delay: 450.ms),

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
