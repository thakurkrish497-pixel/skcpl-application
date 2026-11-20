import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/models/site_staff_model.dart';
import 'package:skcpl_app/models/staff_reminder_model.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/providers/site_staff_provider.dart';
import 'package:skcpl_app/providers/staff_reminder_provider.dart';
import 'package:skcpl_app/providers/attendance_provider.dart';
import 'package:skcpl_app/providers/site_report_provider.dart';
import 'package:skcpl_app/widgets/staff_reminder_host.dart';
import 'dashboard_widget_test.dart' show showPage, closePage;
import '../support/erp_test_backend.dart';

String get site =>
    ErpTestBackend.instance.tables['sites']!.first['id'] as String;
SiteStaffModel person(String id) => SiteStaffModel(
    id: id,
    siteId: site,
    name: 'Staff $id',
    pin: 'fixture',
    role: SiteStaffRole.worker,
    modules: const [StaffModule.attendance, StaffModule.report],
    createdAt: DateTime(2025));

class Selected extends ActiveStaffNotifier {
  Selected(SiteStaffModel? staff) {
    state = staff;
  }
  void change(SiteStaffModel? staff) {
    state = staff;
  }
}

class Punch extends StateNotifier<StaffPunchState>
    implements StaffPunchNotifier {
  Punch() : super(const StaffPunchState());
  void busy(bool value) {
    state = StaffPunchState(isLoading: value);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Report extends StateNotifier<ReportSubmissionState>
    implements ReportSubmissionNotifier {
  Report() : super(const ReportSubmissionState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Checks extends StaffReminderService {
  int calls = 0;
  bool due = true;
  bool fail = false;
  Completer<StaffReminderCheck>? pending;
  Checks() : super(Supabase.instance.client);
  @override
  Future<StaffReminderCheck> check(
      String siteId, String staffId, DateTime now) async {
    calls++;
    if (pending != null) return pending!.future;
    if (fail) throw StateError('offline');
    return StaffReminderCheck(
        due
            ? [
                StaffTaskReminder(StaffReminderTask.dsr, staffId, siteId,
                    '2026-11-20', 'Please submit your DSR')
              ]
            : [],
        staffName: 'Staff $staffId');
  }
}

Future<void> settle(WidgetTester t) async {
  await t.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 20)));
  await t.pump(const Duration(milliseconds: 100));
}

List<Override> overrides(Selected staff, Checks service, {Punch? punch}) => [
      activeStaffProvider.overrideWith((ref) => staff),
      staffReminderServiceProvider.overrideWithValue(service),
      staffPunchProvider.overrideWith((ref) => punch ?? Punch()),
      reportSubmissionProvider.overrideWith((ref) => Report())
    ];
void main() {
  for (final size in [
    const Size(320, 740),
    const Size(844, 390),
    const Size(1440, 1000)
  ]) {
    testWidgets(
        'Personal reminder fits ${size.width}px and preserves an unsaved text field',
        (t) async {
      final selected = Selected(person('s1'));
      final checks = Checks()..due = false;
      await showPage(
          t,
          const StaffReminderHost(
              child: Scaffold(body: TextField(key: ValueKey('draft')))),
          UserRole.worker,
          size,
          overrides: overrides(selected, checks));
      await settle(t);
      await t.enterText(
          find.byKey(const ValueKey('draft')), 'Unsaved work progress');
      final c =
          ProviderScope.containerOf(t.element(find.byType(StaffReminderHost)));
      checks.due = true;
      c.invalidate(staffReminderCheckProvider);
      await t.pump();
      await settle(t);
      expect(find.textContaining('Staff s1 • DSR pending'), findsOneWidget);
      expect(find.text('Unsaved work progress'), findsOneWidget);
      expect(t.takeException(), isNull);
      await closePage(t);
    });
  }
  testWidgets(
      'No personal reminder reads for management or without a selected employee',
      (t) async {
    final checks = Checks();
    await showPage(t, const StaffReminderHost(child: Scaffold()),
        UserRole.admin, const Size(390, 844),
        overrides: overrides(Selected(person('s1')), checks));
    expect(checks.calls, 0);
    await closePage(t);
    await showPage(t, const StaffReminderHost(child: Scaffold()),
        UserRole.worker, const Size(390, 844),
        overrides: overrides(Selected(null), checks));
    expect(checks.calls, 0);
    await closePage(t);
  });
  testWidgets(
      'Polling is five-minute, pauses in background and rechecks on resume',
      (t) async {
    final checks = Checks();
    await showPage(t, const StaffReminderHost(child: Scaffold()),
        UserRole.worker, const Size(390, 844),
        overrides: overrides(Selected(person('s1')), checks));
    await settle(t);
    final first = checks.calls;
    await t.pump(const Duration(minutes: 4));
    expect(checks.calls, first);
    await t.pump(const Duration(minutes: 1));
    await settle(t);
    expect(checks.calls, first + 1);
    for (final phase in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused
    ]) {
      t.binding.handleAppLifecycleStateChanged(phase);
    }
    await t.pump();
    await t.pump(const Duration(minutes: 20));
    expect(checks.calls, first + 1);
    for (final phase in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed
    ]) {
      t.binding.handleAppLifecycleStateChanged(phase);
    }
    await t.pump();
    await settle(t);
    expect(checks.calls, first + 2);
    expect(t.takeException(), isNull);
    await closePage(t);
  });
  testWidgets(
      'Old in-flight employee checks are ignored after switching profile',
      (t) async {
    final selected = Selected(person('s1'));
    final checks = Checks()..pending = Completer<StaffReminderCheck>();
    final old = checks.pending!;
    await showPage(t, const StaffReminderHost(child: Scaffold()),
        UserRole.worker, const Size(390, 844),
        overrides: overrides(selected, checks));
    checks.pending = null;
    selected.change(person('s2'));
    await t.pump();
    await settle(t);
    old.complete(StaffReminderCheck([
      StaffTaskReminder(StaffReminderTask.dsr, 's1', site, '2026-11-20', 'old')
    ], staffName: 'Old staff'));
    await t.pump();
    await settle(t);
    expect(find.textContaining('Staff s2 • DSR pending'), findsOneWidget);
    expect(find.textContaining('Old staff'), findsNothing);
    expect(t.takeException(), isNull);
    await closePage(t);
  });
  testWidgets(
      'Data failure stays quiet and a pending save suppresses reminder checks',
      (t) async {
    final checks = Checks()..fail = true;
    final punch = Punch();
    await showPage(
        t,
        const StaffReminderHost(child: Scaffold(body: Text('Entry screen'))),
        UserRole.worker,
        const Size(390, 844),
        overrides: overrides(Selected(person('s1')), checks, punch: punch));
    await settle(t);
    expect(find.textContaining('pending.'), findsNothing);
    expect(find.text('Entry screen'), findsOneWidget);
    final before = checks.calls;
    punch.busy(true);
    await t.pump();
    await settle(t);
    expect(checks.calls, before);
    checks.fail = false;
    punch.busy(false);
    await t.pump();
    await settle(t);
    expect(find.textContaining('DSR pending'), findsOneWidget);
    expect(t.takeException(), isNull);
    await closePage(t);
  });
}
