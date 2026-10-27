import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/attendance_model.dart';
import '../../models/cash_transaction_model.dart';
import '../../models/daily_site_report_model.dart';
import '../../models/site_model.dart';
import '../../models/site_staff_model.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/cash_provider.dart';
import '../../providers/site_report_provider.dart';
import '../../services/file_saver_helper.dart';

enum ReportTimeframe {
  weekly,
  monthly,
  yearly,
  custom;

  String get displayName {
    switch (this) {
      case ReportTimeframe.weekly:
        return 'Weekly (7 Days)';
      case ReportTimeframe.monthly:
        return 'Monthly (30 Days)';
      case ReportTimeframe.yearly:
        return 'Yearly (365 Days)';
      case ReportTimeframe.custom:
        return 'Custom Range';
    }
  }
}

/// Comprehensive, detailed, and functional performance report for an employee across
/// Attendance, Cashflow, Daily Site Reports, and Stock tasks.
class EmployeePerformanceScreen extends ConsumerStatefulWidget {
  final SiteStaffModel staff;
  final SiteModel site;

  const EmployeePerformanceScreen({
    super.key,
    required this.staff,
    required this.site,
  });

  @override
  ConsumerState<EmployeePerformanceScreen> createState() =>
      _EmployeePerformanceScreenState();
}

