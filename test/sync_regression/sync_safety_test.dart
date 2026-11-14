import '../support/erp_test_backend.dart';
import 'package:skcpl_app/services/storage_service.dart';
import 'package:skcpl_app/services/draft_store.dart';
import 'package:skcpl_app/services/transaction_refresh.dart';
import 'package:skcpl_app/screens/cashbook/expense_form_screen.dart';
import 'package:skcpl_app/screens/stock/add_product_screen.dart';
import 'package:skcpl_app/screens/stock/use_product_screen.dart';
import 'package:skcpl_app/widgets/photo_picker.dart';
import 'package:skcpl_app/providers/stock_provider.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/models/role_permissions_model.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/providers/cash_provider.dart';
import 'package:skcpl_app/services/cash_service.dart';
import 'package:skcpl_app/services/stock_service.dart';
import 'package:skcpl_app/services/offline_service.dart';
import 'package:skcpl_app/services/submission_support.dart';
import 'package:skcpl_app/services/review_access.dart';

const cashKey = 'offline_cash_queue_v1';
CashTransactionModel cash(
        {String? id, String remarks = 'receipt', double amount = 500}) =>
    CashTransactionModel(
        id: id,
        siteId: 'site-a',
        date: DateTime(2026, 11, 14),
        expenseTypeId: 'e72d9d18-2a33-4748-a04f-ddfdc9504a3f',
        expenseAmount: amount,
        cashInHand: 0,
        remarks: remarks);

class FakeCash extends CashService {
  Future<CashTransactionModel> Function(CashTransactionModel)? onSubmit;
  Future<List<CashTransactionModel>> Function()? onLoad;
  FakeCash()
      : super(SupabaseClient('http://127.0.0.1:1', 'fake-public-key',
            httpClient: ErpTestBackend.instance.client));
  @override
  Future<CashTransactionModel> submitTransaction(
          CashTransactionModel tx) async =>
      onSubmit == null
          ? tx.copyWith(id: submissionId(tx.id))
          : await onSubmit!(tx);
  @override
  Future<CashTransactionModel> updateTransaction(
          String id, Map<String, dynamic> updates) async =>
      throw const PostgrestException(
          message: 'permission denied', code: '42501');
  @override
  Future<List<CashTransactionModel>> getAllTransactions(
          {TransactionStatus? status}) async =>
      onLoad == null ? [] : await onLoad!();
}

