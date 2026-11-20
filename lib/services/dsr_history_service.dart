import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/daily_site_report_model.dart';
import 'submission_support.dart';

/// Presentation of existing records only. No review or report is written here.
class DsrHistoryEntry {
  final DailySiteReportModel report;
  final Map<String, dynamic> submittedData;
  final Map<String, dynamic> reviewState;
  final bool reviewAuditAvailable;
  DsrHistoryEntry(Map<String, dynamic> data, Map<String, dynamic> reviews,
      {this.reviewAuditAvailable = true})
      : report = DailySiteReportModel.fromJson(data),
        submittedData = Map.unmodifiable(data),
        reviewState = Map.unmodifiable(reviews);

  bool get rejected => reviewState['final'] is Map
      ? reviewState['final']['decision'] == 'rejected'
      : report.isProjectHeadRejected ||
          report.isAccountsRejected ||
          report.isAdminRejected;
  bool get approved => reviewState['final'] is Map
      ? reviewState['final']['decision'] == 'approved'
      : !rejected && (report.remarks?.contains('[Admin: Approved') ?? false);
  bool get reviewed =>
      reviewState.isNotEmpty ||
      report.isProjectHeadReviewed ||
      report.isAccountsApproved ||
      report.isAccountsRejected ||
      approved ||
      rejected;
  String get status => rejected
      ? 'Rejected'
      : approved
          ? 'Approved'
          : reviewed
              ? 'Reviewed • awaiting final approval'
              : 'Pending review';
}

class DsrHistorySnapshot {
  final List<DsrHistoryEntry> entries;
  final List<String> warnings;
  const DsrHistorySnapshot(this.entries, {this.warnings = const []});
}

class DsrHistoryService {
  final SupabaseClient client;
  DsrHistoryService(this.client);

  Future<List<Map<String, dynamic>>> _pages(String table,
      {String? siteId}) async {
    final result = <Map<String, dynamic>>[];
    final key = table == 'skcpl_entry_reviews' ? 'entry_id' : 'id';
    String? cursor;
    while (true) {
      var query = client.from(table).select();
      if (table == 'tasks') query = query.like('title', 'DSR:%');
      if (siteId != null && table != 'skcpl_entry_reviews') {
        query = query.eq('site_id', siteId);
      }
      if (table == 'skcpl_entry_reviews') query = query.eq('module', 'dsr');
      if (cursor != null) query = query.gt(key, cursor);
      final page =
          List<Map<String, dynamic>>.from(await query.order(key).limit(200));
      result.addAll(page);
      if (page.length < 200) break;
      final next = page.last[key]?.toString();
      if (next == null || next == cursor) {
        throw StateError(
            'History pagination could not advance. Please refresh.');
      }
      cursor = next;
    }
    return result;
  }

  Future<DsrHistorySnapshot> load() => _load();

  Future<DsrHistorySnapshot> loadForSite(String siteId) {
    if (siteId.trim().isEmpty || siteId == 'all') {
      throw ArgumentError('A specific signed-in site is required.');
    }
    return _load(siteId: siteId);
  }

  Future<DsrHistorySnapshot> _load({String? siteId}) async {
    final warnings = <String>[];
    final reports = <String, Map<String, dynamic>>{};
    var unreadable = 0;
    var sourceAvailable = false;
    void add(Map<String, dynamic> data) {
      // Fail closed if a legacy payload disagrees with its enclosing task site.
      if (siteId != null && data['site_id'] != siteId) return;
      if ((data['id']?.toString() ?? '').isEmpty ||
          (data['site_id']?.toString() ?? '').isEmpty ||
          DateTime.tryParse('${data['date']}') == null) {
        unreadable++;
        return;
      }
      reports[data['id'].toString()] = data;
    }

    try {
      final legacy = await _pages('tasks', siteId: siteId);
      sourceAvailable = true;
      for (final row in legacy) {
        try {
          add(Map<String, dynamic>.from(
              jsonDecode(row['description'] as String) as Map));
        } catch (_) {
          unreadable++;
        }
      }
    } catch (e) {
      if (!isSchemaUnavailable(e)) rethrow;
    }
    // The canonical primary record takes precedence over a legacy copy.
    try {
      final primary = await _pages('daily_site_reports', siteId: siteId);
      sourceAvailable = true;
      for (final row in primary) {
        add(row);
      }
    } catch (e) {
      if (!isSchemaUnavailable(e)) rethrow;
    }
    if (!sourceAvailable) {
      throw StateError(
          'DSR history storage is unavailable. No records were changed.');
    }
    final reviewMap = <String, Map<String, dynamic>>{};
    // The review audit is management-only. Site history uses the original
    // report labels and never broadens permissions or queries a forbidden table.
    if (siteId == null) {
      try {
        for (final row in await _pages('skcpl_entry_reviews')) {
          reviewMap[row['entry_id'].toString()] =
              Map<String, dynamic>.from(row['state'] as Map? ?? {});
        }
      } catch (e) {
        if (!isSchemaUnavailable(e)) rethrow;
        warnings.add(
            'Detailed review audit is unavailable. Existing report approval labels are still shown; no review times are inferred.');
      }
    }
    if (unreadable > 0) {
      warnings.add(
          '$unreadable historical record(s) could not be displayed. They remain unchanged on the server.');
    }
    final entries = reports.values
        .map((data) => DsrHistoryEntry(data, reviewMap[data['id']] ?? {},
            reviewAuditAvailable: siteId == null))
        .toList()
      ..sort((a, b) {
        final day = b.report.date.compareTo(a.report.date);
        return day != 0
            ? day
            : b.report.createdAt.compareTo(a.report.createdAt);
      });
    return DsrHistorySnapshot(entries, warnings: warnings);
  }
}
