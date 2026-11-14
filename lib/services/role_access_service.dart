import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/role_permissions_model.dart';

/// Service managing dynamic credentials and approval powers configured by Admin
class RoleAccessService {
  static const String _prefsKey = 'skcpl_role_permissions_config';
  static const String _supabaseConfigTag = 'CONFIG:ROLE_PERMISSIONS';

  final SupabaseClient _client;
  RolePermissionsModel? _cached;

  RoleAccessService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  /// Get current role credentials and approval powers (Cloud-first so all laptops stay in sync)
  Future<RolePermissionsModel> getPermissions(
      {bool forceRefresh = false}) async {
    if (_cached != null && !forceRefresh) return _cached!;

    // 1. Try remote Supabase tasks table FIRST (cloud source of truth for all laptops)
    try {
      final rows = await _client
          .from('tasks')
          .select()
          .eq('title', _supabaseConfigTag)
          .order('updated_at', ascending: false)
          .limit(1);

      if ((rows as List).isNotEmpty) {
        final desc = rows.first['description'] as String?;
        if (desc != null && desc.isNotEmpty) {
          _cached = RolePermissionsModel.fromJsonString(desc);
          // Update local cache for offline fallback
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefsKey, desc);
          return _cached!;
        }
      }
    } catch (_) {}

    // 2. Fallback to local SharedPreferences only if offline / server unreachable
    try {
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString(_prefsKey);
      if (localJson != null && localJson.isNotEmpty) {
        _cached = RolePermissionsModel.fromJsonString(localJson);
        return _cached!;
      }
    } catch (_) {}

    _cached = const RolePermissionsModel();
    return _cached!;
  }

  /// Mutations require the current server policy, never an offline/default cache.
  Future<RolePermissionsModel> getVerifiedPermissions() async {
    final row = await _client
        .from('tasks')
        .select('description')
        .eq('title', _supabaseConfigTag)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return const RolePermissionsModel();
    final data = jsonDecode(row['description'] as String);
    if (data is! Map<String, dynamic>) {
      throw StateError('Company approval policy is invalid.');
    }
    return RolePermissionsModel.fromJson(data);
  }

  /// A settings password does not create an Auth credential. Save policies only after server acknowledgement.
  Future<void> savePermissions(RolePermissionsModel model) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Admin sign-in is required.');
    final profile = await _client
        .from('users')
        .select('role, is_active')
        .eq('id', user.id)
        .single();
    if (profile['role'] != 'admin' || profile['is_active'] == false) {
      throw StateError('Only active Admin accounts can change permissions.');
    }
    final jsonStr = model.toJsonString();
    final existing = await _client
        .from('tasks')
        .select('id')
        .eq('title', _supabaseConfigTag)
        .limit(1)
        .maybeSingle();
    if (existing != null) {
      await _client
          .from('tasks')
          .update({'description': jsonStr})
          .eq('id', existing['id'])
          .select('id')
          .single();
    } else {
      final site = await _client.from('sites').select('id').limit(1).single();
      await _client
          .from('tasks')
          .insert({
            'site_id': site['id'],
            'created_by': user.id,
            'title': _supabaseConfigTag,
            'description': jsonStr,
            'status': 'completed',
            'priority': 'high'
          })
          .select('id')
          .single();
    }
    _cached = model;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonStr);
  }

  Future<RolePermissionsModel> loadRolePermissions() => getPermissions();

  Future<void> saveRolePermissions(RolePermissionsModel model) =>
      savePermissions(model);

  Future<void> resetToDefaults() async {
    const defaultModel = RolePermissionsModel();
    await savePermissions(defaultModel);
  }
}
