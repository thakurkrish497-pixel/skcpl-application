import 'inventory_math.dart';
import 'transaction_mutation.dart';
import 'role_access_service.dart';
import 'submission_support.dart';
import 'storage_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cash_transaction_model.dart';
import '../models/stock_transaction_model.dart'; // for TransactionStatus
import 'audit_service.dart';

/// Handles all cash book CRUD operations
class CashService {
  final SupabaseClient _client;

  CashService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static const String _otherExpensePlaceholder =
      'e72d9d18-2a33-4748-a04f-ddfdc9504a3f';

  Map<String, dynamic> _cleanPayload(Map<String, dynamic> raw) {
    final clean = Map<String, dynamic>.from(raw);
    clean.remove('id');
    clean.remove('local_pending_photos');

    final subBy = clean['submitted_by']?.toString().trim();
    if (subBy == null || subBy.isEmpty || !_uuidRegex.hasMatch(subBy)) {
      clean.remove('submitted_by');
    }

    final expTypeId = clean['expense_type_id']?.toString().trim();
    if (expTypeId == null ||
        expTypeId.isEmpty ||
        !_uuidRegex.hasMatch(expTypeId)) {
      clean['expense_type_id'] = _otherExpensePlaceholder;
    }

    clean['cash_in_hand'] = (clean['cash_in_hand'] as num?)?.toDouble() ?? 0.0;
    clean['expense_amount'] =
        (clean['expense_amount'] as num?)?.toDouble() ?? 0.0;
    clean['amount_received'] =
        (clean['amount_received'] as num?)?.toDouble() ?? 0.0;
    clean['status'] = clean['status'] ?? 'pending_accounts';

    return clean;
  }

  /// Submit a new cash transaction
  Future<CashTransactionModel> submitTransaction(
      CashTransactionModel transaction) async {
    requireFiniteAmount(transaction.expenseAmount, 'Expense');
    requireFiniteAmount(transaction.amountReceived, 'Cash received');
    if ((transaction.expenseAmount > 0) == (transaction.amountReceived > 0)) {
      throw ArgumentError('Enter either an expense or a top-up, not both.');
    }
    final id = submissionId(transaction.id);
    // Acknowledgement may have been lost after the first INSERT committed.
    final existing = await _client
        .from('cash_transactions')
        .select('*, dropdown_items:expense_type_id(value)')
        .eq('id', id)
        .maybeSingle();
    if (existing != null) {
      if (existing['site_id'] != transaction.siteId) {
        throw StateError('Submission identity belongs to another site.');
      }
      return CashTransactionModel.fromJson(existing);
    }
    final urls = List<String>.from(transaction.photoUrls);
    final storage = StorageService(_client);
    for (var i = 0; i < transaction.pendingPhotos.length; i++) {
      final photo = transaction.pendingPhotos[i];
      urls.add(await storage.uploadPhotoBytes(photo.bytes,
          fileName: photo.name, submissionPath: 'photos/cash/$id/$i.jpg'));
    }
    final cleanData = _cleanPayload(transaction.toJson());
    cleanData['id'] = id;
    cleanData['photo_urls'] = urls;
    cleanData['created_at'] = DateTime.now().toUtc().toIso8601String();
    cleanData['updated_at'] = DateTime.now().toUtc().toIso8601String();
    try {
      final data = await _client
          .from('cash_transactions')
          .insert(cleanData)
          .select('*, dropdown_items:expense_type_id(value)')
          .single();
      return CashTransactionModel.fromJson(data);
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
      final data = await _client
          .from('cash_transactions')
          .select('*, dropdown_items:expense_type_id(value)')
          .eq('id', id)
          .single();
      return CashTransactionModel.fromJson(data);
    }
  }

  /// Update an existing cash transaction
  Future<CashTransactionModel> updateTransaction(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final edit =
        await prepareTransactionEdit(_client, 'cash_transactions', id, updates);
    final current = edit['current'] as Map<String, dynamic>;
    final cleanUpdates = edit['changes'] as Map<String, dynamic>;
    final merged = {...current, ...cleanUpdates};
    requireFiniteAmount(merged['expense_amount'] as num, 'Expense');
    requireFiniteAmount(merged['amount_received'] as num, 'Cash received');
    if (((merged['expense_amount'] as num) > 0) ==
        ((merged['amount_received'] as num) > 0)) {
      throw ArgumentError('Enter either an expense or a top-up.');
    }

    final data = await _client
        .from('cash_transactions')
        .update(cleanUpdates)
        .eq('id', id)
        .eq('status', current['status'])
        .eq('updated_at', current['updated_at'])
        .select('*, dropdown_items:expense_type_id(value)')
        .single();

    return CashTransactionModel.fromJson(data);
  }

