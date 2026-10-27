import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stock_transaction_model.dart';
import '../models/cash_transaction_model.dart';
import '../models/user_model.dart';
import 'stock_provider.dart';
import 'cash_provider.dart';
import 'site_provider.dart';
import 'site_report_provider.dart';
import 'auth_provider.dart';
import '../services/notification_service.dart';

enum SlaAlertType {
  pendingStock,
  pendingCash,
  pendingDsr,
}

class SlaAlert {
  final String id;
  final SlaAlertType type;
  final String title;
  final String message;
  final String siteId;
  final String siteName;
  final int hoursElapsed;
  final DateTime createdAt;

  const SlaAlert({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.siteId,
    required this.siteName,
    required this.hoursElapsed,
    required this.createdAt,
  });
}

/// Provider that calculates pending stock & cash requests waiting > 36h for approval.
/// RESTRICTION: Only triggered for Accounts, Project Head, and Admin (NEVER workers).
final slaAlertsProvider = Provider<List<SlaAlert>>((ref) {
  final authState = ref.watch(authProvider);
  final user = authState.user;
  final userRole = user?.role;

  // IMPORTANT: SLA approval alerts are strictly for Accounts, Project Head, and Admin.
  // Workers / site staff do not handle approvals and must NOT receive these notifications.
  final isApprovalAuthority = userRole == UserRole.admin ||
      userRole == UserRole.projectHead ||
      userRole == UserRole.accounts;

  if (!isApprovalAuthority) {
    return const [];
  }

  final stockState = ref.watch(stockProvider);
  final cashState = ref.watch(cashProvider);
  final sitesAsync = ref.watch(activeSitesProvider);

  final sites = sitesAsync.valueOrNull ?? [];
  final siteMap = <String, String>{};
  for (final s in sites) {
    siteMap[s.id] = s.name;
  }

  final alerts = <SlaAlert>[];
  final now = DateTime.now();
  const slaThresholdHours = 36;

  // 1. Check Overdue Pending Stock Approvals (> 36 hours)
  for (final tx in stockState.transactions) {
    final isPending = tx.status == TransactionStatus.pendingAccounts ||
        tx.status == TransactionStatus.pendingAdmin ||
        tx.status.dbValue.contains('pending');
    if (!isPending) continue;

    final txTime = tx.createdAt ?? tx.date;
    final hours = now.difference(txTime).inHours;
    if (hours >= slaThresholdHours) {
      final sName = siteMap[tx.siteId] ?? tx.siteName ?? 'Site';
      final itemDesc = tx.productName ?? tx.remarks ?? 'Material';
      final alertId = 'stock_pending_${tx.id ?? txTime.millisecondsSinceEpoch}';

      final alert = SlaAlert(
        id: alertId,
        type: SlaAlertType.pendingStock,
        title: '⚠️ Stock Approval Overdue (${hours}h)',
        message: '$itemDesc (${tx.quantity} ${tx.metricUnitName ?? 'units'}) waiting >${hours}h at $sName',
        siteId: tx.siteId,
        siteName: sName,
        hoursElapsed: hours,
        createdAt: txTime,
      );
      alerts.add(alert);

      // Trigger Phone/Desktop notification
      NotificationService.showSlaNotification(
        title: 'SKCPL Alert: Stock Approval Overdue (${hours}h)',
        body: '$sName: $itemDesc (${tx.quantity}) waiting for approval for $hours hours.',
        alertKey: alertId,
      );
    }
  }

  // 2. Check Overdue Pending Cash Approvals (> 36 hours)
  for (final tx in cashState.transactions) {
    final isPending = tx.status == TransactionStatus.pendingAccounts ||
        tx.status == TransactionStatus.pendingAdmin ||
        tx.status.dbValue.contains('pending');
    if (!isPending) continue;

    final txTime = tx.createdAt ?? tx.date;
    final hours = now.difference(txTime).inHours;
    if (hours >= slaThresholdHours) {
      final sName = siteMap[tx.siteId] ?? tx.siteName ?? 'Site';
      final alertId = 'cash_pending_${tx.id ?? txTime.millisecondsSinceEpoch}';

      final alert = SlaAlert(
        id: alertId,
        type: SlaAlertType.pendingCash,
        title: '⚠️ Cash Expense Overdue (${hours}h)',
        message: '₹${tx.expenseAmount.toStringAsFixed(0)} (${tx.remarks ?? 'Expense'}) pending review for ${hours}h at $sName',
        siteId: tx.siteId,
        siteName: sName,
        hoursElapsed: hours,
        createdAt: txTime,
      );
      alerts.add(alert);

      NotificationService.showSlaNotification(
        title: 'SKCPL Alert: Cash Approval Overdue (${hours}h)',
        body: '$sName: ₹${tx.expenseAmount.toStringAsFixed(0)} waiting for review for $hours hours.',
        alertKey: alertId,
      );
    }
  }

  // 3. Check Overdue Daily Site Reports Pending Project Head Approval (> 12 hours)
  final dsrAsync = ref.watch(allDailyReportsProvider);
  final dsrList = dsrAsync.valueOrNull ?? [];

  for (final report in dsrList) {
    if (!report.isPendingProjectHeadReview) continue;

    final reportTime = report.createdAt;
    final hours = now.difference(reportTime).inHours;
    if (hours >= 12) {
      final sName = siteMap[report.siteId] ?? report.siteName ?? 'Site';
      final submitter = report.submittedBy ?? 'Site Worker';
      final alertId = 'dsr_pending_${report.id}';

      final alert = SlaAlert(
        id: alertId,
        type: SlaAlertType.pendingDsr,
        title: '⚠️ Daily Site Report Approval Pending (${hours}h)',
        message: 'DSR for $sName ($submitter) waiting for Project Head approval for ${hours}h',
        siteId: report.siteId,
        siteName: sName,
        hoursElapsed: hours,
        createdAt: reportTime,
      );
      alerts.add(alert);

      NotificationService.showSlaNotification(
        title: 'SKCPL Alert: DSR Approval Pending (${hours}h)',
        body: '$sName: Daily site report from $submitter waiting for Project Head approval.',
        alertKey: alertId,
      );
    }
  }

  // Sort by most overdue first
  alerts.sort((a, b) => b.hoursElapsed.compareTo(a.hoursElapsed));
  return alerts;
});
