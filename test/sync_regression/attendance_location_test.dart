import 'package:skcpl_app/core/utils/attendance_time.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:excel/excel.dart';
import 'package:skcpl_app/models/attendance_model.dart';
import 'package:skcpl_app/providers/attendance_provider.dart';
import 'package:skcpl_app/services/attendance_session_policy.dart';
import 'package:skcpl_app/services/attendance_excel_service.dart';
import 'package:skcpl_app/services/location_service.dart';
import 'package:skcpl_app/services/staff_location_tracking.dart';

Position fix(DateTime at,
        {double lat = 22.7, double accuracy = 10, bool mocked = false}) =>
    Position(
        longitude: 75.8,
        latitude: lat,
        timestamp: at,
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
        isMocked: mocked);
const dayPolicy = SiteShiftPolicyModel(siteId: 's', siteName: 'Site');
const nightPolicy = SiteShiftPolicyModel(
    siteId: 's',
    siteName: 'Site',
    shiftStartTime: '20:00',
    shiftEndTime: '06:00');
AttendanceRecordModel record(
        {DateTime? out, DateTime? expiry, DateTime? closure}) =>
    AttendanceRecordModel(
        id: 'a',
        siteId: 's',
        siteName: 'Site',
        staffId: 'u',
        staffName: 'Worker',
        staffRole: 'Worker',
        date: DateTime(2020, 12, 31),
        punchInTime: DateTime.parse('2020-12-31T04:00:00Z'),
        punchOutTime: out,
        sessionExpiresAt: expiry,
        automaticClosedAt: closure,
        status: AttendanceStatus.presentOnTime,
        createdAt: DateTime(2020),
        updatedAt: DateTime(2020));
