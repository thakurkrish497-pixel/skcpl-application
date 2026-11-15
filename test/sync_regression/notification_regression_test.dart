import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/services/notification_service.dart';
import 'package:skcpl_app/services/site_announcement_service.dart';
import 'package:skcpl_app/models/site_announcement_model.dart';
import 'package:skcpl_app/models/site_staff_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/providers/site_announcement_provider.dart';
import 'package:skcpl_app/providers/notification_clock_provider.dart';
import 'package:skcpl_app/providers/birthday_provider.dart';
import 'package:skcpl_app/providers/site_staff_provider.dart';
import 'package:skcpl_app/providers/sla_alert_provider.dart';
import 'package:skcpl_app/providers/auth_provider.dart';
import 'package:skcpl_app/providers/cash_provider.dart';
import 'package:skcpl_app/providers/stock_provider.dart';
import 'package:skcpl_app/providers/site_provider.dart';
import '../test_sla_alerts.dart'
    show AuthNotifierMock, StockNotifierMock, CashNotifierMock;

final time = DateTime(2026, 11, 16, 12);
SiteAnnouncementModel notice(String id,
        {String? site,
        bool active = true,
        AnnouncementCategory category = AnnouncementCategory.general}) =>
    SiteAnnouncementModel(
        id: id,
        title: 'Notice $id',
        message: 'Details',
        targetSiteId: site,
        createdAt: time,
        createdByName: 'Admin',
        createdByRole: 'Admin',
        isActive: active,
        category: category);

class Notices extends SiteAnnouncementService {
  Future<List<SiteAnnouncementModel>> Function()? fetch;
  Future<SiteAnnouncementModel> Function(SiteAnnouncementModel)? save;
  void Function()? changed;
  int stopped = 0;
  @override
  Future<List<SiteAnnouncementModel>> getAnnouncements() async =>
      fetch == null ? [] : await fetch!();
  @override
  Future<SiteAnnouncementModel> createAnnouncement(
          SiteAnnouncementModel model) async =>
      save == null ? model : await save!(model);
  @override
  Future<void> deleteAnnouncement(String id) async {}
  @override
  void Function() watchChanges(void Function() onChange) {
    changed = onChange;
    return () {
      stopped++;
    };
  }
}

UserModel user(UserRole role) => UserModel(
    id: role.name,
    email: '${role.name}@fixture.invalid',
    role: role,
    createdAt: time,
    updatedAt: time);

