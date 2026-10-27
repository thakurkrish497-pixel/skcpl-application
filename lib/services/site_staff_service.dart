import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/site_staff_model.dart';
import '../core/constants/supabase_constants.dart';

/// Service managing site staff (Workers and Supervisors) with resilient dual-mode persistence.
class SiteStaffService {
  final SupabaseClient _client;
  static const _uuid = Uuid();

  SiteStaffService([SupabaseClient? client])
      : _client = client ??
            SupabaseClient(
              SupabaseConstants.supabaseUrl,
              SupabaseConstants.supabaseServiceRoleKey,
            );

  /// Fetch all staff members for a specific site, optionally filtered by module
  Future<List<SiteStaffModel>> getStaffForSite(String siteId, {StaffModule? module}) async {
    try {
      // Primary: query site_staff table
      final data = await _client
          .from('site_staff')
          .select()
          .eq('site_id', siteId)
          .order('name', ascending: true);

      final list = (data as List)
          .map((json) => SiteStaffModel.fromJson(json))
          .toList();

      if (module != null) {
        return list.where((s) => s.hasModule(module)).toList();
      }
      return list;
    } catch (e) {
      // Fallback: fetch from tasks table
      return _getStaffFallback(siteId, module: module);
    }
  }

  /// Fetch all staff members across all sites
  Future<List<SiteStaffModel>> getAllStaff() async {
    try {
      final data = await _client
          .from('site_staff')
          .select()
          .order('name', ascending: true);
      return (data as List)
          .map((json) => SiteStaffModel.fromJson(json))
          .toList();
    } catch (_) {
      try {
        final data = await _client
            .from('tasks')
            .select()
            .like('title', 'STAFF:%')
            .order('created_at', ascending: true);
        final list = <SiteStaffModel>[];
        for (final row in (data as List)) {
          final desc = row['description'] as String?;
          if (desc != null && desc.startsWith('{')) {
            try {
              final decoded = jsonDecode(desc);
              list.add(SiteStaffModel.fromJson(decoded));
            } catch (_) {}
          }
        }
        return list;
      } catch (_) {
        return [];
      }
    }
  }

  /// Check if a supervisor is configured and active for a site and module
  Future<bool> hasSupervisor(String siteId, StaffModule module) async {
    final staffList = await getStaffForSite(siteId, module: module);
    return staffList.any((s) => s.isActive && s.isSupervisor && s.hasModule(module));
  }

  /// Add a new staff member to a site
  Future<SiteStaffModel> createStaff(SiteStaffModel staff) async {
    final staffId = staff.id.isEmpty ? _uuid.v4() : staff.id;
    final staffWithId = staff.copyWith(id: staffId);
    final payload = staffWithId.toJson();

    try {
      final res = await _client
          .from('site_staff')
          .insert(payload)
          .select()
          .single();
      return SiteStaffModel.fromJson(res);
    } catch (e) {
      // Fallback: save into tasks table
      return _saveStaffFallback(staffWithId);
    }
  }

  /// Update an existing staff member
  Future<SiteStaffModel> updateStaff(SiteStaffModel staff) async {
    final payload = staff.toJson();
    SiteStaffModel result;
    try {
      final res = await _client
          .from('site_staff')
          .update(payload)
          .eq('id', staff.id)
          .select()
          .single();
      result = SiteStaffModel.fromJson(res);
    } catch (e) {
      result = await _saveStaffFallback(staff);
    }

    // Cascade update to live locations & attendance records so names never desync
    await _cascadeStaffUpdate(staff);
    return result;
  }

