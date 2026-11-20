import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/providers/cash_provider.dart';
import 'package:skcpl_app/providers/stock_provider.dart';
import 'package:skcpl_app/screens/admin/site_history_screen.dart';
import 'dashboard_widget_test.dart'
    show SeededCash, SeededStock, showPage, closePage;
import '../support/erp_test_backend.dart';

class ChangingCash extends SeededCash {
  ChangingCash(super.rows);
  void update(List<CashTransactionModel> rows, {bool loading = false}) {
    state = CashState(transactions: rows, isLoading: loading);
  }
}

void main() {
  for (final role in [
    UserRole.admin,
    UserRole.accounts,
    UserRole.projectHead
  ]) {
    testWidgets(
        '$role site history shows pending and approved uploads and follows live cache refresh',
        (t) async {
      final site =
          ErpTestBackend.instance.tables['sites']!.first['id'] as String;
      CashTransactionModel row(
              String id, String name, TransactionStatus status) =>
          CashTransactionModel(
              id: id,
              siteId: site,
              date: DateTime(2026, 11, 20),
              expenseTypeId: 'other',
              expenseTypeName: name,
              expenseAmount: 100,
              cashInHand: 0,
              status: status,
              remarks: '[By: Worker (Engineer)]');
      final pending = row(
              'p', 'New pending voucher', TransactionStatus.pendingAccounts),
          approved = row('a', 'Approved voucher', TransactionStatus.approved);
      final cash = ChangingCash([pending, approved]);
      await showPage(t, SiteHistoryScreen(siteId: site, siteName: 'Site'), role,
          role == UserRole.admin ? const Size(390, 844) : const Size(1440, 900),
          overrides: [
            cashProvider.overrideWith((ref) => cash),
            stockProvider.overrideWith((ref) => SeededStock([]))
          ]);
      await t.tap(find.text('Imprest Cashbook'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('New pending voucher'), findsOneWidget);
      expect(find.text('Approved voucher'), findsOneWidget);
      final fresh =
          row('b', 'Uploaded from another device', TransactionStatus.approved);
      cash.update([pending, approved, fresh], loading: true);
      await t.pump();
      expect(find.text('New pending voucher'),
          findsOneWidget); // Keep last history visible during refresh.
      cash.update([pending, approved, fresh]);
      await t.pump();
      expect(find.text('Uploaded from another device'), findsOneWidget);
      await t.tap(find.byType(DropdownButton<String>));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.text('Approved').last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('New pending voucher'), findsNothing);
      expect(find.text('Approved voucher'), findsOneWidget);
      expect(t.takeException(), isNull);
      await closePage(t);
    });
  }
}
