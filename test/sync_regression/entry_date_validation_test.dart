import 'package:skcpl_app/models/site_staff_model.dart';
import 'package:skcpl_app/models/site_announcement_model.dart';
import 'package:skcpl_app/services/site_staff_service.dart';
import 'package:skcpl_app/services/site_announcement_service.dart';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/models/daily_site_report_model.dart';
import 'package:skcpl_app/providers/cash_provider.dart';
import 'package:skcpl_app/providers/stock_provider.dart';
import 'package:skcpl_app/providers/site_report_provider.dart';
import 'package:skcpl_app/services/cash_service.dart';
import 'package:skcpl_app/services/stock_service.dart';
import 'package:skcpl_app/services/site_report_service.dart';
import 'package:skcpl_app/services/attendance_service.dart';
import 'package:skcpl_app/services/entry_date_policy.dart';
import 'package:skcpl_app/services/offline_service.dart';
import 'package:skcpl_app/services/submission_support.dart';
import '../support/erp_test_backend.dart';

CashTransactionModel cash(DateTime date, {String? id, bool topup = false}) =>
    CashTransactionModel(
      id: id,
      siteId: 'site-a',
      date: date,
      expenseTypeId: 'e72d9d18-2a33-4748-a04f-ddfdc9504a3f',
      expenseAmount: topup ? 0 : 100,
      amountReceived: topup ? 100 : 0,
      cashInHand: 0,
    );
StockTransactionModel stock(DateTime date,
        {String? id, TransactionType type = TransactionType.inbound}) =>
    StockTransactionModel(
      id: id,
      siteId: 'site-a',
      date: date,
      type: type,
      productId: '441097fa-eef6-4df4-a4f6-7b003b302c0b',
      metricUnitId: '00000000-0000-0000-0000-000000000002',
      quantity: 1,
    );

