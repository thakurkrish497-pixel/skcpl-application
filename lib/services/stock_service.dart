import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/stock_transaction_model.dart';

/// Handles all stock transaction CRUD operations
class StockService {
  final SupabaseClient _client;

  StockService(this._client);

  /// Submit a new stock transaction (inbound or outbound)
  Future<StockTransactionModel> submitTransaction(
      StockTransactionModel transaction) async {
    final data = await _client
        .from('stock_transactions')
        .insert(transaction.toJson())
        .select()
        .single();

    return StockTransactionModel.fromJson(data);
  }

  /// Update an existing stock transaction (worker editing a pending record)
  Future<StockTransactionModel> updateTransaction(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final data = await _client
        .from('stock_transactions')
        .update(updates)
        .eq('id', id)
        .select()
        .single();

    return StockTransactionModel.fromJson(data);
  }

  /// Fetch all stock transactions for a specific site
  Future<List<StockTransactionModel>> getTransactionsForSite(
    String siteId, {
    TransactionStatus? status,
    TransactionType? type,
  }) async {
    var query = _client
        .from('stock_transactions')
        .select('*, sites(name), dropdowns!stock_transactions_product_id_fkey(value)')
        .eq('site_id', siteId);

    if (status != null) {
      query = query.eq('status', status.dbValue);
    }
    if (type != null) {
      query = query.eq('type', type.name);
    }

    final data = await query.order('date', ascending: false);
    return (data as List)
        .map((json) => StockTransactionModel.fromJson(json))
        .toList();
  }

  /// Fetch all pending transactions (for Accounts dashboard)
  Future<List<StockTransactionModel>> getPendingForAccounts() async {
    final data = await _client
        .from('stock_transactions')
        .select()
        .eq('status', 'pending_accounts')
        .order('created_at', ascending: false);

    return (data as List)
        .map((json) => StockTransactionModel.fromJson(json))
        .toList();
  }

  /// Fetch all pending-admin transactions (for Admin dashboard)
  Future<List<StockTransactionModel>> getPendingForAdmin() async {
    final data = await _client
        .from('stock_transactions')
        .select()
        .eq('status', 'pending_admin')
        .order('created_at', ascending: false);

    return (data as List)
        .map((json) => StockTransactionModel.fromJson(json))
        .toList();
  }

  /// Accounts approves a transaction: pending_accounts -> pending_admin
  Future<void> approveByAccounts(String transactionId, String reviewedBy) async {
    await _client.from('stock_transactions').update({
      'status': 'pending_admin',
      'reviewed_by': reviewedBy,
      'reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', transactionId);
  }

  /// Admin approves a transaction: pending_admin -> approved (permanent lock)
  Future<void> approveByAdmin(String transactionId, String approvedBy) async {
    await _client.from('stock_transactions').update({
      'status': 'approved',
      'approved_by': approvedBy,
      'approved_at': DateTime.now().toIso8601String(),
    }).eq('id', transactionId);
  }

  /// Reject a transaction (by either Accounts or Admin)
  Future<void> rejectTransaction(
    String transactionId,
    String rejectedBy,
    String note,
  ) async {
    await _client.from('stock_transactions').update({
      'status': 'rejected',
      'rejection_note': note,
      'reviewed_by': rejectedBy,
      'reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', transactionId);
  }

  /// Get real-time stock inventory for a specific site
  /// Uses the site_current_stock view
  Future<List<Map<String, dynamic>>> getCurrentStock(String siteId) async {
    final data = await _client
        .from('site_current_stock')
        .select()
        .eq('site_id', siteId);

    return List<Map<String, dynamic>>.from(data);
  }

  /// Get all stock across all sites (admin overview)
  Future<List<Map<String, dynamic>>> getAllSitesStock() async {
    final data = await _client.from('site_current_stock').select();
    return List<Map<String, dynamic>>.from(data);
  }

  /// Delete a stock transaction (admin-only)
  Future<void> deleteTransaction(String id) async {
    await _client.from('stock_transactions').delete().eq('id', id);
  }
}
