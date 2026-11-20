import 'package:skcpl_app/screens/stock/add_product_screen.dart';
import 'package:skcpl_app/screens/stock/use_product_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/models/site_staff_model.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/providers/cash_provider.dart';
import 'package:skcpl_app/providers/stock_provider.dart';
import 'package:skcpl_app/providers/site_staff_provider.dart';
import 'package:skcpl_app/providers/rejected_entry_provider.dart';
import 'package:skcpl_app/services/rejected_entry_service.dart';
import 'package:skcpl_app/widgets/voucher_entry_details.dart';
import 'package:skcpl_app/widgets/rejected_entry_actions.dart';
import 'package:skcpl_app/screens/cashbook/expense_form_screen.dart';
import 'dashboard_widget_test.dart'
    show SeededCash, SeededStock, showPage, closePage;
import '../support/erp_test_backend.dart';

class Selection extends ActiveStaffNotifier {
  Selection(SiteStaffModel person) : super() {
    state = person;
  }
}

class MutableCash extends SeededCash {
  MutableCash(super.rows);
  void remove() {
    state = const CashState();
  }
}

class Actions extends RejectedEntryService {
  int deleted = 0;
  final VoidCallback remove;
  Actions(this.remove) : super(Supabase.instance.client);
  @override
  Future<Map<String, dynamic>?> draft(String module, String id) async => {
        'input': {
          'expense_amount': 175,
          'rejection_note': null,
          'reviewed_at': null,
          'status': 'approved'
        }
      };
  @override
  Future<void> dismiss(String module, String id, DateTime? updated,
      {SiteStaffModel? staff}) async {
    deleted++;
    remove();
  }
}

