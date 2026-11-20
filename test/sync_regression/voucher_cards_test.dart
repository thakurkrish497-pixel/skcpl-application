import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skcpl_app/providers/auth_provider.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/models/site_staff_model.dart';
import 'package:skcpl_app/models/site_model.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/providers/site_provider.dart';
import 'package:skcpl_app/providers/site_staff_provider.dart';
import 'package:skcpl_app/providers/cash_provider.dart';
import 'package:skcpl_app/providers/stock_provider.dart';
import 'package:skcpl_app/screens/accounts/accounts_dashboard.dart';
import 'package:skcpl_app/screens/admin/admin_review_screen.dart';
import 'package:skcpl_app/screens/project_head/project_head_dashboard.dart';
import 'package:skcpl_app/widgets/voucher_entry_details.dart';
import 'package:skcpl_app/widgets/photo_thumbnail_strip.dart';
import 'dashboard_widget_test.dart'
    show showPage, closePage, SeededCash, SeededStock, FixedAuth;
import '../support/erp_test_backend.dart';

String get site =>
    ErpTestBackend.instance.tables['sites']!.first['id'] as String;
String get siteName => 'Archived River Bridge Site • East Section';
String remarks(UserRole role) =>
    '${role == UserRole.projectHead ? '[PENDING SUPERVISOR REVIEW]' : '[Project Head: Approved by Head]'} [By: Ramesh Kumar (Senior Site Engineer)] [Bill: CH-101] Foundation work completed';
CashTransactionModel cash(UserRole role, {bool topup = false}) =>
    CashTransactionModel(
        id: 'cash-card',
        siteId: site,
        date: DateTime(2026, 11, 20),
        expenseTypeId: 'other',
        expenseTypeName: 'Site work',
        amountReceived: topup ? 2500 : 0,
        expenseAmount: topup ? 0 : 1250.5,
        cashInHand: 500,
        remarks: remarks(role),
        status: role == UserRole.admin
            ? TransactionStatus.pendingAdmin
            : TransactionStatus.pendingAccounts,
        photoUrls: const ['http://erp.test.invalid/photo.jpg']);
StockTransactionModel stock(UserRole role, {bool outward = false}) =>
    StockTransactionModel(
        id: 'stock-card',
        siteId: site,
        date: DateTime(2026, 11, 20),
        type: outward ? TransactionType.outbound : TransactionType.inbound,
        productId: 'cement',
        productName: 'Cement PPC',
        metricUnitId: 'bag',
        metricUnitName: 'Bags',
        quantity: 12,
        rate: 300,
        sgst: 9,
        igst: 0,
        finalAmount: 3924,
        vendorName: 'ABC Hardware',
        remarks: remarks(role),
        status: role == UserRole.admin
            ? TransactionStatus.pendingAdmin
            : TransactionStatus.pendingAccounts,
        photoUrls: const ['http://erp.test.invalid/challan.jpg']);
List<Override> directory() => [
      allSitesProvider.overrideWith((ref) async => [
            SiteModel.fromJson({
              ...ErpTestBackend.instance.tables['sites']!.first,
              'name': siteName,
              'is_active': false
            })
          ])
    ];
