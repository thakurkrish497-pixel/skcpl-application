import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/workflow_monitor_model.dart';
import '../models/user_model.dart';
import '../models/cash_transaction_model.dart';
import '../models/stock_transaction_model.dart';
import 'auth_provider.dart';
import 'cash_provider.dart';
import 'stock_provider.dart';
import 'role_access_provider.dart';
import 'management_review_provider.dart';
import 'staff_reminder_provider.dart';
export '../models/workflow_monitor_model.dart';

final workflowPollProvider = StateProvider<int>((ref) => 0);
final workflowRecipientProvider = Provider<String?>((ref) {
  final auth = ref.watch(authProvider);
  if (auth.user != null && auth.user!.role != UserRole.worker) {
    return 'management:${auth.user!.id}:${auth.user!.role.name}';
  }
  final staff = ref.watch(staffReminderIdentityProvider);
  return staff == null ? null : 'staff:${staff.siteId}:${staff.staffId}';
});

/// Read-only observer with a short debounce, separate from submission/queue locks.
final workflowMonitorProvider =
    FutureProvider.autoDispose<WorkflowSnapshot>((ref) async {
  final identity = ref.watch(workflowRecipientProvider);
  final role = ref.watch(authProvider.select((a) => a.user?.role));
  final foreground = ref.watch(staffReminderForegroundProvider);
  ref.watch(workflowPollProvider);
  if (identity == null ||
      role == null ||
      role == UserRole.worker ||
      !foreground) {
    return const WorkflowSnapshot([]);
  }
  final permissions = ref.watch(roleAccessProvider);
  // Existing realtime/provider updates act as signals; no sync engine is changed.
  ref.watch(cashProvider.select((s) => s.transactions));
  ref.watch(stockProvider.select((s) => s.transactions));
  bool disposed = false;
  ref.onDispose(() => disposed = true);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  if (disposed) return const WorkflowSnapshot([]);
  final warnings = <String>[];
  Future<List<T>> safe<T>(String label, Future<List<T>> Function() load) async {
    try {
      return await load();
    } catch (_) {
      warnings.add('$label could not be verified.');
      return [];
    }
  }

  final cashService = ref.read(cashServiceProvider),
      stockService = ref.read(stockServiceProvider);
  final cashEnabled = role == UserRole.admin ||
      (role == UserRole.projectHead
          ? permissions.projectHeadCanApproveCash
          : permissions.accountsCanApproveCash);
  final stockEnabled = role == UserRole.admin ||
      (role == UserRole.projectHead
          ? permissions.projectHeadCanApproveStock
          : permissions.accountsCanApproveStock);
  final dsrEnabled = role == UserRole.admin ||
      (role == UserRole.projectHead
          ? permissions.projectHeadCanApproveDSR
          : permissions.accountsCanApproveDSR);
  final attendanceEnabled = role == UserRole.admin ||
      (role == UserRole.projectHead
          ? permissions.projectHeadCanApproveAttendance
          : permissions.accountsCanApproveAttendance);
  // Watch existing queue futures before awaiting so their normal invalidation is reused.
  final dsr = dsrEnabled
      ? safe<ReviewQueueEntry>(
          'DSR checks',
          () => ref.watch(
              managementReviewQueueProvider((module: 'dsr', site: 'all'))
                  .future))
      : Future.value(<ReviewQueueEntry>[]);
  final attendance = attendanceEnabled
      ? safe<ReviewQueueEntry>(
          'Attendance checks',
          () => ref.watch(
              managementReviewQueueProvider((module: 'attendance', site: 'all'))
                  .future))
      : Future.value(<ReviewQueueEntry>[]);
  final cash = safe<CashTransactionModel>('Cash checks', () async {
    if (!cashEnabled) return [];
    if (role != UserRole.admin) return cashService.getPendingForAccounts();
    final lists = await Future.wait([
      cashService.getPendingForAccounts(),
      cashService.getPendingForAdmin()
    ]);
    return lists.expand((l) => l).toList();
  });
  final stock = safe<StockTransactionModel>('Stock checks', () async {
    if (!stockEnabled) return [];
    if (role != UserRole.admin) return stockService.getPendingForAccounts();
    final lists = await Future.wait([
      stockService.getPendingForAccounts(),
      stockService.getPendingForAdmin()
    ]);
    return lists.expand((l) => l).toList();
  });
  await Future.wait([cash, stock, dsr, attendance]);
  if (disposed) return const WorkflowSnapshot([]);
  return summarizeWorkflow(
      role: role,
      permissions: permissions,
      cash: await cash,
      stock: await stock,
      dsr: await dsr,
      attendance: await attendance,
      now: DateTime.now(),
      warnings: warnings);
});
