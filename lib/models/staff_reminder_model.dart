import 'attendance_model.dart';
import 'site_staff_model.dart';
import 'daily_site_report_model.dart';

const reminderOfficeIds = {
  'office',
  '89e1477d-7f66-4b6d-99ca-6270183143e0',
  'bdb1478e-4fa9-4873-9804-864b0952fa4d'
};
String reminderSiteKey(String id) =>
    reminderOfficeIds.contains(id) ? 'office' : id;
bool sameReminderSite(String a, String b) =>
    reminderSiteKey(a) == reminderSiteKey(b);
String reminderDatabaseSite(String id) => reminderOfficeIds.contains(id)
    ? '89e1477d-7f66-4b6d-99ca-6270183143e0'
    : id;

String staffReportRemarks(String? staffId) =>
    '[Project Head Review: Pending]${staffId == null ? '' : ' [Staff ID: $staffId]'}';
DateTime indiaCalendar(DateTime instant) =>
    instant.toUtc().add(const Duration(minutes: 330));
String reminderDateKey(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

enum StaffReminderTask { punchIn, punchOut, dsr }

enum DsrCompletion { complete, missing, uncertain }

class StaffTaskReminder {
  final StaffReminderTask task;
  final String staffId, siteId, day, message;
  const StaffTaskReminder(
      this.task, this.staffId, this.siteId, this.day, this.message);
  String get key => 'daily_task_${siteId}_${staffId}_${day}_${task.name}';
}

class StaffShiftWindow {
  final DateTime day, punchInDue, shiftEnd;
  StaffShiftWindow(this.day, this.punchInDue, this.shiftEnd);
  factory StaffShiftWindow.fromPolicy(
      SiteShiftPolicyModel policy, DateTime now) {
    int minutes(String text) {
      final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(text);
      if (match == null) throw const FormatException('Invalid shift time');
      final h = int.parse(match[1]!);
      final m = int.parse(match[2]!);
      if (h > 23 || m > 59) throw const FormatException('Invalid shift time');
      return h * 60 + m;
    }

    final start = minutes(policy.shiftStartTime),
        end = minutes(policy.shiftEndTime);
    if (start == end || policy.graceMinutes < 0 || policy.graceMinutes > 1440) {
      throw const FormatException('Invalid shift policy');
    }
    final india = indiaCalendar(now);
    var day = DateTime.utc(india.year, india.month, india.day);
    final overnight = end < start;
    if (overnight && india.hour * 60 + india.minute < start) {
      day = day.subtract(const Duration(days: 1));
    }
    DateTime at(int mins) => day.add(Duration(minutes: mins - 330));
    return StaffShiftWindow(
        day, at(start + policy.graceMinutes), at(end + (overnight ? 1440 : 0)));
  }
}

DsrCompletion staffDsrCompletion(SiteStaffModel staff,
    List<SiteStaffModel> roster, List<DailySiteReportModel> reports) {
  var ambiguous = false;
  final label = '${staff.name.trim()} (${staff.role.displayName})';
  final sameNames = roster
      .where((s) =>
          s.name.trim().toLowerCase() == staff.name.trim().toLowerCase() &&
          s.role == staff.role)
      .length;
  for (final r in reports) {
    if (!sameReminderSite(r.siteId, staff.siteId)) continue;
    final id = RegExp(r'\[Staff ID:\s*([^\]]+)\]')
        .firstMatch(r.remarks ?? '')
        ?.group(1)
        ?.trim();
    final rejected =
        r.isProjectHeadRejected || r.isAccountsRejected || r.isAdminRejected;
    if (id != null) {
      if (id == staff.id && !rejected) return DsrCompletion.complete;
      continue;
    }
    final legacyLabel = r.submittedBy?.trim().toLowerCase();
    if (legacyLabel == null ||
        !roster.any((s) =>
            '${s.name.trim()} (${s.role.displayName})'.toLowerCase() ==
            legacyLabel)) {
      // An unowned/renamed legacy submission must not be attributed by guesswork.
      ambiguous = true;
    }
    if (legacyLabel == label.toLowerCase()) {
      if (sameNames != 1) {
        ambiguous = true;
      } else if (!rejected) {
        return DsrCompletion.complete;
      }
    }
  }
  return ambiguous ? DsrCompletion.uncertain : DsrCompletion.missing;
}

List<StaffTaskReminder> missingStaffTasks(
    {required SiteStaffModel staff,
    required StaffShiftWindow shift,
    required DateTime now,
    required List<AttendanceRecordModel> attendance,
    required DsrCompletion dsr,
    bool holiday = false}) {
  if (!staff.isActive ||
      holiday ||
      staff.createdAt.toUtc().isAfter(shift.shiftEnd)) {
    return [];
  }
  final day = reminderDateKey(shift.day);
  final rows = attendance
      .where((r) =>
          r.staffId == staff.id &&
          sameReminderSite(r.siteId, staff.siteId) &&
          reminderDateKey(r.date) == day)
      .toList();
  if (rows.any((r) => r.isHoliday)) return [];
  final regularized = rows.any((r) =>
      r.status == AttendanceStatus.regularizedPresent ||
      r.status == AttendanceStatus.regularizedHalfDay);
  final pending =
      rows.any((r) => r.status == AttendanceStatus.regularizationPending);
  final inDone =
      rows.any((r) => r.punchInTime != null) || regularized || pending;
  final outDone = rows.any((r) => r.isSessionClosed) || regularized;
  final result = <StaffTaskReminder>[];
  void add(StaffReminderTask task, String message) =>
      result.add(StaffTaskReminder(task, staff.id, staff.siteId, day, message));
  if (staff.hasModule(StaffModule.attendance)) {
    if (!now.toUtc().isBefore(shift.punchInDue) && !inDone) {
      add(StaffReminderTask.punchIn,
          'Attendance punch-in is not recorded yet. Open Attendance to punch in or request regularization.');
    }
    if (!now.toUtc().isBefore(shift.shiftEnd) &&
        inDone &&
        !pending &&
        !outDone) {
      add(StaffReminderTask.punchOut,
          'Your shift has ended and punch-out is not recorded yet. Please complete Attendance.');
    }
  }
  if (staff.hasModule(StaffModule.report) &&
      !now.toUtc().isBefore(shift.shiftEnd) &&
      dsr == DsrCompletion.missing) {
    add(StaffReminderTask.dsr,
        'Your daily site report is not submitted yet, or needs correction. If you have a draft, finish submitting it.');
  }
  return result;
}
