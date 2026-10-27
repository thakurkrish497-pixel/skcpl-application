import 'package:flutter/foundation.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cash_transaction_model.dart';
import '../models/stock_transaction_model.dart';
import '../models/daily_site_report_model.dart';
import '../core/constants/supabase_constants.dart';
import 'file_saver_helper.dart';

/// Comprehensive Excel workbook generator matching SKCPL standards
/// Generates 4 integrated sheets:
/// 1. PROJECT SUMMARY (Financial & Materials executive dashboard)
/// 2. CASH (Exact Imprest Cashbook format with running balance formulas)
/// 3. STOCK REGISTER (Inbound Deliveries and Outbound Consumptions unified chronologically)
/// 4. STOCK BALANCE (Item-wise inventory tally with stock balance formulas)
class ExcelService {
  /// Generates the complete 4-sheet SKCPL workbook
  static Uint8List generateComprehensiveWorkbookBytes({
    required String siteName,
    List<CashTransactionModel> cashTransactions = const [],
    List<StockTransactionModel> stockTransactions = const [],
    DateTime? filterDate,
  }) {
    final excel = Excel.createExcel();

    // Filter transactions if specific date is provided
    var filteredCash = cashTransactions;
    var filteredStock = stockTransactions;
    if (filterDate != null) {
      final dateKey = DateFormat('yyyy-MM-dd').format(filterDate);
      filteredCash = cashTransactions
          .where((c) => DateFormat('yyyy-MM-dd').format(c.date) == dateKey)
          .toList();
      filteredStock = stockTransactions
          .where((s) => DateFormat('yyyy-MM-dd').format(s.date) == dateKey)
          .toList();
    }

    // Filter to ONLY approved transactions (Excel should only sync/export when finally approved by admin)
    final approvedCash = filteredCash
        .where((c) => c.status == TransactionStatus.approved)
        .toList();
    final approvedStock = filteredStock
        .where((s) => s.status == TransactionStatus.approved)
        .toList();

    // Sort cash chronologically ascending (oldest first for running balance)
    final sortedCash = List<CashTransactionModel>.from(approvedCash)
      ..sort((a, b) {
        final cmp = a.date.compareTo(b.date);
        if (cmp != 0) return cmp;
        if (a.createdAt != null && b.createdAt != null) {
          return a.createdAt!.compareTo(b.createdAt!);
        }
        return 0;
      });

    // Sort stock chronologically ascending
    final sortedStock = List<StockTransactionModel>.from(approvedStock)
      ..sort((a, b) {
        final cmp = a.date.compareTo(b.date);
        if (cmp != 0) return cmp;
        if (a.createdAt != null && b.createdAt != null) {
          return a.createdAt!.compareTo(b.createdAt!);
        }
        return 0;
      });

    // Common Cell Styles
    final brandBlueHeaderStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#1E3A8A'), // SKCPL Brand Blue
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final tealHeaderStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#0F766E'), // SKCPL Teal
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final totalStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#E2E8F0'),
    );

