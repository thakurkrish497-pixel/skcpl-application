import 'inventory_math.dart';
import 'transaction_mutation.dart';
import 'role_access_service.dart';
import 'submission_support.dart';
import 'storage_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/stock_transaction_model.dart';
import 'audit_service.dart';

/// Handles all stock transaction CRUD operations
class StockService {
  final SupabaseClient _client;

  StockService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  static const String _stockSelectQuery =
      '*, sites(name), product:dropdowns!stock_transactions_product_id_fkey(value), unit:dropdowns!stock_transactions_metric_unit_id_fkey(value), vendor:dropdowns!stock_transactions_vendor_id_fkey(value)';

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static const String _otherProductPlaceholder =
      '441097fa-eef6-4df4-a4f6-7b003b302c0b';
  static const String _otherUnitPlaceholder =
      '00000000-0000-0000-0000-000000000002';

  Map<String, dynamic> _cleanPayload(Map<String, dynamic> raw) {
    final clean = Map<String, dynamic>.from(raw);
    clean.remove('id');
    clean.remove('local_pending_photos');

    final subBy = clean['submitted_by']?.toString().trim();
    if (subBy == null || subBy.isEmpty || !_uuidRegex.hasMatch(subBy)) {
      clean.remove('submitted_by');
    }

    final vId = clean['vendor_id']?.toString().trim();
    if (vId == null ||
        vId.isEmpty ||
        !_uuidRegex.hasMatch(vId) ||
        vId == 'OTHER') {
      clean.remove('vendor_id');
    }

    final pId = clean['product_id']?.toString().trim();
    if (pId == null ||
        pId.isEmpty ||
        !_uuidRegex.hasMatch(pId) ||
        pId == 'OTHER') {
      clean['product_id'] = _otherProductPlaceholder;
    }

    final uId = clean['metric_unit_id']?.toString().trim();
    if (uId == null ||
        uId.isEmpty ||
        !_uuidRegex.hasMatch(uId) ||
        uId == 'OTHER') {
      clean['metric_unit_id'] = _otherUnitPlaceholder;
    }

    clean['quantity'] = (clean['quantity'] as num?)?.toDouble() ?? 0.0;
    clean['status'] = clean['status'] ?? 'pending_accounts';

    return clean;
  }

  /// Submit a new stock transaction (inbound or outbound)
  Future<StockTransactionModel> submitTransaction(
      StockTransactionModel transaction) async {
    requireFiniteAmount(transaction.quantity, 'Quantity', positive: true);
    if (transaction.rate != null) {
      requireFiniteAmount(transaction.rate!, 'Rate');
    }
    requireFiniteAmount(transaction.sgst, 'SGST');
    requireFiniteAmount(transaction.igst, 'IGST');
    final id = submissionId(transaction.id);
    // Acknowledgement may have been lost after the first INSERT committed.
    final existing = await _client
        .from('stock_transactions')
        .select(_stockSelectQuery)
        .eq('id', id)
        .maybeSingle();
    if (existing != null) {
      if (existing['site_id'] != transaction.siteId) {
        throw StateError('Submission identity belongs to another site.');
      }
      return StockTransactionModel.fromJson(existing);
    }
    final urls = List<String>.from(transaction.photoUrls);
    final storage = StorageService(_client);
    for (var i = 0; i < transaction.pendingPhotos.length; i++) {
      final photo = transaction.pendingPhotos[i];
      urls.add(await storage.uploadPhotoBytes(photo.bytes,
          fileName: photo.name, submissionPath: 'photos/stock/$id/$i.jpg'));
    }
    final cleanData = _cleanPayload(transaction.toJson());
    cleanData['id'] = id;
    cleanData['photo_urls'] = urls;
    cleanData['created_at'] = DateTime.now().toUtc().toIso8601String();
    cleanData['updated_at'] = DateTime.now().toUtc().toIso8601String();
    try {
      final data = await _client
          .from('stock_transactions')
          .insert(cleanData)
          .select(_stockSelectQuery)
          .single();
      return StockTransactionModel.fromJson(data);
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
      final data = await _client
          .from('stock_transactions')
          .select(_stockSelectQuery)
          .eq('id', id)
          .single();
      return StockTransactionModel.fromJson(data);
    }
  }

