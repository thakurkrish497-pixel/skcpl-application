import 'package:skcpl_app/providers/role_access_provider.dart';
import 'package:skcpl_app/services/cash_service.dart';
import 'package:skcpl_app/providers/cash_provider.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/models/role_permissions_model.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/providers/workflow_monitor_provider.dart';
import 'package:skcpl_app/providers/auth_provider.dart';
import 'package:skcpl_app/providers/staff_reminder_provider.dart';
import 'package:skcpl_app/services/management_review_service.dart';
import 'package:skcpl_app/services/notification_service.dart';
import 'dashboard_widget_test.dart' show FixedAuth;
import '../support/erp_test_backend.dart';

final now = DateTime.utc(2026, 11, 20, 12);
CashTransactionModel cash(String id,
        {bool head = false,
        int hours = 40,
        TransactionStatus status = TransactionStatus.pendingAccounts}) =>
    CashTransactionModel(
        id: id,
        siteId: 'site-a',
        date: DateTime(2026, 11, 19),
        expenseTypeId: 'type',
        expenseAmount: 100,
        cashInHand: 0,
        remarks: head ? '[PENDING SUPERVISOR REVIEW]' : null,
        status: status,
        createdAt: now.subtract(Duration(hours: hours)));
StockTransactionModel stock(String id,
        {bool head = false,
        int hours = 40,
        TransactionStatus status = TransactionStatus.pendingAccounts}) =>
    StockTransactionModel(
        id: id,
        siteId: 'site-b',
        date: DateTime(2026, 11, 19),
        type: TransactionType.outbound,
        productId: 'type',
        metricUnitId: 'unit',
        quantity: 1,
        remarks: head ? '[PENDING SUPERVISOR REVIEW]' : null,
        status: status,
        createdAt: now.subtract(Duration(hours: hours)));
ReviewQueueEntry report(String id, int hours) => ReviewQueueEntry.fromJson({
      'entry_id': id,
      'source_version': 'v1',
      'review_revision': 0,
      'review_state': {},
      'data': {
        'id': id,
        'site_id': 'site-a',
        'created_at': now.subtract(Duration(hours: hours)).toIso8601String()
      }
    });
WorkflowSnapshot run(UserRole role,
        {RolePermissionsModel policy = const RolePermissionsModel(),
        List<CashTransactionModel> c = const [],
        List<StockTransactionModel> s = const [],
        List<ReviewQueueEntry> d = const [],
        List<ReviewQueueEntry> a = const []}) =>
    summarizeWorkflow(
        role: role,
        permissions: policy,
        cash: c,
        stock: s,
        dsr: d,
        attendance: a,
        now: now);