class _EmployeePerformanceScreenState
    extends ConsumerState<EmployeePerformanceScreen>
    with SingleTickerProviderStateMixin {
  ReportTimeframe _selectedTimeframe = ReportTimeframe.monthly;
  late DateTime _startDate;
  late DateTime _endDate;
  bool _isLoading = true;
  String? _errorMessage;

  List<AttendanceRecordModel> _attendanceRecords = [];
  List<CashTransactionModel> _cashTransactions = [];
  List<DailySiteReportModel> _siteReports = [];

  late TabController _detailTabController;

  @override
  void initState() {
    super.initState();
    _detailTabController = TabController(length: 3, vsync: this);
    _applyTimeframe(ReportTimeframe.monthly);
  }

  @override
  void dispose() {
    _detailTabController.dispose();
    super.dispose();
  }

  void _applyTimeframe(ReportTimeframe tf) {
    final now = DateTime.now();
    DateTime start;
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (tf) {
      case ReportTimeframe.weekly:
        start = end.subtract(const Duration(days: 7));
        break;
      case ReportTimeframe.monthly:
        start = DateTime(now.year, now.month, 1);
        break;
      case ReportTimeframe.yearly:
        start = DateTime(now.year, 1, 1);
        break;
      case ReportTimeframe.custom:
        start = _startDate;
        break;
    }

    setState(() {
      _selectedTimeframe = tf;
      _startDate = start;
      _endDate = end;
    });

    _loadReportData();
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.surfaceDark,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedTimeframe = ReportTimeframe.custom;
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
      _loadReportData();
    }
  }

  Future<void> _loadReportData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final attendanceService = ref.read(attendanceServiceProvider);
      final cashService = ref.read(cashServiceProvider);
      final reportService = ref.read(siteReportServiceProvider);

      // 1. Fetch attendance records in range
      final allAttendance = await attendanceService.getAttendanceRange(
        siteId: widget.site.id,
        startDate: _startDate,
        endDate: _endDate,
      );
      final staffAttendance = allAttendance
          .where((r) => r.staffId == widget.staff.id || r.staffName.toLowerCase() == widget.staff.name.toLowerCase())
          .toList();

      // 2. Fetch cash transactions for site in range
      final allCash = await cashService.getTransactionsForSite(widget.site.id);
      final staffCash = allCash.where((c) {
        final inRange = c.date.isAfter(_startDate.subtract(const Duration(seconds: 1))) &&
            c.date.isBefore(_endDate.add(const Duration(seconds: 1)));
        if (!inRange) return false;

        final sub = c.submittedBy?.toLowerCase() ?? '';
        final rem = c.remarks?.toLowerCase() ?? '';
        final staffNameLower = widget.staff.name.toLowerCase();

        return sub.contains(staffNameLower) || rem.contains(staffNameLower);
      }).toList();

      // 3. Fetch daily site reports
      final allReports = await reportService.getReportsForSite(widget.site.id);
      final staffReports = allReports.where((r) {
        final inRange = r.date.isAfter(_startDate.subtract(const Duration(seconds: 1))) &&
            r.date.isBefore(_endDate.add(const Duration(seconds: 1)));
        if (!inRange) return false;

        final sub = r.submittedBy?.toLowerCase() ?? '';
        final staffNameLower = widget.staff.name.toLowerCase();

        return sub.contains(staffNameLower);
      }).toList();

      if (mounted) {
        setState(() {
          _attendanceRecords = staffAttendance;
          _cashTransactions = staffCash;
          _siteReports = staffReports;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _exportExcelReport() async {
    try {
      final excel = Excel.createExcel();
      final sheetName = 'PERFORMANCE SUMMARY';
      excel.rename('Sheet1', sheetName);
      final sheet = excel[sheetName];

      final dateFormat = DateFormat('dd-MMM-yyyy');
      final rangeStr = '${dateFormat.format(_startDate)} to ${dateFormat.format(_endDate)}';

      // Header block
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
          TextCellValue('EMPLOYEE 360° PERFORMANCE AUDIT REPORT');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
          TextCellValue('Employee: ${widget.staff.name} | Role: ${widget.staff.role.displayName} | Site: ${widget.site.name}');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value =
          TextCellValue('Period: ${_selectedTimeframe.displayName} ($rangeStr) | Generated: ${dateFormat.format(DateTime.now())}');

      // Summary KPIs
      final presentCount = _attendanceRecords.where((r) =>
          r.status == AttendanceStatus.presentOnTime ||
          r.status == AttendanceStatus.presentLate ||
          r.status == AttendanceStatus.regularizedPresent).length;
      final lateCount = _attendanceRecords.where((r) => r.status == AttendanceStatus.presentLate).length;
      final absentCount = _attendanceRecords.where((r) =>
          r.status == AttendanceStatus.absent ||
          r.status == AttendanceStatus.absentLateLockout).length;
      final totalCashExpense = _cashTransactions.fold<double>(0, (sum, c) => sum + c.expenseAmount);

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4)).value =
          TextCellValue('--- KEY PERFORMANCE INDICATORS ---');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 5)).value =
          TextCellValue('Days Present: $presentCount | Late: $lateCount | Absent/Lockout: $absentCount');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 6)).value =
          TextCellValue('Cash Expenses Logged: ₹${totalCashExpense.toStringAsFixed(2)} (${_cashTransactions.length} entries)');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 7)).value =
          TextCellValue('Daily Site Reports Logged: ${_siteReports.length}');

      // Attendance Table
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 9)).value =
          TextCellValue('--- ATTENDANCE LOG ---');
      final attHeaders = ['Date', 'Status', 'In Time', 'Out Time', 'Late (Mins)', 'Geofence', 'Reason/Notes'];
      for (int c = 0; c < attHeaders.length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 10)).value =
            TextCellValue(attHeaders[c]);
      }
      int attRow = 11;
      for (final r in _attendanceRecords) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: attRow)).value =
            TextCellValue(dateFormat.format(r.date));
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: attRow)).value =
            TextCellValue(r.status.displayName);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: attRow)).value =
            TextCellValue(r.punchInTime != null ? DateFormat('HH:mm').format(r.punchInTime!) : '-');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: attRow)).value =
            TextCellValue(r.punchOutTime != null ? DateFormat('HH:mm').format(r.punchOutTime!) : '-');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: attRow)).value =
            IntCellValue(r.lateMinutes);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: attRow)).value =
            TextCellValue(r.isWithinSite ? 'Within Site' : 'Outside Fence');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: attRow)).value =
            TextCellValue(r.regularizationReason ?? r.adminDecisionNote ?? '-');
        attRow++;
      }

      final fileBytes = excel.save();
      if (fileBytes != null) {
        final fileName = 'Performance_${widget.staff.name.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
        await FileSaverHelper.saveAndOpen(
          bytes: Uint8List.fromList(fileBytes),
          fileName: fileName,
          mimeType: FileSaverHelper.excelMimeType,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Excel Report exported: $fileName'),
              backgroundColor: AppColors.approved,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.rejected),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    final rangeText = '${dateFormat.format(_startDate)} – ${dateFormat.format(_endDate)}';

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.staff.name} — Performance'),
            Text(
              '${widget.site.name} • ${widget.staff.role.displayName}',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Download Excel Report',
            onPressed: _isLoading ? null : _exportExcelReport,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload',
            onPressed: _loadReportData,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Employee Master Profile Header Card ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: widget.staff.isSupervisor
                          ? AppColors.primary.withOpacity(0.18)
                          : AppColors.secondary.withOpacity(0.18),
                      child: Icon(
                        widget.staff.isSupervisor
                            ? Icons.admin_panel_settings_rounded
                            : Icons.person_rounded,
                        color: widget.staff.isSupervisor
                            ? AppColors.primary
                            : AppColors.secondary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                widget.staff.name,
                                style: AppTextStyles.h4.copyWith(fontSize: 16),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: widget.staff.isSupervisor
                                      ? AppColors.primary.withOpacity(0.15)
                                      : AppColors.secondary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  widget.staff.role.displayName,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: widget.staff.isSupervisor
                                        ? AppColors.primary
                                        : AppColors.secondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (widget.staff.identificationSubtitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.staff.identificationSubtitle,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.secondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Assigned Modules Chips
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: widget.staff.modules.map((m) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 12, color: AppColors.approved),
                          const SizedBox(width: 4),
                          Text(
                            m.displayName,
                            style: AppTextStyles.bodySmall.copyWith(
                              fontSize: 11,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // ── Timeframe Filter Segmented Control ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.cardDark,
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildTimeframeChip(ReportTimeframe.weekly, 'Weekly'),
                        const SizedBox(width: 8),
                        _buildTimeframeChip(ReportTimeframe.monthly, 'Monthly'),
                        const SizedBox(width: 8),
                        _buildTimeframeChip(ReportTimeframe.yearly, 'Yearly'),
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: const Icon(Icons.date_range_rounded, size: 14),
                          label: Text(
                            _selectedTimeframe == ReportTimeframe.custom
                                ? rangeText
                                : 'Custom Date',
                            style: TextStyle(
                              fontSize: 12,
                              color: _selectedTimeframe == ReportTimeframe.custom
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                          backgroundColor: _selectedTimeframe == ReportTimeframe.custom
                              ? AppColors.primary.withOpacity(0.15)
                              : AppColors.surfaceDark,
                          onPressed: _pickCustomDateRange,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Main Content Area ──
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _errorMessage != null
                    ? Center(
                        child: Text(
                          'Error loading report: $_errorMessage',
                          style: const TextStyle(color: AppColors.rejected),
                        ),
                      )
                    : Column(
                        children: [
                          // ── KPI Summary Cards ──
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: _buildKpiRow(),
                          ),

                          // ── Detail Tabs ──
                          Container(
                            color: AppColors.surfaceDark,
                            child: TabBar(
                              controller: _detailTabController,
                              indicatorColor: AppColors.primary,
                              labelColor: AppColors.primary,
                              unselectedLabelColor: AppColors.textSecondary,
                              tabs: [
                                Tab(text: 'Attendance (${_attendanceRecords.length})'),
                                Tab(text: 'Cashbook (${_cashTransactions.length})'),
                                Tab(text: 'Daily Reports (${_siteReports.length})'),
                              ],
                            ),
                          ),

                          Expanded(
                            child: TabBarView(
                              controller: _detailTabController,
                              children: [
                                _buildAttendanceLedger(),
                                _buildCashbookLedger(),
                                _buildSiteReportsLedger(),
                              ],
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeframeChip(ReportTimeframe tf, String label) {
    final isSelected = _selectedTimeframe == tf;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surfaceDark,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : AppColors.textSecondary,
      ),
      onSelected: (val) {
        if (val) _applyTimeframe(tf);
      },
    );
  }

  Widget _buildKpiRow() {
    final presentCount = _attendanceRecords.where((r) =>
        r.status == AttendanceStatus.presentOnTime ||
        r.status == AttendanceStatus.presentLate ||
        r.status == AttendanceStatus.regularizedPresent).length;
    final lateCount = _attendanceRecords.where((r) => r.status == AttendanceStatus.presentLate).length;
    final absentCount = _attendanceRecords.where((r) =>
        r.status == AttendanceStatus.absent ||
        r.status == AttendanceStatus.absentLateLockout).length;

    final double totalDays = _attendanceRecords.length.toDouble();
    final double attendanceRate = totalDays > 0 ? (presentCount / totalDays) * 100 : 0;

    final totalExpense = _cashTransactions.fold<double>(0, (sum, c) => sum + c.expenseAmount);

    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            title: 'Attendance',
            value: totalDays > 0 ? '${attendanceRate.toStringAsFixed(0)}%' : '0%',
            subtitle: '$presentCount Pres • $lateCount Late • $absentCount Abs',
            color: attendanceRate >= 80 ? AppColors.approved : AppColors.pending,
            icon: Icons.calendar_today_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricTile(
            title: 'Cashflow Handled',
            value: '₹${NumberFormat.compact().format(totalExpense)}',
            subtitle: '${_cashTransactions.length} expenses recorded',
            color: AppColors.secondary,
            icon: Icons.account_balance_wallet_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricTile(
            title: 'Site Reports',
            value: '${_siteReports.length}',
            subtitle: 'Filed / Reviewed',
            color: AppColors.primary,
            icon: Icons.assignment_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: AppTextStyles.bodySmall.copyWith(fontSize: 10, color: AppColors.textSecondary)),
              Icon(icon, size: 14, color: color),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.h4.copyWith(fontSize: 16, color: color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTextStyles.bodySmall.copyWith(fontSize: 9, color: AppColors.textTertiary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Tab 1: Detailed Attendance Ledger ──
  Widget _buildAttendanceLedger() {
    if (_attendanceRecords.isEmpty) {
      return _buildEmptyState('No attendance punches in this timeframe');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _attendanceRecords.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final r = _attendanceRecords[index];
        final inTimeStr = r.punchInTime != null ? DateFormat('hh:mm a').format(r.punchInTime!) : '--';
        final outTimeStr = r.punchOutTime != null ? DateFormat('hh:mm a').format(r.punchOutTime!) : '--';

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('EEE, dd MMM yyyy').format(r.date),
                    style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                  ),
                  _buildStatusBadge(r.status),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.login_rounded, size: 14, color: AppColors.approved),
                  const SizedBox(width: 4),
                  Text('In: $inTimeStr', style: AppTextStyles.bodySmall),
                  const SizedBox(width: 16),
                  const Icon(Icons.logout_rounded, size: 14, color: AppColors.pending),
                  const SizedBox(width: 4),
                  Text('Out: $outTimeStr', style: AppTextStyles.bodySmall),
                  const Spacer(),
                  if (r.lateMinutes > 0)
                    Text(
                      '${r.lateMinutes}m Late',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.pending, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
              if (r.regularizationReason != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Note: ${r.regularizationReason}',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Tab 2: Detailed Cashbook Ledger ──
  Widget _buildCashbookLedger() {
    if (_cashTransactions.isEmpty) {
      return _buildEmptyState('No cash transactions recorded by this employee in this timeframe');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _cashTransactions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final c = _cashTransactions[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('dd MMM yyyy').format(c.date),
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.expenseTypeName ?? 'Petty Cash Expense',
                      style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (c.remarks != null && c.remarks!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        c.remarks!,
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${c.expenseAmount.toStringAsFixed(0)}',
                    style: AppTextStyles.h4.copyWith(fontSize: 16, color: AppColors.primary),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      c.status.name.toUpperCase(),
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Tab 3: Detailed Daily Site Reports Ledger ──
  Widget _buildSiteReportsLedger() {
    if (_siteReports.isEmpty) {
      return _buildEmptyState('No daily site reports filed by this employee in this timeframe');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _siteReports.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final r = _siteReports[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('EEE, dd MMM yyyy').format(r.date),
                    style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (r.isSupervisorRejected ? AppColors.rejected : AppColors.approved).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      r.isSupervisorApproved
                          ? 'APPROVED'
                          : (r.isSupervisorRejected
                              ? 'REJECTED'
                              : (r.isPendingSupervisorReview ? 'PENDING' : 'SUBMITTED')),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: r.isSupervisorRejected ? AppColors.rejected : AppColors.approved,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (r.remarks != null && r.remarks!.isNotEmpty)
                Text(
                  r.remarks!,
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                )
              else
                Text(
                  'Daily progress and site activity logged',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(AttendanceStatus status) {
    Color color;
    switch (status) {
      case AttendanceStatus.presentOnTime:
      case AttendanceStatus.regularizedPresent:
        color = AppColors.approved;
        break;
      case AttendanceStatus.presentLate:
      case AttendanceStatus.regularizedHalfDay:
      case AttendanceStatus.regularizationPending:
        color = AppColors.pending;
        break;
      case AttendanceStatus.absentLateLockout:
      case AttendanceStatus.rejected:
      case AttendanceStatus.absent:
        color = AppColors.rejected;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