  /// Automatically synchronizes the new name and role across live locations and attendance records
  Future<void> _cascadeStaffUpdate(SiteStaffModel staff) async {
    // 1. Update in SQL tables if available
    try {
      await _client.from('staff_live_locations').update({
        'staff_name': staff.name,
        'staff_role': staff.role.displayName,
      }).eq('staff_id', staff.id);
    } catch (_) {}

    try {
      await _client.from('attendance').update({
        'staff_name': staff.name,
        'staff_role': staff.role.displayName,
      }).eq('staff_id', staff.id);
    } catch (_) {}

    // 2. Update in fallback tasks storage
    try {
      // Find all live location tasks for this staff
      final liveRows = await _client
          .from('tasks')
          .select()
          .like('title', 'LIVELOC:%:${staff.id}');
      for (final r in (liveRows as List)) {
        final desc = r['description'] as String?;
        if (desc != null && desc.startsWith('{')) {
          try {
            final map = jsonDecode(desc) as Map<String, dynamic>;
            map['staff_name'] = staff.name;
            map['staff_role'] = staff.role.displayName;
            await _client
                .from('tasks')
                .update({'description': jsonEncode(map)})
                .eq('id', r['id']);
          } catch (_) {}
        }
      }

      // Also search general LIVELOC: tasks in case format varied
      final anyLiveRows = await _client
          .from('tasks')
          .select()
          .like('title', 'LIVELOC:%');
      for (final r in (anyLiveRows as List)) {
        final desc = r['description'] as String?;
        if (desc != null && desc.startsWith('{')) {
          try {
            final map = jsonDecode(desc) as Map<String, dynamic>;
            if (map['staff_id'] == staff.id && map['staff_name'] != staff.name) {
              map['staff_name'] = staff.name;
              map['staff_role'] = staff.role.displayName;
              await _client
                  .from('tasks')
                  .update({'description': jsonEncode(map)})
                  .eq('id', r['id']);
            }
          } catch (_) {}
        }
      }

      // Update attendance tasks for this staff
      final attRows = await _client
          .from('tasks')
          .select()
          .like('title', 'ATTENDANCE:%:${staff.id}');
      for (final r in (attRows as List)) {
        final desc = r['description'] as String?;
        if (desc != null && desc.startsWith('{')) {
          try {
            final map = jsonDecode(desc) as Map<String, dynamic>;
            map['staff_name'] = staff.name;
            map['staff_role'] = staff.role.displayName;
            await _client
                .from('tasks')
                .update({'description': jsonEncode(map)})
                .eq('id', r['id']);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Delete or deactivate a staff member
  Future<void> deleteStaff(String staffId, String siteId) async {
    try {
      await _client.from('site_staff').delete().eq('id', staffId);
    } catch (e) {
      await _deleteStaffFallback(staffId, siteId);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Resilient Fallback Methods (using tasks table)
  // ─────────────────────────────────────────────────────────────

  Future<SiteStaffModel> _saveStaffFallback(SiteStaffModel staff) async {
    final tagTitle = 'STAFF:${staff.siteId}:${staff.id}';
    final payload = jsonEncode(staff.toJson());

    final existing = await _client
        .from('tasks')
        .select()
        .eq('site_id', staff.siteId)
        .eq('title', tagTitle)
        .limit(1);

    if ((existing as List).isNotEmpty) {
      final taskId = existing.first['id'] as String;
      await _client.from('tasks').update({
        'description': payload,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', taskId);
    } else {
      final users = await _client.from('users').select('id').limit(1);
      final userId =
          (users as List).isNotEmpty ? users.first['id'] as String : staff.siteId;

      await _client.from('tasks').insert({
        'site_id': staff.siteId,
        'title': tagTitle,
        'description': payload,
        'created_by': userId,
        'status': 'completed',
        'priority': 'low',
      });
    }

    return staff;
  }

  Future<List<SiteStaffModel>> _getStaffFallback(String siteId, {StaffModule? module}) async {
    try {
      final data = await _client
          .from('tasks')
          .select()
          .eq('site_id', siteId)
          .like('title', 'STAFF:$siteId:%')
          .order('created_at', ascending: true);

      final list = <SiteStaffModel>[];
      for (final row in (data as List)) {
        final desc = row['description'] as String?;
        if (desc != null && desc.startsWith('{')) {
          try {
            final decoded = jsonDecode(desc);
            final staff = SiteStaffModel.fromJson(decoded);
            if (module == null || staff.hasModule(module)) {
              list.add(staff);
            }
          } catch (_) {}
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _deleteStaffFallback(String staffId, String siteId) async {
    try {
      final tagTitle = 'STAFF:$siteId:$staffId';
      await _client
          .from('tasks')
          .delete()
          .eq('site_id', siteId)
          .eq('title', tagTitle);
    } catch (_) {}
  }
}
