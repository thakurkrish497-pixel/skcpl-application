import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/models/site_announcement_model.dart';
import 'package:skcpl_app/providers/site_announcement_provider.dart';
import 'package:skcpl_app/providers/notification_clock_provider.dart';
import 'package:skcpl_app/providers/sla_alert_provider.dart';
import 'package:skcpl_app/widgets/notice_board_dialog.dart';
import 'package:skcpl_app/widgets/skcpl_announcement_bar.dart';
import 'package:skcpl_app/widgets/sla_notification_bar.dart';
import 'dashboard_widget_test.dart' show showPage, closePage;
import 'notification_regression_test.dart' show Notices, notice, time;

Future<void> settleReads(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  for (final size in [
    const Size(320, 740),
    const Size(844, 390),
    const Size(1440, 1000)
  ]) {
    testWidgets('Notice board and composer fit ${size.width}px',
        (tester) async {
      final service = Notices()
        ..fetch = () async =>
            [notice('urgent', category: AnnouncementCategory.urgent)];
      await showPage(tester, const NoticeBoardDialog(), UserRole.admin, size,
          overrides: [
            siteAnnouncementServiceProvider.overrideWithValue(service),
            notificationNowProvider.overrideWithValue(time)
          ]);
      await settleReads(tester);
      expect(find.text('Notice urgent'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await closePage(tester);
      await showPage(
          tester,
          Builder(
              builder: (context) => Scaffold(
                  body: Center(
                      child: ElevatedButton(
                          onPressed: () =>
                              NoticeBoardDialog.showCreateDialog(context),
                          child: const Text('Compose'))))),
          UserRole.admin,
          size,
          overrides: [
            siteAnnouncementServiceProvider.overrideWithValue(service),
            notificationNowProvider.overrideWithValue(time)
          ]);
      await tester.tap(find.text('Compose'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Audience'), findsOneWidget);
      expect(find.text('Important Notice'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await closePage(tester);
    });
  }
  testWidgets('Opening the board clears the saved unread indicator',
      (tester) async {
    final service = Notices()..fetch = () async => [notice('new')];
    await showPage(tester, const Scaffold(body: SkcplAnnouncementBar()),
        UserRole.admin, const Size(390, 844),
        overrides: [
          siteAnnouncementServiceProvider.overrideWithValue(service),
          notificationNowProvider.overrideWithValue(time)
        ]);
    await settleReads(tester);
    expect(find.textContaining('1 unread'), findsOneWidget);
    await tester.tap(find.byType(SkcplAnnouncementBar));
    await tester.pump(const Duration(milliseconds: 500));
    await settleReads(tester);
    await settleReads(tester);
    expect(find.byType(NoticeBoardDialog), findsOneWidget);
    final c = ProviderScope.containerOf(
        tester.element(find.byType(NoticeBoardDialog)));
    expect(c.read(unreadNoticeCountProvider), 0);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await closePage(tester);
  });
  testWidgets(
      'A newly arriving alert resurfaces after an older banner was dismissed',
      (tester) async {
    SlaAlert alert(String id) => SlaAlert(
        id: id,
        type: SlaAlertType.pendingCash,
        title: 'Cash overdue',
        message: 'Check cash receipt',
        siteId: 'site',
        siteName: 'Site',
        hoursElapsed: 40,
        createdAt: time);
    final source = StateProvider<List<SlaAlert>>((ref) => [alert('old')]);
    await showPage(tester, const Scaffold(body: SlaNotificationBar()),
        UserRole.admin, const Size(390, 844), overrides: [
      slaAlertsProvider.overrideWith((ref) => ref.watch(source))
    ]);
    expect(find.text('1 ALERT'), findsOneWidget);
    final c = ProviderScope.containerOf(
        tester.element(find.byType(SlaNotificationBar)));
    await tester.tap(find.byTooltip('Dismiss banner'));
    await tester.pump();
    expect(find.text('1 ALERT'), findsNothing);
    c.read(source.notifier).state = [alert('old'), alert('new')];
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('2 ALERTS'), findsOneWidget);
    expect(find.textContaining('+1 more alerts'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await closePage(tester);
  });
  testWidgets('Publishing shows progress and preserves the selected audience',
      (tester) async {
    final pending = Completer<SiteAnnouncementModel>();
    SiteAnnouncementModel? submitted;
    final service = Notices()
      ..save = (model) {
        submitted = model;
        return pending.future;
      };
    await showPage(
        tester,
        Builder(
            builder: (context) => Scaffold(
                body: ElevatedButton(
                    onPressed: () =>
                        NoticeBoardDialog.showCreateDialog(context),
                    child: const Text('Compose')))),
        UserRole.admin,
        const Size(1440, 1000),
        overrides: [
          siteAnnouncementServiceProvider.overrideWithValue(service),
          notificationNowProvider.overrideWithValue(time)
        ]);
    await tester.tap(find.text('Compose'));
    await tester.pump(const Duration(milliseconds: 500));
    await settleReads(tester);
    await tester.tap(find.text('All Staff').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Nissarpur').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Important Notice'));
    await tester.enterText(find.byType(TextFormField).first, 'Safety meeting');
    await tester.enterText(
        find.byType(TextFormField).last, 'Please attend the site briefing.');
    await tester.ensureVisible(find.text('Publish Notice'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Publish Notice'));
    await tester.pump();
    expect(find.text('Broadcasting Notice...'), findsOneWidget);
    expect(submitted!.targetSiteId, isNot('all'));
    expect(submitted!.targetSiteName, 'Nissarpur');
    expect(submitted!.category, AnnouncementCategory.important);
    pending.complete(submitted!.copyWith(id: 'posted'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('📢 Notice Published Successfully!'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await closePage(tester);
  });
}
