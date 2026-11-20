import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/attendance_model.dart';
import 'submission_support.dart';

/// Read-only overlay. Source attendance rows and their review hashes remain intact.
class AttendanceSessionMetadata {
  final SupabaseClient client;
  AttendanceSessionMetadata(this.client);
  Future<List<AttendanceRecordModel>> attach(
      List<AttendanceRecordModel> records) async {
    final open = records
        .where((r) =>
            r.punchInTime != null && r.punchOutTime == null && r.id.isNotEmpty)
        .toList();
    if (open.isEmpty) return records;
    final snapshots = <String, Map<String, dynamic>>{},
        closures = <String, Map<String, dynamic>>{};
    for (var i = 0; i < open.length; i += 200) {
      final ids = open.skip(i).take(200).map((r) => r.id).toList();
      for (final table in [
        'skcpl_attendance_sessions',
        'skcpl_attendance_closures'
      ]) {
        try {
          final rows =
              await client.from(table).select().inFilter('attendance_id', ids);
          for (final row in rows) {
            (table.endsWith('sessions')
                ? snapshots
                : closures)[row['attendance_id'] as String] = row;
          }
        } catch (error) {
          if (!isSchemaUnavailable(error)) rethrow;
        }
      }
    }
    return records.map((r) {
      if (r.punchInTime == null || r.punchOutTime != null) return r;
      final snapshot = snapshots[r.id], closure = closures[r.id];
      bool matches(Map<String, dynamic>? row) =>
          row != null &&
          DateTime.tryParse('${row['punch_in_time']}')?.toUtc() ==
              r.punchInTime!.toUtc();
      return r.copyWith(
          sessionWorkDay: matches(snapshot)
              ? DateTime.tryParse('${snapshot!['work_day']}')
              : null,
          sessionExpiresAt: matches(snapshot)
              ? DateTime.tryParse('${snapshot!['expires_at']}')
              : null,
          automaticClosedAt: matches(closure)
              ? DateTime.tryParse('${closure!['cutoff_at']}')
              : null);
    }).toList();
  }
}
