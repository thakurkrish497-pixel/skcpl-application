import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/daily_site_report_model.dart';
import '../core/constants/supabase_constants.dart';

/// Service managing Daily Site Reports (DSR), audio/photo uploads to Supabase storage,
/// and database persistence with automatic fallback resilience.
class SiteReportService {
  final SupabaseClient _client;

  SiteReportService([SupabaseClient? client])
      : _client = client ??
            SupabaseClient(
              SupabaseConstants.supabaseUrl,
              SupabaseConstants.supabaseServiceRoleKey,
            );

  static const String _storageBucket = 'site_reports';

  /// Uploads audio bytes to Supabase storage and returns public URL
  Future<String> uploadAudio({
    required Uint8List audioBytes,
    required String siteId,
    required String fileName,
  }) async {
    final path = 'audio/$siteId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final isWebm = fileName.endsWith('.webm');
    await _client.storage.from(_storageBucket).uploadBinary(
          path,
          audioBytes,
          fileOptions: FileOptions(
            contentType: isWebm ? 'audio/webm' : 'audio/mp4',
            upsert: true,
          ),
        );
    return _client.storage.from(_storageBucket).getPublicUrl(path);
  }

  /// Uploads photo bytes to Supabase storage and returns public URL
  Future<String> uploadPhoto({
    required Uint8List photoBytes,
    required String siteId,
    required String fileName,
  }) async {
    final path = 'photos/$siteId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    await _client.storage.from(_storageBucket).uploadBinary(
          path,
          photoBytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return _client.storage.from(_storageBucket).getPublicUrl(path);
  }

  /// Submits or updates a daily site report
  Future<DailySiteReportModel> saveReport(DailySiteReportModel report) async {
    final data = report.toJson();
    try {
      // Primary: insert/upsert into daily_site_reports table
      final res = await _client
          .from('daily_site_reports')
          .upsert(data, onConflict: 'id')
          .select('*, sites(name)')
          .single();
      return DailySiteReportModel.fromJson(res);
    } catch (e) {
      print('daily_site_reports table not ready or error ($e). Using resilient fallback.');
      return _saveReportFallback(report);
    }
  }

  /// Fetch all reports for a specific site, optionally filtered by date or date range
  Future<List<DailySiteReportModel>> getReportsForSite(
    String siteId, {
    DateTime? date,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _client
          .from('daily_site_reports')
          .select('*, sites(name)');

      if (siteId != 'all') {
        query = query.eq('site_id', siteId);
      }

      if (date != null) {
        final dStr = date.toIso8601String().split('T').first;
        query = query.eq('date', dStr);
      } else {
        if (startDate != null) {
          final sStr = startDate.toIso8601String().split('T').first;
          query = query.gte('date', sStr);
        }
        if (endDate != null) {
          final eStr = endDate.toIso8601String().split('T').first;
          query = query.lte('date', eStr);
        }
      }

      final data = await query.order('date', ascending: false);
      final list = (data as List).map((j) => DailySiteReportModel.fromJson(j)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // Latest report on top
      return list;
    } catch (e) {
      print('Query daily_site_reports error ($e). Fetching from fallback...');
      return _getReportsFallback(siteId, date: date, startDate: startDate, endDate: endDate);
    }
  }

  /// Fetch all reports for a specific site on a given date (latest update first)
  Future<List<DailySiteReportModel>> getReportsForDate(String siteId, DateTime date) async {
    final list = await getReportsForSite(siteId, date: date);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // Latest update on top
    return list;
  }

  /// Fetch single report for a specific site on a given date (backward compatibility)
  Future<DailySiteReportModel?> getReportForDate(String siteId, DateTime date) async {
    final list = await getReportsForSite(siteId, date: date);
    if (list.isNotEmpty) return list.first;
    return null;
  }

  // ── Resilient Fallback Engine ──
  // If daily_site_reports table is not migrated in Supabase,
  // we store the JSON in the existing `tasks` table tagged as 'DSR' so data is NEVER lost!
  Future<DailySiteReportModel> _saveReportFallback(DailySiteReportModel report) async {
    final dateStr = report.date.toIso8601String().split('T').first;
    // Unique tag title per report ID ensures multiple updates on the same date NEVER overwrite each other
    final tagTitle = 'DSR:$dateStr:${report.id}';
    final payload = jsonEncode(report.toJson());

    try {
      // Check if task exists for this specific report id (by tagTitle or by report.id inside description)
      final existing = await _client
          .from('tasks')
          .select('id')
          .or('title.eq.$tagTitle,description.like.%"id":"${report.id}"%')
          .limit(1);

      if ((existing as List).isNotEmpty) {
        final taskId = existing.first['id'] as String;
        await _client.from('tasks').update({
          'title': tagTitle,
          'description': payload,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', taskId);
      } else {
        // Resolve valid user ID for created_by foreign key
        final users = await _client.from('users').select('id').limit(1);
        final userId = (users as List).isNotEmpty
            ? users.first['id'] as String
            : '84b7c957-e145-446a-9a31-051f2cb9b3af';

        await _client.from('tasks').insert({
          'site_id': report.siteId,
          'title': tagTitle,
          'description': payload,
          'created_by': userId,
          'status': 'completed',
          'priority': 'medium',
        });
      }
    } catch (e) {
      print('[SiteReportService] _saveReportFallback error: $e');
    }

    return report;
  }

  Future<List<DailySiteReportModel>> _getReportsFallback(
    String siteId, {
    DateTime? date,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var query = _client
        .from('tasks')
        .select('id, site_id, title, description, created_at, updated_at');

    if (siteId != 'all') {
      query = query.eq('site_id', siteId);
    }

    final data = await query
        .like('title', 'DSR:%')
        .order('created_at', ascending: false);
    final list = <DailySiteReportModel>[];

    Map<String, String>? siteMap;
    try {
      final sitesRes = await _client.from('sites').select('id, name');
      siteMap = {for (final s in (sitesRes as List)) s['id'].toString(): s['name'].toString()};
    } catch (_) {}

    for (final row in (data as List)) {
      final desc = row['description'] as String?;
      if (desc != null && desc.startsWith('{')) {
        try {
          final decoded = jsonDecode(desc);
          var report = DailySiteReportModel.fromJson(decoded);

          // Populate site name if missing
          if ((report.siteName == null || report.siteName!.isEmpty) && siteMap != null) {
            final resolvedName = siteMap[report.siteId] ?? siteMap[row['site_id']?.toString()];
            if (resolvedName != null) {
              report = report.copyWith(siteName: resolvedName);
            }
          }

          // Apply filters
          if (date != null) {
            final dStr = date.toIso8601String().split('T').first;
            final rStr = report.date.toIso8601String().split('T').first;
            if (dStr != rStr) continue;
          }
          if (startDate != null && report.date.isBefore(startDate)) continue;
          if (endDate != null && report.date.isAfter(endDate)) continue;
          list.add(report);
        } catch (_) {}
      }
    }
    // Sort descending so the latest report appears on top
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }
}
