import 'package:skcpl_app/services/offline_service.dart';
import 'package:skcpl_app/providers/cash_provider.dart';
import 'sync_safety_test.dart' show cash, FakeCash, FakeStock;
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/models/site_staff_model.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/services/rejected_entry_service.dart';
import 'package:skcpl_app/widgets/rejected_entry_actions.dart';

const oldId = '10000000-0000-4000-8000-000000000001';
final stamp = DateTime.utc(2026, 11, 20, 10);
final staff = SiteStaffModel(
    id: 'staff',
    siteId: 'site',
    name: 'Ramesh',
    role: SiteStaffRole.worker,
    designation: 'Engineer',
    pin: 'fixture-pin',
    modules: const [StaffModule.cashbook, StaffModule.stock],
    createdAt: stamp);
CashTransactionModel rejected() => CashTransactionModel(
    id: oldId,
    siteId: 'site',
    date: DateTime(2026, 11, 20),
    expenseTypeId: 'type',
    expenseAmount: 100,
    cashInHand: 0,
    status: TransactionStatus.rejected,
    rejectionNote: 'Wrong bill',
    remarks: '[By: Ramesh (Engineer)] Work',
    updatedAt: stamp);

class ActionServer {
  bool fail = false, handled = false;
  int calls = 0;
  final ids = <String>[];
  final requests = <Map<String, dynamic>>[];
  Map<String, dynamic>? saved;
  late final client = SupabaseClient(
      'http://rejected.fixture.invalid', 'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
    Object? body;
    var status = 200;
    if (r.url.path.endsWith('skcpl_rejected_events')) {
      body =
          handled ? {'action': 'resubmit', 'replacement_id': ids.last} : null;
    } else if (r.url.path.endsWith('skcpl_rejected_entry_action')) {
      calls++;
      final params = Map<String, dynamic>.from(jsonDecode(r.body));
      requests.add(params);
      if (fail) {
        status = 503;
        body = {'code': 'gateway', 'message': 'offline'};
      } else {
        if (params['p_action'] == 'resubmit') {
          ids.add(params['p_new_id']);
          saved = {
            ...Map<String, dynamic>.from(params['p_payload']),
            'id': params['p_new_id'],
            'status': 'pending_accounts',
            'rejection_note': null
          };
          body = {
            'entry': saved,
            'action': 'resubmit',
            'already_saved': handled,
            'source_id': params['p_source'],
            'replacement_id': params['p_new_id']
          };
          handled = true;
        } else {
          body = {'action': 'dismiss', 'source_id': params['p_source']};
        }
      }
    } else {
      status = 400;
      body = {'message': 'Unexpected request'};
    }
    return http.Response(jsonEncode(body), status,
        request: r, headers: {'content-type': 'application/json'});
  }));
}

