import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/supabase_constants.dart';
import '../models/role_permissions_model.dart';

/// Service managing dynamic credentials and approval powers configured by Admin
class RoleAccessService {
  static const String _prefsKey = 'skcpl_role_permissions_config';
  static const String _supabaseConfigTag = 'CONFIG:ROLE_PERMISSIONS';
  static const String _defaultAdminUserId = '84b7c957-e145-446a-9a31-051f2cb9b3af';
  static const String _defaultOfficeSiteId = 'bdb1478e-4fa9-4873-9804-864b0952fa4d';

  final SupabaseClient _client;
  static RolePermissionsModel? _cached;

  RoleAccessService([SupabaseClient? client])
      : _client = client ??
            SupabaseClient(
              SupabaseConstants.supabaseUrl,
              SupabaseConstants.supabaseServiceRoleKey,
            );

  /// Get current role credentials and approval powers
  Future<RolePermissionsModel> getPermissions() async {
    if (_cached != null) return _cached!;

    // 1. Try local SharedPreferences first (instant)
    try {
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString(_prefsKey);
      if (localJson != null && localJson.isNotEmpty) {
        _cached = RolePermissionsModel.fromJsonString(localJson);
        return _cached!;
      }
    } catch (_) {}

    // 2. Try remote Supabase tasks table
    try {
      final rows = await _client
          .from('tasks')
          .select()
          .eq('title', _supabaseConfigTag)
          .limit(1);

      if ((rows as List).isNotEmpty) {
        final desc = rows.first['description'] as String?;
        if (desc != null && desc.isNotEmpty) {
          _cached = RolePermissionsModel.fromJsonString(desc);
          // Sync locally
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefsKey, desc);
          return _cached!;
        }
      }
    } catch (_) {}

    _cached = const RolePermissionsModel();
    return _cached!;
  }

  /// Save new role credentials and approval powers configured by Admin
  Future<void> savePermissions(RolePermissionsModel model) async {
    _cached = model;
    final jsonStr = model.toJsonString();

    // 1. Save locally
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonStr);
    } catch (_) {}

    // 2. Save remotely in Supabase
    try {
      final existing = await _client
          .from('tasks')
          .select('id')
          .eq('title', _supabaseConfigTag)
          .limit(1);

      if ((existing as List).isNotEmpty) {
        await _client
            .from('tasks')
            .update({'description': jsonStr})
            .eq('id', existing.first['id']);
      } else {
        final anySite = await _client.from('sites').select('id').limit(1).maybeSingle();
        final anyUser = await _client.from('users').select('id').limit(1).maybeSingle();
        if (anySite != null && anyUser != null) {
          await _client.from('tasks').insert({
            'site_id': anySite['id'],
            'created_by': anyUser['id'],
            'title': _supabaseConfigTag,
            'description': jsonStr,
            'status': 'completed',
            'priority': 'high',
          });
        }
      }
    } catch (_) {}
  }

  Future<RolePermissionsModel> loadRolePermissions() => getPermissions();

  Future<void> saveRolePermissions(RolePermissionsModel model) => savePermissions(model);

  Future<void> resetToDefaults() async {
    const defaultModel = RolePermissionsModel();
    await savePermissions(defaultModel);
  }
}
