import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import '../models/attendance_model.dart';
import 'file_saver_helper.dart';

/// Generates professional payroll-ready monthly attendance register and GPS audit logs
class AttendanceExcelService {
  /// Generates the Excel workbook bytes for monthly attendance
  static Uint8List generateMonthlyAttendanceWorkbookBytes({
    required String title,
    required DateTime month,
    required List<AttendanceRecordModel> records,
    String? siteFilterName,
  }) {
    final excel = Excel.createExcel();

    // ── Sheet 1: MONTHLY REGISTER ──
    const registerSheetName = 'MONTHLY ATTENDANCE REGISTER';
    excel.rename('Sheet1', registerSheetName);
    final sheet = excel[registerSheetName];

    final monthStr = DateFormat('MMMM yyyy').format(month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    // Title banner
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
        TextCellValue('SKCPL — STAFF ATTENDANCE REGISTER');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
        TextCellValue('Month: $monthStr | Filter: ${siteFilterName ?? "All Sites & Indore Office"} | Generated: ${DateFormat('dd-MMM-yyyy').format(DateTime.now())}');

    // Headers
    final baseHeaders = [
      'Emp Name',
      'Role',
      'Site / Location',
    ];

    // Day headers 1..N
    final dayHeaders = List.generate(daysInMonth, (i) => '${i + 1}');

    final summaryHeaders = [
      'Present (P)',
      'Late (L)',
      'Half Day (HD)',
      'Absent (A)',
      'Total Hrs',
    ];

    final allHeaders = [...baseHeaders, ...dayHeaders, ...summaryHeaders];

    for (int col = 0; col < allHeaders.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 3));
      cell.value = TextCellValue(allHeaders[col]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#1E293B'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    // Group records by staff ID
    final Map<String, List<AttendanceRecordModel>> staffMap = {};
    for (final rec in records) {
      staffMap.putIfAbsent(rec.staffId, () => []).add(rec);
    }

    int rowIdx = 4;
    for (final entry in staffMap.entries) {
      final staffRecords = entry.value;
      final firstRec = staffRecords.first;

      final empName = firstRec.staffName;
      final role = firstRec.staffRole.toUpperCase();
      final siteName = firstRec.siteName;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx)).value =
          TextCellValue(empName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx)).value =
          TextCellValue(role);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx)).value =
          TextCellValue(siteName);

      int pCount = 0;
      int lCount = 0;
      int hdCount = 0;
      int aCount = 0;
      double totalHours = 0.0;

      // Populate each day
      for (int d = 1; d <= daysInMonth; d++) {
        final colIndex = 3 + (d - 1);
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIndex, rowIndex: rowIdx));

        // Find record for this day
        final dayRecord = staffRecords.where((r) => r.date.day == d).firstOrNull;

        if (dayRecord == null) {
          // No record for this day
          final targetDate = DateTime(month.year, month.month, d);
          if (targetDate.isAfter(DateTime.now())) {
            cell.value = TextCellValue('-'); // Future date
          } else if (targetDate.weekday == DateTime.sunday) {
            cell.value = TextCellValue('WO'); // Week Off
            cell.cellStyle = CellStyle(
              fontColorHex: ExcelColor.fromHexString('#64748B'),
              horizontalAlign: HorizontalAlign.Center,
            );
          } else {
            cell.value = TextCellValue('A');
            aCount++;
            cell.cellStyle = CellStyle(
              bold: true,
              fontColorHex: ExcelColor.fromHexString('#EF4444'),
              horizontalAlign: HorizontalAlign.Center,
            );
          }
        } else {
          // Status code
          String code = 'P';
          String colorHex = '#10B981';

          if (dayRecord.status == AttendanceStatus.presentOnTime) {
            code = 'P';
            pCount++;
            colorHex = '#10B981';
          } else if (dayRecord.status == AttendanceStatus.presentLate) {
            code = 'L';
            lCount++;
            colorHex = '#F59E0B';
          } else if (dayRecord.status == AttendanceStatus.regularizedPresent) {
            code = 'P(R)';
            pCount++;
            colorHex = '#06B6D4';
          } else if (dayRecord.status == AttendanceStatus.regularizedHalfDay) {
            code = 'HD';
            hdCount++;
            colorHex = '#F97316';
          } else if (dayRecord.status == AttendanceStatus.absentLateLockout ||
              dayRecord.status == AttendanceStatus.rejected ||
              dayRecord.status == AttendanceStatus.absent) {
            code = 'A';
            aCount++;
            colorHex = '#EF4444';
          } else if (dayRecord.status == AttendanceStatus.regularizationPending) {
            code = 'REQ';
            colorHex = '#8B5CF6';
          }

          cell.value = TextCellValue(code);
          cell.cellStyle = CellStyle(
            bold: true,
            fontColorHex: ExcelColor.fromHexString(colorHex),
            horizontalAlign: HorizontalAlign.Center,
          );

          if (dayRecord.totalHoursWorked != null) {
            totalHours += dayRecord.totalHoursWorked!;
          } else if (dayRecord.punchInTime != null) {
            totalHours += 8.0; // standard estimated
          }
        }
      }

      // Summary columns
      final summaryStart = 3 + daysInMonth;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: summaryStart, rowIndex: rowIdx)).value =
          IntCellValue(pCount);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: summaryStart + 1, rowIndex: rowIdx)).value =
          IntCellValue(lCount);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: summaryStart + 2, rowIndex: rowIdx)).value =
          IntCellValue(hdCount);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: summaryStart + 3, rowIndex: rowIdx)).value =
          IntCellValue(aCount);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: summaryStart + 4, rowIndex: rowIdx)).value =
          DoubleCellValue(double.parse(totalHours.toStringAsFixed(1)));

      rowIdx++;
    }

    // Auto width adjustments
    sheet.setColumnWidth(0, 20.0);
    sheet.setColumnWidth(1, 14.0);
    sheet.setColumnWidth(2, 22.0);
    for (int d = 0; d < daysInMonth; d++) {
      sheet.setColumnWidth(3 + d, 6.0);
    }
    for (int s = 0; s < 5; s++) {
      sheet.setColumnWidth(3 + daysInMonth + s, 12.0);
    }

    // ── Sheet 2: DAILY LOGS & GPS AUDIT ──
    const logSheetName = 'DAILY LOGS & GPS AUDIT';
    final logSheet = excel[logSheetName];

    final logHeaders = [
      'Date',
      'Employee Name',
      'Role',
      'Site / Branch',
      'Status',
      'Punch In Time',
      'Punch Out Time',
      'Hours Worked',
      'Late (Mins)',
      'GPS Location',
      'Geofence Status',
      'Regularization Note',
      'Admin Reviewer',
    ];

    for (int col = 0; col < logHeaders.length; col++) {
      final cell = logSheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(logHeaders[col]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#1E293B'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    // Sort chronologically ascending
    final sortedRecords = List<AttendanceRecordModel>.from(records)
      ..sort((a, b) => a.date.compareTo(b.date));

    int logRow = 1;
    for (final rec in sortedRecords) {
      final dateStr = DateFormat('dd-MM-yyyy').format(rec.date);
      final inTimeStr = rec.punchInTime != null ? DateFormat('hh:mm a').format(rec.punchInTime!) : '-';
      final outTimeStr = rec.punchOutTime != null ? DateFormat('hh:mm a').format(rec.punchOutTime!) : '-';
      final gpsStr = rec.punchInLatitude != null && rec.punchInLongitude != null
          ? '${rec.punchInLatitude!.toStringAsFixed(4)}, ${rec.punchInLongitude!.toStringAsFixed(4)}'
          : 'No GPS';
      final geofenceStr = rec.isWithinSite
          ? 'On-Site'
          : (rec.distanceMeters != null ? 'Off-Site (${rec.distanceMeters!.round()}m away)' : 'Off-Site');

      logSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: logRow)).value =
          TextCellValue(dateStr);
      logSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: logRow)).value =
          TextCellValue(rec.staffName);
      logSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: logRow)).value =
          TextCellValue(rec.staffRole.toUpperCase());
      logSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: logRow)).value =
          TextCellValue(rec.siteName);
      logSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: logRow)).value =
          TextCellValue(rec.status.displayName);
      logSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: logRow)).value =
          TextCellValue(inTimeStr);
      logSheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: logRow)).value =
          TextCellValue(outTimeStr);
      logSheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: logRow)).value =
          TextCellValue(rec.totalHoursWorked != null ? '${rec.totalHoursWorked!.toStringAsFixed(1)} hrs' : '-');
      logSheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: logRow)).value =
          IntCellValue(rec.lateMinutes);
      logSheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: logRow)).value =
          TextCellValue(gpsStr);
      logSheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: logRow)).value =
          TextCellValue(geofenceStr);
      logSheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: logRow)).value =
          TextCellValue(rec.regularizationReason ?? '-');
      logSheet.cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: logRow)).value =
          TextCellValue(rec.reviewedBy != null ? '${rec.reviewedBy} (${rec.adminDecisionNote ?? "OK"})' : '-');

      logRow++;
    }

    logSheet.setColumnWidth(0, 14.0);
    logSheet.setColumnWidth(1, 20.0);
    logSheet.setColumnWidth(2, 14.0);
    logSheet.setColumnWidth(3, 20.0);
    logSheet.setColumnWidth(4, 18.0);
    logSheet.setColumnWidth(5, 14.0);
    logSheet.setColumnWidth(6, 14.0);
    logSheet.setColumnWidth(7, 14.0);
    logSheet.setColumnWidth(8, 12.0);
    logSheet.setColumnWidth(9, 22.0);
    logSheet.setColumnWidth(10, 18.0);
    logSheet.setColumnWidth(11, 28.0);
    logSheet.setColumnWidth(12, 22.0);

    excel.setDefaultSheet(registerSheetName);
    final encoded = excel.save();
    return Uint8List.fromList(encoded ?? []);
  }

  /// Exports and triggers file save / download of the Monthly Attendance Register
  static Future<void> exportMonthlyAttendanceExcel({
    required String title,
    required DateTime month,
    required List<AttendanceRecordModel> records,
    String? siteFilterName,
  }) async {
    final bytes = generateMonthlyAttendanceWorkbookBytes(
      title: title,
      month: month,
      records: records,
      siteFilterName: siteFilterName,
    );

    final cleanName = (siteFilterName ?? 'All_Sites')
        .replaceAll(RegExp(r'[^\w\s]+'), '')
        .replaceAll(' ', '_')
        .toUpperCase();
    final monthSuffix = DateFormat('yyyy_MM').format(month);
    final fileName = 'SKCPL_ATTENDANCE_${cleanName}_$monthSuffix.xlsx';

    await FileSaverHelper.saveAndOpen(
      bytes: bytes,
      fileName: fileName,
      mimeType: FileSaverHelper.excelMimeType,
      shareTitle: 'SKCPL Monthly Attendance — $monthSuffix ($fileName)',
    );
  }
}
