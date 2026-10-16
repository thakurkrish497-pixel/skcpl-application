import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cash_transaction_model.dart';
import '../models/stock_transaction_model.dart'; // for TransactionStatus

/// Handles all cash book CRUD operations
class CashService {
  final SupabaseClient _client;

  CashService(this._client);

  /// Submit a new cash transaction
  Future<CashTransactionModel> submitTransaction(
      CashTransactionModel transaction) async {
    final data = await _client
        .from('cash_transactions')
        .insert(transaction.toJson())
        .select()
        .single();

    return CashTransactionModel.fromJson(data);
  }

  /// Update an existing cash transaction (worker editing pending record)
  Future<CashTransactionModel> updateTransaction(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final data = await _client
        .from('cash_transactions')
        .update(updates)
        .eq('id', id)
        .select()
        .single();

    return CashTransactionModel.fromJson(data);
  }

  /// Fetch all cash transactions for a specific site
  Future<List<CashTransactionModel>> getTransactionsForSite(
    String siteId, {
    TransactionStatus? status,
  }) async {
    var query = _client
        .from('cash_transactions')
        .select()
        .eq('site_id', siteId);

    if (status != null) {
      query = query.eq('status', status.dbValue);
    }

    final data = await query.order('date', ascending: false);
    return (data as List)
        .map((json) => CashTransactionModel.fromJson(json))
        .toList();
  }

  /// Fetch pending cash transactions for Accounts review
  Future<List<CashTransactionModel>> getPendingForAccounts() async {
    final data = await _client
        .from('cash_transactions')
        .select()
        .eq('status', 'pending_accounts')
        .order('created_at', ascending: false);

    return (data as List)
        .map((json) => CashTransactionModel.fromJson(json))
        .toList();
  }

  /// Fetch pending-admin cash transactions for Admin approval
  Future<List<CashTransactionModel>> getPendingForAdmin() async {
    final data = await _client
        .from('cash_transactions')
        .select()
        .eq('status', 'pending_admin')
        .order('created_at', ascending: false);

    return (data as List)
        .map((json) => CashTransactionModel.fromJson(json))
        .toList();
  }

  /// Accounts approves a cash transaction
  Future<void> approveByAccounts(String transactionId, String reviewedBy) async {
    await _client.from('cash_transactions').update({
      'status': 'pending_admin',
      'reviewed_by': reviewedBy,
      'reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', transactionId);
  }

  /// Admin approves a cash transaction (permanent lock)
  Future<void> approveByAdmin(String transactionId, String approvedBy) async {
    await _client.from('cash_transactions').update({
      'status': 'approved',
      'approved_by': approvedBy,
      'approved_at': DateTime.now().toIso8601String(),
    }).eq('id', transactionId);
  }

  /// Reject a cash transaction
  Future<void> rejectTransaction(
    String transactionId,
    String rejectedBy,
    String note,
  ) async {
    await _client.from('cash_transactions').update({
      'status': 'rejected',
      'rejection_note': note,
      'reviewed_by': rejectedBy,
      'reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', transactionId);
  }

  /// Get total cash summary for a site (approved records only)
  Future<Map<String, double>> getSiteCashSummary(String siteId) async {
    final data = await _client
        .from('cash_transactions')
        .select('expense_amount, amount_received')
        .eq('site_id', siteId)
        .eq('status', 'approved');

    double totalExpense = 0;
    double totalReceived = 0;

    for (final row in data) {
      totalExpense += (row['expense_amount'] as num).toDouble();
      totalReceived += (row['amount_received'] as num).toDouble();
    }

    return {
      'total_expense': totalExpense,
      'total_received': totalReceived,
      'balance': totalReceived - totalExpense,
    };
  }
}
