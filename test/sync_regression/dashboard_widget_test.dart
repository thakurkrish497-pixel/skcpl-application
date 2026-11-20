import 'package:skcpl_app/services/cash_service.dart';
import 'package:skcpl_app/services/stock_service.dart';
import 'package:skcpl_app/providers/cash_provider.dart';
import 'package:skcpl_app/providers/stock_provider.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/app_routes.dart';
import 'package:skcpl_app/core/theme/app_theme.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/models/site_model.dart';
import 'package:skcpl_app/providers/auth_provider.dart';
import 'package:skcpl_app/services/auth_service.dart';
import 'package:skcpl_app/screens/admin/admin_dashboard.dart';
import 'package:skcpl_app/screens/accounts/accounts_dashboard.dart';
import 'package:skcpl_app/screens/project_head/project_head_dashboard.dart';
import 'package:skcpl_app/screens/home/home_screen.dart';
import 'package:skcpl_app/screens/sites/site_list_screen.dart';
import 'package:skcpl_app/widgets/master_entry_history_view.dart';
import 'package:skcpl_app/widgets/site_finance_summary_header.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../support/erp_test_backend.dart';

class FixedAuth extends AuthNotifier {
  FixedAuth(UserRole role) : super(AuthService(Supabase.instance.client)) {
    final row = ErpTestBackend.instance.tables['users']!.firstWhere(
        (u) =>
            u['role'] ==
            (role == UserRole.projectHead ? 'project_head' : role.name),
        orElse: () => ErpTestBackend.instance.tables['users']!.first);
    state = AuthState(
        user: role == UserRole.worker ? null : UserModel.fromJson(row),
        activeSite: role == UserRole.worker
            ? SiteModel.fromJson(ErpTestBackend.instance.tables['sites']!.first)
            : null);
  }
  @override
  Future<void> checkSession() async {}
}

class SeededCash extends CashNotifier {
  SeededCash(List<CashTransactionModel> rows)
      : super(CashService(Supabase.instance.client)) {
    state = CashState(transactions: rows);
  }
  @override
  Future<void> loadAllTransactions() async {}
}

class SeededStock extends StockNotifier {
  SeededStock(List<StockTransactionModel> rows)
      : super(StockService(Supabase.instance.client)) {
    state = StockState(transactions: rows);
  }
  @override
  Future<void> loadAllTransactions({TransactionType? type}) async {}
}