class FixedMonitorPolicy extends StateNotifier<RolePermissionsModel>
    implements RoleAccessNotifier {
  FixedMonitorPolicy() : super(const RolePermissionsModel());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DeniedMonitorCash extends CashService {
  @override
  Future<List<CashTransactionModel>> getPendingForAccounts() async {
    throw StateError('Connection unavailable');
  }
}

void main() {
  test('Workflow payload roundtrip, unknown types and malformed payload safety',
      () {
    const action = WorkflowAction('staff:site:worker', WorkflowKind.dsr,
        day: '2026-11-20');
    final decoded = WorkflowAction.decode(action.payload)!;
    expect(decoded.recipient, action.recipient);
    expect(decoded.kind, WorkflowKind.dsr);
    expect(decoded.day, action.day);
    for (final input in [
      null,
      'birthday_staff',
      'workflow.v1.bad',
      'workflow.v1.${base64Url.encode(utf8.encode('{"kind":"delete","recipient":"x"}'))}'
    ]) {
      expect(WorkflowAction.decode(input), isNull);
    }
  });
  test('Project Head sees only the supervisor review stage', () {
    final snapshot = run(UserRole.projectHead, c: [
      cash('head', head: true),
      cash('accounts'),
      cash('admin', status: TransactionStatus.pendingAdmin)
    ], s: [
      stock('head-stock', head: true),
      stock('accounts-stock')
    ]);
    expect(snapshot.count, 2);
    expect(snapshot.alerts.map((a) => a.kind),
        [WorkflowKind.cash, WorkflowKind.stock]);
  });
  test('Accounts never receives records still waiting for Project Head', () {
    final snapshot = run(UserRole.accounts,
        c: [cash('head', head: true), cash('accounts')],
        s: [stock('head-stock', head: true), stock('accounts-stock')]);
    expect(snapshot.count, 2);
  });
  test('Disabled Project Head power routes tagged vouchers to Accounts', () {
    final policy = const RolePermissionsModel().copyWith(
        projectHeadCanApproveCash: false, projectHeadCanApproveStock: false);
    expect(
        run(UserRole.projectHead,
            policy: policy,
            c: [cash('a', head: true)],
            s: [stock('b', head: true)]).count,
        0);
    expect(
        run(UserRole.accounts,
            policy: policy,
            c: [cash('a', head: true)],
            s: [stock('b', head: true)]).count,
        2);
  });
  test('Disabled Accounts power bypasses to Admin without duplicate counts',
      () {
    final policy = const RolePermissionsModel().copyWith(
        accountsCanApproveCash: false, accountsCanApproveStock: false);
    final c = cash('a');
    final s = stock('b');
    final snapshot = run(UserRole.admin,
        policy: policy, c: [c, c, cash('head', head: true)], s: [s, s]);
    expect(snapshot.alerts.firstWhere((a) => a.kind == WorkflowKind.cash).count,
        1);
    expect(
        snapshot.alerts.firstWhere((a) => a.kind == WorkflowKind.stock).count,
        1);
    expect(
        snapshot.bottlenecks.where((b) => b.waitingFor == 'Admin').length, 2);
    expect(
        snapshot.bottlenecks
            .where((b) => b.waitingFor == 'Project Head')
            .length,
        1);
    expect(snapshot.count, 3);
  });
  test(
      'Admin summary includes overdue sites across financial stages, excludes completed records',
      () {
    final snapshot = run(UserRole.admin, c: [
      cash('a', head: true),
      cash('b'),
      cash('c', status: TransactionStatus.approved),
      cash('d', status: TransactionStatus.rejected)
    ], s: [
      stock('e', status: TransactionStatus.pendingAdmin)
    ]);
    expect(snapshot.bottlenecks.length, 3);
    expect(snapshot.alerts.first.kind, WorkflowKind.summary);
    expect(snapshot.alerts.first.title, '2 sites need attention');
  });
  test('Fresh vouchers get dashboard cards without a phone popup', () {
    final snapshot = run(UserRole.accounts, c: [cash('fresh', hours: 1)]);
    expect(snapshot.count, 1);
    expect(snapshot.alerts.single.needsPhone, isFalse);
  });
  test('Voucher popup starts at 36h and DSR at 24h, with exact boundaries', () {
    expect(
        run(UserRole.accounts, c: [cash('a', hours: 35)])
            .alerts
            .single
            .needsPhone,
        isFalse);
    expect(
        run(UserRole.accounts, c: [cash('a', hours: 36)])
            .alerts
            .single
            .needsPhone,
        isTrue);
    expect(
        run(UserRole.projectHead, d: [report('a', 23)])
            .alerts
            .single
            .needsPhone,
        isFalse);
    expect(
        run(UserRole.projectHead, d: [report('a', 24)])
            .alerts
            .single
            .needsPhone,
        isTrue);
    expect(
        run(UserRole.projectHead, d: [report('a', 36)])
            .alerts
            .single
            .oldestHours,
        36);
  });
  test('Accounts DSR/attendance approval powers must be explicitly enabled',
      () {
    expect(
        run(UserRole.accounts, d: [report('a', 40)], a: [report('b', 40)])
            .count,
        0);
    final policy = const RolePermissionsModel().copyWith(
        accountsCanApproveDSR: true, accountsCanApproveAttendance: true);
    expect(
        run(UserRole.accounts,
            policy: policy, d: [report('a', 40)], a: [report('b', 40)]).count,
        2);
  });
  test('Workers never receive management backlog summaries', () {
    expect(run(UserRole.worker, c: [cash('a')], d: [report('b', 48)]).alerts,
        isEmpty);
  });
  test('Summarizing never mutates source vouchers or review data', () {
    final c = cash('a', head: true);
    final d = report('b', 48);
    final before = jsonEncode([c.toJson(), d.data, d.review]);
    run(UserRole.admin, c: [c], d: [d]);
    expect(jsonEncode([c.toJson(), d.data, d.review]), before);
  });
  test('Denied/background/worker sessions make no monitoring network requests',
      () async {
    final backend = ErpTestBackend.instance;
    for (final role in [UserRole.admin, UserRole.worker]) {
      final container = ProviderContainer(overrides: [
        authProvider.overrideWith((ref) => FixedAuth(role)),
        staffReminderForegroundProvider.overrideWith((ref) => false)
      ]);
      backend.requests.clear();
      expect((await container.read(workflowMonitorProvider.future)).alerts,
          isEmpty);
      expect(backend.requests, isEmpty);
      container.dispose();
    }
  });
  test(
      'Monitor database failures are incomplete checks, never false all-clear or writes',
      () async {
    final backend = ErpTestBackend.instance;
    backend.requests.clear();
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => FixedAuth(UserRole.accounts)),
      cashServiceProvider.overrideWithValue(DeniedMonitorCash()),
      roleAccessProvider.overrideWith((ref) => FixedMonitorPolicy()),
    ]);
    addTearDown(container.dispose);
    container.listen(workflowMonitorProvider, (_, __) {});
    final snapshot = await container.read(workflowMonitorProvider.future);
    expect(snapshot.warnings, contains('Cash checks could not be verified.'));
    expect(
        backend.requests
            .where((r) => r.method != 'GET' && !r.url.path.contains('/rpc/')),
        isEmpty);
  });
  test(
      'Delivery deduplicates new monitor alerts without clearing prior notices',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final old =
        'announcement_existing:${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setStringList(NotificationDelivery.ledgerKey, [old]);
    var shown = 0;
    final delivery = NotificationDelivery(
        permission: () async => true,
        show: ({required title, required body, tag}) async {
          shown++;
        });
    const action = WorkflowAction('management:user:accounts', WorkflowKind.cash,
        day: '2026-11-20');
    await Future.wait(List.generate(
        5,
        (_) => delivery.send(
            key: action.payload,
            title: 'Pending',
            body: 'Review',
            repeatAfter: const Duration(hours: 6))));
    expect(shown, 1);
    expect(prefs.getStringList(NotificationDelivery.ledgerKey), contains(old));
  });
  test(
      'Reports with unknown submission time remain visible without an invented overdue age',
      () {
    final missing = ReviewQueueEntry.fromJson({
      'entry_id': 'old-report',
      'source_version': 'v1',
      'review_revision': 0,
      'review_state': {},
      'data': {'site_id': 'site-a'}
    });
    final result = run(UserRole.projectHead, d: [missing]);
    expect(result.count, 1);
    expect(result.alerts.single.needsPhone, isFalse);
    expect(result.warnings, isNotEmpty);
  });
}
