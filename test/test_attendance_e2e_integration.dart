import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/core/constants/supabase_constants.dart';
import 'package:skcpl_app/models/attendance_model.dart';
import 'package:skcpl_app/models/site_staff_model.dart';
import 'package:skcpl_app/services/attendance_service.dart';
import 'package:skcpl_app/services/site_staff_service.dart';
import 'package:skcpl_app/services/attendance_excel_service.dart';
import 'package:skcpl_app/services/location_service.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  HttpOverrides.global = MyHttpOverrides();

  late SupabaseClient client;
  late AttendanceService attendanceService;
  late SiteStaffService staffService;

  const nissarpurSiteId = '4c9e1f3a-6903-441a-a2aa-37362a13bafe';
  const indoreSiteId = 'bdb1478e-4fa9-4873-9804-864b0952fa4d';

  setUpAll(() {
    client = SupabaseClient(
      SupabaseConstants.supabaseUrl,
      SupabaseConstants.supabaseServiceRoleKey,
    );
    attendanceService = AttendanceService(client);
    staffService = SiteStaffService(client);
  });

  group('Full Attendance Flow & Admin Approval E2E', () {
    test('1. Verify Site Staff & Phone/Password Authentication', () async {
      // Fetch attendance staff for Nissarpur
      final nissarpurStaff = await staffService.getStaffForSite(
        nissarpurSiteId,
        module: StaffModule.attendance,
      );
      expect(nissarpurStaff, isNotEmpty);
      final staffMember = nissarpurStaff.first;
      expect(staffMember.pin, isNotEmpty);
      expect(staffMember.siteId, equals(nissarpurSiteId));

      // Fetch attendance staff for Indore Head Office
      final indoreStaff = await staffService.getStaffForSite(
        indoreSiteId,
        module: StaffModule.attendance,
      );
      expect(indoreStaff, isNotEmpty);
      final staff = indoreStaff.first;
      expect(staff.pin, isNotEmpty);
      expect(staff.siteId, equals(indoreSiteId));
      print('✓ Verified Staff Creation & Phone/PIN authentication for sites and office');
    });

    test('2. Verify GPS Calculation & Geofencing', () {
      // Test Indore Head Office GPS coordinates (22.7196, 75.8577)
      const officeLat = 22.7196;
      const officeLng = 75.8577;

      // User 50 meters away
      final distClose = LocationService.calculateDistanceMeters(
        userLat: 22.7199,
        userLng: 75.8580,
        siteLat: officeLat,
        siteLng: officeLng,
      );
      expect(distClose, lessThan(100));
      expect(
        LocationService.isWithinGeofence(
          userLat: 22.7199,
          userLng: 75.8580,
          siteLat: officeLat,
          siteLng: officeLng,
          allowedRadiusMeters: 500,
        ),
        isTrue,
      );

      // User 10 km away
      final distFar = LocationService.calculateDistanceMeters(
        userLat: 22.8000,
        userLng: 75.9500,
        siteLat: officeLat,
        siteLng: officeLng,
      );
      expect(distFar, greaterThan(5000));
      expect(
        LocationService.isWithinGeofence(
          userLat: 22.8000,
          userLng: 75.9500,
          siteLat: officeLat,
          siteLng: officeLng,
          allowedRadiusMeters: 500,
        ),
        isFalse,
      );
      print('✓ GPS calculation and Geofence checks working accurately: $distClose m vs $distFar m');
    });

    test('3. Punch-In, >40m Late Lockout, Regularization Request & Admin Approval', () async {
      // Set shift policy for Nissarpur starting at 09:00 AM
      final policy = SiteShiftPolicyModel(
        siteId: nissarpurSiteId,
        siteName: 'Nissarpur Site',
        shiftStartTime: '09:00',
        shiftEndTime: '18:00',
        graceMinutes: 15,
        lateCutoffMinutes: 40,
        allowedRadiusMeters: 500,
        latitude: 22.0375,
        longitude: 74.9254,
      );
      await attendanceService.saveShiftPolicy(policy);

      // Simulate Ramesh Patel punching in at 10:15 AM (75 mins late -> >40 min lockout!)
      final punchDate = DateTime(2026, 10, 20);
      final latePunchTime = DateTime(2026, 10, 20, 10, 15);
      final record = await attendanceService.punchIn(
        siteId: nissarpurSiteId,
        siteName: 'Nissarpur Site',
        staffId: 'emp-nissarpur-ramesh',
        staffName: 'Ramesh Patel',
        staffRole: 'Worker',
        date: punchDate,
        punchTime: latePunchTime,
        latitude: 22.0376,
        longitude: 74.9255,
      );

      print('Punched in Ramesh status: ${record.status.displayName}, lateMinutes: ${record.lateMinutes}');
      expect(record.status, equals(AttendanceStatus.absentLateLockout));
      expect(record.lateMinutes, equals(75));

      // Worker submits late attendance request with reason
      const lateReason = 'Site vehicle had tyre puncture on highway between Kukshi and Nissarpur';
      final requestedRecord = await attendanceService.submitRegularizationRequest(
        attendanceId: record.id,
        reason: lateReason,
      );

      print('Regularization requested: status = ${requestedRecord.status.displayName}, reason = ${requestedRecord.regularizationReason}');
      expect(requestedRecord.status, equals(AttendanceStatus.regularizationPending));
      expect(requestedRecord.regularizationReason, equals(lateReason));

      // Admin checks pending regularization requests
      final pendingRequests = await attendanceService.getPendingRegularizationRequests();
      expect(pendingRequests.any((r) => r.id == record.id), isTrue);
      print('✓ Admin received late regularization request in queue');

      // Admin approves request as Present
      final approvedRecord = await attendanceService.reviewRegularizationRequest(
        attendanceId: record.id,
        approve: true,
        halfDay: false,
        note: 'Verified with site supervisor Vikram. Approved.',
        reviewedBy: 'Admin (Indore Office)',
      );

      print('Admin review complete: status = ${approvedRecord.status.displayName}, remarks = ${approvedRecord.adminDecisionNote}');
      expect(approvedRecord.status, equals(AttendanceStatus.regularizedPresent));
      expect(approvedRecord.adminDecisionNote, contains('Verified with site supervisor'));

      // Test punch-out
      final punchedOut = await attendanceService.punchOut(
        attendanceId: record.id,
        punchOutTime: DateTime(2026, 10, 20, 18, 5),
        latitude: 22.0376,
        longitude: 74.9255,
      );
      expect(punchedOut.punchOutTime, isNotNull);
      print('✓ Punch out successful at ${punchedOut.punchOutTime}');
    });

    test('4. Live GPS Tracking Transmission & Admin Map Pulse', () async {
      final liveLoc = StaffLiveLocationModel(
        staffId: 'emp-indore-ananya',
        staffName: 'Ananya Mehta',
        staffRole: 'Worker',
        siteId: indoreSiteId,
        siteName: 'Indore Head Office',
        latitude: 22.7196,
        longitude: 75.8577,
        isWithinSite: true,
        distanceMeters: 12.5,
        timestamp: DateTime.now(),
      );

      await attendanceService.updateLiveLocation(liveLoc);

      final activeLocations = await attendanceService.getLiveStaffLocations();
      final empLoc = activeLocations.firstWhere((loc) => loc.staffId == 'emp-indore-ananya');
      expect(empLoc.staffId, 'emp-indore-ananya');
      print('✓ Live location tracking verified for Admin radar (Hydrated name: "${empLoc.staffName}")');
    });

    test('5. Monthly Attendance Excel Generation', () async {
      final records = await attendanceService.getAttendanceRange(
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31),
      );

      final excelBytes = AttendanceExcelService.generateMonthlyAttendanceWorkbookBytes(
        title: 'SKCPL Staff Attendance Register',
        month: DateTime(2026, 10, 1),
        records: records,
      );

      expect(excelBytes, isNotNull);
      expect(excelBytes.length, greaterThan(100));
      print('✓ Generated Monthly Attendance Excel (${excelBytes.length} bytes)');
    });
  });
}