    // ─────────────────────────────────────────────────────────────
    final cashSheet = excel['CASH'];
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    cashSheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Description of Expenses'),
      TextCellValue('Account Head'),
      TextCellValue('Amount Received'),
      TextCellValue('Expenses Amount'),
      TextCellValue('Balance in Hand'),
    ]);

    for (int col = 0; col < 6; col++) {
      cashSheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0)).cellStyle = brandBlueHeaderStyle;
    }

    int cashRowIndex = 1;

    for (int i = 0; i < sortedCash.length; i++) {
      final tx = sortedCash[i];
      final rec = tx.amountReceived;
      final exp = tx.expenseAmount;
      final isTopUp = rec > 0 && exp == 0;

      final dateStr = DateFormat('dd-MM-yyyy').format(tx.date);

      // Description formatting: User's narration is front and center
      String desc;
      if (isTopUp) {
        final party = (tx.partyName != null && tx.partyName!.isNotEmpty)
            ? tx.partyName!
            : 'Indore Office';
        final rawDesc = tx.cleanRemarks;
        if (rawDesc != null && rawDesc.isNotEmpty) {
          desc = rawDesc.toLowerCase().contains('cash') || rawDesc.toLowerCase().contains('received')
              ? rawDesc
              : 'Cash Received - $rawDesc';
        } else {
          desc = 'Cash Received $party';
        }
      } else {
        final narration = tx.cleanRemarks ?? tx.displayExpenseTypeName;
        final billClean = (tx.billNo != null && tx.billNo!.isNotEmpty)
            ? tx.billNo!.replaceFirst(RegExp(r'^#+'), '')
            : '';
        final extraDetails = [
          if (tx.partyName != null && tx.partyName!.isNotEmpty) tx.partyName!,
          if (billClean.isNotEmpty) 'Bill: #$billClean',
        ].join(', ');
        desc = extraDetails.isNotEmpty ? '$narration ($extraDetails)' : narration;
      }

      // Account Head (selected from dropdown for expenses, or source for top-ups)
      final head = isTopUp
          ? (tx.customExpenseType ??
              (tx.partyName != null && tx.partyName!.isNotEmpty
                  ? tx.partyName!
                  : 'Indore Office'))
          : tx.displayExpenseTypeName;

      final excelCurrentRow = cashRowIndex + 1;
      final excelPrevRow = cashRowIndex;

      // Formula for running balance: row 2 is =D2-E2; row 3+ is =F2+D3-E3
      final formula = cashRowIndex == 1
          ? 'D$excelCurrentRow-E$excelCurrentRow'
          : 'F$excelPrevRow+D$excelCurrentRow-E$excelCurrentRow';

      cashSheet.appendRow([
        TextCellValue(dateStr),
        TextCellValue(desc),
        TextCellValue(head),
        DoubleCellValue(rec),
        DoubleCellValue(exp),
        FormulaCellValue(formula),
      ]);

      cashRowIndex++;
    }

    if (cashRowIndex == 1) {
      cashSheet.appendRow([
        TextCellValue(DateFormat('dd-MM-yyyy').format(filterDate ?? DateTime.now())),
        TextCellValue('Opening Balance'),
        TextCellValue('Opening Balance'),
        const DoubleCellValue(0.0),
        const DoubleCellValue(0.0),
        const DoubleCellValue(0.0),
      ]);
      cashRowIndex++;
    }

    // Totals row at the bottom of Cash sheet
    final excelLastCashRow = cashRowIndex;
    final excelTotalCashRow = cashRowIndex + 1;

    cashSheet.appendRow([
      TextCellValue('Total'),
      TextCellValue('Cumulative Totals'),
      TextCellValue(''),
      FormulaCellValue('SUM(D2:D$excelLastCashRow)'),
      FormulaCellValue('SUM(E2:E$excelLastCashRow)'),
      FormulaCellValue('D$excelTotalCashRow-E$excelTotalCashRow'),
    ]);

    for (int col = 0; col < 6; col++) {
      cashSheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: cashRowIndex)).cellStyle = totalStyle;
    }

    cashSheet.setColumnWidth(0, 16.0);
    cashSheet.setColumnWidth(1, 45.0);
    cashSheet.setColumnWidth(2, 28.0);
    cashSheet.setColumnWidth(3, 20.0);
    cashSheet.setColumnWidth(4, 20.0);
    cashSheet.setColumnWidth(5, 22.0);

    // ─────────────────────────────────────────────────────────────
    // SHEET 2: PROJECT SUMMARY (Matches Dad's exact clean summary format)
    // ─────────────────────────────────────────────────────────────
    final summarySheet = excel['PROJECT SUMMARY'];

    // Collect totals per Account Head
    final Map<String, _HeadSummary> headSummaries = {};

    for (final tx in sortedCash) {
      final isTopUp = tx.amountReceived > 0 && tx.expenseAmount == 0;
      final head = isTopUp
          ? (tx.customExpenseType ??
              (tx.partyName != null && tx.partyName!.isNotEmpty
                  ? tx.partyName!
                  : 'Indore Office'))
          : tx.displayExpenseTypeName.trim();

      final summary = headSummaries.putIfAbsent(head, () => _HeadSummary());
      summary.received += tx.amountReceived;
      summary.spent += tx.expenseAmount;
    }

    // Sort: Inflow sources with received > 0 first, then expense categories alphabetically
    final sortedHeads = headSummaries.entries.toList()
      ..sort((a, b) {
        if (a.value.received > 0 && b.value.received == 0) return -1;
        if (b.value.received > 0 && a.value.received == 0) return 1;
        return a.key.compareTo(b.key);
      });

    int summaryRowIndex = 0;

    // Header Row matching Dad's Summary
    summarySheet.appendRow([
      TextCellValue('Account Head'),
      TextCellValue('Amount Received (₹)'),
      TextCellValue('Expenses Amount (₹)'),
      TextCellValue('Balance in Hand (₹)'),
    ]);
    for (int col = 0; col < 4; col++) {
      summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: summaryRowIndex)).cellStyle = brandBlueHeaderStyle;
    }
    summaryRowIndex++;

    if (sortedHeads.isNotEmpty) {
      for (final entry in sortedHeads) {
        final excelRow = summaryRowIndex + 1;
        summarySheet.appendRow([
          TextCellValue(entry.key),
          DoubleCellValue(entry.value.received),
          DoubleCellValue(entry.value.spent),
          FormulaCellValue('B$excelRow-C$excelRow'),
        ]);
        summaryRowIndex++;
      }
    } else {
      summarySheet.appendRow([
        TextCellValue('No approved transactions recorded'),
        const DoubleCellValue(0.0),
        const DoubleCellValue(0.0),
        const DoubleCellValue(0.0),
      ]);
      summaryRowIndex++;
    }

    // Grand Total Row matching Dad's Pivot Grand Total
    final excelLastSummaryRow = summaryRowIndex;
    final excelGrandTotalRow = summaryRowIndex + 1;

    summarySheet.appendRow([
      TextCellValue('Grand Total'),
      FormulaCellValue('SUM(B2:B$excelLastSummaryRow)'),
      FormulaCellValue('SUM(C2:C$excelLastSummaryRow)'),
      FormulaCellValue('B$excelGrandTotalRow-C$excelGrandTotalRow'),
    ]);

    for (int col = 0; col < 4; col++) {
      summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: summaryRowIndex)).cellStyle = totalStyle;
    }

    summarySheet.setColumnWidth(0, 32.0);
    summarySheet.setColumnWidth(1, 24.0);
    summarySheet.setColumnWidth(2, 24.0);
    summarySheet.setColumnWidth(3, 24.0);

    // ─────────────────────────────────────────────────────────────
    // SHEET 3: STOCK REGISTER (Unified Stock In & Use Together)
    // ─────────────────────────────────────────────────────────────
    final stockSheet = excel['STOCK REGISTER'];

    stockSheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Movement Type'),
      TextCellValue('Material / Item'),
      TextCellValue('Qty In (Delivered)'),
      TextCellValue('Qty Out (Used)'),
      TextCellValue('Unit'),
      TextCellValue('Vendor / Party Name'),
      TextCellValue('Bill / Challan / Slip No.'),
      TextCellValue('Purpose / Remarks / Location'),
      TextCellValue('Rate (₹)'),
      TextCellValue('Total Value (₹)'),
      TextCellValue('Approval Status'),
    ]);

    for (int col = 0; col < 12; col++) {
      stockSheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0)).cellStyle = tealHeaderStyle;
    }

    int stockRowIndex = 1;

    for (final s in sortedStock) {
      if (s.status == TransactionStatus.rejected) continue;

      final dateStr = DateFormat('dd-MM-yyyy').format(s.date);
      final isInbound = s.type == TransactionType.inbound;
      final movementType = isInbound ? 'DELIVERY (IN)' : 'CONSUMPTION (OUT)';
      final qtyIn = isInbound ? s.quantity : 0.0;
      final qtyOut = !isInbound ? s.quantity : 0.0;
      final unit = s.displayMetricUnitName;
      final party = isInbound
          ? (s.displayVendorName != 'None' ? s.displayVendorName : '-')
          : 'Site Work';
      final billNo = s.billNo ?? '-';
      final remarks = s.cleanRemarks ?? '-';
      final rate = isInbound ? (s.rate ?? 0.0) : 0.0;
      final totalValue = isInbound ? (s.finalAmount ?? 0.0) : 0.0;
      final statusStr = s.status.name.toUpperCase();

      stockSheet.appendRow([
        TextCellValue(dateStr),
        TextCellValue(movementType),
        TextCellValue(s.displayProductName),
        DoubleCellValue(qtyIn),
        DoubleCellValue(qtyOut),
        TextCellValue(unit),
        TextCellValue(party),
        TextCellValue(billNo),
        TextCellValue(remarks),
        DoubleCellValue(rate),
        DoubleCellValue(totalValue),
        TextCellValue(statusStr),
      ]);

      stockRowIndex++;
    }

    if (stockRowIndex == 1) {
      stockSheet.appendRow([
        TextCellValue(DateFormat('dd-MM-yyyy').format(filterDate ?? DateTime.now())),
        TextCellValue('NO TRANSACTIONS'),
        TextCellValue('-'),
        const DoubleCellValue(0.0),
        const DoubleCellValue(0.0),
        TextCellValue('-'),
        TextCellValue('-'),
        TextCellValue('-'),
        TextCellValue('No stock deliveries or consumption recorded'),
        const DoubleCellValue(0.0),
        const DoubleCellValue(0.0),
        TextCellValue('-'),
      ]);
      stockRowIndex++;
    }

    // Totals row for Stock Register
    final excelLastStockRow = stockRowIndex;
    stockSheet.appendRow([
      TextCellValue('Total'),
      TextCellValue('Cumulative Totals'),
      TextCellValue(''),
      FormulaCellValue('SUM(D2:D$excelLastStockRow)'),
      FormulaCellValue('SUM(E2:E$excelLastStockRow)'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      FormulaCellValue('SUM(K2:K$excelLastStockRow)'),
      TextCellValue(''),
    ]);

    for (int col = 0; col < 12; col++) {
      stockSheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: stockRowIndex)).cellStyle = totalStyle;
    }

    stockSheet.setColumnWidth(0, 15.0); // Date
    stockSheet.setColumnWidth(1, 22.0); // Movement Type
    stockSheet.setColumnWidth(2, 28.0); // Material
    stockSheet.setColumnWidth(3, 20.0); // Qty In
    stockSheet.setColumnWidth(4, 20.0); // Qty Out
    stockSheet.setColumnWidth(5, 14.0); // Unit
    stockSheet.setColumnWidth(6, 28.0); // Vendor / Party
    stockSheet.setColumnWidth(7, 24.0); // Bill / Challan
    stockSheet.setColumnWidth(8, 36.0); // Remarks
    stockSheet.setColumnWidth(9, 16.0); // Rate
    stockSheet.setColumnWidth(10, 20.0); // Total Value
    stockSheet.setColumnWidth(11, 18.0); // Status

    // ─────────────────────────────────────────────────────────────
    // SHEET 4: STOCK BALANCE (Item-wise inventory tally)
    // ─────────────────────────────────────────────────────────────
    final balanceSheet = excel['STOCK BALANCE'];

    balanceSheet.appendRow([
      TextCellValue('Material / Item'),
      TextCellValue('Unit'),
      TextCellValue('Total Received (In)'),
      TextCellValue('Total Consumed (Out)'),
      TextCellValue('Balance on Site'),
      TextCellValue('Total Spend (₹)'),
    ]);

    for (int col = 0; col < 6; col++) {
      balanceSheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0)).cellStyle = tealHeaderStyle;
    }

    // Aggregate by material
    final Map<String, _MaterialTally> materialTallies = {};

    for (final s in sortedStock) {
      if (s.status == TransactionStatus.rejected) continue;
      final key = s.displayProductName.trim();
      final tally = materialTallies.putIfAbsent(
        key,
        () => _MaterialTally(unit: s.displayMetricUnitName),
      );

      if (s.type == TransactionType.inbound) {
        tally.totalIn += s.quantity;
        tally.totalCost += (s.finalAmount ?? 0.0);
      } else {
        tally.totalOut += s.quantity;
      }
    }

    final sortedMaterials = materialTallies.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    int balanceRowIndex = 1;

    for (final entry in sortedMaterials) {
      final material = entry.key;
      final tally = entry.value;
      final excelCurrentRow = balanceRowIndex + 1;

      // Balance formula: =C2-D2
      final balanceFormula = 'C$excelCurrentRow-D$excelCurrentRow';

      balanceSheet.appendRow([
        TextCellValue(material),
        TextCellValue(tally.unit),
        DoubleCellValue(tally.totalIn),
        DoubleCellValue(tally.totalOut),
        FormulaCellValue(balanceFormula),
        DoubleCellValue(tally.totalCost),
      ]);

      balanceRowIndex++;
    }

    if (sortedMaterials.isEmpty) {
      balanceSheet.appendRow([
        TextCellValue('No materials tracked'),
        TextCellValue('-'),
        const DoubleCellValue(0.0),
        const DoubleCellValue(0.0),
        const DoubleCellValue(0.0),
        const DoubleCellValue(0.0),
      ]);
      balanceRowIndex++;
    }

    // Totals row for balance sheet
    final excelLastBalanceRow = balanceRowIndex;
    balanceSheet.appendRow([
      TextCellValue('Total'),
      TextCellValue(''),
      FormulaCellValue('SUM(C2:C$excelLastBalanceRow)'),
      FormulaCellValue('SUM(D2:D$excelLastBalanceRow)'),
      FormulaCellValue('SUM(E2:E$excelLastBalanceRow)'),
      FormulaCellValue('SUM(F2:F$excelLastBalanceRow)'),
    ]);

    for (int col = 0; col < 6; col++) {
      balanceSheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: balanceRowIndex)).cellStyle = totalStyle;
    }

    balanceSheet.setColumnWidth(0, 30.0);
    balanceSheet.setColumnWidth(1, 14.0);
    balanceSheet.setColumnWidth(2, 22.0);
    balanceSheet.setColumnWidth(3, 22.0);
    balanceSheet.setColumnWidth(4, 22.0);
    excel.setDefaultSheet('CASH');

    final encoded = excel.encode();
    return Uint8List.fromList(encoded ?? []);
  }

  /// Triggers export and immediately downloads (Web) or opens & shares (Android / iOS)
  static Future<void> exportAndShareComprehensiveExcel({
    required String siteName,
    String? siteId,
    List<CashTransactionModel> cashTransactions = const [],
    List<StockTransactionModel> stockTransactions = const [],
    DateTime? filterDate,
  }) async {
    List<CashTransactionModel> effectiveCash = cashTransactions;
    List<StockTransactionModel> effectiveStock = stockTransactions;

    // If siteId is provided, query fresh live approved data directly from Supabase
    if (siteId != null && siteId.isNotEmpty) {
      try {
        final client = SupabaseClient(
          SupabaseConstants.supabaseUrl,
          SupabaseConstants.supabaseServiceRoleKey,
        );
        final cashData = await client
            .from('cash_transactions')
            .select('*, dropdown_items:expense_type_id(value)')
            .eq('site_id', siteId)
            .eq('status', 'approved')
            .order('date', ascending: true);
        effectiveCash = (cashData as List)
            .map((j) => CashTransactionModel.fromJson(j))
            .toList();

        final stockData = await client
            .from('stock_transactions')
            .select(
                '*, sites(name), product:dropdowns!stock_transactions_product_id_fkey(value), unit:dropdowns!stock_transactions_metric_unit_id_fkey(value), vendor:dropdowns!stock_transactions_vendor_id_fkey(value)')
            .eq('site_id', siteId)
            .eq('status', 'approved')
            .order('date', ascending: true);
        effectiveStock = (stockData as List)
            .map((j) => StockTransactionModel.fromJson(j))
            .toList();
      } catch (e) {
        debugPrint('ExcelService: live Supabase query error ($e), fallback to passed in lists');
      }
    }

    final bytes = generateComprehensiveWorkbookBytes(
      siteName: siteName,
      cashTransactions: effectiveCash,
      stockTransactions: effectiveStock,
      filterDate: filterDate,
    );

    final cleanSiteName = siteName
        .replaceAll(RegExp(r'[^\w\s]+'), '')
        .replaceAll(' ', '_')
        .toUpperCase();
    final dateSuffix = filterDate != null
        ? DateFormat('yyyyMMdd').format(filterDate)
        : DateFormat('yyyyMMdd').format(DateTime.now());
    final fileName = 'SKCPL_${cleanSiteName}_$dateSuffix.xlsx';

    await FileSaverHelper.saveAndOpen(
      bytes: bytes,
      fileName: fileName,
      mimeType: FileSaverHelper.excelMimeType,
      shareTitle: 'SKCPL Site Report — $siteName ($fileName)',
    );
  }

  /// Backward-compatible alias for cashbook-only invocations
  static Future<void> exportAndShareImprestExcel({
    required String siteName,
    String? siteId,
    required List<CashTransactionModel> cashTransactions,
    List<StockTransactionModel> stockTransactions = const [],
    DateTime? filterDate,
  }) =>
      exportAndShareComprehensiveExcel(
        siteName: siteName,
        siteId: siteId,
        cashTransactions: cashTransactions,
        stockTransactions: stockTransactions,
        filterDate: filterDate,
      );

  /// Backward-compatible alias for bytes generator
  static Uint8List generateImprestWorkbookBytes({
    required String siteName,
    required List<CashTransactionModel> cashTransactions,
    DateTime? filterDate,
  }) =>
      generateComprehensiveWorkbookBytes(
        siteName: siteName,
        cashTransactions: cashTransactions,
        stockTransactions: const [],
        filterDate: filterDate,
      );

  /// Generates clean Daily Work Report Excel workbook
  static Uint8List generateDailyWorkReportsWorkbookBytes({
    required String siteName,
    required List<DailySiteReportModel> reports,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final excel = Excel.createExcel();

    // ── Sheet 1: DAILY WORK REPORT ──
    const reportSheetName = 'DAILY WORK REPORT';
    excel.rename('Sheet1', reportSheetName);
    final sheet = excel[reportSheetName];

    // Title banner
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
        TextCellValue('SKCPL — DAILY SITE REPORTS');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
        TextCellValue('Site: $siteName | Generated: ${DateFormat('dd-MMM-yyyy').format(DateTime.now())}');

    // Headers (Col A to E)
    final headers = [
      'Date & Time',
      'Submitted By',
      'Work Report (Voice-to-Text)',
      'Photos Attached',
      'Audio Link (Optional)',
    ];

    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 3));
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#1E293B'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    // Sort reports chronologically ascending by submission time
    final sortedReports = List<DailySiteReportModel>.from(reports)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    int rowIdx = 4;
    for (final report in sortedReports) {
      final dateStr = '${DateFormat('dd-MM-yyyy').format(report.date)} (${DateFormat('hh:mm a').format(report.createdAt)})';
      final notesStr = (report.notes != null && report.notes!.trim().isNotEmpty)
          ? report.notes!.trim()
          : (report.audioUrl != null ? 'Voice note recorded on site' : 'Daily report');

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx)).value =
          TextCellValue(dateStr);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx)).value =
          TextCellValue(report.submittedBy ?? 'Site Team');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx)).value =
          TextCellValue(notesStr);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx)).value =
          TextCellValue(report.photoUrls.isNotEmpty ? '${report.photoUrls.length} photos' : 'None');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx)).value =
          TextCellValue(report.audioUrl ?? '-');

      rowIdx++;
    }

    // Set column widths
    sheet.setColumnWidth(0, 16.0);
    sheet.setColumnWidth(1, 18.0);
    sheet.setColumnWidth(2, 50.0);
    sheet.setColumnWidth(3, 18.0);
    sheet.setColumnWidth(4, 40.0);

    excel.setDefaultSheet(reportSheetName);
    final encoded = excel.save();
    return Uint8List.fromList(encoded ?? []);
  }

  /// Exports and shares the Daily Work Reports Excel workbook
  static Future<void> exportDailyWorkReportsExcel({
    required String siteName,
    required List<DailySiteReportModel> reports,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final bytes = generateDailyWorkReportsWorkbookBytes(
      siteName: siteName,
      reports: reports,
      startDate: startDate,
      endDate: endDate,
    );

    final cleanSiteName = siteName
        .replaceAll(RegExp(r'[^\w\s]+'), '')
        .replaceAll(' ', '_')
        .toUpperCase();
    final dateSuffix = DateFormat('yyyyMMdd').format(DateTime.now());
    final fileName = 'SKCPL_DSR_${cleanSiteName}_$dateSuffix.xlsx';

    await FileSaverHelper.saveAndOpen(
      bytes: bytes,
      fileName: fileName,
      mimeType: FileSaverHelper.excelMimeType,
      shareTitle: 'SKCPL Daily Work Report — $siteName ($fileName)',
    );
  }
}

class _MaterialTally {
  final String unit;
  double totalIn = 0.0;
  double totalOut = 0.0;
  double totalCost = 0.0;

  _MaterialTally({
    required this.unit,
  });
}

class _HeadSummary {
  double received = 0.0;
  double spent = 0.0;
}

