import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/core/constants/supabase_constants.dart';
import 'package:skcpl_app/services/stock_service.dart';
import 'package:skcpl_app/services/cash_service.dart';

void main() {
  group('Admin & Accounts Approval and Rejection Reliability Tests', () {
    late SupabaseClient client;
    late StockService stockService;
    late CashService cashService;

    setUp(() {
      client = SupabaseClient(
        SupabaseConstants.supabaseUrl,
        SupabaseConstants.supabaseServiceRoleKey,
      );
      stockService = StockService(client);
      cashService = CashService(client);
    });

    test('StockService handles mock admin-management-id and approves stock successfully', () async {
      // Find a pending stock transaction, or create a temporary one
      final existing = await client
          .from('stock_transactions')
          .select('id, status')
          .limit(1);

      expect(existing.isNotEmpty, true, reason: 'Should have at least one stock transaction in DB');
      final txId = existing.first['id'] as String;
      final originalStatus = existing.first['status'] as String;

      // Approve using mock / non-UUID ID that previously caused Postgres syntax error
      await stockService.approveByAdmin(txId, 'admin-management-id');

      // Verify DB record
      final updated = await client
          .from('stock_transactions')
          .select('status, approved_by, approved_at')
          .eq('id', txId)
          .single();

      expect(updated['status'], 'approved');
      expect(updated['approved_by'], '84b7c957-e145-446a-9a31-051f2cb9b3af');
      expect(updated['approved_at'], isNotNull);

      // Revert status back if it was pending
      if (originalStatus != 'approved') {
        await client.from('stock_transactions').update({'status': originalStatus}).eq('id', txId);
      }
    });

    test('StockService handles rejection with mock ID and records rejection note', () async {
      final existing = await client
          .from('stock_transactions')
          .select('id, status')
          .limit(1);

      final txId = existing.first['id'] as String;
      final originalStatus = existing.first['status'] as String;

      await stockService.rejectTransaction(
        txId,
        'admin-management-id',
        'Verified rejection test reason',
      );

      final updated = await client
          .from('stock_transactions')
          .select('status, reviewed_by, rejection_note')
          .eq('id', txId)
          .single();

      expect(updated['status'], 'rejected');
      expect(updated['reviewed_by'], '84b7c957-e145-446a-9a31-051f2cb9b3af');
      expect(updated['rejection_note'], 'Verified rejection test reason');

      // Revert status back
      await client.from('stock_transactions').update({'status': originalStatus}).eq('id', txId);
    });

    test('CashService handles mock admin-management-id and approves cash successfully', () async {
      final existing = await client
          .from('cash_transactions')
          .select('id, status')
          .limit(1);

      expect(existing.isNotEmpty, true, reason: 'Should have at least one cash transaction in DB');
      final txId = existing.first['id'] as String;
      final originalStatus = existing.first['status'] as String;

      await cashService.approveByAdmin(txId, 'admin-management-id');

      final updated = await client
          .from('cash_transactions')
          .select('status, approved_by, approved_at')
          .eq('id', txId)
          .single();

      expect(updated['status'], 'approved');
      expect(updated['approved_by'], '84b7c957-e145-446a-9a31-051f2cb9b3af');
      expect(updated['approved_at'], isNotNull);

      // Revert status back if it was pending
      if (originalStatus != 'approved') {
        await client.from('cash_transactions').update({'status': originalStatus}).eq('id', txId);
      }
    });

    test('CashService handles rejection with mock ID and records rejection note', () async {
      final existing = await client
          .from('cash_transactions')
          .select('id, status')
          .limit(1);

      final txId = existing.first['id'] as String;
      final originalStatus = existing.first['status'] as String;

      await cashService.rejectTransaction(
        txId,
        'admin-management-id',
        'Over budget rejection',
      );

      final updated = await client
          .from('cash_transactions')
          .select('status, reviewed_by, rejection_note')
          .eq('id', txId)
          .single();

      expect(updated['status'], 'rejected');
      expect(updated['reviewed_by'], '84b7c957-e145-446a-9a31-051f2cb9b3af');
      expect(updated['rejection_note'], 'Over budget rejection');

      // Revert status back
      await client.from('cash_transactions').update({'status': originalStatus}).eq('id', txId);
    });

    test('Accounts approval handles non-UUID reviewed_by properly', () async {
      final existingStock = await client
          .from('stock_transactions')
          .select('id, status')
          .limit(1);

      final txId = existingStock.first['id'] as String;
      final originalStatus = existingStock.first['status'] as String;

      await stockService.approveByAccounts(txId, 'accounts-management-id');

      final updated = await client
          .from('stock_transactions')
          .select('status, reviewed_by')
          .eq('id', txId)
          .single();

      expect(updated['status'], 'pending_admin');
      expect(updated['reviewed_by'], '3f6ae45e-67ba-4513-93f6-a8e691c01907');

      // Revert status back
      await client.from('stock_transactions').update({'status': originalStatus}).eq('id', txId);
    });
  });
}
