import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/supabase_constants.dart';

/// Layer 4: Audit Trail, Accidental Deletion Protection & Emergency Vault
/// Captures every critical system mutation (delete, update, approval)
/// Keeps an immutable offline emergency vault in SharedPreferences
/// and attempts sync to Supabase audit log.
class AuditService {
  static const String _keyEmergencyVault = 'skcpl_emergency_audit_vault_v1';
  static const _uuid = Uuid();

  static final SupabaseClient _client = SupabaseClient(
    SupabaseConstants.supabaseUrl,
    SupabaseConstants.supabaseAnonKey,
  );

  /// Capture a deletion into the emergency vault before it is removed
  static Future<void> captureDeletedRecord({
    required String entity, // 'cash', 'stock', 'attendance', 'dsr', 'staff'
    required String entityId,
    required Map<String, dynamic> recordData,
    String? userRole,
    String? userName,
    String? reason,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_keyEmergencyVault) ?? [];

      final vaultEntry = {
        'vault_id': 'vault_${_uuid.v4()}',
        'entity': entity,
        'entity_id': entityId,
        'deleted_at': DateTime.now().toIso8601String(),
        'user_role': userRole ?? 'Admin',
        'user_name': userName ?? 'System',
        'reason': reason ?? 'Direct user action',
        'data': recordData,
      };

      rawList.insert(0, jsonEncode(vaultEntry));
      // Keep last 200 items in emergency vault
      if (rawList.length > 200) {
        rawList.removeRange(200, rawList.length);
      }
      await prefs.setStringList(_keyEmergencyVault, rawList);

      // Best effort remote audit logging
      try {
        await _client.from('audit_logs').insert({
          'action': 'DELETE',
          'entity': entity,
          'entity_id': entityId,
          'details': vaultEntry,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {
        // Table may not exist yet, safely preserved in local vault
      }
    } catch (e) {
      debugPrint('[AuditService] Failed to capture into vault: $e');
    }
  }

  /// Log any general action (CREATE, UPDATE, APPROVE, REJECT)
  static Future<void> logAction({
    required String action,
    required String entity,
    required String entityId,
    Map<String, dynamic>? details,
    String? userRole,
    String? userName,
  }) async {
    try {
      final entry = {
        'action': action,
        'entity': entity,
        'entity_id': entityId,
        'timestamp': DateTime.now().toIso8601String(),
        'user_role': userRole ?? 'User',
        'user_name': userName ?? 'Unknown',
        'details': details ?? {},
      };

      try {
        await _client.from('audit_logs').insert({
          'action': action,
          'entity': entity,
          'entity_id': entityId,
          'details': entry,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
    } catch (_) {}
  }

  /// Get all archived/deleted records from the emergency vault
  static Future<List<Map<String, dynamic>>> getArchivedVaultRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_keyEmergencyVault) ?? [];
      return rawList.map((str) => jsonDecode(str) as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  /// Remove a specific entry from the emergency vault
  static Future<void> purgeVaultEntry(String vaultId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_keyEmergencyVault) ?? [];
      final filtered = rawList.where((str) {
        final map = jsonDecode(str) as Map<String, dynamic>;
        return map['vault_id'] != vaultId;
      }).toList();
      await prefs.setStringList(_keyEmergencyVault, filtered);
    } catch (_) {}
  }

  /// Clear the entire emergency vault
  static Future<void> clearVault() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyEmergencyVault);
    } catch (_) {}
  }
}