void main() {
  test(
      'Legacy Admin dot-separated shift settings are read consistently without rewriting them',
      () {
    final source = {
      'site_id': 'site',
      'shift_start_time': '10.00',
      'shift_end_time': '19.30'
    };
    final policy = SiteShiftPolicyModel.fromJson(source);
    expect(policy.shiftStartTime, '10:00');
    expect(policy.shiftEndTime, '19:30');
    expect(policy.startTimeOfDay.hour, 10);
    expect(AttendanceSessionPolicy.minutes('10.00'), 600);
    expect(source['shift_start_time'], '10.00');
  });

  test('Legacy offset-free punches are India time on every device', () {
    expect(parseAttendanceInstant('2026-11-20T09:00:00').toUtc(),
        DateTime.parse('2026-11-20T03:30:00Z'));
    expect(parseAttendanceInstant('2026-11-20T09:00:00+05:30').toUtc(),
        DateTime.parse('2026-11-20T03:30:00Z'));
    final raw = record().toJson()..['punch_in_time'] = '2020-12-31T09:30:00';
    expect(AttendanceRecordModel.fromJson(raw).punchInTime!.toUtc(),
        DateTime.parse('2020-12-31T04:00:00Z'));
    expect(raw['punch_in_time'], '2020-12-31T09:30:00');
  });

  test('India midnight/year rollover independent of device timezone', () {
    final before = DateTime.parse('2026-12-31T18:29:59Z');
    final after = DateTime.parse('2026-12-31T18:30:00Z');
    expect(AttendanceSessionPolicy.workDay(before, dayPolicy),
        DateTime(2026, 12, 31));
    expect(AttendanceSessionPolicy.workDay(after, dayPolicy),
        DateTime(2027, 1, 1));
    expect(AttendanceSessionPolicy.expiry(DateTime(2026, 12, 31), dayPolicy),
        after);
  });
  test('Overnight early morning belongs to prior workday until exact end', () {
    expect(
        AttendanceSessionPolicy.workDay(
            DateTime.parse('2026-11-20T23:30:00Z'), nightPolicy),
        DateTime(2026, 11, 20));
    expect(
        AttendanceSessionPolicy.workDay(
            DateTime.parse('2026-11-21T00:30:00Z'), nightPolicy),
        DateTime(2026, 11, 21));
    expect(AttendanceSessionPolicy.expiry(DateTime(2026, 11, 20), nightPolicy),
        DateTime.parse('2026-11-21T00:30:00Z'));
  });
  test('Captured overnight session survives subsequent Admin shift change', () {
    final r = record(expiry: DateTime.parse('2021-01-01T00:30:00Z'));
    expect(
        AttendanceSessionPolicy.current(
            r, DateTime.parse('2020-12-31T20:30:00Z'), dayPolicy),
        true);
    expect(
        AttendanceSessionPolicy.current(
            r, DateTime.parse('2021-01-01T00:30:00Z'), dayPolicy),
        false);
  });
  test(
      'Automatic end bounds estimates but does not fabricate actual out or change JSON',
      () {
    final cutoff = DateTime.parse('2020-12-31T18:30:00Z');
    final original = record(), closed = record(expiry: cutoff, closure: cutoff);
    expect(closed.punchOutTime, isNull);
    expect(closed.isSessionClosed, true);
    expect(closed.totalHoursWorked, 14.5);
    expect(closed.displayStatusName, contains('review required'));
    expect(closed.toJson(), original.toJson());
  });
  test('Actual corrected punch takes precedence over estimated end', () {
    final r = record(
        out: DateTime.parse('2020-12-31T12:00:00Z'),
        expiry: DateTime.parse('2020-12-31T18:30:00Z'));
    expect(r.totalHoursWorked, 8);
    expect(r.isAutomaticallyClosed, false);
    expect(r.displayStatusName, isNot(contains('estimated')));
  });
  test('Midnight state explicitly clears old record', () {
    final s = StaffPunchState(todayRecord: record());
    expect(s.copyWith(isLoading: true).todayRecord, isNotNull);
    expect(s.copyWith(clearTodayRecord: true).todayRecord, isNull);
  });
  test(
      'Invalid shift times fail instead of making an arbitrary overnight expiry',
      () {
    for (final time in ['25:00', '06:70', 'bogus']) {
      expect(
          () => AttendanceSessionPolicy.minutes(time), throwsFormatException);
    }
  });
  test('Payroll export separates estimated from recorded hours', () {
    final closed = record(closure: DateTime.parse('2020-12-31T18:30:00Z'));
    final bytes = AttendanceExcelService.generateMonthlyAttendanceWorkbookBytes(
        title: 'Audit', month: DateTime(2020, 12), records: [closed]);
    final book = Excel.decodeBytes(bytes);
    final rows = book.tables['MONTHLY ATTENDANCE REGISTER']!.rows;
    expect(rows[3][39]!.value.toString(), 'Estimated Hrs (Review)');
    expect(rows[4][38]!.value.toString(), '0');
    expect(rows[4][39]!.value.toString(), '14.5');
    final log = book.tables['DAILY LOGS & GPS AUDIT']!.rows[1];
    expect(log[4]!.value.toString(), contains('estimated'));
    expect(log[6]!.value.toString(), 'Auto-closed (estimated)');
  });
  test('GPS rejects coarse, stale, mock, future and nonfinite fixes', () {
    final now = DateTime.now();
    expect(
        LocationService.isUsableAttendancePosition(fix(now), now: now), true);
    for (final bad in [
      fix(now, accuracy: 101),
      fix(now, accuracy: double.nan),
      fix(now, lat: 91),
      fix(now, mocked: true),
      fix(now.subtract(const Duration(minutes: 3))),
      fix(now.add(const Duration(seconds: 31)))
    ]) {
      expect(LocationService.isUsableAttendancePosition(bad, now: now), false);
    }
  });
  test('GPS rejects out-of-order samples and isolated impossible jumps',
      () async {
    var now = DateTime.now();
    final sent = <Position>[];
    final tracker = StaffLocationTracking(
        now: () => now,
        publish: (p) async {
          sent.add(p);
        });
    expect(tracker.accept(fix(now)), true);
    await Future<void>.delayed(Duration.zero);
    expect(
        tracker.accept(fix(now.subtract(const Duration(seconds: 1)))), false);
    now = now.add(const Duration(seconds: 1));
    expect(tracker.accept(fix(now, lat: 23.7)), false);
    expect(sent.length, 1);
    tracker.dispose();
  });
  test('Consistent relocation can be confirmed; writes remain throttled',
      () async {
    var now = DateTime.now();
    final sent = <Position>[];
    final tracker = StaffLocationTracking(
        now: () => now,
        publish: (p) async {
          sent.add(p);
        });
    tracker.accept(fix(now));
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(seconds: 1));
    expect(tracker.accept(fix(now, lat: 23.7)), false);
    now = now.add(const Duration(seconds: 4));
    expect(tracker.accept(fix(now, lat: 23.7)), true);
    await Future<void>.delayed(Duration.zero);
    expect(sent.length, 1);
    now = now.add(const Duration(seconds: 21));
    tracker.accept(fix(now, lat: 23.7));
    await Future<void>.delayed(Duration.zero);
    expect(sent.length, 2);
    tracker.dispose();
  });
  test('Telemetry errors are isolated and retry rate bounded', () async {
    var now = DateTime.now(), attempts = 0;
    final tracker = StaffLocationTracking(
        now: () => now,
        publish: (p) async {
          attempts++;
          throw StateError('offline');
        });
    tracker.accept(fix(now));
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(seconds: 1));
    tracker.accept(fix(now));
    await Future<void>.delayed(Duration.zero);
    expect(attempts, 1);
    now = now.add(const Duration(seconds: 20));
    tracker.accept(fix(now));
    await Future<void>.delayed(Duration.zero);
    expect(attempts, 2);
    tracker.dispose();
    now = now.add(const Duration(seconds: 20));
    expect(tracker.accept(fix(now)), false);
  });
  test('Only one GPS publish in flight; disposal drops coalesced pending fix',
      () async {
    var now = DateTime.now();
    var calls = 0;
    final gate = Completer<void>();
    final tracker = StaffLocationTracking(
        now: () => now,
        publish: (p) {
          calls++;
          return gate.future;
        });
    tracker.accept(fix(now));
    now = now.add(const Duration(seconds: 21));
    tracker.accept(fix(now));
    expect(calls, 1);
    tracker.dispose();
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
  });
  test('Missing location timestamp never masquerades as a fresh fix', () {
    expect(StaffLiveLocationModel.fromJson({}).timestamp.year, 1970);
    expect(StaffLiveLocationModel.fromJson({}).isWithinSite, false);
  });
}
