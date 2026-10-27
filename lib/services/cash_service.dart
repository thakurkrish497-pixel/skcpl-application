import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cash_transaction_model.dart';
import '../models/stock_transaction_model.dart'; // for TransactionStatus
import '../core/constants/supabase_constants.dart';
import 'audit_service.dart';

/// Handles all cash book CRUD operations
class CashService {
  final SupabaseClient _client;

  CashService([SupabaseClient? client])
      : _client = client ??
            SupabaseClient(
              SupabaseConstants.supabaseUrl,
              SupabaseConstants.supabaseServiceRoleKey,
            );

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static const String _otherExpensePlaceholder = 'e72d9d18-2a33-4748-a04f-ddfdc9504a3f';

  Map<String, dynamic> _cleanPayload(Map<String, dynamic> raw) {
    final clean = Map<String, dynamic>.from(raw);
    clean.remove('id');

    final subBy = clean['submitted_by']?.toString().trim();
    if (subBy == null || subBy.isEmpty || !_uuidRegex.hasMatch(subBy)) {
      clean.remove('submitted_by');
    }

    final expTypeId = clean['expense_type_id']?.toString().trim();
    if (expTypeId == null || expTypeId.isEmpty || !_uuidRegex.hasMatch(expTypeId)) {
      clean['expense_type_id'] = _otherExpensePlaceholder;
    }

    return clean;
  }

  /// Submit a new cash transaction
  Future<CashTransactionModel> submitTransaction(
      CashTransactionModel transaction) async {
    final cleanData = _cleanPayload(transaction.toJson());
    cleanData['created_at'] = DateTime.now().toIso8601String();
    cleanData['updated_at'] = DateTime.now().toIso8601String();

    final data = await _client
        .from('cash_transactions')
        .insert(cleanData)
        .select('*, dropdown_items:expense_type_id(value)')
        .single();

    return CashTransactionModel.fromJson(data);
  }

  /// Update an existing cash transaction
  Future<CashTransactionModel> updateTransaction(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final cleanUpdates = _cleanPayload(updates);
    cleanUpdates['updated_at'] = DateTime.now().toIso8601String();

    final data = await _client
        .from('cash_transactions')
        .update(cleanUpdates)
        .eq('id', id)
        .select('*, dropdown_items:expense_type_id(value)')
        .single();

    return CashTransactionModel.fromJson(data);
  }

  /// Delete a cash transaction with Emergency Vault protection
  Future<void> deleteTransaction(String id) async {
    try {
      final existing = await _client.from('cash_transactions').select().eq('id', id).maybeSingle();
      if (existing != null) {
        await AuditService.captureDeletedRecord(
          entity: 'cash',
          entityId: id,
          recordData: Map<String, dynamic>.from(existing),
          reason: 'Manual deletion',
        );
      }
      await _client.from('cash_transactions').delete().eq('id', id);
    } catch (_) {}
  }

  /// Fetch all cash transactions across all sites (latest on top)
  Future<List<CashTransactionModel>> getAllTransactions({
    TransactionStatus? status,
  }) async {
    var query = _client
        .from('cash_transactions')
        .select('*, dropdown_items:expense_type_id(value)');

    if (status != null) {
      query = query.eq('status', status.dbValue);
    }

    final data = await query.order('created_at', ascending: false);
    return (data as List)
        .map((json) => CashTransactionModel.fromJson(json))
        .toList();
  }

  /// Fetch all cash transactions for a specific site
  Future<List<CashTransactionModel>> getTransactionsForSite(
    String siteId, {
    TransactionStatus? status,
  }) async {
    var query = _client
        .from('cash_transactions')
        .select('*, dropdown_items:expense_type_id(value)')
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
        .select('*, dropdown_items:expense_type_id(value)')
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
        .select('*, dropdown_items:expense_type_id(value)')
        .eq('status', 'pending_admin')
        .order('created_at', ascending: false);

    return (data as List)
        .map((json) => CashTransactionModel.fromJson(json))
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

  /// Accounts approves a cash transaction
  Future<void> approveByAccounts(String transactionId, String? reviewedBy) async {
    final validUserId = _ensureValidUuid(reviewedBy, isAdmin: false);
    final updateData = <String, dynamic>{
      'status': 'pending_admin',
      'reviewed_at': DateTime.now().toIso8601String(),
      'reviewed_by': validUserId,
    };

    await _client.from('cash_transactions').update(updateData).eq('id', transactionId);
  }

  /// Admin approves a cash transaction (permanent lock)
  Future<void> approveByAdmin(String transactionId, String? approvedBy) async {
    final validUserId = _ensureValidUuid(approvedBy, isAdmin: true);
    final updateData = <String, dynamic>{
      'status': 'approved',
      'approved_at': DateTime.now().toIso8601String(),
      'approved_by': validUserId,
    };

    await _client.from('cash_transactions').update(updateData).eq('id', transactionId);
  }

  /// Reject a cash transaction
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

    await _client.from('cash_transactions').update(updateData).eq('id', transactionId);
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
