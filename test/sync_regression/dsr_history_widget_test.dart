import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/providers/dsr_history_provider.dart';
import 'package:skcpl_app/screens/site_reports/dsr_history_screen.dart';
import 'package:skcpl_app/screens/accounts/accounts_dashboard.dart';
import 'package:skcpl_app/screens/project_head/project_head_dashboard.dart';
import 'package:skcpl_app/screens/admin/daily_site_reports_screen.dart';
import 'package:skcpl_app/widgets/photo_thumbnail_strip.dart';
import 'dashboard_widget_test.dart' show showPage, closePage;
import 'dsr_history_test.dart' show report, audit;

class Archive extends DsrHistoryService {
  int loads = 0;
  bool fail = false;
  Archive() : super(Supabase.instance.client);
  @override
  Future<DsrHistorySnapshot> load() async {
    loads++;
    if (fail) throw StateError('Fixture unavailable');
    return DsrHistorySnapshot([
      DsrHistoryEntry(report('first', site: 'site-a'), audit('first')['state']),
      DsrHistoryEntry(
          report('older',
              site: 'site-a',
              date: '2020-01-02',
              remarks: '[Project Head: Approved by Vikas]'),
          {}),
      DsrHistoryEntry(
          report('rejected',
              site: 'closed-site',
              remarks: '[Project Head: Rejected - Incomplete by Vikas]'),
          {}),
    ]);
  }
}

