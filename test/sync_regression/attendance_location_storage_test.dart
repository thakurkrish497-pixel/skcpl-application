import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/models/attendance_model.dart';
import 'package:skcpl_app/providers/attendance_provider.dart';
import 'package:skcpl_app/services/attendance_service.dart';
import 'package:skcpl_app/services/attendance_session_metadata.dart';
import 'attendance_location_test.dart' show record;

class PunchReads extends AttendanceService {
  final waiting = <String, Completer<List<AttendanceRecordModel>>>{};
  final rows = <AttendanceRecordModel>[];
  bool delay = false;
  @override
  Future<SiteShiftPolicyModel> getShiftPolicy(String id) async =>
      SiteShiftPolicyModel(siteId: id, siteName: id);
  @override
  Future<List<AttendanceRecordModel>> getTodayAttendance(String id,
      [DateTime? date]) async {
    if (delay) {
      final key = '$id:$date';
      return waiting
          .putIfAbsent(key, () => Completer<List<AttendanceRecordModel>>())
          .future;
    }
    return rows;
  }
}

http.Response response(http.Request r, Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        request: r, headers: {'content-type': 'application/json'});
SupabaseClient client(Future<http.Response> Function(http.Request) handle) =>
    SupabaseClient('http://gps.fixture.invalid', 'fixture',
        httpClient: MockClient(handle),
        authOptions: const AuthClientOptions(autoRefreshToken: false));
StaffLiveLocationModel ping(DateTime stamp) => StaffLiveLocationModel(
    staffId: 'w',
    staffName: 'Worker',
    staffRole: 'Worker',
    siteId: 's',
    siteName: 'Site',
    latitude: 22.7,
    longitude: 75.8,
    accuracyMeters: 10,
    isWithinSite: true,
    distanceMeters: 0,
    timestamp: stamp);
void main() {
  test(
      'Missing metadata schema leaves original attendance usable and unchanged',
      () async {
    final c = client((r) async => response(
        r, {'code': '42P01', 'message': 'missing relation'},
        status: 404));
    addTearDown(c.dispose);
    final source = record();
    final result = await AttendanceSessionMetadata(c).attach([source]);
    expect(result.single.toJson(), source.toJson());
    expect(result.single.automaticClosedAt, isNull);
  });
  test(
      'Metadata is attached only to matching original punch; completed punches preserved',
      () async {
    final source = record(), cutoff = DateTime.parse('2020-12-31T18:30:00Z');
    final c = client((r) async => response(r, [
          {
            'attendance_id': 'a',
            'punch_in_time': source.punchInTime!.toIso8601String(),
            'work_day': '2020-12-31',
            'expires_at': cutoff.toIso8601String(),
            'cutoff_at': cutoff.toIso8601String()
          }
        ]));
    addTearDown(c.dispose);
    final result = (await AttendanceSessionMetadata(c).attach([source])).single;
    expect(result.automaticClosedAt, cutoff);
    expect(result.toJson(), source.toJson());
    final completed =
        source.copyWith(punchOutTime: DateTime.parse('2020-12-31T12:00:00Z'));
    expect(
        (await AttendanceSessionMetadata(c).attach([completed]))
            .single
            .totalHoursWorked,
        8);
  });
  test('Stale metadata for an edited punch cannot close the corrected record',
      () async {
    final c = client((r) async => response(r, [
          {
            'attendance_id': 'a',
            'punch_in_time': '2019-01-01T00:00:00Z',
            'expires_at': '2019-01-01T18:30:00Z',
            'cutoff_at': '2019-01-01T18:30:00Z'
          }
        ]));
    addTearDown(c.dispose);
    expect(
        (await AttendanceSessionMetadata(c).attach([record()]))
            .single
            .automaticClosedAt,
        isNull);
  });
  test('Older location sample never overwrites a newer device fix', () async {
    final now = DateTime.now();
    var writes = 0;
    final c = client((r) async {
      if (r.method != 'GET') writes++;
      return response(r, [
        {'staff_id': 'w', 'timestamp': now.toIso8601String()}
      ]);
    });
    addTearDown(c.dispose);
    await AttendanceService(c)
        .updateLiveLocation(ping(now.subtract(const Duration(seconds: 5))));
    expect(writes, 0);
  });
  test(
      'Location compare-and-set collision rereads newest timestamp before writing',
      () async {
    final now = DateTime.now();
    var reads = 0, writes = 0;
    final c = client((r) async {
      if (r.method == 'GET') {
        reads++;
        return response(r, [
          {
            'staff_id': 'w',
            'timestamp': now
                .add(Duration(seconds: reads == 1 ? -10 : 1))
                .toIso8601String()
          }
        ]);
      }
      writes++;
      expect(r.url.queryParameters['timestamp'], startsWith('eq.'));
      return response(r, []);
    });
    addTearDown(c.dispose);
    await AttendanceService(c).updateLiveLocation(ping(now));
    expect(reads, 2);
    expect(writes, 1);
  });
  test('Permission errors never bypass to shared task fallback', () async {
    final paths = <String>[];
    final c = client((r) async {
      paths.add(r.url.path);
      return response(r, {'code': '42501', 'message': 'denied'}, status: 403);
    });
    addTearDown(c.dispose);
    await expectLater(
        AttendanceService(c).updateLiveLocation(ping(DateTime.now())),
        throwsA(isA<PostgrestException>()));
    expect(paths.every((p) => p.endsWith('staff_live_locations')), true);
  });
  test('No-record refresh clears yesterday instead of trapping next punch',
      () async {
    final service = PunchReads(),
        container = ProviderContainer(overrides: [
          attendanceServiceProvider.overrideWithValue(PunchReads())
        ]);
    addTearDown(container.dispose);
    // Use a provider-backed notifier so its lifecycle and async guards are real.
    final provider = StateNotifierProvider<StaffPunchNotifier, StaffPunchState>(
        (ref) => StaffPunchNotifier(service, ref));
    final now = DateTime.now();
    service.rows.add(record().copyWith(date: now, createdAt: now));
    await container
        .read(provider.notifier)
        .loadTodayRecord(siteId: 's', staffId: 'u');
    expect(container.read(provider).todayRecord, isNotNull);
    service.rows.clear();
    await container
        .read(provider.notifier)
        .loadTodayRecord(siteId: 's', staffId: 'u');
    expect(container.read(provider).todayRecord, isNull);
  });
  test('Older asynchronous employee load cannot erase newer employee state',
      () async {
    final service = PunchReads()..delay = true, container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = StateNotifierProvider<StaffPunchNotifier, StaffPunchState>(
        (ref) => StaffPunchNotifier(service, ref));
    final notifier = container.read(provider.notifier);
    final old = notifier.loadTodayRecord(siteId: 's', staffId: 'u');
    await Future<void>.delayed(Duration.zero);
    service.delay = false;
    final now = DateTime.now();
    service.rows
        .add(record().copyWith(date: now, staffId: 'new', createdAt: now));
    await notifier.loadTodayRecord(siteId: 's', staffId: 'new');
    expect(container.read(provider).todayRecord!.staffId, 'new');
    for (final gate in service.waiting.values) {
      gate.complete([]);
    }
    await old;
    expect(container.read(provider).todayRecord!.staffId, 'new');
  });
}