  /// Update an existing stock transaction
  Future<StockTransactionModel> updateTransaction(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final edit = await prepareTransactionEdit(
        _client, 'stock_transactions', id, updates);
    final current = edit['current'] as Map<String, dynamic>;
    final cleanUpdates = edit['changes'] as Map<String, dynamic>;
    final merged = {...current, ...cleanUpdates};
    requireFiniteAmount(merged['quantity'] as num, 'Quantity', positive: true);
    for (final field in ['rate', 'sgst', 'igst', 'final_amount']) {
      if (merged[field] != null) {
        requireFiniteAmount(merged[field] as num, field);
      }
    }

    final data = await _client
        .from('stock_transactions')
        .update(cleanUpdates)
        .eq('id', id)
        .eq('status', current['status'])
        .eq('updated_at', current['updated_at'])
        .select(_stockSelectQuery)
        .single();

    return StockTransactionModel.fromJson(data);
  }

  /// Delete a stock transaction with Emergency Vault protection
  Future<void> deleteTransaction(String id) async {
    try {
      final existing = await _client
          .from('stock_transactions')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (existing != null) {
        await AuditService.captureDeletedRecord(
          entity: 'stock',
          entityId: id,
          recordData: Map<String, dynamic>.from(existing),
          reason: 'Manual deletion',
        );
      }
      await _client.from('stock_transactions').delete().eq('id', id);
    } catch (_) {
      rethrow;
    }
  }

  /// Fetch all stock transactions across all sites (latest on top)
  Future<List<StockTransactionModel>> getAllTransactions({
    TransactionStatus? status,
    TransactionType? type,
  }) async {
    var query = _client.from('stock_transactions').select(_stockSelectQuery);

    if (status != null) {
      query = query.eq('status', status.dbValue);
    }
    if (type != null) {
      query = query.eq('type', type.name);
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
        .map((json) => StockTransactionModel.fromJson(json))
        .toList();
  }

  /// Fetch all pending transactions (for Accounts dashboard)
  Future<List<StockTransactionModel>> getPendingForAccounts() =>
      getAllTransactions(status: TransactionStatus.pendingAccounts);

  /// Fetch all pending-admin transactions (for Admin dashboard)
  Future<List<StockTransactionModel>> getPendingForAdmin() =>
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

  /// Accounts approves a transaction: pending_accounts -> pending_admin
  Future<void> approveByAccounts(
      String transactionId, String? reviewedBy) async {
    final validUserId = await _requireReviewer('accounts', reviewedBy);
    final permissions =
        await RoleAccessService(_client).getVerifiedPermissions();
    if (!permissions.accountsCanApproveStock) {
      throw StateError('Accounts approval is disabled by Admin.');
    }
    final current = StockTransactionModel.fromJson(await _client
        .from('stock_transactions')
        .select()
        .eq('id', transactionId)
        .single());
    if (permissions.projectHeadCanApproveStock &&
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
        .from('stock_transactions')
        .update(updateData)
        .eq('id', transactionId)
        .eq('status', 'pending_accounts')
        .select('id')
        .single();
  }

  /// Admin approves a transaction: pending_admin -> approved (permanent lock)
  Future<void> approveByAdmin(String transactionId, String? approvedBy) async {
    final validUserId = await _requireReviewer('admin', approvedBy);
    final tx = StockTransactionModel.fromJson(await _client
        .from('stock_transactions')
        .select(_stockSelectQuery)
        .eq('id', transactionId)
        .single());
    if (tx.type == TransactionType.outbound) {
      final stock = await getCurrentStock(tx.siteId);
      final balance = stock
              .where((r) => r['inventory_key'] == inventoryKey(tx))
              .firstOrNull?['current_stock'] as num? ??
          0;
      if (tx.quantity > balance + 0.000000001) {
        throw StateError('Insufficient approved stock in this material/unit.');
      }
    }
    final updateData = <String, dynamic>{
      'status': 'approved',
      'approved_at': DateTime.now().toIso8601String(),
      'approved_by': validUserId,
    };

    await _client
        .from('stock_transactions')
        .update(updateData)
        .eq('id', transactionId)
        .eq('status', 'pending_admin')
        .select('id')
        .single();
  }

  /// Reject a transaction (by either Accounts or Admin)
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
    if ((role == 'accounts' && !permissions.accountsCanApproveStock) ||
        (role == 'project_head' && !permissions.projectHeadCanApproveStock)) {
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
        .from('stock_transactions')
        .update(updateData)
        .eq('id', transactionId)
        .eq('status', role == 'admin' ? 'pending_admin' : 'pending_accounts')
        .select('id')
        .single();
  }

  /// Compute complete, approved balances with explicit material/unit identities.
  Future<List<Map<String, dynamic>>> getCurrentStock(String siteId) async =>
      calculateStockBalances(await getTransactionsForSite(siteId,
          status: TransactionStatus.approved));
  Future<List<Map<String, dynamic>>> getAllSitesStock() async =>
      calculateStockBalances(
          await getAllTransactions(status: TransactionStatus.approved));
}