void main() {
  test(
      'Concurrent notification requests produce one delivery and survive permission denial',
      () async {
    var allowed = false;
    var shown = 0;
    final delivery = NotificationDelivery(
        permission: () async => allowed,
        show: ({required title, required body, tag}) async {
          shown++;
        },
        now: () => time);
    await delivery.send(key: 'same:alert', title: 'title', body: 'body');
    expect(shown, 0);
    allowed = true;
    await Future.wait(List.generate(30,
        (_) => delivery.send(key: 'same:alert', title: 'title', body: 'body')));
    expect(shown, 1);
  });
  test(
      'Failed native delivery remains eligible and does not block later notifications',
      () async {
    var attempts = 0;
    final delivery = NotificationDelivery(
        permission: () async => true,
        show: ({required title, required body, tag}) async {
          if (++attempts == 1) throw StateError('device unavailable');
        });
    await delivery.send(key: 'retry', title: 'title', body: 'body');
    expect(
        (await SharedPreferences.getInstance())
            .getStringList(NotificationDelivery.ledgerKey),
        isNull);
    await delivery.send(key: 'retry', title: 'title', body: 'body');
    expect(attempts, 2);
  });
  test(
      'SLA alerts honor the complete six hour quiet period, including colon-containing keys',
      () async {
    var now = time;
    var shown = 0;
    final delivery = NotificationDelivery(
        permission: () async => true,
        show: ({required title, required body, tag}) async {
          shown++;
        },
        now: () => now);
    Future<void> send() => delivery.send(
        key: 'cash:123',
        title: 'title',
        body: 'body',
        repeatAfter: const Duration(hours: 6));
    await send();
    now = time.add(const Duration(hours: 5, minutes: 59));
    await send();
    expect(shown, 1);
    now = time.add(const Duration(hours: 6));
    await send();
    expect(shown, 2);
  });
  test('More than 100 birthday recipients do not evict today\'s deduplication',
      () async {
    var shown = 0;
    final delivery = NotificationDelivery(
        permission: () async => true,
        show: ({required title, required body, tag}) async {
          shown++;
        },
        now: () => time);
    for (var round = 0; round < 2; round++) {
      await Future.wait(List.generate(
          120,
          (i) => delivery.send(
              key: 'birthday_${i}_2026_11_16',
              title: 'Happy birthday',
              body: 'Wishes')));
    }
    expect(shown, 120);
    await delivery.send(
        key: 'birthday_0_2026_11_17', title: 'Happy birthday', body: 'Wishes');
    expect(shown, 121);
  });
  test('A failing permission check never escapes into dashboard providers',
      () async {
    var shown = false;
    final delivery = NotificationDelivery(
        permission: () async => throw StateError('unsupported'),
        show: ({required title, required body, tag}) async {
          shown = true;
        });
    await delivery.send(key: 'permission', title: 'Title', body: 'Message');
    expect(shown, isFalse);
  });
  test(
      'Audience filters distinguish all-company, own-site and management notices',
      () {
    expect(
        noticeMatchesAudience(notice('global'), management: false, siteId: 'a'),
        isTrue);
    expect(
        noticeMatchesAudience(notice('own', site: 'a'),
            management: false, siteId: 'a'),
        isTrue);
    expect(
        noticeMatchesAudience(notice('other', site: 'b'),
            management: false, siteId: 'a'),
        isFalse);
    expect(noticeMatchesAudience(notice('other', site: 'b'), management: true),
        isTrue);
    expect(
        noticeMatchesAudience(notice('deleted', active: false),
            management: true),
        isFalse);
  });
  test('Server save preserves the selected site and Important urgency',
      () async {
    Map<String, dynamic>? stored;
    final client = SupabaseClient('http://fixture.invalid', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
      stored = jsonDecode(r.body) as Map<String, dynamic>;
      return http.Response('', 201, request: r);
    }));
    addTearDown(client.dispose);
    final saved = await SiteAnnouncementService(client).createAnnouncement(
        notice('id', site: 'site-a', category: AnnouncementCategory.important));
    expect(saved.targetSiteId, 'site-a');
    expect(stored!['target_site_id'], 'site-a');
    expect(SiteAnnouncementModel.fromJson(stored!).category,
        AnnouncementCategory.important);
  });
  test('An authoritative empty server response clears cached notices',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('skcpl_announcements_cache_v2',
        jsonEncode([notice('deleted').toJson()]));
    final client = SupabaseClient('http://fixture.invalid', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async => http.Response('[]', 200,
            request: r, headers: {'content-type': 'application/json'})));
    addTearDown(client.dispose);
    expect(await SiteAnnouncementService(client).getAnnouncements(), isEmpty);
    expect(
        jsonDecode(prefs.getString('skcpl_announcements_cache_v2')!), isEmpty);
  });
  test('Mixed legacy and primary notices are merged and deduplicated',
      () async {
    final primary = notice('primary');
    final legacy = notice('legacy');
    final client = SupabaseClient('http://fixture.invalid', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async => http.Response(
            jsonEncode(r.url.path.endsWith('tasks')
                ? [
                    {'description': jsonEncode(legacy.toJson())},
                    {'description': jsonEncode(primary.toJson())}
                  ]
                : [primary.toJson()]),
            200,
            request: r,
            headers: {'content-type': 'application/json'})));
    addTearDown(client.dispose);
    expect(
        (await SiteAnnouncementService(client).getAnnouncements())
            .map((n) => n.id)
            .toSet(),
        {'primary', 'legacy'});
  });
  test(
      'Notice reads persist per account without clearing another user\'s unread state',
      () async {
    final a = NoticeReadNotifier('admin');
    final b = NoticeReadNotifier('accounts');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await Future<void>.delayed(Duration.zero);
    await Future.wait([
      a.markRead(['one']),
      a.markRead(['two'])
    ]);
    expect(a.state, {'one', 'two'});
    expect(b.state, isEmpty);
    final restored = NoticeReadNotifier('admin');
    addTearDown(restored.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(restored.state, {'one', 'two'});
  });
  test('Late notice load cannot overwrite a successful post', () async {
    final slow = Completer<List<SiteAnnouncementModel>>();
    final service = Notices()..fetch = () => slow.future;
    final n = AnnouncementsNotifier(service, poll: false);
    addTearDown(n.dispose);
    await n.postAnnouncement(notice('new'));
    slow.complete([]);
    await n.loadAnnouncements();
    expect(n.state.valueOrNull!.single.id, 'new');
  });
  test('Failed post preserves the displayed board and prevents worker posting',
      () async {
    final service = Notices()
      ..fetch = (() async => [notice('existing')])
      ..save = (_) async => throw StateError('offline');
    final n = AnnouncementsNotifier(service, poll: false);
    addTearDown(n.dispose);
    await n.loadAnnouncements();
    await expectLater(n.postAnnouncement(notice('new')), throwsStateError);
    expect(n.state.valueOrNull!.single.id, 'existing');
    final worker =
        AnnouncementsNotifier(service, poll: false, canPost: () => false);
    addTearDown(worker.dispose);
    await expectLater(worker.postAnnouncement(notice('no')), throwsStateError);
  });
  test('Disposed notice fetches do not update a dead screen', () async {
    final slow = Completer<List<SiteAnnouncementModel>>();
    final n = AnnouncementsNotifier(Notices()..fetch = () => slow.future,
        poll: false);
    final load = n.loadAnnouncements();
    n.dispose();
    slow.complete([notice('late')]);
    await load;
  });
  test(
      'Notification-only realtime listener refreshes notices and closes on logout',
      () async {
    var loads = 0;
    final service = Notices()
      ..fetch = () async {
        loads++;
        return [];
      };
    final auth = AuthNotifierMock(user(UserRole.admin));
    final c = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => auth),
      siteAnnouncementServiceProvider.overrideWithValue(service)
    ]);
    addTearDown(c.dispose);
    c.read(noticeRealtimeProvider);
    await c.read(announcementsProvider.notifier).loadAnnouncements();
    final previous = loads;
    service.changed!();
    await Future<void>.delayed(Duration.zero);
    expect(loads, greaterThan(previous));
    c.invalidate(noticeRealtimeProvider);
    await c.pump();
    expect(service.stopped, 1);
  });
  test('Birthday detection changes at midnight and excludes inactive staff',
      () async {
    SiteStaffModel staff(String id, int day, {bool active = true}) =>
        SiteStaffModel(
            id: id,
            siteId: 'site',
            name: id,
            pin: '1234',
            role: SiteStaffRole.worker,
            createdAt: time,
            dateOfBirth: DateTime(1990, 11, day),
            isActive: active);
    final c = ProviderContainer(overrides: [
      notificationNowProvider.overrideWithValue(time),
      allStaffProvider.overrideWith((ref) async => [
            staff('today', 16),
            staff('tomorrow', 17),
            staff('inactive', 16, active: false)
          ])
    ]);
    addTearDown(c.dispose);
    await c.read(allStaffProvider.future);
    expect(c.read(todayBirthdayStaffProvider).single.id, 'today');
    c.updateOverrides([
      notificationNowProvider
          .overrideWithValue(time.add(const Duration(days: 1))),
      allStaffProvider.overrideWith((ref) async => [
            staff('today', 16),
            staff('tomorrow', 17),
            staff('inactive', 16, active: false)
          ])
    ]);
    await c.read(allStaffProvider.future);
    expect(c.read(todayBirthdayStaffProvider).single.id, 'tomorrow');
  });
  test('Overdue top-ups show the receipt amount and hide internal tags', () {
    final tx = CashTransactionModel(
        id: 'topup',
        siteId: 'site',
        date: time.subtract(const Duration(hours: 40)),
        createdAt: time.subtract(const Duration(hours: 40)),
        expenseTypeId: 'other',
        amountReceived: 5000,
        expenseAmount: 0,
        cashInHand: 0,
        status: TransactionStatus.pendingAccounts,
        remarks: '[PENDING SUPERVISOR REVIEW] Received from HO');
    final c = ProviderContainer(overrides: [
      notificationNowProvider.overrideWithValue(time),
      authProvider
          .overrideWith((ref) => AuthNotifierMock(user(UserRole.admin))),
      cashProvider.overrideWith((ref) => CashNotifierMock([tx])),
      stockProvider.overrideWith((ref) => StockNotifierMock([])),
      activeSitesProvider.overrideWith((ref) => [])
    ]);
    addTearDown(c.dispose);
    final alert = c.read(slaAlertsProvider).single;
    expect(alert.title, contains('Receipt'));
    expect(alert.message, contains('5000'));
    expect(alert.message, isNot(contains('PENDING SUPERVISOR')));
  });
  test('Approval SLA starts strictly after 36 hours and excludes final records',
      () {
    CashTransactionModel cash(
            String id, Duration age, TransactionStatus status) =>
        CashTransactionModel(
            id: id,
            siteId: 'site',
            date: time.subtract(age),
            createdAt: time.subtract(age),
            expenseTypeId: 'other',
            expenseAmount: 100,
            amountReceived: 0,
            cashInHand: 0,
            status: status);
    final rows = [
      cash('exact', const Duration(hours: 36),
          TransactionStatus.pendingAccounts),
      cash('overdue', const Duration(hours: 36, seconds: 1),
          TransactionStatus.pendingAdmin),
      cash('approved', const Duration(hours: 80), TransactionStatus.approved),
      cash('rejected', const Duration(hours: 80), TransactionStatus.rejected)
    ];
    final c = ProviderContainer(overrides: [
      notificationNowProvider.overrideWithValue(time),
      authProvider
          .overrideWith((ref) => AuthNotifierMock(user(UserRole.admin))),
      cashProvider.overrideWith((ref) => CashNotifierMock(rows)),
      stockProvider.overrideWith((ref) => StockNotifierMock([])),
      activeSitesProvider.overrideWith((ref) => [])
    ]);
    addTearDown(c.dispose);
    expect(
        c.read(slaAlertsProvider).map((a) => a.id), ['cash_pending_overdue']);
  });
}
