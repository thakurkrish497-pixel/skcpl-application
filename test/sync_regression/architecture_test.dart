import 'package:skcpl_app/services/site_staff_service.dart';
import 'package:skcpl_app/services/attendance_service.dart';
import 'package:skcpl_app/services/site_announcement_service.dart';
import 'package:skcpl_app/models/site_announcement_model.dart';
import 'package:skcpl_app/services/role_access_service.dart';
import 'package:skcpl_app/providers/role_access_provider.dart';
import 'package:skcpl_app/models/role_permissions_model.dart';
import 'package:geolocator/geolocator.dart';
import 'package:skcpl_app/services/location_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skcpl_app/providers/cash_provider.dart';
import 'package:skcpl_app/models/daily_site_report_model.dart';
import 'package:skcpl_app/services/site_report_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/providers/auth_provider.dart';
import 'package:skcpl_app/services/auth_service.dart';
import 'package:skcpl_app/services/cash_service.dart';
import 'package:skcpl_app/services/stock_service.dart';
import 'package:skcpl_app/services/inventory_math.dart';
import 'package:skcpl_app/services/offline_service.dart';
import 'package:skcpl_app/services/submission_support.dart';
import '../support/erp_test_backend.dart';
import 'sync_safety_test.dart' show FakeCash, FakeStock, cash;

StockTransactionModel stock(
        {String? id,
        TransactionType type = TransactionType.inbound,
        String unit = 'bags',
        double quantity = 10,
        String? material,
        TransactionStatus status = TransactionStatus.approved}) =>
    StockTransactionModel(
        id: id,
        siteId: 'site-a',
        date: DateTime(2026, 11, 14),
        type: type,
        productId: '441097fa-eef6-4df4-a4f6-7b003b302c0b',
        metricUnitId: unit,
        quantity: quantity,
        status: status,
        remarks: material == null ? null : '[Material: $material]');

class DelayedAuth extends AuthService {
  final pending = Completer<UserModel?>();
  DelayedAuth() : super(Supabase.instance.client);
  @override
  Future<UserModel?> getCurrentUserProfile() => pending.future;
  @override
  Future<void> signOut() async {}
}

class DeniedRoleAccess extends RoleAccessService {
  @override
  Future<RolePermissionsModel> getPermissions(
          {bool forceRefresh = false}) async =>
      const RolePermissionsModel();
  @override
  Future<void> savePermissions(RolePermissionsModel model) async =>
      throw StateError('Permission denied');
}