Future<void> showPage(
    WidgetTester tester, Widget page, UserRole role, Size size,
    {List<Override> overrides = const []}) async {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    debugPrint(details.toString());
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => FixedAuth(role)),
        ...overrides
      ],
      child: RepaintBoundary(
          key: const ValueKey('audit-capture'),
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.darkTheme,
              routes: buildAppRoutes(),
              home: page))));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> closePage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void main() {
  for (final size in [
    const Size(320, 740),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 768),
    const Size(1440, 1000),
    const Size(1920, 1080),
  ]) {
    for (final (name, role, page) in <(String, UserRole, Widget)>[
      ('admin', UserRole.admin, const AdminDashboard()),
      ('accounts', UserRole.accounts, const AccountsDashboard()),
      ('project-head', UserRole.projectHead, const ProjectHeadDashboard()),
      ('worker', UserRole.worker, const HomeScreen()),
      ('sites', UserRole.worker, const SiteListScreen(module: 'stock'))
    ]) {
      testWidgets(
          '$name renders at ${size.width.toInt()}px without framework errors',
          (tester) async {
        await showPage(tester, page, role, size);
        expect(tester.takeException(), isNull);
        const output = String.fromEnvironment('AUDIT_SCREENSHOT_DIR');
        if (output.isNotEmpty) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('audit-capture')));
          await tester.runAsync(() async {
            final screenshot = await boundary.toImage();
            final bytes =
                await screenshot.toByteData(format: ui.ImageByteFormat.png);
            Directory(output).createSync(recursive: true);
            File('$output/$name-${size.width.toInt()}.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            screenshot.dispose();
          });
        }
        await closePage(tester);
      });
    }
  }
  for (final route in [
    '/admin-cashflow',
    '/daily-site-reports',
    '/manage-sites',
    '/admin-role-access',
    '/admin-staff',
    '/admin-backup'
  ]) {
    testWidgets('Admin opens $route through the production route map',
        (tester) async {
      await showPage(
          tester,
          Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.pushNamed(context, route),
                      child: const Text('Open')))),
          UserRole.admin,
          const Size(1440, 1000));
      await tester.tap(find.text('Open'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Access required'), findsNothing);
      expect(tester.takeException(), isNull);
      await closePage(tester);
    });
  }
  testWidgets('Accounts cannot navigate directly into an Admin page',
      (tester) async {
    await showPage(
        tester,
        Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/admin-dashboard'),
                    child: const Text('Open')))),
        UserRole.accounts,
        const Size(390, 844));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Access required'), findsOneWidget);
    await closePage(tester);
  });
  testWidgets(
      'History and finance header tolerate an unloaded or missing selected site',
      (tester) async {
    await showPage(
        tester,
        Scaffold(
            body: Column(children: [
          SiteFinanceSummaryHeader(
              selectedSiteId: 'missing', onSiteChanged: (_) {}),
          const Expanded(
              child: MasterEntryHistoryView(selectedSiteId: 'missing'))
        ])),
        UserRole.accounts,
        const Size(390, 844));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Stock OUT (Usage)'));
    await tester.tap(find.text('Stock OUT (Usage)'));
    await tester.pump();
    expect(find.text('No Stock Entries Found'), findsOneWidget);
    await closePage(tester);
  });
  testWidgets(
      'All History filters actual cash, inbound and rejected outbound rows',
      (tester) async {
    final now = DateTime.now();
    final backend = ErpTestBackend.instance;
    backend.tables['cash_transactions'] = [
      CashTransactionModel(
              id: 'cash-history',
              siteId: 'site-a',
              date: now,
              expenseTypeId: 'expense',
              expenseAmount: 100,
              cashInHand: 0,
              remarks: '[Expense: Fuel]')
          .toJson()
    ];
    backend.tables['stock_transactions'] = [
      StockTransactionModel(
              id: 'in-history',
              siteId: 'site-a',
              date: now,
              type: TransactionType.inbound,
              productId: 'steel',
              metricUnitId: 'kg',
              quantity: 10,
              status: TransactionStatus.approved,
              remarks: '[Material: Steel]')
          .toJson(),
      StockTransactionModel(
              id: 'out-history',
              siteId: 'site-a',
              date: now,
              type: TransactionType.outbound,
              productId: 'diesel',
              metricUnitId: 'litres',
              quantity: 1,
              status: TransactionStatus.rejected,
              remarks: '[Material: Diesel]')
          .toJson(),
    ];
    await showPage(tester, const AccountsDashboard(), UserRole.accounts,
        const Size(1440, 1000),
        overrides: [
          cashProvider.overrideWith((ref) => SeededCash(backend
              .tables['cash_transactions']!
              .map(CashTransactionModel.fromJson)
              .toList())),
          stockProvider.overrideWith((ref) => SeededStock(backend
              .tables['stock_transactions']!
              .map(StockTransactionModel.fromJson)
              .toList())),
        ]);
    await tester.tap(find.text('All History'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Fuel'), findsOneWidget);
    final historyList = find
        .descendant(
            of: find.byType(MasterEntryHistoryView),
            matching: find.byWidgetPredicate((w) =>
                w is Scrollable && w.axisDirection == AxisDirection.down))
        .last;
    await tester.scrollUntilVisible(find.textContaining('Steel'), 200,
        scrollable: historyList);
    expect(find.textContaining('Steel'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Diesel'), 200,
        scrollable: historyList);
    expect(find.textContaining('Diesel'), findsOneWidget);
    await tester.ensureVisible(find.text('Stock IN (Inbound)'));
    await tester.tap(find.text('Stock IN (Inbound)'));
    await tester.pump();
    expect(find.textContaining('Steel'), findsOneWidget);
    expect(find.text('Fuel'), findsNothing);
    expect(find.textContaining('Diesel'), findsNothing);
    await tester.ensureVisible(find.text('All Types'));
    await tester.tap(find.text('All Types'));
    await tester.pump();
    await tester.ensureVisible(find.text('Rejected').first);
    await tester.tap(find.text('Rejected').first);
    await tester.pump();
    expect(find.textContaining('Diesel'), findsOneWidget);
    expect(find.text('Fuel'), findsNothing);
    expect(find.textContaining('Steel'), findsNothing);
    expect(tester.takeException(), isNull);
    await closePage(tester);
  });
}
