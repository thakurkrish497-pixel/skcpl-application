import '../models/attendance_model.dart';
import 'entry_date_policy.dart';

/// India-time calendar boundaries; automatic ends are estimates, never actual punches.
class AttendanceSessionPolicy {
  static int minutes(String text) {
    final parts = text.split(':');
    if (parts.length < 2) throw const FormatException('Shift time unavailable');
    final h = int.parse(parts[0]), m = int.parse(parts[1]);
    if (h < 0 || h > 23 || m < 0 || m > 59) {
      throw const FormatException('Invalid shift time');
    }
    return h * 60 + m;
  }

  static DateTime indiaInstant(DateTime instant) =>
      instant.toUtc().add(const Duration(minutes: 330));
  static DateTime midnightAfter(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day + 1)
          .subtract(const Duration(minutes: 330));
  static DateTime expiry(DateTime workDay, SiteShiftPolicyModel policy) {
    final start = minutes(policy.shiftStartTime),
        end = minutes(policy.shiftEndTime);
    if (end < start) {
      return DateTime.utc(workDay.year, workDay.month, workDay.day + 1)
          .add(Duration(minutes: end - 330));
    }
    return midnightAfter(workDay);
  }

  static DateTime workDay(DateTime now, SiteShiftPolicyModel policy) {
    final india = indiaInstant(now);
    final day = DateTime(india.year, india.month, india.day);
    final start = minutes(policy.shiftStartTime),
        end = minutes(policy.shiftEndTime);
    return end < start && india.hour * 60 + india.minute < end
        ? DateTime(day.year, day.month, day.day - 1)
        : day;
  }

  static bool current(
      AttendanceRecordModel record, DateTime now, SiteShiftPolicyModel policy) {
    final expiry = record.sessionExpiresAt;
    if (record.punchInTime != null &&
        record.punchOutTime == null &&
        expiry != null &&
        now.toUtc().isBefore(expiry.toUtc())) {
      return true;
    }
    final day = record.sessionWorkDay ?? record.date;
    return EntryDatePolicy.day(day) == workDay(now, policy);
  }
}