void main() {
  final backend = ErpTestBackend.instance;
  DateTime tomorrow() => EntryDatePolicy.today().add(const Duration(days: 1));
  bool hasWrites() => backend.requests
      .any((r) => ['POST', 'PATCH', 'PUT', 'DELETE'].contains(r.method));
  setUp(() => backend.requests.clear());

  test('India business day rolls over at 18:30 UTC, including year boundary',
      () {
    expect(EntryDatePolicy.today(now: DateTime.utc(2026, 12, 31, 18, 29)),
        DateTime(2026, 12, 31));
    expect(EntryDatePolicy.today(now: DateTime.utc(2026, 12, 31, 18, 30)),
        DateTime(2027, 1, 1));
    expect(
        EntryDatePolicy.today(now: DateTime.parse('2027-01-01T00:00:00+05:30')),
        DateTime(2027, 1, 1));
  });
  test('Calendar validation accepts all of today and history, rejects tomorrow',
      () {
    final now = DateTime.utc(2026, 11, 20, 4);
    EntryDatePolicy.requireNotFuture(DateTime(2026, 11, 20, 23, 59), now: now);
    EntryDatePolicy.requireNotFuture(DateTime(2020, 2, 29), now: now);
    expect(
        () =>
            EntryDatePolicy.requireNotFuture(DateTime(2026, 11, 21), now: now),
        throwsArgumentError);
  });
  test('UTC attendance timestamp uses its India day', () {
    final now = DateTime.utc(2026, 11, 20, 18, 29);
    EntryDatePolicy.requireNotFutureInstant(DateTime.utc(2026, 11, 20, 18, 29),
        now: now);
    expect(
        () => EntryDatePolicy.requireNotFutureInstant(
            DateTime.utc(2026, 11, 20, 18, 30),
            now: now),
        throwsArgumentError);
  });
  test('Manual malformed and normalized-overflow dates are rejected', () {
    for (final date in ['2026-02-30', '2026-13-01', 'not a date', '', null]) {
      expect(() => EntryDatePolicy.requireDateValue(date), throwsArgumentError);
    }
    EntryDatePolicy.requireDateValue('2024-02-29');
    expect(() => EntryDatePolicy.requireDateValue('2999-01-01'),
        throwsArgumentError);
  });
  for (final topup in [false, true]) {
    test(
        'Service blocks future cash ${topup ? "topup" : "expense"} before any write',
        () async {
      await expectLater(
          CashService().submitTransaction(cash(tomorrow(), topup: topup)),
          throwsArgumentError);
      expect(hasWrites(), isFalse);
    });
  }
  for (final type in TransactionType.values) {
    test('Service blocks future stock $type before any write', () async {
      await expectLater(
          StockService().submitTransaction(stock(tomorrow(), type: type)),
          throwsArgumentError);
      expect(hasWrites(), isFalse);
    });
  }
  for (final kind in ['cash', 'stock']) {
    test('New future $kind submission never enters the offline queue',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final before = await OfflineService.getPendingSyncCount();
      final success = kind == 'cash'
          ? await container
              .read(cashProvider.notifier)
              .submitTransaction(cash(tomorrow()))
          : await container
              .read(stockProvider.notifier)
              .submitTransaction(stock(tomorrow()));
      expect(success, isFalse);
      expect(await OfflineService.getPendingSyncCount(), before);
      expect(hasWrites(), isFalse);
    });
    test('Future $kind queued edit preserves original bytes and attachments',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final photo =
          PendingPhoto(bytes: Uint8List.fromList([1, 2, 3]), name: 'bill.jpg');
      final id = kind == 'cash'
          ? (await OfflineService.queueCashTransaction(
                  cash(EntryDatePolicy.today())
                      .copyWith(pendingPhotos: [photo])))
              .id!
          : (await OfflineService.queueStockTransaction(
                  stock(EntryDatePolicy.today())
                      .copyWith(pendingPhotos: [photo])))
              .id!;
      final prefs = await SharedPreferences.getInstance();
      final key = 'offline_${kind}_queue_v1';
      final before = List<String>.of(prefs.getStringList(key)!);
      final success = kind == 'cash'
          ? await container
              .read(cashProvider.notifier)
              .updateTransaction(cash(tomorrow(), id: id))
          : await container
              .read(stockProvider.notifier)
              .updateTransaction(stock(tomorrow(), id: id));
      expect(success, isFalse);
      expect(prefs.getStringList(key), before);
      expect(hasWrites(), isFalse);
    });
    test('Future $kind online edit is rejected without changing source row',
        () async {
      final tx = kind == 'cash'
          ? cash(EntryDatePolicy.today(), id: 'row-a').toJson()
          : stock(EntryDatePolicy.today(), id: 'row-a').toJson();
      backend.tables['${kind}_transactions'] = [tx];
      final snapshot = Map<String, dynamic>.from(tx);
      final future = kind == 'cash'
          ? CashService().updateTransaction('row-a', {'date': '2999-01-01'})
          : StockService().updateTransaction('row-a', {'date': '2999-01-01'});
      await expectLater(future, throwsArgumentError);
      expect(backend.tables['${kind}_transactions']!.single, snapshot);
      expect(hasWrites(), isFalse);
    });
    test(
        'Retry acknowledges an existing historic $kind row without rewriting its date',
        () async {
      const id = 'f9aac0db-bd21-49b2-8dbd-794ebc94ff60';
      final tx = kind == 'cash'
          ? cash(tomorrow(), id: id).toJson()
          : stock(tomorrow(), id: id).toJson();
      backend.tables['${kind}_transactions'] = [tx];
      if (kind == 'cash') {
        expect(
            (await CashService().submitTransaction(cash(tomorrow(), id: id)))
                .date,
            tomorrow());
      } else {
        expect(
            (await StockService().submitTransaction(stock(tomorrow(), id: id)))
                .date,
            tomorrow());
      }
      expect(hasWrites(), isFalse);
    });
  }
  test('Future DSR blocks primary and fallback storage', () async {
    final report = DailySiteReportModel(
        id: 'report-a',
        siteId: 'site-a',
        date: tomorrow(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now());
    await expectLater(
        SiteReportService().saveReport(report), throwsArgumentError);
    expect(backend.requests, isEmpty);
  });
  test('Future DSR fails before uploading attached photos or audio', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saved = await container
        .read(reportSubmissionProvider.notifier)
        .submitDailyReport(
            siteId: 'site-a',
            siteName: 'Site',
            date: tomorrow(),
            submittedBy: 'Worker',
            audioBytes: Uint8List.fromList([1]),
            photoBytesList: [
          Uint8List.fromList([2])
        ]);
    expect(saved, isNull);
    expect(container.read(reportSubmissionProvider).error,
        contains('Future dates'));
    expect(container.read(reportSubmissionProvider).isLoading, isFalse);
    expect(backend.requests, isEmpty);
  });
  test(
      'Future punch-in and punch-out dates cannot reach primary or fallback writes',
      () async {
    final service = AttendanceService();
    await expectLater(
        service.punchIn(
            siteId: 'site-a',
            siteName: 'Site',
            staffId: 'staff-a',
            staffName: 'Staff',
            staffRole: 'worker',
            date: tomorrow(),
            punchTime: DateTime.now()),
        throwsArgumentError);
    await expectLater(
        service.punchOut(
            attendanceId: 'record-a',
            punchOutTime: DateTime.now().add(const Duration(days: 2))),
        throwsArgumentError);
    expect(backend.requests, isEmpty);
  });
  test('Admin manual attendance has no future-date exemption', () async {
    await expectLater(
        AttendanceService().markManualAttendance(
            siteId: 'site-a',
            siteName: 'Site',
            staffId: 'staff-a',
            staffName: 'Staff',
            staffRole: 'worker',
            date: tomorrow(),
            punchInTime: DateTime.now(),
            punchOutTime: DateTime.now(),
            reason: 'Correction',
            adminName: 'Admin'),
        throwsArgumentError);
    expect(backend.requests, isEmpty);
  });
  test('Verified Admin can plan future holidays', () async {
    final result = await AttendanceService().declareHoliday(
        title: 'Planned holiday',
        date: tomorrow(),
        siteIds: ['all'],
        createdBy: 'Admin');
    expect(result.date, tomorrow());
    expect(hasWrites(), isTrue);
  });
  for (final role in ['accounts', 'projecthead']) {
    test('$role cannot use future holiday exemption', () async {
      await Supabase.instance.client.auth.signInWithPassword(
          email: '$role@skcpl.com', password: 'fixture-password');
      backend.requests.clear();
      await expectLater(
          AttendanceService().declareHoliday(
              title: 'Holiday',
              date: tomorrow(),
              siteIds: ['all'],
              createdBy: 'Admin'),
          throwsStateError);
      expect(hasWrites(), isFalse);
    });
  }
  test('Future staff birth dates cannot be saved through create or edit',
      () async {
    final staff = SiteStaffModel(
        id: 'staff-a',
        siteId: 'site-a',
        name: 'Staff',
        role: SiteStaffRole.worker,
        pin: 'fixture',
        createdAt: DateTime.now(),
        dateOfBirth: tomorrow());
    await expectLater(
        SiteStaffService().createStaff(staff), throwsArgumentError);
    await expectLater(
        SiteStaffService().updateStaff(staff), throwsArgumentError);
    expect(backend.requests, isEmpty);
  });
  test('Notice meeting dates have no future planning exception', () async {
    final notice = SiteAnnouncementModel(
        id: 'notice-a',
        title: 'Meeting',
        message: 'Update',
        createdByName: 'Admin',
        createdByRole: 'admin',
        createdAt: DateTime.now(),
        scheduledAt: DateTime.now().add(const Duration(days: 2)));
    await expectLater(SiteAnnouncementService().createAnnouncement(notice),
        throwsArgumentError);
    expect(backend.requests, isEmpty);
  });
  test('Unauthenticated holiday planning cannot bypass Admin verification',
      () async {
    final client = SupabaseClient(
        'http://erp.test.invalid', 'fixture-public-key',
        httpClient: backend.client);
    addTearDown(client.dispose);
    await expectLater(
        AttendanceService(client).declareHoliday(
            title: 'Holiday',
            date: tomorrow(),
            siteIds: ['all'],
            createdBy: 'Admin'),
        throwsStateError);
    expect(hasWrites(), isFalse);
  });
}