void main() {
  for (final (alias, role) in [
    ('admin', UserRole.admin),
    ('project', UserRole.projectHead),
    ('accounts', UserRole.accounts)
  ]) {
    test('Official $alias alias uses authenticated profile identity', () async {
      final result = await AuthService()
          .signInWithEmail(email: alias, password: 'fixture-password');
      expect(result.role, role);
      await expectLater(
          AuthService().signInWithEmail(email: alias, password: 'wrong'),
          throwsA(isA<AuthException>()));
    });
  }
  test('Late session restoration cannot undo logout', () async {
    final service = DelayedAuth();
    final notifier = AuthNotifier(service);
    addTearDown(notifier.dispose);
    await notifier.signOut();
    service.pending.complete(
        UserModel.fromJson(ErpTestBackend.instance.tables['users']!.first));
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.user, isNull);
    expect(notifier.state.activeSite, isNull);
  });
  test('Stock math separates bag, kg and litre balances', () {
    final balances = calculateStockBalances([
      stock(unit: 'bags'),
      stock(unit: 'kg', quantity: 200),
      stock(unit: 'litres', quantity: 50),
      stock(type: TransactionType.outbound, quantity: 4)
    ]);
    expect(balances.length, 3);
    expect(
        balances
            .firstWhere((r) => r['metric_unit_id'] == 'bags')['current_stock'],
        6);
    expect(
        balances
            .firstWhere((r) => r['metric_unit_id'] == 'kg')['current_stock'],
        200);
  });
  test('Manual materials sharing the placeholder ID never merge', () {
    final balances = calculateStockBalances(
        [stock(material: 'Bricks'), stock(material: 'Diesel')]);
    expect(balances.length, 2);
  });
  test('Existing negative inventory is explicitly flagged', () {
    expect(
        calculateStockBalances([stock(type: TransactionType.outbound)])
            .single['is_negative'],
        true);
  });
  test('NaN, infinity, negative quantities and zero usage are rejected',
      () async {
    for (final number in [double.nan, double.infinity, -1.0, 0.0]) {
      await expectLater(
          StockService().submitTransaction(stock(
              quantity: number, status: TransactionStatus.pendingAccounts)),
          throwsArgumentError);
    }
    expect(parseFiniteNumber('NaN'), isNull);
    expect(parseFiniteNumber('Infinity'), isNull);
    expect(parseFiniteNumber('1.5'), 1.5);
  });
  test('Legacy supervisor marker keeps Accounts review blocked', () {
    expect(
        cash()
            .copyWith(remarks: '[PENDING SUPERVISOR REVIEW]')
            .isPendingSupervisorReview,
        true);
    expect(
        stock(status: TransactionStatus.pendingAccounts)
            .copyWith(remarks: '[PENDING SUPERVISOR REVIEW]')
            .isPendingSupervisorReview,
        true);
  });
  test('A second site can persist a submission while an upload is stalled',
      () async {
    await OfflineService.queueCashTransaction(cash());
    final entered = Completer<void>();
    final release = Completer<void>();
    final service = FakeCash()
      ..onSubmit = (tx) async {
        entered.complete();
        await release.future;
        return tx;
      };
    final sync = OfflineService.syncAllQueued(
        stockService: FakeStock(), cashService: service);
    await entered.future;
    final added = await OfflineService.queueCashTransaction(
            cash().copyWith(siteId: 'site-b'))
        .timeout(const Duration(seconds: 1));
    expect(added.siteId, 'site-b');
    release.complete();
    await sync;
    expect((await OfflineService.getQueuedCashTransactions()).single.siteId,
        'site-b');
  });
  test('Removing a valid entry preserves unrelated corrupt queue data',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('offline_cash_queue_v1', ['broken-json']);
    final queued = await OfflineService.queueCashTransaction(cash());
    await OfflineService.removeQueuedCashTransaction(queued.id!);
    expect(prefs.getStringList('offline_cash_queue_v1'), ['broken-json']);
  });
  test('A UUID cannot overwrite another site pending submission', () async {
    final tx = cash(id: submissionId(null));
    await OfflineService.queueCashTransaction(tx);
    await expectLater(
        OfflineService.queueCashTransaction(tx.copyWith(siteId: 'site-b')),
        throwsStateError);
    expect((await OfflineService.getQueuedCashTransactions()).single.siteId,
        'site-a');
  });
  test(
      'Cash passes Project Head then Accounts then Admin, and final edit is blocked',
      () async {
    final client = Supabase.instance.client;
    final service = CashService(client);
    final created = await service.submitTransaction(cash(id: submissionId(null))
        .copyWith(remarks: '[PENDING SUPERVISOR REVIEW]'));
    await client.auth.signInWithPassword(
        email: 'accounts@skcpl.com', password: 'fixture-password');
    await expectLater(
        service.approveByAccounts(created.id!, ErpTestBackend.accountsId),
        throwsStateError);
    await client.auth.signInWithPassword(
        email: 'projecthead@skcpl.com', password: 'fixture-password');
    await service.updateTransaction(created.id!, {
      'remarks': '[Project Head: Approved by fixture]',
      'status': 'pending_accounts'
    });
    await expectLater(
        service.updateTransaction(created.id!, {'remarks': 'second review'}),
        throwsStateError);
    await client.auth.signInWithPassword(
        email: 'accounts@skcpl.com', password: 'fixture-password');
    await service.approveByAccounts(created.id!, ErpTestBackend.accountsId);
    await client.auth.signInWithPassword(
        email: 'admin@skcpl.com', password: 'fixture-password');
    await service.approveByAdmin(created.id!, ErpTestBackend.adminId);
    await expectLater(
        service.updateTransaction(created.id!, {'expense_amount': 2}),
        throwsStateError);
    final finalRow = await client
        .from('cash_transactions')
        .select()
        .eq('id', created.id!)
        .single();
    expect(finalRow['status'], 'approved');
    expect(finalRow['reviewed_at'], isNotNull);
  });
  test('Final stock approval refuses more than the same-unit approved balance',
      () async {
    final backend = ErpTestBackend.instance;
    backend.tables['stock_transactions'] = [
      {
        ...stock(id: submissionId(null), unit: 'bags', quantity: 10).toJson(),
        'updated_at': '2026-11-14T00:00:00Z'
      },
      {
        ...stock(
                id: 'pending-out',
                unit: 'bags',
                quantity: 11,
                type: TransactionType.outbound,
                status: TransactionStatus.pendingAdmin)
            .toJson(),
        'updated_at': '2026-11-14T00:00:00Z'
      },
    ];
    await expectLater(
        StockService().approveByAdmin('pending-out', ErpTestBackend.adminId),
        throwsStateError);
    expect(
        backend.tables['stock_transactions']!.last['status'], 'pending_admin');
  });
  test('Approved finance summary excludes pending and rejected vouchers',
      () async {
    ErpTestBackend.instance.tables['cash_transactions'] = [
      {
        ...cash(id: 'in')
            .copyWith(
                expenseAmount: 0,
                amountReceived: 1000,
                status: TransactionStatus.approved)
            .toJson(),
        'created_at': DateTime.now().toIso8601String()
      },
      {
        ...cash(id: 'out')
            .copyWith(expenseAmount: 200, status: TransactionStatus.approved)
            .toJson(),
        'created_at': DateTime.now().toIso8601String()
      },
      {
        ...cash(id: 'pending').toJson(),
        'created_at': DateTime.now().toIso8601String()
      },
      {
        ...cash(id: 'rejected')
            .copyWith(status: TransactionStatus.rejected)
            .toJson(),
        'created_at': DateTime.now().toIso8601String()
      },
    ];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
        (await container.read(allSitesFinanceSummaryProvider.future))
            .single['balance'],
        800);
    final activity =
        await container.read(recentTransactionActivityProvider.future);
    expect(activity.cash.last, 4);
    expect(activity.stock.last, 0);
  });
  for (final operation in [
    'staff-site',
    'staff-all',
    'staff-delete',
    'attendance',
    'notice-delete'
  ]) {
    test('Denied $operation operation surfaces failure without fallback',
        () async {
      final paths = <String>[];
      final client = SupabaseClient('http://erp.test.invalid', 'fixture',
          httpClient: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(
            '{"code":"42501","message":"permission denied"}', 403,
            request: request, headers: {'content-type': 'application/json'});
      }));
      final Future<Object?> result;
      switch (operation) {
        case 'staff-site':
          result = SiteStaffService(client).getStaffForSite('site-a');
        case 'staff-all':
          result = SiteStaffService(client).getAllStaff();
        case 'staff-delete':
          result = SiteStaffService(client).deleteStaff('staff-a', 'site-a');
        case 'attendance':
          result = AttendanceService(client)
              .getTodayAttendance('site-a', DateTime.now());
        default:
          result =
              SiteAnnouncementService(client).deleteAnnouncement('notice-a');
      }
      await expectLater(result, throwsA(isA<PostgrestException>()));
      expect(paths, hasLength(1));
      expect(paths.single, isNot(endsWith('/tasks')));
    });
  }

  test('Permission reset reports failed server persistence', () async {
    final notifier = RoleAccessNotifier(DeniedRoleAccess());
    addTearDown(notifier.dispose);
    expect(await notifier.resetToDefaults(), isFalse);
  });
  test('Denied announcement broadcast never falls back or caches success',
      () async {
    final paths = <String>[];
    final client = SupabaseClient('http://erp.test.invalid', 'fixture',
        httpClient: MockClient((request) async {
      paths.add(request.url.path);
      return http.Response(
          '{"code":"42501","message":"permission denied"}', 403,
          request: request, headers: {'content-type': 'application/json'});
    }));
    await expectLater(
        SiteAnnouncementService(client).createAnnouncement(
            SiteAnnouncementModel(
                id: submissionId(null),
                title: 'Safety',
                message: 'Notice',
                createdByName: 'Admin',
                createdByRole: 'Admin',
                createdAt: DateTime.now())),
        throwsA(isA<PostgrestException>()));
    expect(paths, everyElement(endsWith('/site_announcements')));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('skcpl_announcements_cache_v2'), isNull);
  });

  test('A denied DSR write never falls back or reports success', () async {
    final paths = <String>[];
    final client = SupabaseClient('http://erp.test.invalid', 'fixture',
        httpClient: MockClient((request) async {
      paths.add(request.url.path);
      return http.Response(
          '{"code":"42501","message":"permission denied"}', 403,
          request: request, headers: {'content-type': 'application/json'});
    }));
    final report = DailySiteReportModel(
        id: submissionId(null),
        siteId: 'site-a',
        siteName: 'Site A',
        date: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        notes: 'Daily progress');
    await expectLater(SiteReportService(client).saveReport(report),
        throwsA(isA<PostgrestException>()));
    expect(paths, everyElement(endsWith('/daily_site_reports')));
  });

  test(
      'Attendance geofence denies missing, non-finite and invalid site coordinates',
      () {
    for (final latitude in <double?>[null, double.nan, 100]) {
      expect(
          LocationService.isWithinGeofence(
              userLat: 22, userLng: 75, siteLat: latitude, siteLng: 75),
          false);
    }
    expect(
        LocationService.isWithinGeofence(
            userLat: 22,
            userLng: 75,
            siteLat: 22,
            siteLng: 75,
            allowedRadiusMeters: 0),
        false);
  });
  test('Attendance rejects stale, mocked or future GPS fixes', () {
    final now = DateTime.now();
    Position fix(DateTime timestamp, {bool mocked = false}) => Position(
        latitude: 22,
        longitude: 75,
        timestamp: timestamp,
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
        isMocked: mocked);
    expect(
        LocationService.isUsableAttendancePosition(fix(now), now: now), true);
    expect(
        LocationService.isUsableAttendancePosition(
            fix(now.subtract(const Duration(hours: 1))),
            now: now),
        false);
    expect(
        LocationService.isUsableAttendancePosition(fix(now, mocked: true),
            now: now),
        false);
    expect(
        LocationService.isUsableAttendancePosition(
            fix(now.add(const Duration(minutes: 5))),
            now: now),
        false);
  });

  test('A stale supervisor tag cannot reopen the Admin stage for Project Head',
      () {
    expect(
        cash()
            .copyWith(
                status: TransactionStatus.pendingAdmin,
                remarks: '[PENDING SUPERVISOR REVIEW]')
            .isPendingSupervisorReview,
        false);
    expect(
        stock(status: TransactionStatus.pendingAdmin)
            .copyWith(remarks: '[PENDING SUPERVISOR REVIEW]')
            .isPendingSupervisorReview,
        false);
  });
}
