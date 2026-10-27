import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../models/stock_transaction_model.dart';
import '../models/cash_transaction_model.dart';
import '../models/daily_site_report_model.dart';
import '../models/attendance_model.dart';
import 'status_badge.dart';
import 'photo_thumbnail_strip.dart';

/// Modal dialog that shows all written information of an approval request
/// (Stock, Cash, Daily Site Report, or Attendance Regularization)
class EntryDetailDialog extends StatelessWidget {
  final StockTransactionModel? stockTransaction;
  final CashTransactionModel? cashTransaction;
  final DailySiteReportModel? dailyReport;
  final AttendanceRecordModel? attendanceRecord;

  final VoidCallback? onEdit;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const EntryDetailDialog({
    super.key,
    this.stockTransaction,
    this.cashTransaction,
    this.dailyReport,
    this.attendanceRecord,
    this.onEdit,
    this.onApprove,
    this.onReject,
  });

  static Future<void> show(
    BuildContext context, {
    StockTransactionModel? stockTransaction,
    CashTransactionModel? cashTransaction,
    DailySiteReportModel? dailyReport,
    AttendanceRecordModel? attendanceRecord,
    VoidCallback? onEdit,
    VoidCallback? onApprove,
    VoidCallback? onReject,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => EntryDetailDialog(
        stockTransaction: stockTransaction,
        cashTransaction: cashTransaction,
        dailyReport: dailyReport,
        attendanceRecord: attendanceRecord,
        onEdit: onEdit,
        onApprove: onApprove,
        onReject: onReject,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.cardBorder, width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──
            _buildHeader(context),

            const Divider(color: AppColors.divider, height: 1),

            // ── Scrollable Body ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (stockTransaction != null) _buildStockContent(stockTransaction!),
                    if (cashTransaction != null) _buildCashContent(cashTransaction!),
                    if (dailyReport != null) _buildReportContent(dailyReport!),
                    if (attendanceRecord != null) _buildAttendanceContent(attendanceRecord!),
                  ],
                ),
              ),
            ),

            const Divider(color: AppColors.divider, height: 1),

            // ── Footer Actions ──
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    IconData icon;
    Color iconColor;
    String title;
    TransactionStatus? status;

    if (stockTransaction != null) {
      icon = Icons.inventory_2_rounded;
      iconColor = AppColors.primary;
      title = '${stockTransaction!.type.displayName}: ${stockTransaction!.displayProductName}';
      status = stockTransaction!.status;
    } else if (cashTransaction != null) {
      final isTopUp = cashTransaction!.amountReceived > 0 && cashTransaction!.expenseAmount == 0;
      icon = Icons.account_balance_wallet_rounded;
      iconColor = isTopUp ? AppColors.approved : const Color(0xFFF59E0B);
      title = isTopUp ? 'Cash Received (Top-up)' : 'Cash Expense';
      status = cashTransaction!.status;
    } else if (dailyReport != null) {
      icon = Icons.assignment_rounded;
      iconColor = AppColors.goldAccent;
      title = 'Daily Site Report';
    } else {
      icon = Icons.access_time_filled_rounded;
      iconColor = const Color(0xFF14B8A6);
      title = 'Attendance Regularization';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.h4.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Full Entry Information',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          if (status != null) StatusBadge(status: status, compact: true),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary),
            onPressed: () => Navigator.pop(context),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildStockContent(StockTransactionModel tx) {
    final baseAmount = (tx.rate ?? 0) * tx.quantity;
    final sgstAmount = baseAmount * (tx.sgst / 100);
    final igstAmount = baseAmount * (tx.igst / 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tx.finalAmount != null && tx.finalAmount! > 0)
          _amountHighlightCard(
            label: 'Total Amount',
            amountText: '₹${NumberFormat('#,##,###.##').format(tx.finalAmount)}',
            color: AppColors.primary,
          ),

        _infoSectionTitle('Material & Quantity'),
        _detailRow('Transaction Type', tx.type.displayName),
        _detailRow('Product / Item', tx.displayProductName),
        _detailRow('Quantity', '${tx.quantity} ${tx.displayMetricUnitName}'),
        if (tx.rate != null && tx.rate! > 0)
          _detailRow('Unit Rate', '₹${NumberFormat('#,##,###.##').format(tx.rate)}'),

        const SizedBox(height: 12),
        _infoSectionTitle('Commercial & Billing Details'),
        _detailRow('Date', DateFormat('dd MMMM yyyy').format(tx.date)),
        if (tx.displayVendorName != 'None')
          _detailRow('Vendor / Party', tx.displayVendorName),
        if (tx.billNo != null && tx.billNo!.isNotEmpty)
          _detailRow('Bill / Challan No', '#${tx.billNo}'),
        if (baseAmount > 0)
          _detailRow('Base Amount', '₹${NumberFormat('#,##,###.##').format(baseAmount)}'),
        if (tx.sgst > 0)
          _detailRow('SGST (${tx.sgst}%)', '₹${NumberFormat('#,##,###.##').format(sgstAmount)}'),
        if (tx.igst > 0)
          _detailRow('IGST (${tx.igst}%)', '₹${NumberFormat('#,##,###.##').format(igstAmount)}'),

        const SizedBox(height: 12),
        _infoSectionTitle('Audit & Workflow Trail'),
        if (tx.submitterName != null && tx.submitterName!.isNotEmpty)
          _detailRow('Entered By', tx.submitterName!),
        if (tx.supervisorReviewNote != null && tx.supervisorReviewNote!.isNotEmpty)
          _detailRow('Project Head Note', tx.supervisorReviewNote!),
        if (tx.rejectionNote != null && tx.rejectionNote!.isNotEmpty)
          _detailRow('Rejection Reason', tx.rejectionNote!, isWarning: true),
        if (tx.cleanRemarks != null && tx.cleanRemarks!.isNotEmpty)
          _detailRow('Remarks / Notes', tx.cleanRemarks!),

        if (tx.photoUrls.isNotEmpty) ...[
          const SizedBox(height: 14),
          _infoSectionTitle('Attached Bills & Challans (${tx.photoUrls.length})'),
          PhotoThumbnailStrip(photoUrls: tx.photoUrls, size: 76),
        ],
      ],
    );
  }

  Widget _buildCashContent(CashTransactionModel tx) {
    final isTopUp = tx.amountReceived > 0 && tx.expenseAmount == 0;
    final primaryAmount = isTopUp ? tx.amountReceived : tx.expenseAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _amountHighlightCard(
          label: isTopUp ? 'Cash Received (Top-up)' : 'Expense Amount',
          amountText: '₹${NumberFormat('#,##,###.##').format(primaryAmount)}',
          color: isTopUp ? AppColors.approved : const Color(0xFFF59E0B),
        ),

        _infoSectionTitle('Cash Transaction Details'),
        _detailRow('Entry Type', isTopUp ? 'Cash Top-up / Received' : 'Site Expense'),
        _detailRow('Category', tx.displayExpenseTypeName),
        _detailRow('Date', DateFormat('dd MMMM yyyy').format(tx.date)),
        if (tx.partyName != null && tx.partyName!.isNotEmpty)
          _detailRow('Party / Vendor / Person', tx.partyName!),
        if (tx.billNo != null && tx.billNo!.isNotEmpty)
          _detailRow('Bill / Voucher / Ref No', '#${tx.billNo}'),

        if (tx.amountReceived > 0 && !isTopUp)
          _detailRow('Amount Received', '₹${NumberFormat('#,##,###.##').format(tx.amountReceived)}'),
        if (tx.cashInHand > 0)
          _detailRow('Remaining Cash In Hand', '₹${NumberFormat('#,##,###.##').format(tx.cashInHand)}'),

        const SizedBox(height: 12),
        _infoSectionTitle('Audit & Workflow Trail'),
        if (tx.submitterName != null && tx.submitterName!.isNotEmpty)
          _detailRow('Entered By', tx.submitterName!),
        if (tx.supervisorReviewNote != null && tx.supervisorReviewNote!.isNotEmpty)
          _detailRow('Project Head Note', tx.supervisorReviewNote!),
        if (tx.rejectionNote != null && tx.rejectionNote!.isNotEmpty)
          _detailRow('Rejection Reason', tx.rejectionNote!, isWarning: true),
        if (tx.cleanRemarks != null && tx.cleanRemarks!.isNotEmpty)
          _detailRow('Remarks / Description', tx.cleanRemarks!),

        if (tx.photoUrls.isNotEmpty) ...[
          const SizedBox(height: 14),
          _infoSectionTitle('Attached Receipts & Proofs (${tx.photoUrls.length})'),
          PhotoThumbnailStrip(photoUrls: tx.photoUrls, size: 76),
        ],
      ],
    );
  }

  Widget _buildReportContent(DailySiteReportModel report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoSectionTitle('Site & Submission Details'),
        _detailRow('Date', DateFormat('dd MMMM yyyy').format(report.date)),
        if (report.siteName != null) _detailRow('Site', report.siteName!),
        if (report.submittedBy != null) _detailRow('Submitted By', report.submittedBy!),

        const SizedBox(height: 12),
        _infoSectionTitle('Work Done & Progress'),
        if (report.workDone.isNotEmpty)
          ...report.workDone.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    Expanded(child: Text(w, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary))),
                  ],
                ),
              ))
        else
          Text('No specific progress items recorded', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary)),

        if (report.tomorrowPlan.isNotEmpty) ...[
          const SizedBox(height: 12),
          _infoSectionTitle('Tomorrow Plan'),
          ...report.tomorrowPlan.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: Color(0xFF14B8A6), fontWeight: FontWeight.bold)),
                    Expanded(child: Text(p, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary))),
                  ],
                ),
              )),
        ],

        if (report.manpowerDetails != null && report.manpowerDetails!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _infoSectionTitle('Manpower & Labor'),
          Text(report.manpowerDetails!, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary)),
        ],

        if (report.materialsUsed != null && report.materialsUsed!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _infoSectionTitle('Materials Used'),
          Text(report.materialsUsed!, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary)),
        ],

        if (report.notes != null && report.notes!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _infoSectionTitle('Written Notes'),
          Text(report.notes!, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary)),
        ],

        if (report.remarks != null && report.remarks!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _infoSectionTitle('Review Remarks'),
          Text(report.remarks!, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary)),
        ],

        if (report.photoUrls.isNotEmpty) ...[
          const SizedBox(height: 14),
          _infoSectionTitle('Site Photos (${report.photoUrls.length})'),
          PhotoThumbnailStrip(photoUrls: report.photoUrls, size: 76),
        ],
      ],
    );
  }

  Widget _buildAttendanceContent(AttendanceRecordModel att) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoSectionTitle('Staff & Shift Information'),
        _detailRow('Staff Name', att.staffName),
        _detailRow('Role', att.staffRole.toUpperCase()),
        _detailRow('Date', DateFormat('dd MMMM yyyy').format(att.date)),

        const SizedBox(height: 12),
        _infoSectionTitle('Punch Timings'),
        _detailRow(
          'Punch In',
          att.punchInTime != null
              ? DateFormat('hh:mm a').format(att.punchInTime!)
              : 'Not punched in',
        ),
        _detailRow(
          'Punch Out',
          att.punchOutTime != null
              ? DateFormat('hh:mm a').format(att.punchOutTime!)
              : 'Not punched out',
        ),
        if (att.totalHoursWorked != null)
          _detailRow('Total Hours', '${att.totalHoursWorked!.toStringAsFixed(1)} hrs'),
        _detailRow(
          'Location',
          att.isWithinSite ? 'Within Geofence (Verified)' : 'Outside Site (${att.distanceMeters?.toStringAsFixed(0) ?? "?"}m)',
          isWarning: !att.isWithinSite,
        ),

        const SizedBox(height: 12),
        _infoSectionTitle('Regularization Details'),
        if (att.regularizationReason != null && att.regularizationReason!.isNotEmpty)
          _detailRow('Worker Reason', att.regularizationReason!),
        if (att.adminDecisionNote != null && att.adminDecisionNote!.isNotEmpty)
          _detailRow('Decision Note', att.adminDecisionNote!),
      ],
    );
  }

  Widget _amountHighlightCard({
    required String label,
    required String amountText,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(amountText, style: AppTextStyles.h2.copyWith(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
        ],
      ),
    );
  }

  Widget _infoSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textTertiary,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(
                color: isWarning ? AppColors.rejected : AppColors.textPrimary,
                fontWeight: isWarning ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          if (onEdit != null) ...[
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onEdit!();
              },
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (onReject != null) ...[
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onReject!();
              },
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Reject'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.rejected,
                side: const BorderSide(color: AppColors.rejected),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (onApprove != null) ...[
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onApprove!();
              },
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Approve'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.approved,
              ),
            ),
            const SizedBox(width: 8),
          ],
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
