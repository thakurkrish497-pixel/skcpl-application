import 'package:skcpl_app/providers/cash_provider.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skcpl_app/services/live_refresh_scheduler.dart';
import 'package:skcpl_app/services/offline_service.dart';
import 'package:skcpl_app/services/transaction_refresh.dart';
import 'package:skcpl_app/providers/dsr_history_provider.dart';
import 'package:skcpl_app/providers/attendance_provider.dart';
import 'sync_safety_test.dart' show cash, FakeCash, FakeStock;

void main() {
  test('A late cloud response cannot erase an acknowledged voucher', () async {
    final pending = Completer<List<CashTransactionModel>>();
    final service = FakeCash()..onLoad = () => pending.future;
    final notifier = CashNotifier(service);
    addTearDown(notifier.dispose);
    final oldFetch = notifier.loadAllTransactions();
    await Future<void>.delayed(Duration.zero);
    expect(await notifier.submitTransaction(cash()), true);
    final acknowledgedId = notifier.state.transactions.single.id;
    pending.complete([]);
    await oldFetch;
    expect(notifier.state.transactions.single.id, acknowledgedId);
    expect(notifier.state.isLoading, false);
  });

  testWidgets(
      'Live event bursts coalesce, with no parallel fetch and a follow-up for in-flight changes',
      (t) async {
    var calls = 0;
    final gate = Completer<void>();
    final scheduler = LiveRefreshScheduler(
        active: () => true,
        refresh: () async {
          calls++;
          if (calls == 1) await gate.future;
        });
    for (var i = 0; i < 20; i++) {
      scheduler.request();
    }
    await t.pump(const Duration(milliseconds: 151));
    expect(calls, 1);
    scheduler.request();
    await t.pump(const Duration(milliseconds: 151));
    expect(calls, 1);
    gate.complete();
    await t.pump();
    expect(calls, 2);
    scheduler.dispose();
  });
  testWidgets(
      'Refreshes stop in background and dispose; foreground request catches up',
      (t) async {
    var active = true, calls = 0;
    final scheduler = LiveRefreshScheduler(
        active: () => active,
        refresh: () async {
          calls++;
        });
    scheduler.request();
    active = false;
    await t.pump(const Duration(seconds: 1));
    expect(calls, 0);
    active = true;
    scheduler.request();
    await t.pump(const Duration(milliseconds: 151));
    expect(calls, 1);
    scheduler.request();
    scheduler.dispose();
    await t.pump(const Duration(seconds: 1));
    expect(calls, 1);
  });
  testWidgets('Refresh error does not lock the next live refresh', (t) async {
    var calls = 0;
    final scheduler = LiveRefreshScheduler(
        active: () => true,
        refresh: () async {
          calls++;
          if (calls == 1) throw StateError('network');
        });
    scheduler.request();
    await t.pump(const Duration(milliseconds: 151));
    scheduler.request();
    await t.pump(const Duration(milliseconds: 151));
    expect(calls, 2);
    scheduler.dispose();
  });
  test(
      'Explicit repaired-permission retry preserves identity and removes only acknowledged row',
      () async {
    final queued = await OfflineService.queueCashTransaction(cash());
    await OfflineService.pauseCash(
        queued.id!,
        StateError(
            'StorageException statusCode: 403 new row violates row-level security policy'));
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getStringList('offline_cash_queue_v1')!.single;
    var calls = 0;
    final service = FakeCash()
      ..onSubmit = (tx) async {
        calls++;
        expect(tx.id, queued.id);
        expect(
            tx.toJson(),
            jsonDecode(before)
              ..remove('sync_paused')
              ..remove('sync_error')
              ..remove('sync_version'));
        return tx;
      };
    final automatic = await OfflineService.syncAllQueued(
        stockService: FakeStock(), cashService: service);
    expect(automatic.remainingCount, 1);
    expect(calls, 0);
    expect(prefs.getStringList('offline_cash_queue_v1')!.single, before);
    final manual = await OfflineService.syncAllQueued(
        stockService: FakeStock(),
        cashService: service,
        retryPermissionFailures: true);
    expect(manual.syncedCount, 1);
    expect(manual.remainingCount, 0);
    expect(calls, 1);
  });
  test('Failed permission retry keeps the original entry and UUID', () async {
    final q = await OfflineService.queueCashTransaction(cash());
    await OfflineService.pauseCash(q.id!, StateError('403'));
    final service = FakeCash()
      ..onSubmit = (tx) async {
        throw StateError('403 still denied');
      };
    final result = await OfflineService.syncAllQueued(
        stockService: FakeStock(),
        cashService: service,
        retryPermissionFailures: true);
    expect(result.remainingCount, 1);
    expect(result.syncedCount, 0);
    expect((await OfflineService.getQueuedCashTransactions()).single.id, q.id);
  });
  test(
      'Manual retry never releases validation failures or ambiguous legacy queues',
      () async {
    final q = await OfflineService.queueCashTransaction(cash());
    await OfflineService.pauseCash(
        q.id!, StateError('Foreign key violation 23503'));
    var calls = 0;
    final service = FakeCash()
      ..onSubmit = (tx) async {
        calls++;
        return tx;
      };
    final result = await OfflineService.syncAllQueued(
        stockService: FakeStock(),
        cashService: service,
        retryPermissionFailures: true);
    expect(calls, 0);
    expect(result.remainingCount, 1);
    expect(
        OfflineService.canRetryPermissionFailure({
          'id': 'offline_cash_legacy',
          'sync_version': 1,
          'sync_error': '403'
        }),
        false);
    expect(
        OfflineService.canRetryPermissionFailure({
          'id': 'offline_cash_not-a-uuid',
          'sync_version': 2,
          'sync_error': '403'
        }),
        false);
  });
  test('Live refresh includes DSR history and dated/monthly attendance', () {
    final invalidated = <Object>[];
    invalidateTransactionViews(invalidated.add);
    expect(
        invalidated,
        containsAll([
          dsrHistoryProvider,
          attendanceForDateAndSiteProvider,
          monthlyAttendanceProvider
        ]));
  });
}
