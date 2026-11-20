import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cash_transaction_model.dart';
import '../models/stock_transaction_model.dart';
import '../models/site_staff_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/site_staff_provider.dart';
import '../providers/rejected_entry_provider.dart';
import '../screens/cashbook/expense_form_screen.dart';
import '../screens/stock/add_product_screen.dart';
import '../screens/stock/use_product_screen.dart';

// Worker actions stay disabled in production until a separate access rollout.
final workerRejectedEntryActionsProvider = Provider<bool>((ref) => false);

bool canHandleRejected(
    {required UserRole? role,
    required String? userId,
    required String? submittedBy,
    required String siteId,
    required String? submitter,
    required SiteStaffModel? staff,
    required bool stock,
    bool workerActionsEnabled = false}) {
  if (role == UserRole.admin) return true;
  if (!workerActionsEnabled) return false;
  if (role != null && role != UserRole.worker) return false;
  if (userId != null && submittedBy == userId) return true;
  if (submittedBy != null ||
      staff == null ||
      staff.siteId != siteId ||
      !staff.isActive ||
      !staff.hasModule(stock ? StaffModule.stock : StaffModule.cashbook)) {
    return false;
  }
  return submitter ==
      '${staff.name} (${staff.designation ?? staff.role.displayName})';
}

class RejectedEntryActions extends ConsumerStatefulWidget {
  final CashTransactionModel? cash;
  final StockTransactionModel? stock;
  const RejectedEntryActions({super.key, this.cash, this.stock})
      : assert((cash != null) != (stock != null));
  @override
  ConsumerState<RejectedEntryActions> createState() =>
      _RejectedEntryActionsState();
}

class _RejectedEntryActionsState extends ConsumerState<RejectedEntryActions> {
  bool _busy = false;
  String get _module => widget.cash != null ? 'cash' : 'stock';
  String? get _id => widget.cash?.id ?? widget.stock?.id;
  void _closeHandledDialog() {
    final route = ModalRoute.of(context);
    if (route is PopupRoute && route.isCurrent) Navigator.pop(context, true);
  }

  Future<void> _dismiss() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Delete / Dismiss rejected entry?'),
                content: const Text(
                    'This rejected entry will be removed from history for everyone. It will not be resubmitted. A protected audit record is retained.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete / Dismiss'))
                ]));
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(rejectedEntryServiceProvider).dismiss(
          _module, _id!, widget.cash?.updatedAt ?? widget.stock?.updatedAt,
          staff: ref.read(activeStaffProvider));
      if (!mounted) return;
      await refreshRejectedEntries(ref);
      if (mounted) _closeHandledDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Rejected entry removed from all histories.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Could not confirm dismissal. Refresh history before retrying: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _sourceData() => {
        ...?widget.cash?.toJson(),
        ...?widget.stock?.toJson(),
        'rejection_note':
            widget.cash?.rejectionNote ?? widget.stock?.rejectionNote,
        'reviewed_by': widget.cash?.reviewedBy ?? widget.stock?.reviewedBy,
        'reviewed_at': (widget.cash?.reviewedAt ?? widget.stock?.reviewedAt)
            ?.toIso8601String(),
        'approved_by': widget.cash?.approvedBy ?? widget.stock?.approvedBy,
        'approved_at': (widget.cash?.approvedAt ?? widget.stock?.approvedAt)
            ?.toIso8601String(),
        'created_at': (widget.cash?.createdAt ?? widget.stock?.createdAt)
            ?.toIso8601String(),
        'updated_at': (widget.cash?.updatedAt ?? widget.stock?.updatedAt)
            ?.toIso8601String(),
      };
  Map<String, dynamic> _restore(Map<String, dynamic> source, Map input) => {
        ...source,
        ...Map<String, dynamic>.from(input),
        for (final key in [
          'id',
          'site_id',
          'submitted_by',
          'status',
          'rejection_note',
          'reviewed_by',
          'reviewed_at',
          'approved_by',
          'approved_at',
          'created_at',
          'updated_at'
        ])
          key: source[key],
      };
  Future<void> _edit() async {
    setState(() => _busy = true);
    try {
      final draft =
          await ref.read(rejectedEntryServiceProvider).draft(_module, _id!);
      if (!mounted) return;
      final data = draft?['input'] as Map?;
      final restoredCash = widget.cash == null
          ? null
          : data == null
              ? widget.cash
              : CashTransactionModel.fromJson(_restore(_sourceData(), data));
      final restoredStock = widget.stock == null
          ? null
          : data == null
              ? widget.stock
              : StockTransactionModel.fromJson(_restore(_sourceData(), data));
      final page = restoredCash != null
          ? ExpenseFormScreen(existingTransaction: restoredCash)
          : restoredStock!.type == TransactionType.inbound
              ? AddProductScreen(existingTransaction: restoredStock)
              : UseProductScreen(existingTransaction: restoredStock);
      final changed = await Navigator.push(
          context, MaterialPageRoute(builder: (_) => page));
      if (mounted) await refreshRejectedEntries(ref);
      if (mounted && changed == true) _closeHandledDialog();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open correction: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.cash?.status ?? widget.stock!.status;
    if (status != TransactionStatus.rejected ||
        _id == null ||
        _id!.startsWith('offline_')) {
      return const SizedBox.shrink();
    }
    final auth = ref.watch(authProvider),
        staff = ref.watch(activeStaffProvider);
    final workerActionsEnabled = ref.watch(workerRejectedEntryActionsProvider);
    final bySnapshot = canHandleRejected(
        workerActionsEnabled: workerActionsEnabled,
        role: auth.user?.role,
        userId: auth.user?.id,
        submittedBy: widget.cash?.submittedBy ?? widget.stock?.submittedBy,
        siteId: widget.cash?.siteId ?? widget.stock!.siteId,
        submitter: widget.cash?.submitterName ?? widget.stock?.submitterName,
        staff: staff,
        stock: widget.stock != null);
    final eligibleStaff = workerActionsEnabled &&
        staff != null &&
        staff.isActive &&
        staff.siteId == (widget.cash?.siteId ?? widget.stock!.siteId) &&
        staff.hasModule(
            widget.stock != null ? StaffModule.stock : StaffModule.cashbook) &&
        (auth.user == null || auth.user!.role == UserRole.worker);
    final owners = !bySnapshot && eligibleStaff
        ? ref.watch(rejectedResubmissionOwnersProvider).valueOrNull
        : null;
    final linkedOwner = owners == null ? null : owners['$_module:$_id'];
    final allowed = bySnapshot || (eligibleStaff && linkedOwner == staff.id);
    if (!allowed) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_busy)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              if (!auth.isAdmin)
                OutlinedButton.icon(
                    onPressed: _busy ? null : _edit,
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Edit & Resubmit')),
              TextButton.icon(
                  onPressed: _busy ? null : _dismiss,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete / Dismiss')),
            ]));
  }
}
