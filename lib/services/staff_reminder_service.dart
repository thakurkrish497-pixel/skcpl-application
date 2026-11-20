import 'shift_policy_resolver.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/attendance_model.dart';
import '../models/daily_site_report_model.dart';
import '../models/site_staff_model.dart';
import '../models/staff_reminder_model.dart';
import 'submission_support.dart';

class StaffReminderCheck {
  final List<StaffTaskReminder> tasks;
  final String? notice;
  final String staffName;
  const StaffReminderCheck(this.tasks, {this.notice, this.staffName = ''});
}

class StaffReminderService {
  final SupabaseClient client;
  StaffReminderService(this.client);
  Future<List<Map<String, dynamic>>> _rows(String table,
      {Map<String, String> equals = const {},
      String? titleLike,
      List<String>? descriptionIds,
      String select = '*'}) async {
    final out = <Map<String, dynamic>>[];
    String? cursor;
    while (true) {
      var q = client.from(table).select(select);
      for (final e in equals.entries) {
        q = q.eq(e.key, e.value);
      }
      if (titleLike != null) q = q.like('title', titleLike);
      if (descriptionIds != null) {
        if (!descriptionIds
            .every((id) => RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id))) {
          throw const FormatException('Invalid reminder scope');
        }
        q = q
            .or(descriptionIds.map((id) => 'description.like.%$id%').join(','));
      }
      if (cursor != null) q = q.gt('id', cursor);
      final page =
          List<Map<String, dynamic>>.from(await q.order('id').limit(200));
      out.addAll(page);
      if (page.length < 200) break;
      final next = page.last['id']?.toString();
      if (next == null || next == cursor) {
        throw StateError('Reminder read did not advance');
      }
      cursor = next;
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _records(String table, String tag,
      {Map<String, String> equals = const {},
      String select = '*',
      List<String>? tags,
      List<String>? descriptionIds}) async {
    List<Map<String, dynamic>>? primary, legacy;
    try {
      primary = await _rows(table, equals: equals, select: select);
    } catch (e) {
      if (!isSchemaUnavailable(e)) rethrow;
    }
    try {
      legacy = [];
      for (final currentTag in tags ?? [tag]) {
        legacy.addAll((await _rows('tasks',
                titleLike: currentTag,
                descriptionIds: descriptionIds,
                select: 'id,title,description'))
            .map((r) => Map<String, dynamic>.from(
                jsonDecode(r['description'] as String) as Map)));
      }
    } catch (e) {
      if (!isSchemaUnavailable(e)) rethrow;
      legacy = null;
    }
    if (primary == null && legacy == null) {
      throw StateError('Reminder information is unavailable');
    }
    return {
      for (final r in legacy ?? <Map<String, dynamic>>[]) r['id'].toString(): r,
      for (final r in primary ?? <Map<String, dynamic>>[]) r['id'].toString(): r
    }.values.toList();
  }

  Future<SiteShiftPolicyModel?> _policy(String site) =>
      ShiftPolicyResolver(client).configured(site);

  Future<StaffReminderCheck> check(
          String siteId, String staffId, DateTime now) =>
      _check(siteId, staffId, now).timeout(const Duration(seconds: 12));
  Future<StaffReminderCheck> _check(
      String siteId, String staffId, DateTime now) async {
    final policy = await _policy(siteId);
    if (policy == null) {
      return const StaffReminderCheck([],
          notice: 'Reminders are waiting for a confirmed Admin shift policy.');
    }
    final shift = StaffShiftWindow.fromPolicy(policy, now);
    final roster = (await _records('site_staff', 'STAFF:$siteId:%', equals: {
      'site_id': reminderDatabaseSite(siteId)
    }, tags: [
      for (final id in {
        siteId,
        if (reminderOfficeIds.contains(siteId)) ...reminderOfficeIds
      })
        'STAFF:$id:%'
    ]))
        .map((r) => SiteStaffModel.fromJson({...r, 'pin': ''}))
        .where((s) => sameReminderSite(s.siteId, siteId))
        .toList();
    final matches = roster.where((s) => s.id == staffId && s.isActive);
    if (matches.isEmpty) return const StaffReminderCheck([]);
    final staff = matches.first;
    if (!staff.hasModule(StaffModule.attendance) &&
        !staff.hasModule(StaffModule.report)) {
      return const StaffReminderCheck([]);
    }
    if (staff.createdAt.toUtc().isAfter(shift.shiftEnd) ||
        ((!staff.hasModule(StaffModule.attendance) ||
                now.toUtc().isBefore(shift.punchInDue)) &&
            (!staff.hasModule(StaffModule.report) ||
                now.toUtc().isBefore(shift.shiftEnd)))) {
      return StaffReminderCheck([], staffName: staff.name);
    }
    final date = reminderDateKey(shift.day);
    final holidayRows =
        await _records('holidays', 'HOLIDAY:$date%', equals: {'date': date});
    final holiday = holidayRows.map(HolidayModel.fromJson).any((h) =>
        reminderDateKey(h.date) == date &&
        (h.appliesTo(siteId,
                isHeadOffice: reminderOfficeIds.contains(siteId)) ||
            h.siteIds.any((id) => sameReminderSite(id, siteId))));
    if (holiday) return StaffReminderCheck([], staffName: staff.name);
    final attendance = staff.hasModule(StaffModule.attendance)
        ? (await _records(
                'attendance',
                reminderOfficeIds.contains(siteId)
                    ? 'ATTENDANCE:$date:%'
                    : 'ATTENDANCE:$date:$siteId:$staffId',
                equals: {'staff_id': staffId, 'date': date}))
            .map(AttendanceRecordModel.fromJson)
            .toList()
        : <AttendanceRecordModel>[];
    var dsr = DsrCompletion.complete;
    if (staff.hasModule(StaffModule.report) &&
        !now.toUtc().isBefore(shift.shiftEnd)) {
      final rows = await _records('daily_site_reports', 'DSR:$date%',
          equals: {'site_id': reminderDatabaseSite(siteId), 'date': date},
          descriptionIds: {
            siteId,
            if (reminderOfficeIds.contains(siteId)) ...reminderOfficeIds
          }.toList(),
          select: 'id,site_id,date,submitted_by,remarks,created_at,updated_at');
      final reports = rows
          .map(DailySiteReportModel.fromJson)
          .where((r) => reminderDateKey(r.date) == date)
          .toList();
      dsr = staffDsrCompletion(staff, roster, reports);
    }
    return StaffReminderCheck(
        missingStaffTasks(
            staff: staff,
            shift: shift,
            now: now,
            attendance: attendance,
            dsr: dsr),
        staffName: staff.name,
        notice: dsr == DsrCompletion.uncertain
            ? 'An older name-only DSR could not be attributed safely; no DSR reminder was sent.'
            : null);
  }
}
