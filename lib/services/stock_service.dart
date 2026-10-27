import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/stock_transaction_model.dart';
import '../core/constants/supabase_constants.dart';
import 'audit_service.dart';

/// Handles all stock transaction CRUD operations
class StockService {
  final SupabaseClient _client;

  StockService([SupabaseClient? client])
      : _client = client ??
            SupabaseClient(
              SupabaseConstants.supabaseUrl,
              SupabaseConstants.supabaseServiceRoleKey,
            );

  static const String _stockSelectQuery =
      '*, sites(name), product:dropdowns!stock_transactions_product_id_fkey(value), unit:dropdowns!stock_transactions_metric_unit_id_fkey(value), vendor:dropdowns!stock_transactions_vendor_id_fkey(value)';

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static const String _otherProductPlaceholder = '441097fa-eef6-4df4-a4f6-7b003b302c0b';
  static const String _otherUnitPlaceholder = '00000000-0000-0000-0000-000000000002';

  Map<String, dynamic> _cleanPayload(Map<String, dynamic> raw) {
    final clean = Map<String, dynamic>.from(raw);
    clean.remove('id');

    final subBy = clean['submitted_by']?.toString().trim();
    if (subBy == null || subBy.isEmpty || !_uuidRegex.hasMatch(subBy)) {
      clean.remove('submitted_by');
    }

    final vId = clean['vendor_id']?.toString().trim();
    if (vId == null || vId.isEmpty || !_uuidRegex.hasMatch(vId) || vId == 'OTHER') {
      clean.remove('vendor_id');
    }

    final pId = clean['product_id']?.toString().trim();
    if (pId == null || pId.isEmpty || !_uuidRegex.hasMatch(pId) || pId == 'OTHER') {
      clean['product_id'] = _otherProductPlaceholder;
    }

    final uId = clean['metric_unit_id']?.toString().trim();
    if (uId == null || uId.isEmpty || !_uuidRegex.hasMatch(uId) || uId == 'OTHER') {
      clean['metric_unit_id'] = _otherUnitPlaceholder;
    }

    return clean;
  }

  /// Submit a new stock transaction (inbound or outbound)
  Future<StockTransactionModel> submitTransaction(
      StockTransactionModel transaction) async {
    final cleanData = _cleanPayload(transaction.toJson());
    cleanData['created_at'] = DateTime.now().toIso8601String();
    cleanData['updated_at'] = DateTime.now().toIso8601String();

    final data = await _client
        .from('stock_transactions')
        .insert(cleanData)
        .select(_stockSelectQuery)
        .single();

    return StockTransactionModel.fromJson(data);
  }

  /// Update an existing stock transaction
  Future<StockTransactionModel> updateTransaction(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final cleanUpdates = _cleanPayload(updates);
    cleanUpdates['updated_at'] = DateTime.now().toIso8601String();

    final data = await _client
        .from('stock_transactions')
        .update(cleanUpdates)
        .eq('id', id)
        .select(_stockSelectQuery)
        .single();

    return StockTransactionModel.fromJson(data);
  }

  /// Delete a stock transaction with Emergency Vault protection
  Future<void> deleteTransaction(String id) async {
    try {
      final existing = await _client.from('stock_transactions').select().eq('id', id).maybeSingle();
      if (existing != null) {
        await AuditService.captureDeletedRecord(
          entity: 'stock',
          entityId: id,
          recordData: Map<String, dynamic>.from(existing),
          reason: 'Manual deletion',
        );
      }
      await _client.from('stock_transactions').delete().eq('id', id);
    } catch (_) {}
  }

  /// Fetch all stock transactions across all sites (latest on top)
  Future<List<StockTransactionModel>> getAllTransactions({
    TransactionStatus? status,
    TransactionType? type,
  }) async {
    var query = _client
        .from('stock_transactions')
        .select(_stockSelectQuery);

    if (status != null) {
      query = query.eq('status', status.dbValue);
    }
    if (type != null) {
      query = query.eq('type', type.name);
    }

    final data = await query.order('created_at', ascending: false);
    return (data as List)
        .map((json) => StockTransactionModel.fromJson(json))
        .toList();
  }

  /// Fetch all stock transactions for a specific site
  Future<List<StockTransactionModel>> getTransactionsForSite(
    String siteId, {
    TransactionStatus? status,
    TransactionType? type,
  }) async {
    var query = _client
        .from('stock_transactions')
        .select(_stockSelectQuery)
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
        .select(_stockSelectQuery)
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
        .select(_stockSelectQuery)
        .eq('status', 'pending_admin')
        .order('created_at', ascending: false);

    return (data as List)
        .map((json) => StockTransactionModel.fromJson(json))
        .toList();
  }

  static const String _defaultAdminUserId = '84b7c957-e145-446a-9a31-051f2cb9b3af';
  static const String _defaultAccountsUserId = '3f6ae45e-67ba-4513-93f6-a8e691c01907';

  String _ensureValidUuid(String? rawId, {bool isAdmin = true}) {
    if (rawId != null && _uuidRegex.hasMatch(rawId.trim())) {
      return rawId.trim();
    }
    final authId = _client.auth.currentUser?.id;
    if (authId != null && _uuidRegex.hasMatch(authId)) {
      return authId;
    }
    return isAdmin ? _defaultAdminUserId : _defaultAccountsUserId;
  }

  /// Accounts approves a transaction: pending_accounts -> pending_admin
  Future<void> approveByAccounts(String transactionId, String? reviewedBy) async {
    final validUserId = _ensureValidUuid(reviewedBy, isAdmin: false);
    final updateData = <String, dynamic>{
      'status': 'pending_admin',
      'reviewed_at': DateTime.now().toIso8601String(),
      'reviewed_by': validUserId,
    };

    await _client.from('stock_transactions').update(updateData).eq('id', transactionId);
  }

  /// Admin approves a transaction: pending_admin -> approved (permanent lock)
  Future<void> approveByAdmin(String transactionId, String? approvedBy) async {
    final validUserId = _ensureValidUuid(approvedBy, isAdmin: true);
    final updateData = <String, dynamic>{
      'status': 'approved',
      'approved_at': DateTime.now().toIso8601String(),
      'approved_by': validUserId,
    };

    await _client.from('stock_transactions').update(updateData).eq('id', transactionId);
  }

  /// Reject a transaction (by either Accounts or Admin)
  Future<void> rejectTransaction(
    String transactionId,
    String? rejectedBy,
    String note,
  ) async {
    final validUserId = _ensureValidUuid(rejectedBy, isAdmin: true);
    final updateData = <String, dynamic>{
      'status': 'rejected',
      'rejection_note': note,
      'reviewed_at': DateTime.now().toIso8601String(),
      'reviewed_by': validUserId,
    };

    await _client.from('stock_transactions').update(updateData).eq('id', transactionId);
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

}
