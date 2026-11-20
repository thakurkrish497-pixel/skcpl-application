import 'dart:convert';
import 'user_model.dart';
import 'role_permissions_model.dart';
import 'cash_transaction_model.dart';
import 'stock_transaction_model.dart';
import '../services/management_review_service.dart';

enum WorkflowKind { cash, stock, dsr, attendance, summary }

class WorkflowAction {
  final String recipient;
  final WorkflowKind kind;
  final String day;
  const WorkflowAction(this.recipient, this.kind, {this.day = ''});
  String get payload => 'workflow.v1.${base64Url.encode(utf8.encode(jsonEncode({
            'recipient': recipient,
            'kind': kind.name,
            'day': day
          })))}';
  static WorkflowAction? decode(String? value) {
    if (value == null ||
        !value.startsWith('workflow.v1.') ||
        value.length > 2048) {
      return null;
    }
    try {
      final data =
          jsonDecode(utf8.decode(base64Url.decode(value.substring(12)))) as Map;
      final kind = WorkflowKind.values.byName(data['kind'] as String);
      final recipient = data['recipient'] as String;
      if (recipient.isEmpty) return null;
      return WorkflowAction(recipient, kind, day: data['day'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }
}

class WorkflowAlert {
  final WorkflowKind kind;
  final int count, overdue, oldestHours;
  final String title, message;
  const WorkflowAlert(this.kind, this.count, this.overdue, this.oldestHours,
      this.title, this.message);
  bool get needsPhone => oldestHours >= (kind == WorkflowKind.dsr ? 24 : 36);
}

class WorkflowBottleneck {
  final String id, siteId, waitingFor;
  final WorkflowKind kind;
  final int hours;
  const WorkflowBottleneck(
      this.id, this.siteId, this.kind, this.waitingFor, this.hours);
}

class WorkflowSnapshot {
  final List<WorkflowAlert> alerts;
  final List<WorkflowBottleneck> bottlenecks;
  final List<String> warnings;
  const WorkflowSnapshot(this.alerts,
      {this.bottlenecks = const [], this.warnings = const []});
  int get count =>
      alerts
          .where((a) => a.kind != WorkflowKind.summary)
          .fold<int>(0, (n, a) => n + a.count) +
      bottlenecks.where((b) => b.waitingFor != 'Admin').length;
}

/// Pure, linear aggregation. Never mutates records or advances an approval stage.
WorkflowSnapshot summarizeWorkflow(
    {required UserRole role,
    required RolePermissionsModel permissions,
    required List<CashTransactionModel> cash,
    required List<StockTransactionModel> stock,
    List<ReviewQueueEntry> dsr = const [],
    List<ReviewQueueEntry> attendance = const [],
    required DateTime now,
    List<String> warnings = const []}) {
  final verifiedWarnings = List<String>.from(warnings);
  final alerts = <WorkflowAlert>[];
  final bottlenecks = <WorkflowBottleneck>[];
  bool mine(TransactionStatus status, bool tagged, bool isStock) {
    if (role == UserRole.admin) {
      final head = isStock
          ? permissions.projectHeadCanApproveStock
          : permissions.projectHeadCanApproveCash;
      final accounts = isStock
          ? permissions.accountsCanApproveStock
          : permissions.accountsCanApproveCash;
      return status == TransactionStatus.pendingAdmin ||
          (status == TransactionStatus.pendingAccounts &&
              !accounts &&
              (!head || !tagged));
    }
    if (status != TransactionStatus.pendingAccounts) return false;
    final head = isStock
        ? permissions.projectHeadCanApproveStock
        : permissions.projectHeadCanApproveCash;
    final accounts = isStock
        ? permissions.accountsCanApproveStock
        : permissions.accountsCanApproveCash;
    if (role == UserRole.projectHead) return head && tagged;
    return role == UserRole.accounts && accounts && (!head || !tagged);
  }

  int hours(DateTime date) => now.toUtc().difference(date.toUtc()).inHours;
  void add(WorkflowKind kind, List<int> ages, String label,
      {int threshold = 36}) {
    if (ages.isEmpty) return;
    final oldest = ages.fold<int>(0, (a, b) => a > b ? a : b);
    final overdue = ages.where((a) => a >= threshold).length;
    alerts.add(WorkflowAlert(
        kind,
        ages.length,
        overdue,
        oldest,
        '$label: ${ages.length} pending',
        overdue > 0
            ? '$overdue waiting at least $threshold hours • oldest submitted ${oldest}h ago'
            : 'Ready for your review. Tap to open the pending queue.'));
  }

  void bottleneck(String? id, String site, WorkflowKind kind,
      TransactionStatus status, bool tagged, DateTime date, bool isStock) {
    final age = hours(date);
    if (role != UserRole.admin ||
        id == null ||
        age < 36 ||
        ![TransactionStatus.pendingAccounts, TransactionStatus.pendingAdmin]
            .contains(status)) {
      return;
    }
    final head = isStock
        ? permissions.projectHeadCanApproveStock
        : permissions.projectHeadCanApproveCash;
    bottlenecks.add(WorkflowBottleneck(
        id,
        site,
        kind,
        (status == TransactionStatus.pendingAdmin ||
                !(isStock
                        ? permissions.accountsCanApproveStock
                        : permissions.accountsCanApproveCash) &&
                    (!head || !tagged))
            ? 'Admin'
            : head && tagged
                ? 'Project Head'
                : 'Accounts',
        age));
  }

  if (role == UserRole.worker) return const WorkflowSnapshot([]);
  final cashAges = <int>[], stockAges = <int>[];
  final uniqueCash = {
    for (final t in cash) t.id ?? '${t.siteId}:${t.date}:${t.expenseAmount}': t
  };
  final uniqueStock = {
    for (final t in stock) t.id ?? '${t.siteId}:${t.date}:${t.quantity}': t
  };
  for (final t in uniqueCash.values) {
    if (mine(t.status, t.isPendingSupervisorReview, false)) {
      cashAges.add(hours(t.createdAt ?? t.date));
    }
    bottleneck(t.id, t.siteId, WorkflowKind.cash, t.status,
        t.isPendingSupervisorReview, t.createdAt ?? t.date, false);
  }
  for (final t in uniqueStock.values) {
    if (mine(t.status, t.isPendingSupervisorReview, true)) {
      stockAges.add(hours(t.createdAt ?? t.date));
    }
    bottleneck(t.id, t.siteId, WorkflowKind.stock, t.status,
        t.isPendingSupervisorReview, t.createdAt ?? t.date, true);
  }
  add(WorkflowKind.cash, cashAges, 'Cash vouchers');
  add(WorkflowKind.stock, stockAges, 'Stock vouchers');
  void nonFinancial(WorkflowKind kind, List<ReviewQueueEntry> rows,
      String label, int threshold) {
    final ages = <int>[];
    for (final row in rows) {
      final date = DateTime.tryParse('${row.data['created_at']}');
      if (date == null) {
        ages.add(0);
        final warning = '$label waiting time could not be verified.';
        if (!verifiedWarnings.contains(warning)) {
          verifiedWarnings.add(warning);
        }
      } else {
        final age = hours(date);
        ages.add(age);
        if (role == UserRole.admin && age >= threshold) {
          bottlenecks.add(WorkflowBottleneck(
              row.id, '${row.data['site_id']}', kind, 'Admin', age));
        }
      }
    }
    add(kind, ages, label, threshold: threshold);
  }

  final dsrAllowed = role == UserRole.admin ||
      (role == UserRole.projectHead
          ? permissions.projectHeadCanApproveDSR
          : permissions.accountsCanApproveDSR);
  final attendanceAllowed = role == UserRole.admin ||
      (role == UserRole.projectHead
          ? permissions.projectHeadCanApproveAttendance
          : permissions.accountsCanApproveAttendance);
  if (dsrAllowed) nonFinancial(WorkflowKind.dsr, dsr, 'DSR checks', 24);
  if (attendanceAllowed) {
    nonFinancial(WorkflowKind.attendance, attendance, 'Attendance reviews', 36);
  }
  if (role == UserRole.admin && bottlenecks.isNotEmpty) {
    final sites = bottlenecks.map((b) => b.siteId).toSet().length;
    final oldest =
        bottlenecks.fold<int>(0, (a, b) => a > b.hours ? a : b.hours);
    alerts.insert(
        0,
        WorkflowAlert(
            WorkflowKind.summary,
            bottlenecks.length,
            bottlenecks.length,
            oldest,
            '$sites sites need attention',
            '${bottlenecks.length} overdue items. See the site and approval stage holding each item.'));
  }
  return WorkflowSnapshot(List.unmodifiable(alerts),
      bottlenecks: List.unmodifiable(bottlenecks),
      warnings: List.unmodifiable(verifiedWarnings));
}
