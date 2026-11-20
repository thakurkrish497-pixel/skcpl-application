import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/attendance_model.dart';
import '../models/staff_reminder_model.dart' show reminderOfficeIds;
import 'submission_support.dart';

const canonicalOfficeShiftId = '89e1477d-7f66-4b6d-99ca-6270183143e0';
String shiftLocationKey(String id) =>
    reminderOfficeIds.contains(id.trim()) ? canonicalOfficeShiftId : id.trim();
final shiftPolicySaved = StreamController<String>.broadcast();

bool shiftStorageUnavailable(Object error, String id) =>
    isSchemaUnavailable(error) ||
    (error is PostgrestException &&
        error.code == '22P02' &&
        !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id));

/// One lookup contract for staff profiles, attendance and reminder deadlines.
class ShiftPolicyResolver {
  final SupabaseClient client;
  ShiftPolicyResolver(this.client);
  Future<SiteShiftPolicyModel?> configured(String siteId) async {
    final key = shiftLocationKey(siteId);
    final scopes = [
      key,
      if (key == canonicalOfficeShiftId)
        ...reminderOfficeIds.where((id) => id != key)
    ];
    var primaryAvailable = true;
    Future<({SiteShiftPolicyModel policy, DateTime? stamp})?> read(
        String id) async {
      Map<String, dynamic>? row;
      if (primaryAvailable) {
        try {
          final rows = await client
              .from('site_shift_policies')
              .select()
              .eq('site_id', id)
              .limit(1);
          if (rows.isNotEmpty) row = rows.first;
        } catch (error) {
          if (!shiftStorageUnavailable(error, id)) rethrow;
          if (isSchemaUnavailable(error)) primaryAvailable = false;
        }
      }
      if (row != null) {
        return (
          policy: SiteShiftPolicyModel.fromJson(row),
          stamp: DateTime.tryParse('${row['updated_at']}')
        );
      }
      final rows = await client
          .from('tasks')
          .select('description,updated_at')
          .eq('title', 'SHIFT_POLICY:$id')
          .order('updated_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return null;
      final data = Map<String, dynamic>.from(
          jsonDecode(rows.first['description'] as String) as Map);
      return (
        policy: SiteShiftPolicyModel.fromJson(data),
        stamp: DateTime.tryParse('${rows.first['updated_at']}')
      );
    }

    final candidates = <({SiteShiftPolicyModel policy, DateTime? stamp})>[];
    for (final scope in scopes) {
      final candidate = await read(scope);
      if (candidate != null) candidates.add(candidate);
    }
    if (candidates.isEmpty && key != 'global') {
      final global = await read('global');
      if (global != null) candidates.add(global);
    }
    if (candidates.isEmpty) return null;
    // Known updated_at dates resolve competing legacy office aliases consistently.
    // With no revision metadata, canonical location order is deterministic.
    var chosen = candidates.first;
    if (chosen.stamp != null) {
      for (final other in candidates.skip(1)) {
        if (other.stamp != null && other.stamp!.isAfter(chosen.stamp!)) {
          chosen = other;
        }
      }
    }
    // Binding a default to its requested site avoids editing the company default
    // when Admin opens settings for an otherwise unconfigured location.
    return chosen.policy.copyWith(siteId: key);
  }
}
