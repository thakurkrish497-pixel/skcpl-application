import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/site_announcement_model.dart';
import '../core/constants/supabase_constants.dart';

/// Resilient service for broadcasting announcements to all staff.
/// Multi-layered persistence: Primary `site_announcements` table -> Resilient `tasks` table -> Local `SharedPreferences`.
class SiteAnnouncementService {
  final SupabaseClient _client;
  static const _uuid = Uuid();
  static const _prefsKey = 'skcpl_announcements_cache_v2';
  static const _defaultAdminUserId = '84b7c957-e145-446a-9a31-051f2cb9b3af';
  static const _defaultOfficeSiteId = 'bdb1478e-4fa9-4873-9804-864b0952fa4d';

  SiteAnnouncementService([SupabaseClient? client])
      : _client = client ??
            SupabaseClient(
              SupabaseConstants.supabaseUrl,
              SupabaseConstants.supabaseServiceRoleKey,
            );

  /// Fetch active broadcast announcements
  Future<List<SiteAnnouncementModel>> getAnnouncements() async {
    // 1. Try primary table
    try {
      final data = await _client
          .from('site_announcements')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false);

      final list = (data as List)
          .map((json) => SiteAnnouncementModel.fromJson(json))
          .toList();

      if (list.isNotEmpty) {
        _cacheLocally(list);
        return list;
      }
    } catch (_) {}

    // 2. Try resilient fallback tasks table
    try {
      final fallbackList = await _getFallbackAnnouncements();
      if (fallbackList.isNotEmpty) {
        _cacheLocally(fallbackList);
        return fallbackList;
      }
    } catch (_) {}

    // 3. Try local cache
    return _getLocalCachedAnnouncements();
  }

  /// Create a new broadcast announcement (simplified: broadcast to all staff)
  Future<SiteAnnouncementModel> createAnnouncement(SiteAnnouncementModel announcement) async {
    final effectiveId = announcement.id.isEmpty ? _uuid.v4() : announcement.id;
    final toSave = announcement.copyWith(
      id: effectiveId,
      targetSiteId: 'all',
      targetSiteName: 'All Staff',
      isActive: true,
    );

    bool savedRemotely = false;

    // 1. Try primary table
    try {
      final payload = toSave.toJson();
      await _client.from('site_announcements').insert(payload);
      savedRemotely = true;
    } catch (e) {
      debugPrint('[SiteAnnouncementService] Primary insert fallback: $e');
    }

    // 2. Resilient fallback to tasks table with valid site_id
    try {
      await _saveFallbackAnnouncement(toSave);
      savedRemotely = true;
    } catch (e) {
      debugPrint('[SiteAnnouncementService] Tasks fallback notice: $e');
    }

    // 3. Always update local cache so it appears immediately on device
    try {
      final current = await _getLocalCachedAnnouncements();
      final updated = [toSave, ...current.where((a) => a.id != toSave.id)];
      await _cacheLocally(updated);
    } catch (_) {}

    return toSave;
  }

  /// Delete or deactivate an announcement
  Future<void> deleteAnnouncement(String id) async {
    try {
      await _client
          .from('site_announcements')
          .update({'is_active': false})
          .eq('id', id);
    } catch (_) {}

    try {
      await _client
          .from('tasks')
          .delete()
          .eq('title', 'ANNOUNCEMENT:$id');
    } catch (_) {}

    try {
      final current = await _getLocalCachedAnnouncements();
      await _cacheLocally(current.where((a) => a.id != id).toList());
    } catch (_) {}
  }

  // ── Resilient Storage Helpers ──
  Future<String> _resolveValidSiteId() async {
    try {
      final sites = await _client.from('sites').select('id').limit(1);
      if ((sites as List).isNotEmpty) {
        final id = sites.first['id']?.toString();
        if (id != null && id.isNotEmpty) return id;
      }
    } catch (_) {}
    return _defaultOfficeSiteId;
  }

  Future<void> _saveFallbackAnnouncement(SiteAnnouncementModel model) async {
    final validSiteId = await _resolveValidSiteId();
    final jsonStr = jsonEncode(model.toJson());
    final tag = 'ANNOUNCEMENT:${model.id}';

    final existing = await _client.from('tasks').select('id').eq('title', tag).limit(1);
    if ((existing as List).isNotEmpty) {
      await _client.from('tasks').update({
        'description': jsonStr,
        'status': model.isActive ? 'pending' : 'completed',
      }).eq('id', existing.first['id']);
    } else {
      await _client.from('tasks').insert({
        'site_id': validSiteId,
        'created_by': _defaultAdminUserId,
        'title': tag,
        'description': jsonStr,
        'status': model.isActive ? 'pending' : 'completed',
        'priority': 'medium',
        'created_at': model.createdAt.toIso8601String(),
      });
    }
  }

  Future<List<SiteAnnouncementModel>> _getFallbackAnnouncements() async {
    final data = await _client
        .from('tasks')
        .select()
        .like('title', 'ANNOUNCEMENT:%')
        .order('created_at', ascending: false);

    final list = <SiteAnnouncementModel>[];
    for (final row in (data as List)) {
      final desc = row['description'] as String?;
      if (desc != null && desc.startsWith('{')) {
        try {
          final decoded = jsonDecode(desc);
          final announcement = SiteAnnouncementModel.fromJson(decoded);
          if (announcement.isActive) {
            list.add(announcement);
          }
        } catch (_) {}
      }
    }
    return list;
  }

  Future<void> _cacheLocally(List<SiteAnnouncementModel> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = jsonEncode(list.map((a) => a.toJson()).toList());
      await prefs.setString(_prefsKey, str);
    } catch (_) {}
  }

  Future<List<SiteAnnouncementModel>> _getLocalCachedAnnouncements() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_prefsKey);
      if (str != null && str.isNotEmpty) {
        final list = (jsonDecode(str) as List)
            .map((j) => SiteAnnouncementModel.fromJson(j))
            .where((a) => a.isActive)
            .toList();
        return list;
      }
    } catch (_) {}
    return [];
  }
}