void main() {
  testWidgets('Production release keeps rejected actions Admin-only',
      (t) async {
    final site = ErpTestBackend.instance.tables['sites']!.first['id'] as String;
    final source = CashTransactionModel(
        id: '10000000-0000-4000-8000-000000000099',
        siteId: site,
        date: DateTime(2026, 11, 20),
        expenseTypeId: 'e72d9d18-2a33-4748-a04f-ddfdc9504a3f',
        expenseAmount: 100,
        cashInHand: 0,
        status: TransactionStatus.rejected,
        rejectionNote: 'Keep this feedback',
        remarks: '[By: Ramesh (Engineer)] Work');
    final staff = SiteStaffModel(
        id: 'worker',
        siteId: site,
        name: 'Ramesh',
        role: SiteStaffRole.worker,
        designation: 'Engineer',
        pin: 'fixture',
        modules: const [StaffModule.cashbook],
        createdAt: DateTime(2026));
    await showPage(
        t,
        Scaffold(body: ListView(children: [VoucherEntryDetails(cash: source)])),
        UserRole.worker,
        const Size(390, 844),
        overrides: [
          activeStaffProvider.overrideWith((ref) => Selection(staff)),
        ]);
    expect(find.textContaining('Keep this feedback'), findsOneWidget);
    expect(find.text('Edit & Resubmit'), findsNothing);
    expect(find.text('Delete / Dismiss'), findsNothing);
    expect(t.takeException(), isNull);
    await closePage(t);
  });
  for (final direction in [TransactionType.inbound, TransactionType.outbound]) {
    testWidgets(
        '$direction worker opens the matching resubmission editor with feedback intact',
        (t) async {
      final site =
          ErpTestBackend.instance.tables['sites']!.first['id'] as String;
      final person = SiteStaffModel(
          id: 'worker',
          siteId: site,
          name: 'Ramesh',
          role: SiteStaffRole.worker,
          designation: 'Engineer',
          pin: 'fixture',
          modules: const [StaffModule.cashbook, StaffModule.stock],
          createdAt: DateTime(2026));
      final row = StockTransactionModel(
          id: '20000000-0000-4000-8000-000000000001',
          siteId: site,
          type: direction,
          date: DateTime(2026, 11, 20),
          productId: '441097fa-eef6-4df4-a4f6-7b003b302c0b',
          metricUnitId: '00000000-0000-0000-0000-000000000002',
          quantity: 10,
          remarks: '[By: Ramesh (Engineer)] Work',
          status: TransactionStatus.rejected,
          rejectionNote: 'Wrong quantity',
          updatedAt: DateTime.utc(2026, 11, 20));
      await showPage(
          t,
          Scaffold(body: ListView(children: [VoucherEntryDetails(stock: row)])),
          UserRole.worker,
          const Size(390, 844),
          overrides: [
            workerRejectedEntryActionsProvider.overrideWithValue(true),
            cashProvider.overrideWith((ref) => SeededCash([])),
            stockProvider.overrideWith((ref) => SeededStock([row])),
            activeStaffProvider.overrideWith((ref) => Selection(person)),
            rejectedEntryServiceProvider.overrideWithValue(Actions(() {}))
          ]);
      await t.ensureVisible(find.text('Edit & Resubmit'));
      await t.tap(find.text('Edit & Resubmit'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      if (direction == TransactionType.inbound) {
        expect(find.byType(AddProductScreen), findsOneWidget);
        expect(
            t
                .widget<AddProductScreen>(find.byType(AddProductScreen))
                .existingTransaction!
                .rejectionNote,
            'Wrong quantity');
      } else {
        expect(find.byType(UseProductScreen), findsOneWidget);
        expect(
            t
                .widget<UseProductScreen>(find.byType(UseProductScreen))
                .existingTransaction!
                .rejectionNote,
            'Wrong quantity');
      }
      expect(row.status, TransactionStatus.rejected);
      expect(t.takeException(), isNull);
      await closePage(t);
    });
  }

  for (final role in [
    UserRole.worker,
    UserRole.admin,
    UserRole.accounts,
    UserRole.projectHead
  ]) {
    testWidgets(
        '$role rejected voucher keeps reason until explicit confirmation',
        (t) async {
      final site =
          ErpTestBackend.instance.tables['sites']!.first['id'] as String;
      final person = SiteStaffModel(
          id: 'worker',
          siteId: site,
          name: 'Ramesh',
          role: SiteStaffRole.worker,
          designation: 'Engineer',
          pin: 'fixture',
          modules: const [StaffModule.cashbook, StaffModule.stock],
          createdAt: DateTime(2026));
      final source = CashTransactionModel(
          id: '10000000-0000-4000-8000-000000000001',
          siteId: site,
          date: DateTime(2026, 11, 20),
          expenseTypeId: 'e72d9d18-2a33-4748-a04f-ddfdc9504a3f',
          expenseAmount: 100,
          cashInHand: 0,
          remarks: '[By: Ramesh (Engineer)] Work',
          status: TransactionStatus.rejected,
          rejectionNote: 'Wrong bill',
          updatedAt: DateTime.utc(2026, 11, 20));
      final rows = MutableCash([source]);
      final deleting = Actions(rows.remove);
      await showPage(
          t,
          Consumer(
              builder: (context, ref, _) => Scaffold(
                      body: ListView(children: [
                    for (final row in ref.watch(cashProvider).transactions)
                      VoucherEntryDetails(cash: row)
                  ]))),
          role,
          role == UserRole.worker
              ? const Size(390, 844)
              : const Size(1440, 900),
          overrides: [
            workerRejectedEntryActionsProvider.overrideWithValue(true),
            cashProvider.overrideWith((ref) => rows),
            stockProvider.overrideWith((ref) => SeededStock([])),
            activeStaffProvider.overrideWith((ref) => Selection(person)),
            rejectedEntryServiceProvider.overrideWithValue(deleting)
          ]);
      expect(
          find.textContaining('Rejection reason: Wrong bill'), findsOneWidget);
      if (role == UserRole.accounts || role == UserRole.projectHead) {
        expect(find.text('Delete / Dismiss'), findsNothing);
        expect(find.text('Edit & Resubmit'), findsNothing);
      } else {
        expect(find.text('Delete / Dismiss'), findsOneWidget);
        expect(find.text('Edit & Resubmit'),
            role == UserRole.worker ? findsOneWidget : findsNothing);
        await t.ensureVisible(find.text('Delete / Dismiss'));
        await t.tap(find.text('Delete / Dismiss'));
        await t.pumpAndSettle();
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(deleting.deleted, 0);
        expect(find.textContaining('Rejection reason: Wrong bill'),
            findsOneWidget);
        if (role == UserRole.worker) {
          await t.tap(find.text('Edit & Resubmit'));
          await t.pump();
          await t.pump(const Duration(seconds: 1));
          expect(find.byType(ExpenseFormScreen), findsOneWidget);
          expect(
              t
                  .widget<ExpenseFormScreen>(find.byType(ExpenseFormScreen))
                  .existingTransaction!
                  .rejectionNote,
              'Wrong bill');
          expect(
              t
                  .widget<ExpenseFormScreen>(find.byType(ExpenseFormScreen))
                  .existingTransaction!
                  .status,
              TransactionStatus.rejected);
          await t.scrollUntilVisible(find.text('Resubmit for approval'), 400,
              scrollable: find
                  .descendant(
                      of: find.byType(ExpenseFormScreen),
                      matching: find.byType(Scrollable))
                  .first);
          expect(find.text('Resubmit for approval'), findsOneWidget);
          Navigator.of(t.element(find.byType(ExpenseFormScreen))).pop();
          await t.pumpAndSettle();
        }
        await t.ensureVisible(find.text('Delete / Dismiss'));
        await t.tap(find.text('Delete / Dismiss'));
        await t.pumpAndSettle();
        await t.tap(find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Delete / Dismiss')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(deleting.deleted, 1);
        expect(
            find.textContaining('Rejection reason: Wrong bill'), findsNothing);
      }
      expect(source.rejectionNote, 'Wrong bill');
      expect(t.takeException(), isNull);
      await closePage(t);
    });
  }
}