class FakeStock extends StockService {
  FakeStock()
      : super(SupabaseClient('http://127.0.0.1:1', 'fake-public-key',
            httpClient: ErpTestBackend.instance.client));
  @override
  Future<StockTransactionModel> submitTransaction(
          StockTransactionModel tx) async =>
      tx;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('queue reads preserve sabji and hp expenses', () async {
    await OfflineService.queueCashTransaction(
        cash(remarks: 'sabji', amount: 5000));
    await OfflineService.queueCashTransaction(
        cash(remarks: 'hp', amount: 3000));
    expect((await OfflineService.getQueuedCashTransactions()).length, 2);
    expect(await OfflineService.getPendingSyncCount(), 2);
  });
  test('legacy entries are preserved and held for reconciliation', () async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode({...cash().toJson(), 'id': 'offline_cash_old'});
    await prefs.setStringList(cashKey, [raw]);
    var called = false;
    final service = FakeCash()
      ..onSubmit = (tx) async {
        called = true;
        return tx;
      };
    final result = await OfflineService.syncAllQueued(
        stockService: FakeStock(), cashService: service);
    expect(called, false);
    expect(result.remainingCount, 1);
    expect(result.errors.single, contains('reconciliation'));
    expect(await OfflineService.getPendingSyncCount(), 1);
  });
  test('enqueue during a flush is retained and overlapping flush joins',
      () async {
    await OfflineService.queueCashTransaction(cash());
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    final service = FakeCash()
      ..onSubmit = (tx) async {
        calls++;
        entered.complete();
        await release.future;
        return tx;
      };
    final first = OfflineService.syncAllQueued(
        stockService: FakeStock(), cashService: service);
    await entered.future;
    final second = OfflineService.syncAllQueued(
        stockService: FakeStock(), cashService: service);
    final added =
        OfflineService.queueCashTransaction(cash(remarks: 'during sync'));
    release.complete();
    await Future.wait([first, second, added]);
    expect(calls, 1);
    expect((await OfflineService.getQueuedCashTransactions()).single.remarks,
        'during sync');
  });
  test('failed cloud edit is not acknowledged or queued as a new insert',
      () async {
    final notifier = CashNotifier(FakeCash());
    addTearDown(notifier.dispose);
    expect(
        await notifier.updateTransaction(cash(id: submissionId(null))), false);
    expect(notifier.state.error, contains('permission denied'));
    expect(await OfflineService.getPendingSyncCount(), 0);
  });
  test('permanent submission errors are not labelled offline', () async {
    final notifier = CashNotifier(FakeCash()
      ..onSubmit = (tx) async => throw const PostgrestException(
          message: 'missing expense type', code: '23503'));
    addTearDown(notifier.dispose);
    expect(await notifier.submitTransaction(cash()), false);
    expect(notifier.state.error, contains('missing expense type'));
    expect(await OfflineService.getPendingSyncCount(), 1);
    var called = false;
    final retry = FakeCash()
      ..onSubmit = (tx) async {
        called = true;
        return tx;
      };
    await OfflineService.syncAllQueued(
        stockService: FakeStock(), cashService: retry);
    expect(called, false);
  });
  test('photo bytes and stable identity survive offline retry', () async {
    final tx = cash(id: submissionId(null)).copyWith(pendingPhotos: [
      PendingPhoto(bytes: Uint8List.fromList([1, 2, 3]), name: 'receipt.jpg')
    ]);
    final notifier = CashNotifier(FakeCash()
      ..onSubmit = (tx) async => throw http.ClientException('offline'));
    addTearDown(notifier.dispose);
    expect(await notifier.submitTransaction(tx), true);
    final queued = (await OfflineService.getQueuedCashTransactions()).single;
    expect(submissionId(queued.id), tx.id);
    expect(queued.pendingPhotos.single.bytes, [1, 2, 3]);
    expect(notifier.state.error, 'OFFLINE_SAVED');
  });
  test('an absent queue edit cannot match another record by remarks', () async {
    final queued = await OfflineService.queueCashTransaction(cash());
    await expectLater(
        OfflineService.updateQueuedCashTransaction(
            queued.copyWith(id: 'offline_cash_missing')),
        throwsStateError);
    expect((await OfflineService.getQueuedCashTransactions()).single.id,
        queued.id);
  });
  test('failed refresh retains last successful cloud history', () async {
    final service = FakeCash()..onLoad = () async => [cash(id: 'cloud-row')];
    final notifier = CashNotifier(service);
    addTearDown(notifier.dispose);
    await notifier.loadAllTransactions();
    service.onLoad = () async => throw http.ClientException('offline');
    await notifier.loadAllTransactions();
    expect(notifier.state.transactions.single.id, 'cloud-row');
    expect(notifier.state.error, isNotNull);
  });
  test('late refresh responses cannot overwrite newer history', () async {
    final old = Completer<List<CashTransactionModel>>();
    var loads = 0;
    final notifier = CashNotifier(FakeCash()
      ..onLoad =
          () => ++loads == 1 ? old.future : Future.value([cash(id: 'new')]));
    addTearDown(notifier.dispose);
    final first = notifier.loadAllTransactions();
    await notifier.loadAllTransactions();
    old.complete([cash(id: 'old')]);
    await first;
    expect(notifier.state.transactions.single.id, 'new');
  });
  test('commit followed by lost response is reconciled without a second INSERT',
      () async {
    Map<String, dynamic>? stored;
    var inserts = 0;
    final client = SupabaseClient('http://127.0.0.1:1', 'fake-public-key',
        httpClient: MockClient((request) async {
      if (request.method == 'POST') {
        inserts++;
        stored = Map<String, dynamic>.from(jsonDecode(request.body));
        throw http.ClientException('response lost after commit');
      }
      return http.Response(jsonEncode(stored == null ? [] : [stored]), 200,
          request: request, headers: {'content-type': 'application/json'});
    }));
    final service = CashService(client);
    final tx = cash(id: submissionId(null));
    await expectLater(
        service.submitTransaction(tx), throwsA(isA<http.ClientException>()));
    final result = await service.submitTransaction(tx);
    expect(result.id, tx.id);
    expect(inserts, 1);
  });
  test('review gate respects role, stage, permission and local state', () {
    bool gate(UserRole role, TransactionStatus status,
            {bool head = false,
            bool queued = false,
            RolePermissionsModel permissions = const RolePermissionsModel()}) =>
        canReviewTransaction(
            role: role,
            status: status,
            stock: false,
            pendingProjectHead: head,
            queued: queued,
            permissions: permissions);
    expect(
        gate(UserRole.projectHead, TransactionStatus.pendingAccounts), false);
    expect(gate(UserRole.accounts, TransactionStatus.pendingAdmin), false);
    expect(
        gate(UserRole.accounts, TransactionStatus.pendingAccounts, head: true),
        false);
    expect(
        gate(UserRole.accounts, TransactionStatus.pendingAccounts,
            permissions:
                const RolePermissionsModel(accountsCanApproveCash: false)),
        false);
    expect(gate(UserRole.accounts, TransactionStatus.pendingAccounts), true);
    expect(gate(UserRole.admin, TransactionStatus.pendingAdmin), true);
    expect(gate(UserRole.admin, TransactionStatus.pendingAdmin, queued: true),
        false);
  });
  test('submission is durable before the service attempts a network write',
      () async {
    final notifier = CashNotifier(FakeCash()
      ..onSubmit = (tx) async {
        final pending = await OfflineService.getQueuedCashTransactions();
        expect(pending.single.id, tx.id);
        expect(pending.single.pendingPhotos.single.bytes, [7, 8]);
        return tx.copyWith(id: submissionId(tx.id), pendingPhotos: []);
      });
    addTearDown(notifier.dispose);
    expect(
        await notifier.submitTransaction(cash().copyWith(pendingPhotos: [
          PendingPhoto(bytes: Uint8List.fromList([7, 8]), name: 'receipt.jpg')
        ])),
        true);
    expect(await OfflineService.getPendingSyncCount(), 0);
  });
  test('stock queue also preserves raw photos and identity', () async {
    final tx = StockTransactionModel(
        id: submissionId(null),
        siteId: 'site-a',
        type: TransactionType.inbound,
        date: DateTime(2026, 11, 14),
        productId: 'material',
        metricUnitId: 'bags',
        quantity: 20,
        pendingPhotos: [
          PendingPhoto(bytes: Uint8List.fromList([9]), name: 'challan.jpg')
        ]);
    final queued = await OfflineService.queueStockTransaction(tx);
    final restored = (await OfflineService.getQueuedStockTransactions()).single;
    expect(restored.pendingPhotos.single.bytes, [9]);
    expect(submissionId(restored.id), tx.id);
    await OfflineService.updateQueuedStockTransaction(
        queued.copyWith(quantity: 30));
    expect((await OfflineService.getQueuedStockTransactions()).single.quantity,
        30);
  });
  test('correcting a paused entry resumes only new-format submissions',
      () async {
    final queued = await OfflineService.queueCashTransaction(cash());
    await OfflineService.pauseCash(queued.id!, StateError('correct me'));
    await OfflineService.updateQueuedCashTransaction(
        queued.copyWith(remarks: 'corrected'));
    final result = await OfflineService.syncAllQueued(
        stockService: FakeStock(), cashService: FakeCash());
    expect(result.syncedCount, 1);
    expect(result.remainingCount, 0);
  });
  test('malformed queue payload remains in storage and produces an error',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(cashKey, ['not json']);
    final result = await OfflineService.syncAllQueued(
        stockService: FakeStock(), cashService: FakeCash());
    expect(result.errors, isNotEmpty);
    expect(result.remainingCount, 1);
    expect(prefs.getStringList(cashKey), ['not json']);
  });
  test('staged cash, inward and outward drafts roundtrip with receipt bytes',
      () async {
    final draft = CashEntryDraft(
        id: submissionId(null),
        mode: CashEntryMode.expense,
        expenseTypeId: 'expense',
        expenseTypeName: 'Fuel',
        amount: 500,
        date: DateTime(2026, 11, 14),
        billNo: '123',
        photos: [
          PickedPhoto(bytes: Uint8List.fromList([4, 5]), name: 'receipt.jpg')
        ]);
    await DraftStore.save('test-staged', {
      'entries': [draft.toLocalJson()]
    });
    final saved = await DraftStore.load('test-staged');
    final restored = CashEntryDraft.fromLocalJson(
        Map<String, dynamic>.from((saved!['entries'] as List).single));
    expect(restored.id, draft.id);
    expect(restored.photos.single.bytes, [4, 5]);
    expect(restored.billNo, '123');
    final inward = StockInwardDraft(
        id: 'in',
        productId: 'cement',
        productName: 'Cement',
        metricUnitId: 'bags',
        metricUnitName: 'Bags',
        quantity: 50,
        rate: 300);
    expect(StockInwardDraft.fromLocalJson(inward.toLocalJson()).toLocalJson(),
        inward.toLocalJson());
    final outward = StockOutwardDraft(
        id: 'out',
        productId: 'cement',
        productName: 'Cement',
        metricUnitId: 'bags',
        metricUnitName: 'Bags',
        quantity: 10);
    expect(StockOutwardDraft.fromLocalJson(outward.toLocalJson()).toLocalJson(),
        outward.toLocalJson());
  });
  test('central refresh invalidates approval queues and summary families', () {
    final invalidated = <Object>[];
    invalidateTransactionViews(invalidated.add);
    expect(
        invalidated,
        containsAll([
          pendingCashAccountsProvider,
          pendingCashAdminProvider,
          pendingStockAccountsProvider,
          pendingStockAdminProvider,
          siteCashSummaryProvider,
          stockOverviewProvider,
          allSitesStockProvider
        ]));
  });
  test('transaction history and cash totals paginate beyond the first page',
      () async {
    final offsets = <int>[];
    final client = SupabaseClient('http://127.0.0.1:1', 'fake-public-key',
        httpClient: MockClient((request) async {
      final offset = int.parse(request.url.queryParameters['offset']!);
      offsets.add(offset);
      final rows = List.generate(
          offset == 0 ? 500 : 1,
          (i) => {
                ...cash(id: 'row-${offset + i}', amount: 1).toJson(),
                'status': 'approved',
                'amount_received': 2
              });
      return http.Response(jsonEncode(rows), 200,
          request: request, headers: {'content-type': 'application/json'});
    }));
    final summary = await CashService(client).getSiteCashSummary('site-a');
    expect(offsets, [0, 500]);
    expect(summary['balance'], 501);
  });
  test('partial cash updates cannot reset unrelated financial fields',
      () async {
    Map<String, dynamic>? sent;
    final client = SupabaseClient('http://erp.test.invalid', 'fake-public-key',
        httpClient: MockClient((request) async {
      final current = {
        ...cash(id: 'cloud-id').toJson(),
        'updated_at': '2026-11-14T00:00:00Z'
      };
      if (request.method == 'PATCH') {
        sent = Map<String, dynamic>.from(jsonDecode(request.body));
      }
      final body =
          request.url.path.endsWith('/tasks') ? [] : {...current, ...?sent};
      return http.Response(jsonEncode(body), 200,
          request: request, headers: {'content-type': 'application/json'});
    }));
    await CashService(client)
        .updateTransaction('cloud-id', {'remarks': 'corrected'});
    expect(sent!.containsKey('expense_amount'), false);
    expect(sent!.containsKey('amount_received'), false);
    expect(sent!.containsKey('expense_type_id'), false);
    expect(sent!.containsKey('status'), false);
    expect(sent!['remarks'], 'corrected');
  });
  test('attachment retry uses injected auth client and a deterministic path',
      () async {
    final paths = <String>[];
    final client = SupabaseClient('http://127.0.0.1:1', 'fake-public-key',
        httpClient: MockClient((request) async {
      paths.add(request.url.path);
      return http.Response(
          jsonEncode({'Key': 'transaction_photos/photos/cash/entry/0.jpg'}),
          200,
          request: request,
          headers: {'content-type': 'application/json'});
    }));
    final storage = StorageService(client);
    for (var i = 0; i < 2; i++) {
      await storage.uploadPhotoBytes(Uint8List.fromList([1, 2]),
          submissionPath: 'photos/cash/entry/0.jpg');
    }
    expect(paths.length, 2);
    expect(paths[0], paths[1]);
    expect(paths.first, endsWith('/photos/cash/entry/0.jpg'));
  });
}
