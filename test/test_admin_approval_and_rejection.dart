import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/services/cash_service.dart';
import 'package:skcpl_app/services/stock_service.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'support/erp_test_backend.dart';

void main() {
  for (final stock in [false, true]) {
    test(
        '${stock ? "Stock" : "Cash"}: authenticated Accounts → Admin, duplicate approval and final lock',
        () async {
      final client = Supabase.instance.client;
      final cash = CashService(client);
      final inventory = StockService(client);
      final table = stock ? 'stock_transactions' : 'cash_transactions';
      final payload = stock
          ? StockTransactionModel(
                  siteId: 'site-a',
                  type: TransactionType.inbound,
                  date: DateTime(2026, 11, 14),
                  productId: '441097fa-eef6-4df4-a4f6-7b003b302c0b',
                  metricUnitId: '00000000-0000-0000-0000-000000000002',
                  quantity: 20)
              .toJson()
          : CashTransactionModel(
                  siteId: 'site-a',
                  date: DateTime(2026, 11, 14),
                  expenseTypeId: 'e72d9d18-2a33-4748-a04f-ddfdc9504a3f',
                  amountReceived: 5000,
                  cashInHand: 0)
              .toJson();
      final row = await client.from(table).insert(payload).select().single();
      final id = row['id'] as String;
      Future<void> account(String user) => stock
          ? inventory.approveByAccounts(id, user)
          : cash.approveByAccounts(id, user);
      Future<void> admin(String user) => stock
          ? inventory.approveByAdmin(id, user)
          : cash.approveByAdmin(id, user);
      await expectLater(account('forged-reviewer'), throwsStateError);
      await client.auth.signInWithPassword(
          email: 'accounts@skcpl.com', password: 'fixture-password');
      await account(ErpTestBackend.accountsId);
      expect(
          (await client.from(table).select().eq('id', id).single())['status'],
          'pending_admin');
      await expectLater(admin(ErpTestBackend.accountsId), throwsStateError);
      await client.auth.signInWithPassword(
          email: 'admin@skcpl.com', password: 'fixture-password');
      await admin(ErpTestBackend.adminId);
      final approved = await client.from(table).select().eq('id', id).single();
      expect(approved['status'], 'approved');
      expect(approved['approved_by'], ErpTestBackend.adminId);
      await expectLater(
          admin(ErpTestBackend.adminId), throwsA(isA<PostgrestException>()));
      await expectLater(
          stock
              ? inventory.updateTransaction(id, {'quantity': 30})
              : cash.updateTransaction(id, {'amount_received': 6000}),
          throwsStateError);
    });
    test(
        '${stock ? "Stock" : "Cash"}: rejection requires a reason and persists reviewer/time',
        () async {
      final client = Supabase.instance.client;
      final table = stock ? 'stock_transactions' : 'cash_transactions';
      final row = await client
          .from(table)
          .insert({'site_id': 'site-a', 'status': 'pending_admin'})
          .select()
          .single();
      Future<void> reject(String note) => stock
          ? StockService(client)
              .rejectTransaction(row['id'], ErpTestBackend.adminId, note)
          : CashService(client)
              .rejectTransaction(row['id'], ErpTestBackend.adminId, note);
      await expectLater(reject('  '), throwsArgumentError);
      await reject('Bill mismatch');
      final result =
          await client.from(table).select().eq('id', row['id']).single();
      expect(result['status'], 'rejected');
      expect(result['rejection_note'], 'Bill mismatch');
      expect(result['reviewed_by'], ErpTestBackend.adminId);
      expect(result['reviewed_at'], isNotNull);
    });
  }
}