  /// Delete a cash transaction with Emergency Vault protection
  Future<void> deleteTransaction(String id) async {
    try {
      final existing = await _client
          .from('cash_transactions')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (existing != null) {
        await AuditService.captureDeletedRecord(
          entity: 'cash',
          entityId: id,
          recordData: Map<String, dynamic>.from(existing),
          reason: 'Manual deletion',
        );
      }
      await _client.from('cash_transactions').delete().eq('id', id);
    } catch (_) {
      rethrow;
    }
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

    final data = <Map<String, dynamic>>[];
    for (var offset = 0;; offset += 500) {
      final page = await query
          .order('created_at', ascending: false)
          .order('id')
          .range(offset, offset + 499);
      data.addAll(List<Map<String, dynamic>>.from(page));
      if (page.length < 500) break;
    }
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

    final data = <Map<String, dynamic>>[];
    for (var offset = 0;; offset += 500) {
      final page = await query
          .order('date', ascending: false)
          .order('id')
          .range(offset, offset + 499);
      data.addAll(List<Map<String, dynamic>>.from(page));
      if (page.length < 500) break;
    }
    return (data as List)
        .map((json) => CashTransactionModel.fromJson(json))
        .toList();
  }

  /// Fetch pending cash transactions for Accounts review
  Future<List<CashTransactionModel>> getPendingForAccounts() =>
      getAllTransactions(status: TransactionStatus.pendingAccounts);

  /// Fetch pending-admin cash transactions for Admin approval
  Future<List<CashTransactionModel>> getPendingForAdmin() =>
      getAllTransactions(status: TransactionStatus.pendingAdmin);

  Future<({String id, String role})> _reviewIdentity(String? claimedId) async {
    final id = _client.auth.currentUser?.id;
    if (id == null || (claimedId != null && claimedId != id)) {
      throw StateError(
          'Sign in with your verified company account before reviewing.');
    }
    final profile = await _client
        .from('users')
        .select('role, is_active')
        .eq('id', id)
        .single();
    if (profile['is_active'] == false) {
      throw StateError('This company account is inactive.');
    }
    return (id: id, role: profile['role'] as String);
  }

  Future<String> _requireReviewer(String role, String? claimedId) async {
    final identity = await _reviewIdentity(claimedId);
    if (identity.role != role) {
      throw StateError('This approval stage requires $role access.');
    }
    return identity.id;
  }

  /// Accounts approves a cash transaction
  Future<void> approveByAccounts(
      String transactionId, String? reviewedBy) async {
    final validUserId = await _requireReviewer('accounts', reviewedBy);
    final permissions =
        await RoleAccessService(_client).getVerifiedPermissions();
    if (!permissions.accountsCanApproveCash) {
      throw StateError('Accounts approval is disabled by Admin.');
    }
    final current = CashTransactionModel.fromJson(await _client
        .from('cash_transactions')
        .select()
        .eq('id', transactionId)
        .single());
    if (permissions.projectHeadCanApproveCash &&
        current.isPendingSupervisorReview) {
      throw StateError(
          'Project Head review is still pending. Refresh this entry.');
    }
    final updateData = <String, dynamic>{
      'status': 'pending_admin',
      'reviewed_at': DateTime.now().toIso8601String(),
      'reviewed_by': validUserId,
    };

    await _client
        .from('cash_transactions')
        .update(updateData)
        .eq('id', transactionId)
        .eq('status', 'pending_accounts')
        .select('id')
        .single();
  }

  /// Admin approves a cash transaction (permanent lock)
  Future<void> approveByAdmin(String transactionId, String? approvedBy) async {
    final validUserId = await _requireReviewer('admin', approvedBy);
    final updateData = <String, dynamic>{
      'status': 'approved',
      'approved_at': DateTime.now().toIso8601String(),
      'approved_by': validUserId,
    };

    await _client
        .from('cash_transactions')
        .update(updateData)
        .eq('id', transactionId)
        .eq('status', 'pending_admin')
        .select('id')
        .single();
  }

  /// Reject a cash transaction
  Future<void> rejectTransaction(
    String transactionId,
    String? rejectedBy,
    String note, {
    String? remarks,
  }) async {
    final identity = await _reviewIdentity(rejectedBy);
    final validUserId = identity.id;
    final role = identity.role;
    if (!['admin', 'accounts', 'project_head'].contains(role)) {
      throw StateError('Review access required.');
    }
    final permissions =
        await RoleAccessService(_client).getVerifiedPermissions();
    if ((role == 'accounts' && !permissions.accountsCanApproveCash) ||
        (role == 'project_head' && !permissions.projectHeadCanApproveCash)) {
      throw StateError('This review permission is disabled by Admin.');
    }
    if (note.trim().isEmpty) {
      throw ArgumentError('A rejection reason is required.');
    }
    final updateData = <String, dynamic>{
      'status': 'rejected',
      'rejection_note': note,
      if (remarks != null) 'remarks': remarks,
      'reviewed_at': DateTime.now().toIso8601String(),
      'reviewed_by': validUserId,
    };

    await _client
        .from('cash_transactions')
        .update(updateData)
        .eq('id', transactionId)
        .eq('status', role == 'admin' ? 'pending_admin' : 'pending_accounts')
        .select('id')
        .single();
  }

  /// Get total cash summary for a site (approved records only)
  Future<Map<String, double>> getSiteCashSummary(String siteId) async {
    final transactions = await getTransactionsForSite(siteId,
        status: TransactionStatus.approved);

    double totalExpense = 0;
    double totalReceived = 0;

    for (final transaction in transactions) {
      totalExpense += transaction.expenseAmount;
      totalReceived += transaction.amountReceived;
    }

    return {
      'total_expense': totalExpense,
      'total_received': totalReceived,
      'balance': totalReceived - totalExpense,
    };
  }
}
