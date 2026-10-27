import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/core/constants/supabase_constants.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/services/excel_service.dart';

void main() {
  test('Verify Dad Excel format and approval-only filtering', () {
    final now = DateTime(2026, 4, 15);

    final cashTxList = [
      // 1. Approved Top-up
      CashTransactionModel(
        id: '1',
        siteId: 'site-1',
        date: now,
        expenseTypeId: 'topup-id',
        amountReceived: 50000,
        expenseAmount: 0,
        cashInHand: 50000,
        remarks: 'Cash Received Indore Office Online [Party: Indore Office]',
        status: TransactionStatus.approved,
      ),
      // 2. Approved Expense with Dropdown Account Head
      CashTransactionModel(
        id: '2',
        siteId: 'site-1',
        date: now.add(const Duration(days: 1)),
        expenseTypeId: 'exp-purchase-id',
        expenseTypeName: 'Purchase',
        amountReceived: 0,
        expenseAmount: 2500,
        cashInHand: 47500,
        remarks: 'mattresses for room 4 no [Party: Bombay Dyeing] [Bill: #1024]',
        status: TransactionStatus.approved,
      ),
      // 3. Approved Expense with Dropdown Account Head
      CashTransactionModel(
        id: '3',
        siteId: 'site-1',
        date: now.add(const Duration(days: 2)),
        expenseTypeId: 'exp-mess-id',
        expenseTypeName: 'Mess Exp',
        amountReceived: 0,
        expenseAmount: 1200,
        cashInHand: 46300,
        remarks: 'kirana samaan [Party: Sharma Store]',
        status: TransactionStatus.approved,
      ),
      // 4. Pending Accounts - MUST NOT appear in Excel
      CashTransactionModel(
        id: '4',
        siteId: 'site-1',
        date: now.add(const Duration(days: 3)),
        expenseTypeId: 'exp-pending-id',
        expenseTypeName: 'Electricity Exp',
        amountReceived: 0,
        expenseAmount: 8000,
        cashInHand: 38300,
        remarks: 'Pending bill',
        status: TransactionStatus.pendingAccounts,
      ),
      // 5. Pending Admin - MUST NOT appear in Excel
      CashTransactionModel(
        id: '5',
        siteId: 'site-1',
        date: now.add(const Duration(days: 4)),
        expenseTypeId: 'exp-admin-id',
        expenseTypeName: 'JCB & Mech Exp',
        amountReceived: 0,
        expenseAmount: 4000,
        cashInHand: 34300,
        remarks: 'JCB hourly work',
        status: TransactionStatus.pendingAdmin,
      ),
      // 6. Rejected - MUST NOT appear in Excel
      CashTransactionModel(
        id: '6',
        siteId: 'site-1',
        date: now.add(const Duration(days: 5)),
        expenseTypeId: 'exp-rej-id',
        expenseTypeName: 'Room Rent',
        amountReceived: 0,
        expenseAmount: 5000,
        cashInHand: 29300,
        remarks: 'Duplicate entry',
        status: TransactionStatus.rejected,
      ),
    ];

    final bytes = ExcelService.generateComprehensiveWorkbookBytes(
      siteName: 'Nissarpur Site',
      cashTransactions: cashTxList,
      stockTransactions: const [],
    );

    expect(bytes.isNotEmpty, true);

    final excel = Excel.decodeBytes(bytes);
    expect(excel.tables.keys.first, 'CASH');
    expect(excel.tables.containsKey('PROJECT SUMMARY'), true);
    expect(excel.tables.containsKey('CASH'), true);

    // ──────────────────────────────────────────────
    // Verify PROJECT SUMMARY (Sheet 1)
    // ──────────────────────────────────────────────
    final summarySheet = excel.tables['PROJECT SUMMARY']!;
    print('PROJECT SUMMARY rows: ${summarySheet.maxRows}');

    // Header row
    final headerRow = summarySheet.rows[0].map((c) => c?.value?.toString()).toList();
    expect(headerRow[0], 'Account Head');
    expect(headerRow[1], 'Amount Received (₹)');
    expect(headerRow[2], 'Expenses Amount (₹)');
    expect(headerRow[3], 'Balance in Hand (₹)');

    // Data rows: Indore Office, Mess Exp, Purchase (pending/rejected heads should NOT appear)
    final headsInSummary = <String>[];
    for (int r = 1; r < summarySheet.maxRows - 1; r++) {
      final head = summarySheet.rows[r][0]?.value?.toString() ?? '';
      headsInSummary.add(head);
      print('Summary Row $r: ${summarySheet.rows[r].map((c) => c?.value?.toString()).join(" | ")}');
    }

    expect(headsInSummary.contains('Indore Office'), true);
    expect(headsInSummary.contains('Mess Exp'), true);
    expect(headsInSummary.contains('Purchase'), true);
    expect(headsInSummary.contains('Electricity Exp'), false); // pendingAccounts
    expect(headsInSummary.contains('JCB & Mech Exp'), false); // pendingAdmin
    expect(headsInSummary.contains('Room Rent'), false); // rejected

    // Grand Total row
    final grandTotalRow = summarySheet.rows.last.map((c) => c?.value?.toString()).toList();
    expect(grandTotalRow[0], 'Grand Total');
    print('Summary Grand Total: ${grandTotalRow.join(" | ")}');

    // ──────────────────────────────────────────────
    // Verify CASH (Sheet 2)
    // ──────────────────────────────────────────────
    final cashSheet = excel.tables['CASH']!;
    print('\nCASH rows: ${cashSheet.maxRows}');

    // Cash Header
    final cashHeader = cashSheet.rows[0].map((c) => c?.value?.toString()).toList();
    expect(cashHeader[0], 'Date');
    expect(cashHeader[1], 'Description of Expenses');
    expect(cashHeader[2], 'Account Head');
    expect(cashHeader[3], 'Amount Received');
    expect(cashHeader[4], 'Expenses Amount');
    expect(cashHeader[5], 'Balance in Hand');

    // Only 3 approved transactions + header + total = 5 rows
    expect(cashSheet.maxRows, 5);

    // Row 1 (Indore Office Top-up)
    final cashRow1 = cashSheet.rows[1].map((c) => c?.value?.toString()).toList();
    print('Cash Row 1: ${cashRow1.join(" | ")}');
    expect(cashRow1[2], 'Indore Office');
    expect(cashRow1[3], '50000');
    expect(cashRow1[4], '0');
    expect(cashRow1[5], 'D2-E2');

    // Row 2 (Purchase)
    final cashRow2 = cashSheet.rows[2].map((c) => c?.value?.toString()).toList();
    print('Cash Row 2: ${cashRow2.join(" | ")}');
    expect(cashRow2[1], contains('mattresses for room 4 no'));
    expect(cashRow2[1], contains('Bombay Dyeing'));
    expect(cashRow2[2], 'Purchase');
    expect(cashRow2[3], '0');
    expect(cashRow2[4], '2500');
    expect(cashRow2[5], 'F2+D3-E3');

    // Row 3 (Mess Exp)
    final cashRow3 = cashSheet.rows[3].map((c) => c?.value?.toString()).toList();
    print('Cash Row 3: ${cashRow3.join(" | ")}');
    expect(cashRow3[1], contains('kirana samaan'));
    expect(cashRow3[1], contains('Sharma Store'));
    expect(cashRow3[2], 'Mess Exp');
    expect(cashRow3[3], '0');
    expect(cashRow3[4], '1200');
    expect(cashRow3[5], 'F3+D4-E4');

    // Row 4 (Grand Total)
    final cashTotalRow = cashSheet.rows[4].map((c) => c?.value?.toString()).toList();
    print('Cash Total Row: ${cashTotalRow.join(" | ")}');
    expect(cashTotalRow[0], 'Total');
    expect(cashTotalRow[1], 'Cumulative Totals');
    expect(cashTotalRow[3], 'SUM(D2:D4)');
    expect(cashTotalRow[4], 'SUM(E2:E4)');
    expect(cashTotalRow[5], 'D5-E5');
  });

  test('Print live cash transactions from Supabase for Nissarpur', () async {
    final client = SupabaseClient(
      SupabaseConstants.supabaseUrl,
      SupabaseConstants.supabaseServiceRoleKey,
    );
    final sites = await client.from('sites').select().eq('name', 'Nissarpur');
    if (sites.isEmpty) {
      print('Nissarpur site not found');
      return;
    }
    final siteId = sites.first['id'] as String;
    print('Nissarpur Site ID: $siteId');

    final cashData = await client
        .from('cash_transactions')
        .select('*, dropdown_items:expense_type_id(value)')
        .eq('site_id', siteId)
        .eq('status', 'approved')
        .order('date', ascending: true);

    try {
      final res = await client.rpc('exec_sql', params: {'sql': 'SELECT 1;'});
      print('exec_sql exists! $res');
    } catch (e) {
      print('exec_sql error: $e');
    }
  });
}
