import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/providers/cash_provider.dart';
import 'package:skcpl_app/services/offline_service.dart';
import 'package:skcpl_app/services/transaction_refresh.dart';
import 'package:skcpl_app/services/submission_support.dart';
import '../support/erp_test_backend.dart';
import 'sync_safety_test.dart' show FakeCash;

String get siteId =>
    ErpTestBackend.instance.tables['sites']!.first['id'] as String;
CashTransactionModel entry(String id,
        {double received = 0,
        double spent = 0,
        TransactionStatus status = TransactionStatus.approved,
        String? site}) =>
    CashTransactionModel(
        id: id,
        siteId: site ?? siteId,
        date: DateTime(2026, 11, 16),
        expenseTypeId: 'e72d9d18-2a33-4748-a04f-ddfdc9504a3f',
        amountReceived: received,
        expenseAmount: spent,
        cashInHand: 0,
        status: status);
List<CashTransactionModel> entries() => [
      entry('topup', received: 1000),
      entry('spent', spent: 200),
      entry('pending', spent: 100, status: TransactionStatus.pendingAccounts),
      entry('rejected', spent: 999, status: TransactionStatus.rejected),
      entry('other-site', received: 8000, site: 'other')
    ];
void main() {
  test(
      'Operational cash recomputes on submit, edit, approval, rejection and deletion without changing accounting totals',
      () async {
    var rows = entries();
    final service = FakeCash()..onLoad = () async => rows;
    final container = ProviderContainer(
        overrides: [cashProvider.overrideWith((ref) => CashNotifier(service))]);
    addTearDown(container.dispose);
    final subscription = container.listen(
        siteOperationalCashSummaryProvider(siteId), (_, __) {});
    addTearDown(subscription.close);
    Future<Map<String, double>> refresh() async {
      invalidateTransactionViews(container.invalidate);
      await container.read(cashProvider.notifier).refresh();
      return container.read(siteOperationalCashSummaryProvider(siteId));
    }

    var sum = await refresh();
    expect(sum['balance'], 700);
    expect(sum['approved_balance'], 800);
    expect(sum['pending_count'], 1);
    expect(sum['approved_expense'], 200);
    rows = [
      ...rows,
      entry('new', spent: 50, status: TransactionStatus.pendingAdmin)
    ];
    sum = await refresh();
    expect(sum['balance'], 650);
    expect(sum['pending_count'], 2);
    rows = rows
        .map((e) => e.id == 'new' ? e.copyWith(expenseAmount: 75) : e)
        .toList();
    expect((await refresh())['balance'], 625);
    rows = rows
        .map((e) => e.id == 'pending'
            ? e.copyWith(status: TransactionStatus.approved)
            : e)
        .toList();
    sum = await refresh();
    expect(sum['balance'], 625);
    expect(sum['approved_balance'], 700);
    expect(sum['pending_count'], 1);
    rows = rows
        .map((e) =>
            e.id == 'new' ? e.copyWith(status: TransactionStatus.rejected) : e)
        .toList();
    expect((await refresh())['balance'], 700);
    rows = rows.where((e) => e.id != 'pending').toList();
    sum = await refresh();
    expect(sum['balance'], 800);
    expect(sum['pending_count'], 0);
  });
  test(
      'Cashflow counts durable offline work once and never removes it while loading',
      () async {
    final queued = await OfflineService.queueCashTransaction(
        entry('queued', spent: 40, status: TransactionStatus.pendingAccounts));
    var rows = [entry('received', received: 100)];
    final service = FakeCash()..onLoad = () async => rows;
    final c = ProviderContainer(
        overrides: [cashProvider.overrideWith((ref) => CashNotifier(service))]);
    addTearDown(c.dispose);
    final sub =
        c.listen(siteOperationalCashSummaryProvider(siteId), (_, __) {});
    addTearDown(sub.close);
    await c.read(cashProvider.notifier).refresh();
    expect(c.read(siteOperationalCashSummaryProvider(siteId))['balance'], 60);
    expect(await OfflineService.getQueuedCashTransactions(), hasLength(1));
    rows = [...rows, queued.copyWith(id: submissionId(queued.id))];
    await c.read(cashProvider.notifier).refresh();
    expect(c.read(siteOperationalCashSummaryProvider(siteId))['balance'], 60);
    expect(await OfflineService.getQueuedCashTransactions(), hasLength(1));
  });
}
