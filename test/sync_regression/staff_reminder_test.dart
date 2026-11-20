import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/staff_reminder_model.dart';
import 'package:skcpl_app/models/site_staff_model.dart';
import 'package:skcpl_app/models/attendance_model.dart';
import 'package:skcpl_app/models/daily_site_report_model.dart';
import 'package:skcpl_app/services/notification_service.dart';
import 'package:skcpl_app/services/staff_reminder_service.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

final day = DateTime.utc(2026, 11, 20);
SiteStaffModel staff(
        {String id = 's1',
        String site = 'site-a',
        String name = 'Ramesh',
        bool active = true,
        List<StaffModule> modules = const [
          StaffModule.attendance,
          StaffModule.report
        ]}) =>
    SiteStaffModel(
        id: id,
        siteId: site,
        name: name,
        role: SiteStaffRole.worker,
        pin: 'fixture',
        modules: modules,
        isActive: active,
        createdAt: DateTime.utc(2025));
SiteShiftPolicyModel policy({String start = '09:00', String end = '18:00'}) =>
    SiteShiftPolicyModel(
        siteId: 'site-a',
        siteName: 'Site A',
        shiftStartTime: start,
        shiftEndTime: end,
        graceMinutes: 15);
AttendanceRecordModel attendance(
        {String id = 'a',
        String staffId = 's1',
        String site = 'site-a',
        bool punchedIn = false,
        bool punchedOut = false,
        AttendanceStatus status = AttendanceStatus.presentOnTime}) =>
    AttendanceRecordModel(
        id: id,
        siteId: site,
        siteName: 'Site A',
        staffId: staffId,
        staffName: 'Ramesh',
        staffRole: 'Worker',
        date: day,
        punchInTime: punchedIn ? day : null,
        punchOutTime: punchedOut ? day : null,
        status: status,
        createdAt: day,
        updatedAt: day);
DailySiteReportModel dsr(
        {String id = 'd',
        String? marker,
        String name = 'Ramesh (Worker)',
        String site = 'site-a',
        String? rejection}) =>
    DailySiteReportModel(
        id: id,
        siteId: site,
        date: day,
        submittedBy: name,
        remarks:
            '${marker == null ? '' : staffReportRemarks(marker)} ${rejection ?? ''}',
        createdAt: day,
        updatedAt: day);
List<StaffTaskReminder> tasks(
    {SiteStaffModel? employee,
    DateTime? now,
    List<AttendanceRecordModel> records = const [],
    DsrCompletion done = DsrCompletion.missing,
    bool holiday = false}) {
  final n = now ?? DateTime.utc(2026, 11, 20, 14);
  return missingStaffTasks(
      staff: employee ?? staff(),
      shift: StaffShiftWindow.fromPolicy(policy(), n),
      now: n,
      attendance: records,
      dsr: done,
      holiday: holiday);
}

