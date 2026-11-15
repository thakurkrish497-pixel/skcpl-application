import 'package:shared_preferences/shared_preferences.dart';
import 'package:skcpl_app/services/stock_service.dart';
import 'cashbook_form_test_support.dart';

void main() {
  test(
      'Background retries preserve paused cash errors without growing Bad state prefixes',
      () async {
    final tx = CashTransactionModel(
        id: submissionId(null),
        siteId: 'fixture-site',
        date: DateTime.now(),
        expenseTypeId: 'e72d9d18-2a33-4748-a04f-ddfdc9504a3f',
        expenseAmount: 10,
        cashInHand: -10);
    final queued = await OfflineService.queueCashTransaction(tx);
    await OfflineService.pauseCash(queued.id!,
        const StorageException('Photo upload denied', statusCode: '403'));
    final prefs = await SharedPreferences.getInstance();
    final original =
        List<String>.from(prefs.getStringList('offline_cash_queue_v1')!);
    for (var i = 0; i < 3; i++) {
      final result = await OfflineService.syncAllQueued(
          stockService: StockService(Supabase.instance.client),
          cashService: FormCash());
      expect(result.syncedCount, 0);
      expect(result.errors.single, contains('Photo upload denied'));
      expect(result.errors.single, isNot(contains('Bad state:')));
      expect(prefs.getStringList('offline_cash_queue_v1'), original);
    }
  });
}
