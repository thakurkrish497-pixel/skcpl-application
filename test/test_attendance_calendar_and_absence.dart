import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/attendance_model.dart';
import 'package:skcpl_app/models/site_staff_model.dart';

void main() {
  group('Attendance Calendar & Automatic Absence Detection Tests', () {
    final testDate = DateTime(2026, 10, 25);

    final staff1 = SiteStaffModel(
      id: 'staff-1',
      siteId: 'site-a',
      name: 'Ramesh Patel',
      role: SiteStaffRole.worker,
      pin: '1234',
      phone: '9876543210',
      designation: 'Senior Mason',
      createdAt: DateTime(2026, 1, 1),
    );

    final staff2 = SiteStaffModel(
      id: 'staff-2',
      siteId: 'site-a',
      name: 'Suresh Kumar',
      role: SiteStaffRole.worker,
      pin: '5678',
      phone: '9876543211',
      designation: 'Bar Bender',
      createdAt: DateTime(2026, 1, 1),
    );

    final staff3 = SiteStaffModel(
      id: 'staff-3',
      siteId: 'site-a',
      name: 'Vikram Singh',
      role: SiteStaffRole.worker,
      pin: '9999',
      phone: '9876543212',
      designation: 'Electrician',
      createdAt: DateTime(2026, 1, 1),
    );

    test('1. Present employee is detected and has isPresent == true', () {
      final punchRecord = AttendanceRecordModel(
        id: 'punch-1',
        siteId: 'site-a',
        siteName: 'Indore Highway Project',
        staffId: staff1.id,
        staffName: staff1.name,
        staffRole: staff1.designation!,
        date: testDate,
        punchInTime: DateTime(2026, 10, 25, 9, 5),
        status: AttendanceStatus.presentOnTime,
        createdAt: testDate,
        updatedAt: testDate,
      );

      expect(punchRecord.isPresent, isTrue);
      expect(punchRecord.isAbsent, isFalse);
      expect(punchRecord.isUnmarkedAbsent, isFalse);
      expect(punchRecord.displayStatusName, 'Present (On-Time)');
    });

    test('2. Unmarked employee is computed as Absent with isUnmarkedAbsent == true', () {
      final recordedList = [
        AttendanceRecordModel(
          id: 'punch-1',
          siteId: 'site-a',
          siteName: 'Indore Highway Project',
          staffId: staff1.id,
          staffName: staff1.name,
          staffRole: staff1.designation!,
          date: testDate,
          punchInTime: DateTime(2026, 10, 25, 9, 5),
          status: AttendanceStatus.presentOnTime,
          createdAt: testDate,
          updatedAt: testDate,
        ),
      ];

      final allActiveStaff = [staff1, staff2, staff3];

      // Replicate the Automatic Absence detection logic
      final effectiveRoster = <AttendanceRecordModel>[];
      final recordedStaffIds = <String>{};

      for (final r in recordedList) {
        effectiveRoster.add(r);
        if (r.staffId.isNotEmpty) recordedStaffIds.add(r.staffId);
      }

      for (final staff in allActiveStaff) {
        if (!recordedStaffIds.contains(staff.id)) {
          effectiveRoster.add(AttendanceRecordModel(
            id: 'unmarked-${staff.id}-2026-10-25',
            siteId: staff.siteId,
            siteName: 'Indore Highway Project',
            staffId: staff.id,
            staffName: staff.name,
            staffRole: staff.designation ?? staff.role.displayName,
            date: testDate,
            punchInTime: null,
            punchOutTime: null,
            status: AttendanceStatus.absent,
            adminDecisionNote: 'Unmarked Attendance • Considered Absent',
            createdAt: testDate,
            updatedAt: testDate,
          ));
        }
      }

      expect(effectiveRoster.length, 3);

      final presentList = effectiveRoster.where((r) => r.isPresent).toList();
      final absentList = effectiveRoster.where((r) => r.isAbsent).toList();

      expect(presentList.length, 1);
      expect(presentList.first.staffId, 'staff-1');

      expect(absentList.length, 2);
      expect(absentList.any((r) => r.staffId == 'staff-2'), isTrue);
      expect(absentList.any((r) => r.staffId == 'staff-3'), isTrue);

      final unmarkedRecord = absentList.first;
      expect(unmarkedRecord.isUnmarkedAbsent, isTrue);
      expect(unmarkedRecord.displayStatusName, 'Absent (Not Marked)');
      expect(unmarkedRecord.punchInTime, isNull);
      expect(unmarkedRecord.adminDecisionNote, contains('Considered Absent'));
    });

    test('3. Calendar date calculations and same-day logic', () {
      final d1 = DateTime(2026, 10, 25, 9, 30);
      final d2 = DateTime(2026, 10, 25, 18, 0);
      final d3 = DateTime(2026, 10, 26, 9, 0);

      bool isSameDay(DateTime a, DateTime b) {
        return a.year == b.year && a.month == b.month && a.day == b.day;
      }

      expect(isSameDay(d1, d2), isTrue);
      expect(isSameDay(d1, d3), isFalse);

      // Verify October 2026 days
      final oct2026FirstDay = DateTime(2026, 10, 1);
      final oct2026DaysInMonth = DateTime(2026, 10 + 1, 0).day;
      expect(oct2026DaysInMonth, 31);
      expect(oct2026FirstDay.weekday, DateTime.thursday); // Thursday
    });

    test('4. Site selection strictly isolates employees of that site only', () {
      final staffSiteA = SiteStaffModel(
        id: 'staff-a',
        siteId: 'site-a',
        name: 'Worker A',
        role: SiteStaffRole.worker,
        pin: '1111',
        createdAt: DateTime(2026, 1, 1),
      );

      final staffSiteB = SiteStaffModel(
        id: 'staff-b',
        siteId: 'site-b',
        name: 'Worker B',
        role: SiteStaffRole.worker,
        pin: '2222',
        createdAt: DateTime(2026, 1, 1),
      );

      final allStaff = [staffSiteA, staffSiteB];

      final recordedPunches = [
        AttendanceRecordModel(
          id: 'punch-a',
          siteId: 'site-a',
          siteName: 'Site A',
          staffId: 'staff-a',
          staffName: 'Worker A',
          staffRole: 'Worker',
          date: testDate,
          punchInTime: DateTime(2026, 10, 25, 9, 0),
          status: AttendanceStatus.presentOnTime,
          createdAt: testDate,
          updatedAt: testDate,
        ),
        AttendanceRecordModel(
          id: 'punch-b',
          siteId: 'site-b',
          siteName: 'Site B',
          staffId: 'staff-b',
          staffName: 'Worker B',
          staffRole: 'Worker',
          date: testDate,
          punchInTime: DateTime(2026, 10, 25, 9, 30),
          status: AttendanceStatus.presentOnTime,
          createdAt: testDate,
          updatedAt: testDate,
        ),
      ];

      // Filtering strictly for site-a
      final targetSite = 'site-a';

      final siteAStaff = allStaff.where((s) => s.siteId == targetSite).toList();
      final siteAPunches = recordedPunches.where((r) => r.siteId == targetSite).toList();

      final rosterA = <AttendanceRecordModel>[...siteAPunches];
      for (final s in siteAStaff) {
        if (!rosterA.any((r) => r.staffId == s.id)) {
          rosterA.add(AttendanceRecordModel(
            id: 'unmarked-${s.id}',
            siteId: s.siteId,
            siteName: 'Site A',
            staffId: s.id,
            staffName: s.name,
            staffRole: 'Worker',
            date: testDate,
            status: AttendanceStatus.absent,
            createdAt: testDate,
            updatedAt: testDate,
          ));
        }
      }

      // Verify site-a roster has ONLY Worker A, and NOT Worker B
      expect(rosterA.length, 1);
      expect(rosterA.first.staffId, 'staff-a');
      expect(rosterA.any((r) => r.staffId == 'staff-b'), isFalse);
    });
  });
}
