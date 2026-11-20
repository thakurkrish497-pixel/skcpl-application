import '../providers/dsr_history_provider.dart';
import '../providers/management_review_provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/site_report_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/cash_provider.dart';
import '../providers/stock_provider.dart';

/// All table events, completed retries and manual refreshes use the same dependencies.
void invalidateTransactionViews(void Function(ProviderOrFamily) invalidate) {
  invalidate(managementReviewQueueProvider);
  invalidate(pendingRegularizationRequestsProvider);
  invalidate(todayAttendanceForSiteProvider);
  invalidate(attendanceForDateAndSiteProvider);
  invalidate(monthlyAttendanceProvider);
  invalidate(dsrHistoryProvider);
  invalidate(allDailyReportsProvider);
  invalidate(siteReportsForSiteProvider);
  invalidate(siteReportsForDateProvider);
  invalidate(pendingCashAccountsProvider);
  invalidate(pendingCashAdminProvider);
  invalidate(pendingStockAccountsProvider);
  invalidate(pendingStockAdminProvider);
  invalidate(siteCashSummaryProvider);
  invalidate(stockOverviewProvider);
  invalidate(allSitesStockProvider);
  invalidate(allSitesFinanceSummaryProvider);
  invalidate(recentTransactionActivityProvider);
}
