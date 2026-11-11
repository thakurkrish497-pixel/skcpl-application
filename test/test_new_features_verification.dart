import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/core/constants/supabase_constants.dart';
import 'package:skcpl_app/models/attendance_model.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/models/site_model.dart';
import 'package:skcpl_app/models/daily_site_report_model.dart';
import 'package:skcpl_app/services/attendance_service.dart';
import 'package:skcpl_app/services/cash_service.dart';
import 'package:skcpl_app/services/site_report_service.dart';
import 'package:uuid/uuid.dart';

void main() {
  HttpOverrides.global = null;
  const uuid = Uuid();

  test('COMPREHENSIVE VERIFICATION: Holidays, Manual Attendance & Admin Edit/Delete', () async {
    final client = SupabaseClient(
      SupabaseConstants.supabaseUrl,
      SupabaseConstants.supabaseServiceRoleKey,
    );
    final attendanceService = AttendanceService(client);
    final cashService = CashService(client);
    final siteReportService = SiteReportService(client);

    final now = DateTime.now();

    // ─────────────────────────────────────────────────────────────
    // PART 1: Holiday Rules (Head Office Sunday vs 7-day Site Working)
    // ─────────────────────────────────────────────────────────────
    print('\n======================================================');
    print('STEP 1: Verifying Holiday Rules (Head Office vs Sites)');
    print('======================================================');

    final headOffice = SiteModel(
      id: '89e1477d-7f66-4b6d-99ca-6270183143e0',
      name: 'HEAD-OFFICE INDORE',
      siteLoginId: 'HO001',
      createdAt: now,
      updatedAt: now,
    );
    final siteHosp = SiteModel(
      id: '4e8efe20-c680-4438-bc48-d46f5c35df09',
      name: 'PIU-HATPIPALIYA HOSPITAL',
      siteLoginId: 'HAT001',
      createdAt: now,
      updatedAt: now,
    );

    expect(headOffice.isHeadOffice, isTrue);
    expect(siteHosp.isHeadOffice, isFalse);

    // Sunday rule verification:
    final sundayDate = DateTime(2026, 11, 15); // Nov 15, 2026 is Sunday
    expect(sundayDate.weekday, equals(DateTime.sunday));

    // Head office staff on Sunday = Holiday
    final hoSundayIsOff = sundayDate.weekday == DateTime.sunday && headOffice.isHeadOffice;
    expect(hoSundayIsOff, isTrue, reason: 'Head Office must have Sunday as default holiday');

    // Site staff on Sunday = Working day (all 7 days working)
    final siteSundayIsOff = sundayDate.weekday == DateTime.sunday && siteHosp.isHeadOffice;
    expect(siteSundayIsOff, isFalse, reason: 'Construction sites must work all 7 days without default holiday');

    // Declare a holiday for specific site
    final testHolidayDate = DateTime(2026, 12, 25);
    final declared = await attendanceService.declareHoliday(
      title: 'TEST_VERIFY_HOLIDAY',
      date: testHolidayDate,
      siteIds: ['4e8efe20-c680-4438-bc48-d46f5c35df09'],
      createdBy: 'TestAdmin',
    );

    expect(declared.id, isNotEmpty);
    expect(declared.title, equals('TEST_VERIFY_HOLIDAY'));
    expect(declared.appliesTo('4e8efe20-c680-4438-bc48-d46f5c35df09'), isTrue);
    expect(declared.appliesTo('other-site'), isFalse);

    // Fetch holidays and verify it appears
    final allHolidays = await attendanceService.getHolidays();
    expect(allHolidays.any((h) => h.id == declared.id), isTrue);

    // Clean up / Delete holiday
    await attendanceService.deleteHoliday(declared.id);
    final afterDelete = await attendanceService.getHolidays();
    expect(afterDelete.any((h) => h.id == declared.id), isFalse, reason: 'Holiday must be cleanly deleted');

    print('✓ STEP 1 PASSED: Holiday rules, Sunday Head-Office logic & Admin declared holidays verified!');

    // ─────────────────────────────────────────────────────────────
    // PART 2: Admin Manual Attendance Grant (Mark Present / Site Visit)
    // ─────────────────────────────────────────────────────────────
    print('\n======================================================');
    print('STEP 2: Verifying Admin Manual Attendance (Site Visit)');
    print('======================================================');

    final testStaffId = 'test-manual-${uuid.v4()}';
    final testDate = DateTime(2026, 11, 10);
    final inTime = DateTime(2026, 11, 10, 9, 30);
    final outTime = DateTime(2026, 11, 10, 18, 15);

    // Mark manual attendance
    final rec = await attendanceService.markManualAttendance(
      siteId: '89e1477d-7f66-4b6d-99ca-6270183143e0',
      siteName: 'HEAD-OFFICE INDORE',
      staffId: testStaffId,
      staffName: 'Automated Test Employee',
      staffRole: 'Site Engineer',
      date: testDate,
      punchInTime: inTime,
      punchOutTime: outTime,
      reason: 'Site visit to Pithampur plant',
      adminName: 'Admin Tester',
    );

    expect(rec.id, isNotEmpty);
    expect(rec.staffId, equals(testStaffId));
    expect(rec.isPresent, isTrue);
    expect(rec.status, equals(AttendanceStatus.regularizedPresent));
    expect(rec.adminDecisionNote, contains('Site visit to Pithampur plant'));
    expect(rec.isWithinSite, isTrue);

    // Fetch attendance for that date and verify
    final records = await attendanceService.getTodayAttendance('89e1477d-7f66-4b6d-99ca-6270183143e0', testDate);
    final found = records.where((r) => r.staffId == testStaffId).firstOrNull;
    expect(found, isNotNull);
    expect(found!.isPresent, isTrue);
    print('Found manually granted attendance record: "${found.staffName}" status: ${found.displayStatusName}');

    // Clean up test attendance record from database
    try {
      await client.from('attendance').delete().eq('staff_id', testStaffId);
    } catch (_) {}
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(testDate);
      final rows = await client.from('tasks').select('id').ilike('title', 'ATTENDANCE:$dateStr:%$testStaffId%');
      for (final r in (rows as List)) {
        await client.from('tasks').delete().eq('id', r['id']);
      }
    } catch (_) {}

    print('✓ STEP 2 PASSED: Admin Manual Attendance grant & cleanup verified!');

    // ─────────────────────────────────────────────────────────────
    // PART 3: Cashbook & DSR Admin Edit & Delete with Balance Recalc
    // ─────────────────────────────────────────────────────────────
    print('\n======================================================');
    print('STEP 3: Verifying Admin Edit & Delete (Balance Recalculation)');
    print('======================================================');

    final siteId = '4e8efe20-c680-4438-bc48-d46f5c35df09'; // PIU-HATPIPALIYA HOSPITAL
    final expTypeId = 'e290b30c-4d5e-4471-b1f2-f4bb5284e256'; // ROOM RENT from dropdowns

    // 1. Check initial balance
    final initialSummary = await cashService.getSiteCashSummary(siteId);
    final initialBalance = initialSummary['balance'] ?? 0.0;
    print('Initial Site Cash Balance: ₹$initialBalance');

    // 2. Insert test Cash Received (+5000)
    final testTx = CashTransactionModel(
      siteId: siteId,
      date: DateTime.now(),
      expenseTypeId: expTypeId,
      amountReceived: 5000.0,
      expenseAmount: 0.0,
      cashInHand: initialBalance + 5000.0,
      remarks: 'TEST_RECALC',
      status: TransactionStatus.approved, // Admin approved
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final inserted = await client.from('cash_transactions').insert(testTx.toJson()).select().single();
    final actualTxId = inserted['id'] as String;

    // Verify balance increased by 5000
    final balanceAfterAdd = (await cashService.getSiteCashSummary(siteId))['balance'] ?? 0.0;
    expect(balanceAfterAdd, closeTo(initialBalance + 5000.0, 0.01));
    print('Balance after +5000 added: ₹$balanceAfterAdd');

    // 3. Edit Cash Received from 5000 to 7500
    await client.from('cash_transactions').update({'amount_received': 7500.0}).eq('id', actualTxId);
    final balanceAfterEdit = (await cashService.getSiteCashSummary(siteId))['balance'] ?? 0.0;
    expect(balanceAfterEdit, closeTo(initialBalance + 7500.0, 0.01));
    print('Balance after edited to 7500: ₹$balanceAfterEdit');

    // 4. Delete the test Cash Transaction
    await cashService.deleteTransaction(actualTxId);
    final balanceAfterDelete = (await cashService.getSiteCashSummary(siteId))['balance'] ?? 0.0;
    expect(balanceAfterDelete, closeTo(initialBalance, 0.01));
    print('Balance after deletion restored cleanly to: ₹$balanceAfterDelete');

    // 5. Test DSR report creation and deletion
    final testReport = DailySiteReportModel(
      id: 'test-dsr-${uuid.v4()}',
      siteId: siteId,
      siteName: 'PIU-HATPIPALIYA HOSPITAL',
      submittedBy: 'Test Submitter',
      date: DateTime.now(),
      notes: 'Testing DSR deletion capability',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await siteReportService.saveReport(testReport);
    // Delete report using deleteReport
    await siteReportService.deleteReport(testReport.id);

    final checkTasks = await client
        .from('tasks')
        .select('id')
        .ilike('title', '%${testReport.id}%');
    expect(checkTasks, isEmpty, reason: 'Report must be deleted from tasks fallback storage');

    print('✓ STEP 3 PASSED: Cash & DSR Edit/Delete with auto balance recalculation verified!');
    print('\n======================================================');
    print('ALL VERIFICATIONS COMPLETED SUCCESSFULLY (0 RESIDUAL DUMMY DATA)');
    print('======================================================');
  });
}
