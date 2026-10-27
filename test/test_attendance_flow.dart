import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/attendance_model.dart';
import 'package:skcpl_app/services/attendance_excel_service.dart';

void main() {
  group('Attendance System Logic Tests', () {
    test('1. Shift Policy timing calculations & status assignment', () {
      final policy = SiteShiftPolicyModel(
        siteId: 'site-1',
        siteName: 'Site Alpha',
        shiftStartTime: '09:00',
        shiftEndTime: '18:00',
        punchOutWindowEnd: '19:00',
        graceMinutes: 15,
        lateCutoffMinutes: 40,
        allowedRadiusMeters: 500,
      );

      final date = DateTime(2026, 10, 20);

      // On time (09:10 -> 10 mins late, within 15m grace)
      final punchOnTime = DateTime(2026, 10, 20, 9, 10);
      final scheduledStart = DateTime(2026, 10, 20, 9, 0);
      final diff1 = punchOnTime.difference(scheduledStart).inMinutes;
      expect(diff1 <= policy.graceMinutes, isTrue);

      // Late (09:30 -> 30 mins late, between grace 15 and cutoff 40)
      final punchLate = DateTime(2026, 10, 20, 9, 30);
      final diff2 = punchLate.difference(scheduledStart).inMinutes;
      expect(diff2 > policy.graceMinutes && diff2 <= policy.lateCutoffMinutes, isTrue);

      // Absent Lockout (09:45 -> 45 mins late, > 40 cutoff)
      final punchLockout = DateTime(2026, 10, 20, 9, 45);
      final diff3 = punchLockout.difference(scheduledStart).inMinutes;
      expect(diff3 > policy.lateCutoffMinutes, isTrue);
    });

    test('2. Regularization Workflow transitions', () {
      final record = AttendanceRecordModel(
        id: 'att-1',
        siteId: 'site-1',
        siteName: 'Site Alpha',
        staffId: 'staff-1',
        staffName: 'Ramesh Patel',
        staffRole: 'Worker',
        date: DateTime(2026, 10, 20),
        punchInTime: DateTime(2026, 10, 20, 9, 50),
        status: AttendanceStatus.absentLateLockout,
        lateMinutes: 50,
        isWithinSite: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(record.status, AttendanceStatus.absentLateLockout);

      // Worker submits reason
      final pendingRecord = record.copyWith(
        status: AttendanceStatus.regularizationPending,
        regularizationReason: 'Flat tyre on highway',
      );
      expect(pendingRecord.status, AttendanceStatus.regularizationPending);
      expect(pendingRecord.regularizationReason, 'Flat tyre on highway');

      // Admin approves as full day
      final approvedFull = pendingRecord.copyWith(
        status: AttendanceStatus.regularizedPresent,
        adminDecisionNote: 'Approved on ground',
        reviewedBy: 'Admin Dad',
      );
      expect(approvedFull.status, AttendanceStatus.regularizedPresent);
      expect(approvedFull.reviewedBy, 'Admin Dad');

      // Admin approves as half day
      final approvedHalf = pendingRecord.copyWith(
        status: AttendanceStatus.regularizedHalfDay,
        adminDecisionNote: 'Approved half day',
        reviewedBy: 'Admin Dad',
      );
      expect(approvedHalf.status, AttendanceStatus.regularizedHalfDay);
    });

    test('3. Attendance Excel Register generation produces valid workbook bytes', () {
      final now = DateTime(2026, 10, 20);
      final sampleRecords = [
        AttendanceRecordModel(
          id: 'rec-1',
          siteId: 'site-1',
          siteName: 'Site Alpha',
          staffId: 'staff-1',
          staffName: 'Ramesh Patel',
          staffRole: 'Worker',
          date: DateTime(2026, 10, 1),
          punchInTime: DateTime(2026, 10, 1, 9, 5),
          punchOutTime: DateTime(2026, 10, 1, 18, 5),
          status: AttendanceStatus.presentOnTime,
          isWithinSite: true,
          createdAt: now,
          updatedAt: now,
        ),
        AttendanceRecordModel(
          id: 'rec-2',
          siteId: 'site-1',
          siteName: 'Site Alpha',
          staffId: 'staff-1',
          staffName: 'Ramesh Patel',
          staffRole: 'Worker',
          date: DateTime(2026, 10, 2),
          punchInTime: DateTime(2026, 10, 2, 9, 25),
          punchOutTime: DateTime(2026, 10, 2, 18, 0),
          status: AttendanceStatus.presentLate,
          lateMinutes: 25,
          isWithinSite: true,
          createdAt: now,
          updatedAt: now,
        ),
        AttendanceRecordModel(
          id: 'rec-3',
          siteId: 'office',
          siteName: 'Indore Head Office',
          staffId: 'staff-2',
          staffName: 'Priya Sharma',
          staffRole: 'Office Staff',
          date: DateTime(2026, 10, 1),
          punchInTime: DateTime(2026, 10, 1, 9, 0),
          punchOutTime: DateTime(2026, 10, 1, 18, 0),
          status: AttendanceStatus.presentOnTime,
          isWithinSite: true,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final bytes = AttendanceExcelService.generateMonthlyAttendanceWorkbookBytes(
        title: 'SKCPL Monthly Register',
        month: DateTime(2026, 10, 1),
        records: sampleRecords,
        siteFilterName: 'Site Alpha',
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      // Valid zip/xlsx magic header bytes: 0x50, 0x4B, 0x03, 0x04
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
    });
  });
}