Future<void> pulse(WidgetTester tester) async {
  await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  for (final role in [
    UserRole.admin,
    UserRole.projectHead,
    UserRole.accounts
  ]) {
    testWidgets(
        '$role opens complete read-only DSR history, including disabled approval roles',
        (t) async {
      final service = Archive();
      final page = role == UserRole.admin
          ? const DailySiteReportsScreen()
          : role == UserRole.projectHead
              ? const ProjectHeadDashboard()
              : const AccountsDashboard();
      await showPage(t, page, role, const Size(1440, 1000),
          overrides: [dsrHistoryServiceProvider.overrideWithValue(service)]);
      if (role != UserRole.admin) {
        final tabs = t.widgetList<Tab>(find.byType(Tab));
        final tab = tabs.firstWhere((tab) => (tab.text ?? '')
            .startsWith(role == UserRole.projectHead ? 'DSR Reports' : 'DSR'));
        final label = find.text(tab.text!);
        await t.ensureVisible(label);
        await t.pump(const Duration(milliseconds: 500));
        await pulse(t);
        await t.tap(label);
        await t.pump(const Duration(milliseconds: 500));
        await pulse(t);
        await t.tap(find.text('DSR History'));
      } else {
        await t.tap(find.byTooltip('DSR History'));
      }
      await t.pump(const Duration(milliseconds: 500));
      await pulse(t);
      await pulse(t);
      expect(find.byType(DsrHistoryScreen), findsOneWidget);
      expect(find.text('3 report(s)'), findsOneWidget);
      expect(find.textContaining('2020'), findsOneWidget);
      expect(find.textContaining('Rejected'), findsOneWidget);
      expect(t.takeException(), isNull);
      await closePage(t);
    });
  }
  testWidgets(
      'Site and review-status filters include archived sites and retain all source entries',
      (t) async {
    final service = Archive();
    await showPage(
        t, const DsrHistoryScreen(), UserRole.accounts, const Size(1440, 1000),
        overrides: [dsrHistoryServiceProvider.overrideWithValue(service)]);
    await t.tap(find.text('All sites'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('closed-site').last);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('1 report(s)'), findsOneWidget);
    expect(find.textContaining('Rejected'), findsOneWidget);
    await t.tap(find.text('All reports'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Approved').last);
    await t.pump();
    expect(find.text('No DSRs match these filters.'), findsOneWidget);
    expect(service.loads, 1);
    expect((await service.load()).entries.length, 3);
    await closePage(t);
  });
  testWidgets(
      'Inclusive date range selects past report and clearing it restores full history',
      (t) async {
    final service = Archive();
    await showPage(
        t, const DsrHistoryScreen(), UserRole.admin, const Size(1440, 1000),
        overrides: [dsrHistoryServiceProvider.overrideWithValue(service)]);
    await t.tap(find.text('All dates'));
    await t.pump(const Duration(milliseconds: 500));
    await pulse(t);
    await t.tap(find.byTooltip('Switch to input'));
    await t.pump(const Duration(milliseconds: 300));
    final inputs = find.byType(TextField);
    expect(inputs, findsNWidgets(2));
    await t.enterText(inputs.at(0), '01/02/2020');
    await t.enterText(inputs.at(1), '01/02/2020');
    await t.tap(find.text('OK'));
    await t.pump(const Duration(milliseconds: 500));
    await pulse(t);
    expect(find.text('1 report(s)'), findsOneWidget);
    expect(find.textContaining('2020'), findsWidgets);
    await t.tap(find.text('Clear dates'));
    await t.pump();
    expect(find.text('3 report(s)'), findsOneWidget);
    expect(t.takeException(), isNull);
    await closePage(t);
  });
  for (final size in [
    const Size(320, 740),
    const Size(844, 390),
    const Size(1440, 1000)
  ]) {
    testWidgets(
        'History and full detail fit ${size.width}px without mutation controls',
        (t) async {
      final service = Archive();
      await showPage(t, const DsrHistoryScreen(), UserRole.projectHead, size,
          overrides: [dsrHistoryServiceProvider.overrideWithValue(service)]);
      expect(t.takeException(), isNull);
      await t.tap(find.textContaining('site-a • 16 Nov'));
      await t.pump(const Duration(milliseconds: 500));
      await pulse(t);
      expect(find.byType(DsrHistoryDetailsScreen), findsOneWidget);
      expect(find.text('Slab casting complete'), findsOneWidget);
      expect(find.text('Masons: 3; Helpers: 7'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('Measurements checked'), findsOneWidget);
      expect(find.byType(PhotoThumbnailStrip), findsOneWidget);
      expect(find.text('Reviewed at'), findsNWidgets(2));
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(t.takeException(), isNull);
      await closePage(t);
    });
  }
  testWidgets(
      'Legacy approvals explain missing timestamps instead of inventing them',
      (t) async {
    final e = DsrHistoryEntry(
        report('legacy', remarks: '[Project Head: Approved by Vikas]')
          ..remove('created_at')
          ..remove('updated_at'),
        {});
    await showPage(t, DsrHistoryDetailsScreen(entry: e, siteName: 'Old Site'),
        UserRole.accounts, const Size(390, 844));
    expect(find.textContaining('timestamps were not recorded'), findsOneWidget);
    expect(find.text('Not recorded'), findsNWidgets(2));
    expect(find.text('[Project Head: Approved by Vikas]'), findsOneWidget);
    expect(t.takeException(), isNull);
    await closePage(t);
  });
  testWidgets(
      'History load failure is explicit and retry succeeds without changing stored entries',
      (t) async {
    final service = Archive()..fail = true;
    await showPage(
        t, const DsrHistoryScreen(), UserRole.admin, const Size(390, 844),
        overrides: [dsrHistoryServiceProvider.overrideWithValue(service)]);
    expect(find.textContaining('Could not load DSR history'), findsOneWidget);
    service.fail = false;
    await t.tap(find.text('Retry'));
    await t.pump();
    await pulse(t);
    expect(find.text('3 report(s)'), findsOneWidget);
    expect(t.takeException(), isNull);
    await closePage(t);
  });
  testWidgets('Worker cannot open history or a stale management detail view',
      (t) async {
    final service = Archive();
    await showPage(
        t, const DsrHistoryScreen(), UserRole.worker, const Size(390, 844),
        overrides: [dsrHistoryServiceProvider.overrideWithValue(service)]);
    expect(service.loads, 0);
    expect(find.textContaining('Management sign-in'), findsOneWidget);
    await closePage(t);
    await showPage(
        t,
        DsrHistoryDetailsScreen(
            entry: DsrHistoryEntry(report('private'), {}), siteName: 'Private'),
        UserRole.worker,
        const Size(390, 844));
    expect(find.text('Slab casting complete'), findsNothing);
    expect(find.textContaining('Management sign-in'), findsOneWidget);
    await closePage(t);
  });
}
