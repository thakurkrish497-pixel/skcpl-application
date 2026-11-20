import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/models/attendance_model.dart';
import 'package:skcpl_app/models/staff_reminder_model.dart';
import 'package:skcpl_app/services/attendance_service.dart';
import 'package:skcpl_app/services/shift_policy_resolver.dart';
import '../support/erp_test_backend.dart';

const site = '4c9e1f3a-6903-441a-a2aa-37362a13bafe';
SiteShiftPolicyModel policy(String id,
        {String start = '10:00', String end = '19:00', int grace = 20}) =>
    SiteShiftPolicyModel(
        siteId: id,
        siteName: 'Assigned location',
        shiftStartTime: start,
        shiftEndTime: end,
        graceMinutes: grace,
        latitude: 22.7,
        longitude: 75.8);

class PolicyStore {
  final primary = <String, Map<String, dynamic>>{};
  final legacy = <String, Map<String, dynamic>>{};
  final requests = <http.Request>[];
  bool missingPrimary = false,
      failSave = false,
      failRead = false,
      failLegacySave = false;
  late final client = SupabaseClient('http://shift.fixture.invalid', 'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(handle));
  http.Response response(http.Request request, Object body,
          {int status = 200}) =>
      http.Response(jsonEncode(body), status,
          request: request, headers: {'content-type': 'application/json'});
  Future<http.Response> handle(http.Request req) async {
    requests.add(req);
    final path = req.url.path;
    if (path.endsWith('site_shift_policies')) {
      if (missingPrimary) {
        return response(req, {'code': '42P01', 'message': 'missing relation'},
            status: 404);
      }
      if (failRead && req.method == 'GET') {
        return response(req, {'code': '42501', 'message': 'denied'},
            status: 403);
      }
      if (req.method == 'GET') {
        final id =
            (req.url.queryParameters['site_id'] ?? '').replaceFirst('eq.', '');
        return response(req, primary[id] == null ? [] : [primary[id]]);
      }
      if (failSave) {
        return response(req, {'code': '42501', 'message': 'denied'},
            status: 403);
      }
      final data = Map<String, dynamic>.from(jsonDecode(req.body) as Map);
      data['updated_at'] = DateTime.now().toUtc().toIso8601String();
      primary[data['site_id'] as String] = data;
      return response(req, data);
    }
    if (path.endsWith('tasks')) {
      if (req.method == 'GET') {
        final title =
            (req.url.queryParameters['title'] ?? '').replaceFirst('eq.', '');
        return response(req, legacy[title] == null ? [] : [legacy[title]]);
      }
      if (failLegacySave) {
        return response(req, {'code': '42501', 'message': 'denied'},
            status: 403);
      }
      final data = Map<String, dynamic>.from(jsonDecode(req.body) as Map);
      if (req.method == 'PATCH') {
        final id = req.url.queryParameters['id']!.replaceFirst('eq.', '');
        final row = legacy.values.firstWhere((r) => r['id'] == id);
        row.addAll(data);
        row['updated_at'] = DateTime.now().toUtc().toIso8601String();
        return response(req, {});
      }
      data['id'] = 'task-${legacy.length}';
      data['updated_at'] = DateTime.now().toUtc().toIso8601String();
      legacy[data['title'] as String] = data;
      return response(req, {});
    }
    return ErpTestBackend.instance.handle(req);
  }

  void task(SiteShiftPolicyModel value, {DateTime? stamp}) {
    legacy['SHIFT_POLICY:${value.siteId}'] = {
      'id': 'task-${legacy.length}',
      'title': 'SHIFT_POLICY:${value.siteId}',
      'description': jsonEncode(value.toJson()),
      'updated_at': (stamp ?? DateTime.now()).toUtc().toIso8601String()
    };
  }
}

void main() {
  late PolicyStore store;
  setUp(() => store = PolicyStore());
  tearDown(() async => store.client.dispose());
  test('A site legacy override takes precedence over a primary global default',
      () async {
    store.primary['global'] = policy('global', start: '08:00').toJson();
    store.task(policy(site, start: '11:00', grace: 30));
    final result = await AttendanceService(store.client).getShiftPolicy(site);
    expect(result.shiftStartTime, '11:00');
    expect(result.graceMinutes, 30);
    expect(result.siteId, site);
  });
  test(
      'Global fallback is inherited but bound to the requested site for future edits',
      () async {
    store.missingPrimary = true;
    store.task(policy('global', start: '08:30'));
    final before = store.legacy['SHIFT_POLICY:global']!['description'];
    final service = AttendanceService(store.client);
    final inherited = await service.getShiftPolicy(site);
    expect(inherited.siteId, site);
    expect(inherited.shiftStartTime, '08:30');
    await service.saveShiftPolicy(inherited.copyWith(shiftStartTime: '11:00'));
    expect(store.legacy['SHIFT_POLICY:global']!['description'], before);
    expect((await service.getShiftPolicy(site)).shiftStartTime, '11:00');
  });
  test('All office aliases resolve the same latest configured office timing',
      () async {
    final old = DateTime.now().subtract(const Duration(days: 2));
    store.primary[canonicalOfficeShiftId] = {
      ...policy(canonicalOfficeShiftId, start: '08:00').toJson(),
      'updated_at': old.toIso8601String()
    };
    store.task(
        policy('bdb1478e-4fa9-4873-9804-864b0952fa4d',
            start: '10:30', grace: 25),
        stamp: old.add(const Duration(days: 1)));
    for (final id in reminderOfficeIds) {
      final result = await AttendanceService(store.client).getShiftPolicy(id);
      expect(result.shiftStartTime, '10:30');
      expect(result.graceMinutes, 25);
      expect(result.siteId, canonicalOfficeShiftId);
    }
  });
  test(
      'Office saves use one canonical location and never write individual staff settings',
      () async {
    final service = AttendanceService(store.client);
    await service.saveShiftPolicy(policy('office', start: '10:15'));
    await service.saveShiftPolicy(policy('bdb1478e-4fa9-4873-9804-864b0952fa4d',
        start: '11:15', grace: 35));
    expect(store.primary.keys, [canonicalOfficeShiftId]);
    for (final id in reminderOfficeIds) {
      final result = await service.getShiftPolicy(id);
      expect(result.shiftStartTime, '11:15');
      expect(result.graceMinutes, 35);
    }
    expect(
        store.requests
            .where((r) => r.method != 'GET')
            .every((r) => r.url.path.endsWith('site_shift_policies')),
        isTrue);
  });
  test(
      'A configured site remains independent of a later company default change',
      () async {
    store.primary[site] = policy(site, start: '11:30').toJson();
    await AttendanceService(store.client)
        .saveShiftPolicy(policy('global', start: '07:30'));
    expect(
        (await AttendanceService(store.client).getShiftPolicy(site))
            .shiftStartTime,
        '11:30');
  });
  test('Permission failures never substitute guessed shift timings', () async {
    store.failRead = true;
    await expectLater(AttendanceService(store.client).getShiftPolicy(site),
        throwsA(isA<PostgrestException>()));
    expect(store.requests.every((r) => r.method == 'GET'), isTrue);
  });
  test(
      'A denied policy save does not emit a successful-save refresh or fallback write',
      () async {
    store.failSave = true;
    var events = 0;
    final sub = shiftPolicySaved.stream.listen((_) => events++);
    addTearDown(sub.cancel);
    await expectLater(
        AttendanceService(store.client).saveShiftPolicy(policy(site)),
        throwsA(isA<PostgrestException>()));
    await Future<void>.delayed(Duration.zero);
    expect(events, 0);
    expect(store.legacy, isEmpty);
  });
  test('Failed legacy persistence cannot pretend the new shift was saved',
      () async {
    store.missingPrimary = true;
    store.failLegacySave = true;
    var events = 0;
    final sub = shiftPolicySaved.stream.listen((_) => events++);
    addTearDown(sub.cancel);
    await expectLater(
        AttendanceService(store.client).saveShiftPolicy(policy(site)),
        throwsA(isA<PostgrestException>()));
    await Future<void>.delayed(Duration.zero);
    expect(events, 0);
    expect(store.legacy, isEmpty);
  });
  test('Invalid times and grace are rejected before any network writes',
      () async {
    for (final p in [
      policy(site, start: '25:00'),
      policy(site, start: '09:99'),
      policy(site, start: '09:00:99'),
      policy(site, start: '19:00', end: '19:00'),
      policy(site, grace: -1)
    ]) {
      await expectLater(AttendanceService(store.client).saveShiftPolicy(p),
          throwsArgumentError);
    }
    expect(store.requests, isEmpty);
  });
  test(
      'Shift save preserves completed and active attendance records and recorded hours',
      () async {
    final backend = ErpTestBackend.instance;
    final record = AttendanceRecordModel(
        id: 'old-punch',
        siteId: site,
        siteName: 'Site',
        staffId: 'staff-a',
        staffName: 'Staff',
        staffRole: 'worker',
        date: DateTime(2026, 11, 18),
        punchInTime: DateTime(2026, 11, 18, 9),
        punchOutTime: DateTime(2026, 11, 18, 18),
        status: AttendanceStatus.presentLate,
        lateMinutes: 30,
        createdAt: DateTime(2026, 11, 18),
        updatedAt: DateTime(2026, 11, 18));
    final active = AttendanceRecordModel.fromJson(
        {...record.toJson(), 'id': 'active-punch', 'punch_out_time': null});
    expect(active.punchOutTime, isNull);
    backend.tables['attendance'] = [record.toJson(), active.toJson()];
    final before = jsonEncode(backend.tables['attendance']);
    final hours = record.totalHoursWorked;
    await AttendanceService(store.client)
        .saveShiftPolicy(policy(site, start: '11:30', grace: 40));
    expect(jsonEncode(backend.tables['attendance']), before);
    expect(
        AttendanceRecordModel.fromJson(backend.tables['attendance']!.first)
            .totalHoursWorked,
        hours);
    expect(
        store.requests
            .where((r) => r.method != 'GET')
            .every((r) => r.url.path.endsWith('site_shift_policies')),
        isTrue);
  });
  test('Only a new punch uses the revised location grace and timing', () async {
    final service = AttendanceService(store.client);
    await service.saveShiftPolicy(policy(site, start: '10:00', grace: 30));
    final result = await service.punchIn(
        siteId: site,
        siteName: 'Site',
        staffId: 'new-staff',
        staffName: 'Staff',
        staffRole: 'worker',
        date: DateTime(2026, 11, 19),
        punchTime: DateTime(2026, 11, 19, 10, 20),
        latitude: 22.7,
        longitude: 75.8);
    expect(result.status, AttendanceStatus.presentOnTime);
    expect(result.lateMinutes, 0);
  });
}