void main() {
  for (final direction in [TransactionType.inbound, TransactionType.outbound]) {
    test(
        '$direction rejection resubmission preserves direction and uses a fresh identity',
        () async {
      final server = ActionServer();
      addTearDown(server.client.dispose);
      final source = StockTransactionModel(
          id: oldId,
          siteId: 'site',
          date: DateTime(2026, 11, 20),
          type: direction,
          productId: 'product',
          metricUnitId: 'unit',
          quantity: 10,
          rate: 5,
          sgst: 0,
          igst: 0,
          status: TransactionStatus.rejected,
          rejectionNote: 'Check quantity',
          updatedAt: stamp);
      final result = await RejectedEntryService(server.client)
          .resubmitStock(source, source.copyWith(quantity: 12), staff: staff);
      expect(result.id, isNot(oldId));
      expect(result.type, direction);
      expect(result.quantity, 12);
      expect(result.status, TransactionStatus.pendingAccounts);
      expect(source.quantity, 10);
      expect(source.rejectionNote, 'Check quantity');
      expect(server.requests.single['p_module'], 'stock');
    });
  }

  test(
      'A handled rejected queue copy is archived and resolved without a new voucher',
      () async {
    final queued = await OfflineService.queueCashTransaction(cash());
    final id = queued.id!.split('offline_cash_').last;
    final client = SupabaseClient('http://receipt.fixture.invalid', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async => http.Response(
            jsonEncode(
                {'source_id': id, 'action': 'dismiss', 'replacement_id': null}),
            200,
            request: r,
            headers: {'content-type': 'application/json'})));
    addTearDown(client.dispose);
    final receipts = RejectedEntryService(client);
    final service = FakeCash()
      ..onSubmit = (tx) async {
        await receipts.checkHandledSubmission('cash', tx.id!, tx.toJson());
        return tx;
      };
    final result = await OfflineService.syncAllQueued(
        stockService: FakeStock(), cashService: service);
    expect(result.retiredCount, 1);
    expect(result.syncedCount, 0);
    expect(result.remainingCount, 0);
    expect(result.errors, isEmpty);
    final saved = (await SharedPreferences.getInstance())
        .getString('handled_rejected_copy_v1_cash_$id');
    expect(saved, isNotNull);
    expect(jsonDecode(saved!)['payload']['expense_amount'], 500);
  });
  test('Direct retry of a handled entry never adds it back to visible history',
      () async {
    const id = '40000000-0000-4000-8000-000000000001';
    final client = SupabaseClient('http://receipt.fixture.invalid', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async => http.Response(
            jsonEncode({
              'source_id': id,
              'action': 'resubmit',
              'replacement_id': '40000000-0000-4000-8000-000000000002'
            }),
            200,
            request: r,
            headers: {'content-type': 'application/json'})));
    addTearDown(client.dispose);
    final receipts = RejectedEntryService(client);
    final service = FakeCash()
      ..onSubmit = (tx) async {
        await receipts.checkHandledSubmission('cash', tx.id!, tx.toJson());
        return tx;
      };
    final notifier = CashNotifier(service);
    addTearDown(notifier.dispose);
    expect(await notifier.submitTransaction(cash(id: id)), false);
    expect(notifier.state.transactions, isEmpty);
    expect(notifier.state.error, contains('preserved'));
    expect(await OfflineService.getPendingSyncCount(), 0);
  });

  test('Only original staff or Admin can see rejection cleanup controls', () {
    bool allowed(UserRole? role, {SiteStaffModel? person, String? owner}) =>
        canHandleRejected(
            workerActionsEnabled: true,
            role: role,
            userId: 'auth',
            submittedBy: owner,
            siteId: 'site',
            submitter: 'Ramesh (Engineer)',
            staff: person,
            stock: false);
    expect(allowed(null, person: staff), true);
    expect(allowed(UserRole.admin), true);
    expect(allowed(UserRole.accounts, person: staff), false);
    expect(allowed(UserRole.projectHead, person: staff), false);
    expect(allowed(null, person: staff.copyWith(siteId: 'other')), false);
    expect(allowed(null, person: staff.copyWith(name: 'Other')), false);
    expect(allowed(null, person: staff, owner: 'another-user'), false);
    expect(allowed(UserRole.worker, owner: 'auth'), true);
  });
  test(
      'Resubmission creates a fresh identity and keeps source/reason unmodified',
      () async {
    final server = ActionServer();
    addTearDown(server.client.dispose);
    final service = RejectedEntryService(server.client), source = rejected();
    final original = source.toJson();
    final result = await service.resubmitCash(
        source, source.copyWith(expenseAmount: 125),
        staff: staff);
    expect(result.id, isNot(source.id));
    expect(result.status, TransactionStatus.pendingAccounts);
    expect(source.toJson(), original);
    expect(source.rejectionNote, 'Wrong bill');
    expect(server.requests.single['p_source'], oldId);
    expect(server.requests.single['p_staff_pin'], 'fixture-pin');
    expect(await service.draft('cash', oldId), isNull);
  });
  test(
      'Failure preserves original feedback and durable correction without storing credentials',
      () async {
    final server = ActionServer()..fail = true;
    addTearDown(server.client.dispose);
    final service = RejectedEntryService(server.client), source = rejected();
    await expectLater(
        service.resubmitCash(source, source.copyWith(expenseAmount: 175),
            staff: staff),
        throwsA(isA<PostgrestException>()));
    final draft = await service.draft('cash', oldId);
    expect(draft!['input']['expense_amount'], 175);
    expect(jsonEncode(draft), isNot(contains('fixture-pin')));
    expect(source.status, TransactionStatus.rejected);
    expect(source.rejectionNote, 'Wrong bill');
    final attemptedId = server.requests.single['p_new_id'];
    server.fail = false;
    final retry = await service.resubmitCash(
        source, source.copyWith(expenseAmount: 175),
        staff: staff);
    expect(retry.id, attemptedId);
    expect(server.requests.last['p_new_id'], attemptedId);
  });
  test(
      'Acknowledgement loss retries the same saved operation without another identity',
      () async {
    final server = ActionServer()..fail = true;
    addTearDown(server.client.dispose);
    final service = RejectedEntryService(server.client), source = rejected();
    try {
      await service.resubmitCash(source, source, staff: staff);
    } catch (_) {}
    final pending = await service.draft('cash', oldId);
    server.fail = false;
    server.handled = true;
    server.ids.add(pending!['new_id']);
    final result = await service.resubmitCash(source, source, staff: staff);
    expect(result.id, pending['new_id']);
    expect(await service.draft('cash', oldId), isNull);
  });
  test('Dismissal never edits the source or clears operational queues',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('offline_cash_queue_v1', ['existing-queue-row']);
    final server = ActionServer();
    addTearDown(server.client.dispose);
    await RejectedEntryService(server.client)
        .dismiss('cash', oldId, stamp, staff: staff);
    expect(server.requests.single['p_action'], 'dismiss');
    expect(
        server.requests.single['p_expected_updated'], stamp.toIso8601String());
    expect(
        prefs.getStringList('offline_cash_queue_v1'), ['existing-queue-row']);
  });
}