Future<void> pulse(WidgetTester t) async {
  await t.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 20)));
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  test(
      'Site IDs resolve exactly, including inactive sites; missing metadata is explicit',
      () {
    expect(voucherSiteLabel('a', 'Old name', {'a': 'Exact site name'}),
        'Exact site name');
    expect(voucherSiteLabel('a', 'Saved Site', {}), 'Saved Site');
    expect(voucherSiteLabel('a', null, {}), contains('ID: a'));
  });
  test('Saved name and designated role take precedence over current profiles',
      () {
    expect(
        voucherSubmitterLabel(
            snapshot: 'Ramesh (Site Engineer)',
            reference: 'someone',
            users: {'someone': (name: 'Different person', role: 'Admin')}),
        'Ramesh (Site Engineer)');
    expect(voucherSubmitterLabel(snapshot: 'Ramesh'),
        contains('role not recorded'));
  });
  test(
      'Linked management and staff IDs resolve without guessing the current viewer',
      () {
    const id = '11111111-1111-4111-8111-111111111111';
    expect(
        voucherSubmitterLabel(
            reference: id, users: {id: (name: 'Vikas', role: 'Project Head')}),
        'Vikas (Project Head) • linked profile');
    final s = SiteStaffModel(
        id: id,
        siteId: 's',
        name: 'Mohan',
        designation: 'Foreman',
        role: SiteStaffRole.worker,
        pin: 'fixture',
        createdAt: DateTime(2020));
    expect(voucherSubmitterLabel(reference: id, siteId: 's', staff: [s]),
        'Mohan (Foreman) • linked profile');
    expect(voucherSubmitterLabel(reference: id, siteId: 'other', staff: [s]),
        contains('unavailable'));
    expect(
        voucherSubmitterLabel(reference: null), 'Name and role not recorded');
  });
  for (final role in [
    UserRole.admin,
    UserRole.accounts,
    UserRole.projectHead
  ]) {
    for (final kind in ['expense', 'topup', 'inward', 'outward']) {
      testWidgets(
          '$role $kind card uses shared complete details with site and submitter',
          (t) async {
        final c = cash(role, topup: kind == 'topup');
        final s = stock(role, outward: kind == 'outward');
        final isCash = kind == 'expense' || kind == 'topup';
        final page = role == UserRole.admin
            ? const AdminReviewScreen()
            : role == UserRole.accounts
                ? const AccountsDashboard()
                : const ProjectHeadDashboard();
        final before = jsonEncode([c.toJson(), s.toJson()]);
        await showPage(t, page, role, const Size(1440, 1100), overrides: [
          ...directory(),
          cashProvider.overrideWith((ref) => SeededCash(isCash ? [c] : [])),
          stockProvider.overrideWith((ref) => SeededStock(isCash ? [] : [s])),
          pendingCashAccountsProvider
              .overrideWith((ref) async => isCash ? [c] : []),
          pendingStockAccountsProvider
              .overrideWith((ref) async => isCash ? [] : [s]),
          pendingCashAdminProvider
              .overrideWith((ref) async => isCash ? [c] : []),
          pendingStockAdminProvider
              .overrideWith((ref) async => isCash ? [] : [s])
        ]);
        final index =
            role == UserRole.projectHead ? (isCash ? 0 : 1) : (isCash ? 1 : 0);
        final tab = find.byType(Tab).at(index);
        final target =
            find.descendant(of: tab, matching: find.byType(Text)).first;
        await t.ensureVisible(target);
        await t.pump(const Duration(milliseconds: 400));
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 500));
        await pulse(t);
        await pulse(t);
        final details = find.byType(VoucherEntryDetails);
        expect(details, findsOneWidget);
        final within = find.descendant(
            of: details, matching: find.text('Site: $siteName'));
        expect(within, findsOneWidget);
        expect(
            find.descendant(
                of: details,
                matching: find
                    .text('Submitted by: Ramesh Kumar (Senior Site Engineer)')),
            findsOneWidget);
        expect(
            find.descendant(
                of: details,
                matching: find.text('Bill / Challan / Voucher: CH-101')),
            findsOneWidget);
        expect(
            find.descendant(
                of: details, matching: find.text('Entry date: 20 Nov 2026')),
            findsOneWidget);
        expect(
            find.descendant(
                of: details,
                matching: find.textContaining('Foundation work completed')),
            findsOneWidget);
        expect(
            find.descendant(
                of: details, matching: find.byType(PhotoThumbnailStrip)),
            findsOneWidget);
        if (isCash) {
          expect(
              find.descendant(
                  of: details,
                  matching: find.textContaining(
                      kind == 'topup' ? '2,500.00' : '1,250.50')),
              findsOneWidget);
        } else {
          expect(
              find.descendant(
                  of: details, matching: find.text('Quantity: 12.0 Bags')),
              findsOneWidget);
          expect(
              find.descendant(
                  of: details,
                  matching: find.text('Vendor / Party: ABC Hardware')),
              findsOneWidget);
        }
        expect(jsonEncode([c.toJson(), s.toJson()]), before);
        expect(t.takeException(), isNull);
        await closePage(t);
      });
    }
  }
  for (final size in [
    const Size(320, 740),
    const Size(844, 390),
    const Size(1440, 1000)
  ]) {
    testWidgets(
        'Long voucher identity and all parameters wrap at ${size.width}px',
        (t) async {
      final tx = cash(UserRole.admin).copyWith(
          remarks:
              '[By: Very long employee name with a detailed designation (Senior Construction Site Engineer)] [Bill: INVOICE-VERY-LONG-REFERENCE-2026-11111] A complete remark that must remain readable on narrow phones.');
      await showPage(
          t,
          Scaffold(
              body: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: VoucherEntryDetails(cash: tx))),
          UserRole.admin,
          size,
          overrides: directory());
      expect(find.text('Site: $siteName'), findsOneWidget);
      expect(find.textContaining('Senior Construction Site Engineer'),
          findsOneWidget);
      expect(t.takeException(), isNull);
      await closePage(t);
    });
  }
  testWidgets(
      'Missing saved By label resolves a linked profile and never displays a UUID as a person',
      (t) async {
    const id = '11111111-1111-4111-8111-111111111111';
    final tx = cash(UserRole.accounts)
        .copyWith(remarks: '[Bill: 22]', submittedBy: id);
    await showPage(t, Scaffold(body: VoucherEntryIdentity(cash: tx)),
        UserRole.accounts, const Size(390, 844),
        overrides: [
          ...directory(),
          voucherUserNamesProvider.overrideWith(
              (ref) async => {id: (name: 'Vikas', role: 'Project Head')}),
          allStaffProvider.overrideWith((ref) async => [])
        ]);
    expect(find.text('Submitted by: Vikas (Project Head) • linked profile'),
        findsOneWidget);
    expect(find.textContaining(id), findsNothing);
    expect(t.takeException(), isNull);
    await closePage(t);
  });
  test(
      'Shared submitter directory paginates read-only lookups without mutating profiles',
      () async {
    final rows = List.generate(
        205,
        (i) => {
              'id': i.toString().padLeft(5, '0'),
              'full_name': 'Employee $i',
              'email': 'fixture@example.invalid',
              'role': 'project_head'
            });
    final before = jsonEncode(rows);
    final requests = <http.Request>[];
    final client = SupabaseClient('http://cards.fixture.invalid', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
      requests.add(r);
      final after = r.url.queryParameters['id']?.replaceFirst('gt.', '');
      final page = rows
          .where((row) =>
              after == null || (row['id'] as String).compareTo(after) > 0)
          .take(200)
          .toList();
      return http.Response(jsonEncode(page), 200,
          request: r, headers: {'content-type': 'application/json'});
    }));
    addTearDown(client.dispose);
    final c = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => FixedAuth(UserRole.admin)),
      supabaseClientProvider.overrideWithValue(client)
    ]);
    addTearDown(c.dispose);
    final names = await c.read(voucherUserNamesProvider.future);
    expect(names.length, 205);
    expect(names['00000']!.role, 'Project Head');
    expect(requests.length, 2);
    expect(requests.every((r) => r.method == 'GET'), isTrue);
    expect(jsonEncode(rows), before);
  });
  test(
      'Management directory does not fetch private profile metadata for worker sessions',
      () async {
    final c = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => FixedAuth(UserRole.worker))
    ]);
    addTearDown(c.dispose);
    expect(await c.read(voucherUserNamesProvider.future), isEmpty);
  });
}
