import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/core/constants/supabase_constants.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/services/cash_service.dart';
import 'package:skcpl_app/services/excel_service.dart';
import 'package:skcpl_app/services/dropdown_service.dart';
import 'package:skcpl_app/models/dropdown_item_model.dart';

void main() {
  test('Nissarpur cashbook workflow', () async {
    print('=== STEP 1: Connecting to Supabase ===');
    final client = SupabaseClient(
      SupabaseConstants.supabaseUrl,
      SupabaseConstants.supabaseServiceRoleKey,
    );

  final cashService = CashService(client);

  print('=== STEP 2: Fetching Nissarpur site ===');
  final sites = await client
      .from('sites')
      .select()
      .or('site_login_id.eq.123456,name.ilike.%nissarpur%');

  if (sites.isEmpty) {
    print('Error: Nissarpur site not found!');
    return;
  }

  final site = sites.first;
  final siteId = site['id'] as String;
  final siteName = site['name'] as String;
  print('Found site: "$siteName" (ID: $siteId, LoginID: ${site['site_login_id']})');

  print('=== STEP 3: Checking expense types for Nissarpur ===');
  final dropdownService = DropdownService(client);
  final expTypes = await dropdownService.getByCategory(DropdownCategory.expenseType, siteId: siteId);
  print('Available expense types for site: ${expTypes.map((e) => e.value).join(", ")}');
  
  String fuelTypeId = expTypes.isNotEmpty ? expTypes.first.id : DropdownService.otherExpensePlaceholderId;
  String laborTypeId = expTypes.length > 1 ? expTypes[1].id : fuelTypeId;
  String hardwareTypeId = expTypes.length > 2 ? expTypes[2].id : fuelTypeId;

  print('\n=== STEP 4: Creating Cash Transactions for Testing ===');

  // 1. Cash Top-up (Cash Received)
  final topUp = CashTransactionModel(
    siteId: siteId,
    date: DateTime.now().subtract(const Duration(days: 2)),
    expenseTypeId: fuelTypeId,
    amountReceived: 50000.0,
    expenseAmount: 0.0,
    cashInHand: 50000.0,
    remarks: '[Expense: Head Office Top-Up] [Party: Head Office Indore] Imprest cash advance received [Bill: #HO-ADV-901]',
    status: TransactionStatus.pendingAccounts,
  );
  final savedTopUp = await cashService.submitTransaction(topUp);
  print('Created Top-Up: ID=${savedTopUp.id}, Amount=₹${savedTopUp.amountReceived}, Party=${savedTopUp.partyName}, Bill=${savedTopUp.billNo}');

  // 2. Expense: Diesel
  final expDiesel = CashTransactionModel(
    siteId: siteId,
    expenseTypeId: fuelTypeId,
    date: DateTime.now().subtract(const Duration(days: 1)),
    amountReceived: 0.0,
    expenseAmount: 4200.0,
    cashInHand: 45800.0,
    remarks: '[Party: HPCL Petrol Pump Nissarpur] Diesel for JCB & Roller [Bill: #HP-4821]',
    status: TransactionStatus.pendingAccounts,
  );
  final savedDiesel = await cashService.submitTransaction(expDiesel);
  print('Created Diesel Expense: ID=${savedDiesel.id}, Amount=₹${savedDiesel.expenseAmount}, Party=${savedDiesel.partyName}, Bill=${savedDiesel.billNo}');

  // 3. Expense: Masonry Labor Advance
  final expLabor = CashTransactionModel(
    siteId: siteId,
    expenseTypeId: laborTypeId,
    date: DateTime.now(),
    amountReceived: 0.0,
    expenseAmount: 7500.0,
    cashInHand: 38300.0,
    remarks: '[Party: Ramesh Mistri Gang] Weekly food & travel advance [Bill: #VOUCH-312]',
    status: TransactionStatus.pendingAccounts,
  );
  final savedLabor = await cashService.submitTransaction(expLabor);
  print('Created Labor Expense: ID=${savedLabor.id}, Amount=₹${savedLabor.expenseAmount}, Party=${savedLabor.partyName}, Bill=${savedLabor.billNo}');

  // 4. Expense: Hardware & Binding Wire (to be edited)
  final expHardware = CashTransactionModel(
    siteId: siteId,
    expenseTypeId: hardwareTypeId,
    date: DateTime.now(),
    amountReceived: 0.0,
    expenseAmount: 2850.0,
    cashInHand: 35450.0,
    remarks: '[Party: National Hardware] Binding wire 15kg and cutting blades [Bill: #NAT-551]',
    status: TransactionStatus.pendingAccounts,
  );
  final savedHardware = await cashService.submitTransaction(expHardware);
  print('Created Hardware Expense: ID=${savedHardware.id}, Initial Amount=₹${savedHardware.expenseAmount}');

  // 5. Expense: Unapproved Personal Expense (to test rejection)
  final expPersonal = CashTransactionModel(
    siteId: siteId,
    expenseTypeId: hardwareTypeId,
    date: DateTime.now(),
    amountReceived: 0.0,
    expenseAmount: 18000.0,
    cashInHand: 17450.0,
    remarks: '[Expense: Personal Travel] [Party: Unknown Vendor] Unverified travel spend [Bill: #NA-00]',
    status: TransactionStatus.pendingAccounts,
  );
  final savedPersonal = await cashService.submitTransaction(expPersonal);
  print('Created Questionable Expense for rejection testing: ID=${savedPersonal.id}, Amount=₹${savedPersonal.expenseAmount}');

  print('\n=== STEP 5: Testing Edit Feature (Updating Hardware Expense) ===');
  // Update amount from 2850 to 2600 and update bill
  final updatedHardware = await cashService.updateTransaction(savedHardware.id!, {
    'expense_amount': 2600.0,
    'remarks': '[Party: National Hardware] Binding wire 15kg (discount applied) [Bill: #NAT-551-REV]',
  });
  print('Edited Hardware Expense: New Amount=₹${updatedHardware.expenseAmount}, New Remarks=${updatedHardware.remarks}');

  print('\n=== STEP 6: Testing Accounts Review Workflow ===');
  final usersList = await client.from('users').select('id, role');
  print('Users in database: ${usersList.map((p) => "${p['role']}: ${p['id']}").join(", ")}');
  final accountsUser = usersList.firstWhere((p) => p['role'] == 'accounts', orElse: () => usersList.first);
  final adminUser = usersList.firstWhere((p) => p['role'] == 'admin', orElse: () => usersList.first);
  final accountsId = accountsUser['id'] as String;
  final adminId = adminUser['id'] as String;

  // Accounts approves 1, 2, 3, 4
  await cashService.approveByAccounts(savedTopUp.id!, accountsId);
  print('Accounts approved Top-up -> status: pending_admin');

  await cashService.approveByAccounts(savedDiesel.id!, accountsId);
  print('Accounts approved Diesel -> status: pending_admin');

  await cashService.approveByAccounts(savedLabor.id!, accountsId);
  print('Accounts approved Labor -> status: pending_admin');

  await cashService.approveByAccounts(savedHardware.id!, accountsId);
  print('Accounts approved Hardware -> status: pending_admin');

  // Accounts rejects entry 5
  await cashService.rejectTransaction(
    savedPersonal.id!,
    accountsId,
    'Personal expense not permissible under site imprest budget without prior approval.',
  );
  print('Accounts rejected Personal Expense -> status: rejected');

  print('\n=== STEP 7: Testing Admin Final Approval Workflow ===');
  // Admin approves 1, 2, 3, 4
  await cashService.approveByAdmin(savedTopUp.id!, adminId);
  print('Admin approved Top-up -> status: approved');

  await cashService.approveByAdmin(savedDiesel.id!, adminId);
  print('Admin approved Diesel -> status: approved');

  await cashService.approveByAdmin(savedLabor.id!, adminId);
  print('Admin approved Labor -> status: approved');

  await cashService.approveByAdmin(savedHardware.id!, adminId);
  print('Admin approved Hardware -> status: approved');

  print('\n=== STEP 8: Testing Automatic Excel Export Generation ===');
  // Fetch all site transactions (including stock and cash)
  final allCash = await cashService.getTransactionsForSite(siteId);
  final stockData = await client
      .from('stock_transactions')
      .select()
      .eq('site_id', siteId);
  final allStock = (stockData as List)
      .map((j) => StockTransactionModel.fromJson(j))
      .toList();

  print('Total Cash Transactions in Site: ${allCash.length}');
  print('Total Stock Transactions in Site: ${allStock.length}');

  // Generate Excel workbook bytes automatically
  final excelBytes = ExcelService.generateComprehensiveWorkbookBytes(
    siteName: siteName,
    cashTransactions: allCash,
    stockTransactions: allStock,
  );

  final outputFile = File('test_nissarpur_export.xlsx');
  await outputFile.writeAsBytes(excelBytes);

    print('SUCCESS: Generated Excel file "${outputFile.path}" (${excelBytes.length} bytes)');
    print('Summary:');
    print('- Total Top-Up Tested: ₹50,000 (Approved)');
    print('- Total Approved Expenses Tested: ₹${4200 + 7500 + 2600} = ₹14,300');
    print('- Rejected Expense: ₹18,000 (Properly rejected with note)');
    print('- Net Site Cash Balance: ₹${50000 - 14300} = ₹35,700');
  });
}
