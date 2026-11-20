import 'entry_date_policy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'role_access_service.dart';

/// Validate an edit against the current row, not a stale screen snapshot.
Future<Map<String, dynamic>> prepareTransactionEdit(SupabaseClient client,
    String table, String id, Map<String, dynamic> updates) async {
  final current = await client.from(table).select().eq('id', id).single();
  if (current['status'] == 'approved') {
    throw StateError('Approved records are permanently locked.');
  }
  final changes = Map<String, dynamic>.from(updates)
    ..remove('id')
    ..remove('local_pending_photos')
    ..remove('created_at')
    ..remove('submitted_by')
    ..remove('reviewed_by')
    ..remove('reviewed_at')
    ..remove('approved_by')
    ..remove('approved_at')
    ..remove('site_id');
  EntryDatePolicy.requireDateValue(changes['date'] ?? current['date']);
  final auth = client.auth.currentUser;
  final profile = auth == null
      ? null
      : await client
          .from('users')
          .select('role, is_active')
          .eq('id', auth.id)
          .single();
  if (profile?['is_active'] == false) {
    throw StateError('This company account is inactive.');
  }
  final role = profile?['role'];
  final next = changes['status'] ?? current['status'];
  final permissions = await RoleAccessService(client).getVerifiedPermissions();
  final stock = table == 'stock_transactions';
  final headEnabled = stock
      ? permissions.projectHeadCanApproveStock
      : permissions.projectHeadCanApproveCash;
  final accountsEnabled = stock
      ? permissions.accountsCanApproveStock
      : permissions.accountsCanApproveCash;
  if (role == 'project_head') {
    final oldRemarks = current['remarks']?.toString() ?? '';
    if (RegExp(r'\[(?:Project Head|Supervisor): (?:Approved|Edited & Approved)')
        .hasMatch(oldRemarks)) {
      throw StateError('This entry has already been forwarded to Accounts.');
    }
    if (!headEnabled || current['status'] != 'pending_accounts') {
      throw StateError('Project Head review is unavailable for this stage.');
    }
    if (next != 'pending_accounts' &&
        !(next == 'pending_admin' && !accountsEnabled)) {
      throw StateError('Invalid Project Head approval transition.');
    }
  } else if (role == 'accounts') {
    if (!accountsEnabled ||
        current['status'] != 'pending_accounts' ||
        next != current['status']) {
      throw StateError('Accounts cannot edit this approval stage.');
    }
    final remarks = current['remarks']?.toString() ?? '';
    if (headEnabled &&
        RegExp(r'\[(?:PENDING SUPERVISOR REVIEW|(?:Project Head|Supervisor) Review: Pending)\]')
            .hasMatch(remarks)) {
      throw StateError('Project Head review is still pending.');
    }
  } else if (role == 'admin') {
    if (next != current['status']) {
      throw StateError('Use the approval action to advance a voucher.');
    }
  } else {
    if (!['pending_accounts', 'rejected'].contains(current['status']) ||
        next != current['status']) {
      throw StateError('This entry can no longer be edited.');
    }
    // A worker's free-text edit cannot remove or impersonate management review tags.
    final tags = RegExp(
        r'\[(?:PENDING SUPERVISOR REVIEW|(?:Project Head|Supervisor)[^\]]*)\]');
    if (changes.containsKey('remarks')) {
      changes['remarks'] = [
        (changes['remarks']?.toString() ?? '').replaceAll(tags, ''),
        ...tags
            .allMatches(current['remarks']?.toString() ?? '')
            .map((m) => m.group(0)!),
      ].join(' ').trim();
    }
  }
  changes['updated_at'] = DateTime.now().toUtc().toIso8601String();
  return {'current': current, 'changes': changes};
}
