import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/models/attendance_model.dart';
import 'package:skcpl_app/providers/attendance_provider.dart';
import 'package:skcpl_app/providers/shift_policy_sync_provider.dart';
import 'package:skcpl_app/services/attendance_service.dart';
import 'package:skcpl_app/services/shift_policy_resolver.dart';
import 'package:skcpl_app/widgets/inherited_shift_info.dart';

class LocationShifts extends AttendanceService {
  String start = '09:00', end = '18:00';
  int grace = 15;
  final reads = <String>[];
  @override
  Future<SiteShiftPolicyModel> getShiftPolicy(String id) async {
    reads.add(id);
    return SiteShiftPolicyModel(
        siteId: id,
        siteName: id,
        shiftStartTime: start,
        shiftEndTime: end,
        graceMinutes: grace);
  }
}

void main() {
  testWidgets(
      'All staff displays inherit one site update without replacing their unsaved profile fields',
      (t) async {
    final service = LocationShifts();
    await t.pumpWidget(ProviderScope(
        overrides: [attendanceServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(
            home: Scaffold(
                body: Column(children: [
          InheritedShiftInfo(siteId: 'site-a'),
          InheritedShiftInfo(siteId: 'site-a'),
          TextField(key: ValueKey('draft'))
        ])))));
    await t.pump();
    await t.pump();
    expect(find.textContaining('09:00 – 18:00'), findsNWidgets(2));
    await t.enterText(
        find.byKey(const ValueKey('draft')), 'Unsaved profile note');
    final c = ProviderScope.containerOf(
        t.element(find.byType(InheritedShiftInfo).first));
    final observer = ShiftPolicyObserver(Supabase.instance.client,
        refresh: () => c.invalidate(shiftPolicyForSiteProvider),
        foreground: () => true,
        connect: false);
    service.start = '10:30';
    service.end = '19:30';
    service.grace = 25;
    shiftPolicySaved.add('site-a');
    await t.pump();
    await t.pump(const Duration(milliseconds: 151));
    await t.pump();
    expect(find.textContaining('10:30 – 19:30 • Grace 25'), findsNWidgets(2));
    expect(find.text('Unsaved profile note'), findsOneWidget);
    expect(service.reads.length, 2);
    await t.runAsync(observer.dispose);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
  testWidgets(
      'Shift events debounce and stop on background/disposal; fallback poll does not rescan reminders',
      (t) async {
    var active = true, refreshes = 0, reminders = 0;
    final observer = ShiftPolicyObserver(Supabase.instance.client,
        refresh: () => refreshes++,
        refreshReminders: () => reminders++,
        foreground: () => active,
        connect: false);
    for (var i = 0; i < 20; i++) {
      observer.changed();
    }
    await t.pump(const Duration(milliseconds: 149));
    expect(refreshes, 0);
    await t.pump(const Duration(milliseconds: 2));
    expect(refreshes, 1);
    expect(reminders, 1);
    await t.pump(const Duration(minutes: 1));
    await t.pump(const Duration(milliseconds: 151));
    expect(refreshes, 2);
    expect(reminders, 1);
    active = false;
    observer.changed();
    await t.pump(const Duration(minutes: 2));
    expect(refreshes, 2);
    active = true;
    observer.changed();
    await t.runAsync(observer.dispose);
    await t.pump(const Duration(minutes: 2));
    expect(refreshes, 2);
    expect(t.takeException(), isNull);
  });
  test('Only shift-policy task changes are refresh signals', () {
    expect(
        ShiftPolicyObserver.relevantTask({'title': 'SHIFT_POLICY:site-a'}, {}),
        isTrue);
    expect(
        ShiftPolicyObserver.relevantTask({}, {'title': 'SHIFT_POLICY:global'}),
        isTrue);
    expect(
        ShiftPolicyObserver.relevantTask(
            {'title': 'ATTENDANCE:today'}, {'title': 'STAFF:site-a:person'}),
        isFalse);
    expect(ShiftPolicyObserver.relevantTask({'title': 'Cash voucher'}, {}),
        isFalse);
  });
}
