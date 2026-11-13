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
import '../../widgets/locked_form_banner.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/photo_picker.dart';
import '../../widgets/universal_sync_button.dart';
import '../../services/auto_sync_engine.dart';
import '../../widgets/language_toggle_button.dart';
import '../../widgets/skcpl_brand_logo.dart';
import '../../widgets/responsive_layout.dart';
import '../../providers/site_staff_provider.dart';
import '../../services/dropdown_service.dart';
import '../../services/excel_service.dart';
import '../../providers/role_access_provider.dart';
import '../../widgets/voice_input_field.dart';
import '../../providers/sla_alert_provider.dart';

enum CashEntryMode { expense, received }

/// Staged draft for multi-entry cashbook batches
class CashEntryDraft {
  final String id;
  final CashEntryMode mode;
  final String? expenseTypeId;
  final String? customExpenseType;
  final String expenseTypeName;
  final double amount;
  final String? remarks;
  final String? billNo;
  final String? partyName;
  final List<PickedPhoto> photos;
  final DateTime date;

  CashEntryDraft({
    required this.id,
    required this.mode,
    required this.expenseTypeId,
    this.customExpenseType,
    required this.expenseTypeName,
    required this.amount,
    this.remarks,
    this.billNo,
    this.partyName,
    this.photos = const [],
    required this.date,
  });
}

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

  // Multi-entry batch staging
  final List<CashEntryDraft> _stagedEntries = [];
  Key _photoPickerKey = UniqueKey();

  bool get isLocked {
    final user = ref.read(authProvider);
    // Admin ALWAYS has full edit privileges on ANY transaction, including approved historical entries
    if (user.isAdmin) return false;

    // For non-admin users, approved records are permanently locked
    if (widget.existingTransaction?.status == TransactionStatus.approved) return true;

    // Accounts has edit privileges for pending and rejected records
    if (user.isAccounts) return false;

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
    if (activeStaff != null && !activeStaff.hasModule(StaffModule.cashbook)) return true;

    if (widget.existingTransaction == null) return false;
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

  bool get _hasCurrentDraftData {
    final exp = double.tryParse(_expenseAmountController.text) ?? 0;
    final rec = double.tryParse(_amountReceivedController.text) ?? 0;
    return (_entryMode == CashEntryMode.expense ? exp > 0 : rec > 0);
  }

  String _getCategoryDisplayName(String? id, List<DropdownItemModel> types) {
    if (_entryMode == CashEntryMode.received) {
      if (_customExpenseTypeController.text.trim().isNotEmpty) {
        return _customExpenseTypeController.text.trim();
      }
      return 'Indore Office (Cash Top-up)';
    }
    if (id == 'OTHER') {
      return _customExpenseTypeController.text.trim().isNotEmpty
          ? _customExpenseTypeController.text.trim()
          : 'Manual Expense';
    }
    final match = types.where((t) => t.id == id).firstOrNull;
    return match?.value ?? 'General Expense';
  }

  bool _stageCurrentEntry({bool silent = false, List<DropdownItemModel> types = const []}) {
    final exp = double.tryParse(_expenseAmountController.text) ?? 0;
    final rec = double.tryParse(_amountReceivedController.text) ?? 0;
    final amount = _entryMode == CashEntryMode.expense ? exp : rec;

    if (amount <= 0) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid amount greater than 0'),
            backgroundColor: AppColors.rejected,
          ),
        );
      }
      return false;
    }

    if (_entryMode == CashEntryMode.expense) {
      if (_selectedExpenseTypeId == null) {
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select an Expense Type'),
              backgroundColor: AppColors.rejected,
            ),
          );
        }
        return false;
      }
      if (_selectedExpenseTypeId == 'OTHER' && _customExpenseTypeController.text.trim().isEmpty) {
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enter custom expense type name'),
              backgroundColor: AppColors.rejected,
            ),
          );
        }
        return false;
      }
    }

    final catName = _getCategoryDisplayName(_selectedExpenseTypeId, types);

    final draft = CashEntryDraft(
      id: 'DRAFT-${DateTime.now().microsecondsSinceEpoch}',
      mode: _entryMode,
      expenseTypeId: _selectedExpenseTypeId,
      customExpenseType: _customExpenseTypeController.text.trim().isNotEmpty ? _customExpenseTypeController.text.trim() : null,
      expenseTypeName: catName,
      amount: amount,
      remarks: _remarksController.text.trim().isNotEmpty ? _remarksController.text.trim() : null,
      billNo: _billNoController.text.trim().isNotEmpty ? _billNoController.text.trim() : null,
      partyName: _partyNameController.text.trim().isNotEmpty ? _partyNameController.text.trim() : null,
      photos: List.from(_selectedPhotos),
      date: _selectedDate,
    );

    setState(() {
      _stagedEntries.add(draft);
      _expenseAmountController.clear();
      _amountReceivedController.clear();
      _remarksController.clear();
      _customExpenseTypeController.clear();
      _billNoController.clear();
      _partyNameController.clear();
      _selectedPhotos = [];
      _selectedExpenseTypeId = null;
      _photoPickerKey = UniqueKey();
    });

    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added to batch! (${_stagedEntries.length} items staged)'),
          backgroundColor: AppColors.approved,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    return true;
  }

  void _showBatchSuccessDialog(int count, double total) {
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
                'Batch Submitted Successfully!',
                style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                '$count ${count == 1 ? "entry" : "entries"} recorded • Total: ${currencyFmt.format(total)}',
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
                        Navigator.pushNamed(context, '/cash-history');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('+ Enter More'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
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

  Future<void> _handleSubmit([List<DropdownItemModel> currentTypes = const []]) async {
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
    if (!isPrivileged && activeStaff != null && !activeStaff.hasModule(StaffModule.cashbook)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Access Denied: Cashbook entries are turned off for ${activeStaff.name}.'),
          backgroundColor: AppColors.rejected,
        ),
      );
      return;
    }

    final roleAccess = ref.read(roleAccessProvider);
    final phCanApproveCash = roleAccess.projectHeadCanApproveCash;
    final accountsCanApproveCash = roleAccess.accountsCanApproveCash;

    TransactionStatus initialStatus = TransactionStatus.pendingAccounts;
    if (!phCanApproveCash && !accountsCanApproveCash) {
      initialStatus = TransactionStatus.pendingAdmin;
    }

    // ── Single Edit Mode ──
    if (widget.existingTransaction != null) {
      if (!_formKey.currentState!.validate()) return;

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
      if (activeStaff != null) {
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

      var transaction = CashTransactionModel(
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

        final success = await ref.read(cashProvider.notifier).updateTransaction(transaction);
        if (success && mounted) {
          ref.invalidate(siteCashSummaryProvider(siteId));
          ref.read(cashProvider.notifier).loadTransactions(siteId);
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

    // ── Batch / Multi-Entry Creation Mode ──
    // If the user filled inputs right now without clicking "+ Add to Batch", auto-stage it
    if (_hasCurrentDraftData) {
      final staged = _stageCurrentEntry(silent: true, types: currentTypes);
      if (!staged) return; // Validation failed
    }

    if (_stagedEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an amount or add at least one entry to submit.'),
          backgroundColor: AppColors.rejected,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final batchId = 'BATCH-${DateTime.now().millisecondsSinceEpoch}';
      final storageService = ref.read(storageServiceProvider);
      int successCount = 0;
      double batchTotal = 0;

      for (final draft in _stagedEntries) {
        List<String> uploadedUrls = [];
        if (draft.photos.isNotEmpty) {
          for (var photo in draft.photos) {
            try {
              final url = await storageService.uploadPhotoBytes(photo.bytes, fileName: photo.name);
              uploadedUrls.add(url);
            } catch (uploadError) {
              debugPrint('Batch photo upload failed: $uploadError');
            }
          }
        }

        String? encodedRemarks = draft.remarks;
        encodedRemarks = '[Batch: $batchId] ${encodedRemarks ?? ''}'.trim();

        if (draft.mode == CashEntryMode.expense) {
          if (draft.expenseTypeId == 'OTHER' || draft.customExpenseType != null) {
            final tag = '[Expense: ${draft.customExpenseType ?? "General"}]';
            encodedRemarks = '$tag $encodedRemarks';
          }
        } else {
          final headName = draft.customExpenseType ?? 'Indore Office';
          final tag = '[Expense: $headName]';
          encodedRemarks = '$tag $encodedRemarks';
        }

        if (activeStaff != null) {
          final staffTag = '[By: ${activeStaff.name} (${activeStaff.designation ?? activeStaff.role.displayName})]';
          encodedRemarks = '$staffTag $encodedRemarks';
        }
        if (phCanApproveCash) {
          const supTag = '[Project Head Review: Pending] [Supervisor Review: Pending]';
          encodedRemarks = '$encodedRemarks $supTag';
        } else {
          const supTag = '[Project Head Review: Bypassed by Admin Policy]';
          encodedRemarks = '$encodedRemarks $supTag';
        }
        if (draft.partyName != null && draft.partyName!.isNotEmpty) {
          final tag = '[Party: ${draft.partyName}]';
          encodedRemarks = '$tag $encodedRemarks';
        }
        if (draft.billNo != null && draft.billNo!.isNotEmpty) {
          final tag = '[Bill: ${draft.billNo}]';
          encodedRemarks = '$tag $encodedRemarks';
        }

        final double expenseAmt = draft.mode == CashEntryMode.expense ? draft.amount : 0;
        final double receivedAmt = draft.mode == CashEntryMode.received ? draft.amount : 0;
        final currentBal = _getCurrentSiteBalance(ref.read(cashProvider).transactions, siteId);
        final cashInHand = currentBal + (receivedAmt - expenseAmt);

        final effectiveExpenseTypeId = draft.expenseTypeId == null || draft.expenseTypeId == 'OTHER'
            ? DropdownService.otherExpensePlaceholderId
            : draft.expenseTypeId!;

        final transaction = CashTransactionModel(
          siteId: siteId,
          submittedBy: userId,
          date: draft.date,
          expenseTypeId: effectiveExpenseTypeId,
          expenseAmount: expenseAmt,
          amountReceived: receivedAmt,
          cashInHand: cashInHand,
          remarks: encodedRemarks.trim(),
          status: initialStatus,
          photoUrls: uploadedUrls,
        );

        final success = await ref.read(cashProvider.notifier).submitTransaction(transaction);
        if (success) {
          successCount++;
          batchTotal += draft.amount;
        }
      }

      if (mounted) {
        ref.invalidate(siteCashSummaryProvider(siteId));
        ref.read(cashProvider.notifier).loadTransactions(siteId);

        if (successCount > 0) {
          setState(() {
            _stagedEntries.clear();
          });
          _showBatchSuccessDialog(successCount, batchTotal);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ref.read(cashProvider).error ?? 'Submission failed'),
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
    final activeSite = ref.watch(authProvider).activeSite;
    final siteName = widget.existingTransaction?.siteName ?? activeSite?.name ?? 'Site';
    final isLight = AppColors.isLight;

    double siteTotalReceived = 0.0;
    double siteTotalExpense = 0.0;
    for (final t in cashState.transactions) {
      if (siteId != null && t.siteId != siteId) continue;
      if (t.status != TransactionStatus.rejected) {
        siteTotalReceived += t.amountReceived;
        siteTotalExpense += t.expenseAmount;
      }
    }

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
          UniversalSyncButton(siteId: siteId),
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
          child: RefreshIndicator(
            color: AppColors.waveCyan,
            backgroundColor: AppColors.cardDark,
            onRefresh: () async {
              final activeSiteId = siteId ?? ref.read(authProvider).activeSite?.id;
              if (activeSiteId != null) {
                await ref.read(cashProvider.notifier).loadTransactions(activeSiteId);
              }
              await ref.read(autoSyncProvider.notifier).syncNow();
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
            if (isLocked)
              const LockedFormBanner().animate().fadeIn(),

            // ── Missed Cashbook Entry Warning Banner for Worker ──
            Builder(
              builder: (context) {
                final missedDates = ref.watch(missedCashbookForWorkerProvider);
                if (missedDates.isEmpty) return const SizedBox.shrink();

                final formattedDates = missedDates
                    .map((d) => DateFormat('dd MMM yyyy').format(d))
                    .join(', ');

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309), size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '⚠️ Action Required: Missed Cashbook Entry',
                              style: TextStyle(
                                color: Color(0xFF92400E),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'No cash transactions recorded for this site on $formattedDates. Please submit daily cash entries or opening balance immediately.',
                              style: const TextStyle(
                                color: Color(0xFF78350F),
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ).animate().shake(duration: 400.ms);
              },
            ),

            // ── TOP HERO: Live Site Cash in Hand Balance (Visible Before Entering Inputs) ──
            Container(
              padding: const EdgeInsets.all(18),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isLight
                      ? [const Color(0xFFE0F2FE), const Color(0xFFBAE6FD)]
                      : [const Color(0xFF0C1D3B), const Color(0xFF132A54)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isLight ? const Color(0xFF7DD3FC) : AppColors.primary.withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.account_balance_wallet_rounded,
                                color: AppColors.primary, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$siteName Cashbook',
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: isLight ? AppColors.textPrimaryLight : AppColors.textPrimaryDark,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Current Balance at Site',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: isLight ? AppColors.textSecondaryLight : AppColors.textTertiaryDark,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: currentBalance >= 0
                              ? AppColors.approved.withValues(alpha: 0.15)
                              : AppColors.rejected.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: currentBalance >= 0 ? AppColors.approved : AppColors.rejected,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 3,
                              backgroundColor: currentBalance >= 0 ? AppColors.approved : AppColors.rejected,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              currentBalance >= 0 ? 'Live Balance' : 'Low / Deficit',
                              style: TextStyle(
                                color: currentBalance >= 0 ? AppColors.approved : AppColors.rejected,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    cashState.isLoading && cashState.transactions.isEmpty
                        ? 'Syncing live balance...'
                        : currencyFmt.format(currentBalance),
                    style: AppTextStyles.h2.copyWith(
                      color: currentBalance >= 0
                          ? (isLight ? const Color(0xFF047857) : AppColors.approved)
                          : AppColors.rejected,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Divider(
                    color: isLight ? const Color(0xFFBAE6FD) : AppColors.dividerDark,
                    height: 1,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.arrow_downward_rounded, color: AppColors.approved, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'Received: ${currencyFmt.format(siteTotalReceived)}',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: isLight ? AppColors.textSecondaryLight : Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(Icons.arrow_upward_rounded, color: AppColors.rejected, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'Spent: ${currencyFmt.format(siteTotalExpense)}',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: isLight ? AppColors.textSecondaryLight : Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if ((_entryMode == CashEntryMode.expense && (double.tryParse(_expenseAmountController.text) ?? 0) > 0) ||
                      (_entryMode == CashEntryMode.received && (double.tryParse(_amountReceivedController.text) ?? 0) > 0)) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isLight ? Colors.white.withValues(alpha: 0.8) : Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _entryMode == CashEntryMode.expense
                                ? 'Est. after expense (-${currencyFmt.format(double.tryParse(_expenseAmountController.text) ?? 0)}):'
                                : 'Est. after inflow (+${currencyFmt.format(double.tryParse(_amountReceivedController.text) ?? 0)}):',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isLight ? AppColors.textPrimaryLight : AppColors.textPrimaryDark,
                            ),
                          ),
                          Text(
                            currencyFmt.format(projectedBalance),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: projectedBalance >= 0 ? AppColors.approved : AppColors.rejected,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.05),

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
                      value: (types.any((t) => t.id == _selectedExpenseTypeId) || _selectedExpenseTypeId == 'OTHER')
                          ? _selectedExpenseTypeId
                          : null,
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
                        decoration: InputDecoration(
                          labelText: 'Enter Custom Expense Type *',
                          hintText: 'e.g. Indar Civil Cont., Mess Exp, Vehicle Repair',
                          prefixIcon: const Icon(Icons.edit_note_rounded,
                              color: AppColors.primary, size: 20),
                          suffixIcon: isLocked
                              ? null
                              : VoiceInputIconButton(
                                  controller: _customExpenseTypeController,
                                  fieldLabel: 'Expense Type',
                                ),
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
                      decoration: InputDecoration(
                        labelText: 'Party / Vendor (Optional)',
                        hintText: 'e.g. Sharma Hardware',
                        prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.textTertiary, size: 20),
                        suffixIcon: isLocked
                            ? null
                            : VoiceInputIconButton(
                                controller: _partyNameController,
                                fieldLabel: 'Party Name',
                              ),
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
                decoration: InputDecoration(
                  labelText: 'Description of Expenses *',
                  hintText: 'e.g. Sabji, oil / JCB 5.18 hr / Tractor diesel 30L / Auto rent',
                  alignLabelWithHint: true,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 24),
                    child: Icon(Icons.notes_rounded, color: AppColors.textTertiary, size: 20),
                  ),
                  suffixIcon: isLocked
                      ? null
                      : VoiceInputIconButton(
                          controller: _remarksController,
                          fieldLabel: 'Description of Expense',
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
                decoration: InputDecoration(
                  labelText: 'Received From / Head',
                  hintText: 'e.g. Indore Office, Bank Transfer, Head Office Advance',
                  prefixIcon: const Icon(Icons.account_balance_rounded,
                      color: AppColors.primary, size: 20),
                  suffixIcon: isLocked
                      ? null
                      : VoiceInputIconButton(
                          controller: _customExpenseTypeController,
                          fieldLabel: 'Received From',
                        ),
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
                      decoration: InputDecoration(
                        labelText: 'Party / Depositor (Optional)',
                        hintText: 'e.g. Indore Office',
                        prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.textTertiary, size: 20),
                        suffixIcon: isLocked
                            ? null
                            : VoiceInputIconButton(
                                controller: _partyNameController,
                                fieldLabel: 'Party / Depositor',
                              ),
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
                decoration: InputDecoration(
                  labelText: 'Description / Narration (Optional)',
                  hintText: 'e.g. Advance cash received for site kickoff / NEFT Ref #1234',
                  alignLabelWithHint: true,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 24),
                    child: Icon(Icons.notes_rounded, color: AppColors.textTertiary, size: 20),
                  ),
                  suffixIcon: isLocked
                      ? null
                      : VoiceInputIconButton(
                          controller: _remarksController,
                          fieldLabel: 'Description / Narration',
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
              key: _photoPickerKey,
              initialPhotoUrls: widget.existingTransaction?.photoUrls ?? [],
              isReadOnly: isLocked,
              onPhotosChanged: (photos) {
                setState(() {
                  _selectedPhotos = photos;
                });
              },
            ).animate().fadeIn(delay: 400.ms),

            const SizedBox(height: 24),

            // ── Staged Entries Tray (Multi-Entry Batch) ──
            if (widget.existingTransaction == null)
              _buildStagedEntriesTray(currencyFmt),

            // ── Action Buttons ──
            if (!isLocked) ...[
              if (widget.existingTransaction != null)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: (_isSubmitting || cashState.isLoading)
                        ? null
                        : () => _handleSubmit(expenseTypesAsync.valueOrNull ?? []),
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
                        : const Icon(Icons.check_circle_rounded),
                    label: Text(
                      (_isSubmitting || cashState.isLoading) ? 'Saving Changes...' : 'Save Changes',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ).animate().fadeIn(delay: 450.ms)
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
                              : () => _stageCurrentEntry(types: expenseTypesAsync.valueOrNull ?? []),
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
                          onPressed: (_isSubmitting || cashState.isLoading || isLocked)
                              ? null
                              : () => _handleSubmit(expenseTypesAsync.valueOrNull ?? []),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _entryMode == CashEntryMode.expense
                                ? AppColors.primary
                                : AppColors.approved,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: (_isSubmitting || cashState.isLoading)
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send_rounded, size: 20),
                          label: Text(
                            (_isSubmitting || cashState.isLoading)
                                ? 'Submitting Batch...'
                                : (_stagedEntries.isNotEmpty
                                    ? 'Submit Batch (${_stagedEntries.length + (_hasCurrentDraftData ? 1 : 0)})'
                                    : 'Submit Entry'),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 450.ms),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  ),
);
  }

  Widget _buildStagedEntriesTray(NumberFormat currencyFmt) {
    if (_stagedEntries.isEmpty) return const SizedBox.shrink();

    final totalStaged = _stagedEntries.fold<double>(0.0, (sum, e) => sum + e.amount);

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
                  const Icon(Icons.layers_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Staged Batch (${_stagedEntries.length} ${_stagedEntries.length == 1 ? "item" : "items"})',
                    style: AppTextStyles.h4.copyWith(fontSize: 15, color: AppColors.textPrimary),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Total: ${currencyFmt.format(totalStaged)}',
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
            itemCount: _stagedEntries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final item = _stagedEntries[idx];
              final isExpense = item.mode == CashEntryMode.expense;
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
                        color: isExpense ? AppColors.rejected.withOpacity(0.15) : AppColors.approved.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isExpense ? 'EXP' : 'REC',
                        style: TextStyle(
                          color: isExpense ? AppColors.rejected : AppColors.approved,
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
                            item.expenseTypeName,
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${currencyFmt.format(item.amount)}${item.billNo != null ? ' • Bill #${item.billNo}' : ''}${item.partyName != null ? ' • ${item.partyName}' : ''}',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (item.photos.isNotEmpty) ...[
                      const Icon(Icons.photo_camera_rounded, size: 16, color: AppColors.textTertiary),
                      const SizedBox(width: 4),
                      Text('${item.photos.length}', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary)),
                      const SizedBox(width: 8),
                    ],
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.rejected, size: 20),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() {
                          _stagedEntries.removeAt(idx);
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