void main() {
  test('India shift deadlines are correct regardless of device timezone', () {
    final before = DateTime.parse('2026-11-20T03:44:59Z');
    expect(tasks(now: before), isEmpty);
    expect(tasks(now: before.add(const Duration(seconds: 1))).single.task,
        StaffReminderTask.punchIn);
    final office = StaffShiftWindow.fromPolicy(
        policy(start: '10:30', end: '19:30'),
        DateTime.parse('2026-11-20T19:00:00+05:30'));
    expect(office.punchInDue, DateTime.parse('2026-11-20T05:15:00Z'));
    expect(office.shiftEnd, DateTime.parse('2026-11-20T14:00:00Z'));
  });
  test('Night shift uses its original work date across midnight', () {
    final night = StaffShiftWindow.fromPolicy(
        policy(start: '22:00', end: '06:00'),
        DateTime.parse('2026-11-21T02:00:00+05:30'));
    expect(reminderDateKey(night.day), '2026-11-20');
    expect(night.shiftEnd, DateTime.parse('2026-11-21T00:30:00Z'));
  });
  test(
      'Only the employee\'s missing tasks are reminded; another staff punch does not count',
      () {
    final result = tasks(records: [
      attendance(staffId: 's2', punchedIn: true, punchedOut: true)
    ]);
    expect(result.map((e) => e.task),
        [StaffReminderTask.punchIn, StaffReminderTask.dsr]);
    expect(
        result.every((r) => r.staffId == 's1' && r.siteId == 'site-a'), isTrue);
  });
  test(
      'Punch-in completion switches to punch-out at shift end, then all reminders stop',
      () {
    expect(
        tasks(
                records: [attendance(punchedIn: true)],
                done: DsrCompletion.complete)
            .single
            .task,
        StaffReminderTask.punchOut);
    expect(
        tasks(
            records: [attendance(punchedIn: true, punchedOut: true)],
            done: DsrCompletion.complete),
        isEmpty);
  });
  test(
      'Inactive staff, unassigned modules and holidays do not receive false reminders',
      () {
    expect(tasks(employee: staff(active: false)), isEmpty);
    expect(
        tasks(
            employee:
                staff(modules: [StaffModule.cashbook, StaffModule.stock])),
        isEmpty);
    expect(tasks(holiday: true), isEmpty);
    expect(tasks(records: [attendance(status: AttendanceStatus.holiday)]),
        isEmpty);
  });
  test(
      'Regularization awaiting review and approved half/full day do not trigger duplicate attendance demands',
      () {
    for (final status in [
      AttendanceStatus.regularizationPending,
      AttendanceStatus.regularizedPresent,
      AttendanceStatus.regularizedHalfDay
    ]) {
      expect(
          tasks(
              records: [attendance(status: status)],
              done: DsrCompletion.complete),
          isEmpty);
    }
  });
  test(
      'Stable DSR staff IDs distinguish identical names and retain existing pending-review tag',
      () {
    final a = staff(), b = staff(id: 's2');
    final report = dsr(marker: 's2');
    expect(staffDsrCompletion(a, [a, b], [report]), DsrCompletion.missing);
    expect(staffDsrCompletion(b, [a, b], [report]), DsrCompletion.complete);
    expect(report.isPendingProjectHeadReview, isTrue);
    expect(staffReportRemarks(null), '[Project Head Review: Pending]');
  });
  test(
      'Unique legacy names are credited, ambiguous legacy names are not accused',
      () {
    final a = staff();
    expect(staffDsrCompletion(a, [a], [dsr()]), DsrCompletion.complete);
    expect(staffDsrCompletion(a, [a, staff(id: 's2')], [dsr()]),
        DsrCompletion.uncertain);
    expect(tasks(done: DsrCompletion.uncertain).map((t) => t.task),
        [StaffReminderTask.punchIn]);
  });
  test(
      'Rejected DSR needs attention but approved or pending submitted DSR satisfies daily submission',
      () {
    final a = staff();
    expect(
        staffDsrCompletion(a, [
          a
        ], [
          dsr(
              marker: 's1',
              rejection: '[Project Head: Rejected - Correct it by Head]')
        ]),
        DsrCompletion.missing);
    expect(staffDsrCompletion(a, [a], [dsr(marker: 's1')]),
        DsrCompletion.complete);
  });
  test('Existing office aliases match, construction sites remain separate', () {
    expect(sameReminderSite('office', '89e1477d-7f66-4b6d-99ca-6270183143e0'),
        isTrue);
    expect(sameReminderSite('site-a', 'site-b'), isFalse);
    final office = staff(site: 'office');
    expect(
        tasks(
            employee: office,
            records: [
              attendance(
                  site: '89e1477d-7f66-4b6d-99ca-6270183143e0',
                  punchedIn: true,
                  punchedOut: true)
            ],
            done: DsrCompletion.complete),
        isEmpty);
  });
  test(
      'Notification suppression survives a staff switch during the permission check',
      () async {
    final permission = Completer<bool>();
    var samePerson = true;
    var shown = 0;
    final delivery = NotificationDelivery(
        permission: () => permission.future,
        show: ({required title, required body, tag}) async {
          shown++;
        });
    final send = delivery.send(
        key: 'daily_task_s1_day',
        title: 'Reminder',
        body: 'Complete attendance',
        stillRelevant: () => samePerson);
    await Future<void>.delayed(Duration.zero);
    samePerson = false;
    permission.complete(true);
    await send;
    expect(shown, 0);
  });
  test(
      'Daily reminders deduplicate per staff/day/task without a global 100-recipient cap',
      () async {
    var shown = 0;
    final delivery = NotificationDelivery(
        permission: () async => true,
        show: ({required title, required body, tag}) async {
          shown++;
        });
    for (var round = 0; round < 2; round++) {
      await Future.wait([
        for (final key in [
          'daily_task_s1_20_punch',
          'daily_task_s2_20_punch',
          'daily_task_s1_20_dsr'
        ])
          delivery.send(key: key, title: 'Reminder', body: 'Due')
      ]);
    }
    expect(shown, 3);
    await delivery.send(
        key: 'daily_task_s1_21_punch', title: 'Reminder', body: 'Due');
    expect(shown, 4);
  });
  test(
      'Service uses the Admin-specific shift (without an id column), GET requests only and skips no-spending checks',
      () async {
    final requests = <http.Request>[];
    final c = SupabaseClient('http://reminders.fixture.invalid', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
      requests.add(r);
      Object payload = [];
      if (r.url.path.endsWith('site_shift_policies')) {
        expect(r.url.queryParameters.containsKey('order'), isFalse);
        payload = [policy(start: '10:30', end: '19:30').toJson()];
      }
      if (r.url.path.endsWith('site_staff')) payload = [staff().toJson()];
      return http.Response(jsonEncode(payload), 200,
          request: r, headers: {'content-type': 'application/json'});
    }));
    addTearDown(c.dispose);
    final result = await StaffReminderService(c)
        .check('site-a', 's1', DateTime.parse('2026-11-20T10:40:00+05:30'));
    expect(result.tasks, isEmpty);
    expect(requests.every((r) => r.method == 'GET'), isTrue);
    expect(
        requests.any((r) =>
            r.url.path.contains('cash_transactions') ||
            r.url.path.contains('stock_transactions')),
        isFalse);
  });
  test(
      'A failed record/shift read is not replaced with guessed default deadlines',
      () async {
    final c = SupabaseClient('http://reminders.fixture.invalid', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async => http.Response(
            '{"code":"42501","message":"denied"}', 403,
            request: r, headers: {'content-type': 'application/json'})));
    addTearDown(c.dispose);
    await expectLater(StaffReminderService(c).check('site-a', 's1', day),
        throwsA(isA<PostgrestException>()));
  });
  test(
      'End-of-shift checks produce only verified missing tasks and use GETs exclusively',
      () async {
    final requests = <http.Request>[];
    final c = SupabaseClient('http://reminders.fixture.invalid', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
      requests.add(r);
      Object payload = [];
      if (r.url.path.endsWith('site_shift_policies')) {
        payload = [policy().toJson()];
      }
      if (r.url.path.endsWith('site_staff')) payload = [staff().toJson()];
      return http.Response(jsonEncode(payload), 200,
          request: r, headers: {'content-type': 'application/json'});
    }));
    addTearDown(c.dispose);
    final result = await StaffReminderService(c)
        .check('site-a', 's1', DateTime.utc(2026, 11, 20, 14));
    expect(result.tasks.map((t) => t.task),
        [StaffReminderTask.punchIn, StaffReminderTask.dsr]);
    expect(
        requests
            .where((r) =>
                r.url.path.endsWith('tasks') &&
                (r.url.queryParameters['title'] ?? '').startsWith('like.DSR:'))
            .single
            .url
            .queryParameters['or'],
        contains('site-a'));
    expect(requests.every((r) => r.method == 'GET'), isTrue);
    expect(
        requests
            .where((r) => r.url.path.endsWith('attendance'))
            .single
            .url
            .queryParameters['staff_id'],
        'eq.s1');
  });
  test(
      'Verified submitted records suppress reminders on another device without modifying them',
      () async {
    final originalAttendance =
        attendance(punchedIn: true, punchedOut: true).toJson();
    final originalDsr = dsr(marker: 's1').toJson();
    final before = jsonEncode([originalAttendance, originalDsr]);
    final c = SupabaseClient('http://reminders.fixture.invalid', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
      Object payload = [];
      if (r.url.path.endsWith('site_shift_policies')) {
        payload = [policy().toJson()];
      }
      if (r.url.path.endsWith('site_staff')) payload = [staff().toJson()];
      if (r.url.path.endsWith('attendance')) payload = [originalAttendance];
      if (r.url.path.endsWith('daily_site_reports')) payload = [originalDsr];
      return http.Response(jsonEncode(payload), 200,
          request: r, headers: {'content-type': 'application/json'});
    }));
    addTearDown(c.dispose);
    expect(
        (await StaffReminderService(c)
                .check('site-a', 's1', DateTime.utc(2026, 11, 20, 14)))
            .tasks,
        isEmpty);
    expect(jsonEncode([originalAttendance, originalDsr]), before);
  });
  test(
      'Office override is honored through the existing office aliases instead of global hours',
      () async {
    const office = '89e1477d-7f66-4b6d-99ca-6270183143e0';
    final c = SupabaseClient('http://reminders.fixture.invalid', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
      Object payload = [];
      if (r.url.path.endsWith('site_shift_policies') &&
          r.url.queryParameters['site_id'] == 'eq.office') {
        payload = [policy(start: '10:30', end: '19:30').toJson()];
      }
      if (r.url.path.endsWith('site_staff')) {
        payload = [staff(site: office).toJson()];
      }
      if (r.url.path.endsWith('attendance')) {
        payload = [attendance(site: 'office', punchedIn: true).toJson()];
      }
      return http.Response(jsonEncode(payload), 200,
          request: r, headers: {'content-type': 'application/json'});
    }));
    addTearDown(c.dispose);
    final result = await StaffReminderService(c)
        .check(office, 's1', DateTime.parse('2026-11-20T19:20:00+05:30'));
    expect(result.tasks, isEmpty);
  });
  test('Declared site holiday prevents attendance/DSR scans and alerts',
      () async {
    var taskScans = 0;
    final c = SupabaseClient('http://reminders.fixture.invalid', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
      Object payload = [];
      if (r.url.path.endsWith('site_shift_policies')) {
        payload = [policy().toJson()];
      }
      if (r.url.path.endsWith('site_staff')) payload = [staff().toJson()];
      if (r.url.path.endsWith('holidays')) {
        payload = [
          {
            'id': 'holiday',
            'date': '2026-11-20',
            'site_ids': ['site-a'],
            'title': 'Holiday',
            'created_at': '2026-01-01'
          }
        ];
      }
      if (r.url.path.endsWith('attendance') ||
          r.url.path.endsWith('daily_site_reports')) {
        taskScans++;
      }
      return http.Response(jsonEncode(payload), 200,
          request: r, headers: {'content-type': 'application/json'});
    }));
    addTearDown(c.dispose);
    expect(
        (await StaffReminderService(c)
                .check('site-a', 's1', DateTime.utc(2026, 11, 20, 14)))
            .tasks,
        isEmpty);
    expect(taskScans, 0);
  });
  test(
      'Unowned or renamed legacy DSRs suppress accusations until attribution is verified',
      () {
    final a = staff();
    expect(staffDsrCompletion(a, [a], [dsr(name: 'Old employee name')]),
        DsrCompletion.uncertain);
    expect(
        staffDsrCompletion(a, [a], [dsr(name: '')]), DsrCompletion.uncertain);
  });
}
