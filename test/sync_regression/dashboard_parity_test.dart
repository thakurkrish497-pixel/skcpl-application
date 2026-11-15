import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/providers/cash_provider.dart';
import 'package:skcpl_app/screens/admin/admin_cashflow_screen.dart';
import 'package:skcpl_app/screens/admin/site_details_screen.dart';
import 'package:skcpl_app/screens/accounts/accounts_dashboard.dart';
import 'package:skcpl_app/screens/project_head/project_head_dashboard.dart';
import 'package:skcpl_app/services/transaction_refresh.dart';
import 'package:skcpl_app/widgets/sites_overview.dart';
import 'package:skcpl_app/widgets/site_finance_summary_header.dart';
import 'package:skcpl_app/widgets/master_entry_history_view.dart';
import '../support/erp_test_backend.dart';
import 'dashboard_widget_test.dart' show showPage, closePage;
import 'package:skcpl_app/services/cash_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Keep widget tests independent of device storage; the companion provider tests
// exercise the real durable queue and CashNotifier refresh behavior.
class DashboardCash extends CashNotifier {
  DashboardCash() : super(CashService(Supabase.instance.client));
  Future<List<CashTransactionModel>> Function()? onLoad;
  @override
  Future<void> loadAllTransactions() async {
    try {
      state = CashState(transactions: await onLoad!());
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }
}

String get siteId =>
    ErpTestBackend.instance.tables['sites']!.first['id'] as String;
CashTransactionModel entry(String id,
        {double received = 0,
        double spent = 0,
        TransactionStatus status = TransactionStatus.approved,
        String? site}) =>
    CashTransactionModel(
        id: id,
        siteId: site ?? siteId,
        date: DateTime(2026, 11, 16),
        expenseTypeId: 'e72d9d18-2a33-4748-a04f-ddfdc9504a3f',
        amountReceived: received,
        expenseAmount: spent,
        cashInHand: 0,
        status: status);
List<CashTransactionModel> entries() => [
      entry('topup', received: 1000),
      entry('spent', spent: 200),
      entry('pending', spent: 100, status: TransactionStatus.pendingAccounts),
      entry('rejected', spent: 999, status: TransactionStatus.rejected),
      entry('other-site', received: 8000, site: 'other')
    ];
void main() {
  for (final size in [
    const Size(320, 740),
    const Size(844, 390),
    const Size(1440, 1000)
  ]) {
    testWidgets(
        'Cashflow opens directly, displays pending cash and fits ${size.width}px',
        (tester) async {
      ErpTestBackend.instance.tables['sites']!.first['allocated_budget'] = 2000;
      final service = DashboardCash()..onLoad = () async => entries();
      await showPage(tester, const AdminCashflowScreen(), UserRole.admin, size,
          overrides: [cashProvider.overrideWith((ref) => service)]);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Nissarpur'), 150,
          scrollable: find.byType(Scrollable).first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('₹700.00'), findsOneWidget);
      expect(find.text('₹1,800.00'), findsOneWidget);
      expect(find.text('1 pending entries'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await closePage(tester);
    });
  }
  testWidgets(
      'An open cashflow screen responds to the realtime refresh path and retains figures after a network failure',
      (tester) async {
    var rows = entries();
    final service = DashboardCash()..onLoad = () async => rows;
    await showPage(tester, const AdminCashflowScreen(), UserRole.admin,
        const Size(390, 844),
        overrides: [cashProvider.overrideWith((ref) => service)]);
    final c = ProviderScope.containerOf(
        tester.element(find.byType(AdminCashflowScreen)));
    rows = rows
        .map((e) => e.id == 'pending'
            ? e.copyWith(status: TransactionStatus.rejected)
            : e)
        .toList();
    invalidateTransactionViews(c.invalidate);
    await tester.runAsync(() => c.read(cashProvider.notifier).refresh());
    await tester.pump();
    expect(find.text('₹700.00'), findsNothing);
    expect(find.text('₹800.00'), findsNWidgets(2));
    service.onLoad = () async => throw StateError('Network unavailable');
    await tester.runAsync(() => c.read(cashProvider.notifier).refresh());
    await tester.pump();
    expect(
        find.textContaining('Showing the last loaded figures'), findsOneWidget);
    expect(find.text('₹800.00'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await closePage(tester);
  });
  for (final role in [UserRole.accounts, UserRole.projectHead]) {
    testWidgets('$role has the shared Sites overview and site workbook export',
        (tester) async {
      await showPage(
          tester,
          role == UserRole.accounts
              ? const AccountsDashboard()
              : const ProjectHeadDashboard(),
          role,
          const Size(1440, 1000));
      final tab = find.widgetWithText(Tab, 'Sites');
      await tester.ensureVisible(tab);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Sites'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(SitesOverview), findsOneWidget);
      expect(find.text('Select Site for Details'), findsOneWidget);
      await tester.tap(find.text('Nissarpur').last);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(SiteDetailsScreen), findsOneWidget);
      await tester.drag(find.byType(ListView).last, const Offset(0, -1100));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Export Excel Workbook'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await closePage(tester);
    });
  }
  testWidgets(
      'Project Head retains all four queues, stock summary, header export and complete history',
      (tester) async {
    await showPage(tester, const ProjectHeadDashboard(), UserRole.projectHead,
        const Size(1440, 1000));
    final tabs = tester
        .widgetList<Tab>(find.byType(Tab))
        .map((t) => t.text ?? '')
        .toList();
    for (final name in [
      'Cash (',
      'Stock (',
      'Attendance (',
      'DSR Reports (',
      'All History',
      'Sites'
    ]) {
      expect(tabs.any((t) => t.startsWith(name)), isTrue);
    }
    expect(find.byType(SiteFinanceSummaryHeader), findsOneWidget);
    expect(find.text('Export Excel'), findsOneWidget);
    expect(find.text('Approved Stock (IN / OUT / BALANCE)'), findsOneWidget);
    final history = find.widgetWithText(Tab, 'All History');
    await tester.ensureVisible(history);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('All History'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(MasterEntryHistoryView), findsOneWidget);
    expect(find.text('Stock IN (Inbound)'), findsOneWidget);
    expect(find.text('Stock OUT (Usage)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closePage(tester);
  });
}
