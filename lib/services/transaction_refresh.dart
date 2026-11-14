import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/cash_provider.dart';
import '../providers/stock_provider.dart';

/// All table events, completed retries and manual refreshes use the same dependencies.
void invalidateTransactionViews(void Function(ProviderOrFamily) invalidate) {
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
