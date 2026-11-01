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
  missedCashbook,
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

  // 4. Check Missed Cashbook Entries for Active Construction Sites (> 24 hours / Evening Cut-off)
  final yesterday = now.subtract(const Duration(days: 1));
  final checkTodayMissed = now.hour >= 18;

  for (final site in sites) {
    if (site.isHeadOffice) continue; // Only construction sites check cashbook entries

    // Check yesterday's cash entries
    final hasYesterdayEntry = cashState.transactions.any((tx) =>
        tx.siteId == site.id &&
        tx.status != TransactionStatus.rejected &&
        tx.date.year == yesterday.year &&
        tx.date.month == yesterday.month &&
        tx.date.day == yesterday.day);

    if (!hasYesterdayEntry) {
      final yDateKey = '${yesterday.year}_${yesterday.month}_${yesterday.day}';
      final alertId = 'missed_cash_${site.id}_$yDateKey';
      final alert = SlaAlert(
        id: alertId,
        type: SlaAlertType.missedCashbook,
        title: '⚠️ Missed Cashbook Entry (${site.name})',
        message: 'No cash transactions recorded for ${site.name} on yesterday (${yesterday.day}/${yesterday.month}).',
        siteId: site.id,
        siteName: site.name,
        hoursElapsed: now.difference(DateTime(yesterday.year, yesterday.month, yesterday.day, 20)).inHours.clamp(1, 999),
        createdAt: DateTime(yesterday.year, yesterday.month, yesterday.day, 20),
      );
      alerts.add(alert);

      NotificationService.showSlaNotification(
        title: 'SKCPL Alert: Cashbook Entry Missed',
        body: 'Site ${site.name} has missed cashbook entry for yesterday (${yesterday.day}/${yesterday.month}).',
        alertKey: alertId,
      );
    }

    if (checkTodayMissed) {
      final hasTodayEntry = cashState.transactions.any((tx) =>
          tx.siteId == site.id &&
          tx.status != TransactionStatus.rejected &&
          tx.date.year == now.year &&
          tx.date.month == now.month &&
          tx.date.day == now.day);

      if (!hasTodayEntry) {
        final tDateKey = '${now.year}_${now.month}_${now.day}';
        final alertId = 'missed_cash_today_${site.id}_$tDateKey';
        final alert = SlaAlert(
          id: alertId,
          type: SlaAlertType.missedCashbook,
          title: '⚠️ Today\'s Cashbook Pending (${site.name})',
          message: 'No cash transactions recorded yet for ${site.name} today. Evening cut-off passed.',
          siteId: site.id,
          siteName: site.name,
          hoursElapsed: (now.hour - 18).clamp(1, 24),
          createdAt: DateTime(now.year, now.month, now.day, 18),
        );
        alerts.add(alert);
      }
    }
  }

  // Sort by most overdue first
  alerts.sort((a, b) => b.hoursElapsed.compareTo(a.hoursElapsed));
  return alerts;
});

/// Provider for the Site Worker to check if their active site has missed cashbook entries
final missedCashbookForWorkerProvider = Provider<List<DateTime>>((ref) {
  final activeSite = ref.watch(authProvider).activeSite;
  if (activeSite == null || activeSite.isHeadOffice) return const [];

  final cashState = ref.watch(cashProvider);
  final now = DateTime.now();
  final yesterday = now.subtract(const Duration(days: 1));
  final missed = <DateTime>[];

  // 1. Check yesterday
  final hasYesterday = cashState.transactions.any((tx) =>
      tx.siteId == activeSite.id &&
      tx.status != TransactionStatus.rejected &&
      tx.date.year == yesterday.year &&
      tx.date.month == yesterday.month &&
      tx.date.day == yesterday.day);

  if (!hasYesterday) {
    missed.add(yesterday);
  }

  // 2. Check today after 6:00 PM
  if (now.hour >= 18) {
    final hasToday = cashState.transactions.any((tx) =>
        tx.siteId == activeSite.id &&
        tx.status != TransactionStatus.rejected &&
        tx.date.year == now.year &&
        tx.date.month == now.month &&
        tx.date.day == now.day);
    if (!hasToday) {
      missed.add(now);
    }
  }

  // Trigger worker notification if missed entries exist
  if (missed.isNotEmpty) {
    final d = missed.first;
    final dKey = '${d.year}_${d.month}_${d.day}';
    final isYesterday = d.day == yesterday.day;
    NotificationService.showSlaNotification(
      title: '⚠️ Missed Cashbook Entry (${activeSite.name})',
      body: 'No cash entries recorded for ${isYesterday ? "yesterday" : "today"} at ${activeSite.name}. Tap to submit.',
      alertKey: 'worker_missed_cash_${activeSite.id}_$dKey',
    );
  }

  return missed;
});
