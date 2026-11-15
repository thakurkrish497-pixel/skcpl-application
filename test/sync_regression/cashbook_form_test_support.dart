export 'package:flutter/material.dart';
export 'package:flutter_riverpod/flutter_riverpod.dart';
export 'package:flutter_test/flutter_test.dart';
export 'package:skcpl_app/core/theme/app_theme.dart';
export 'package:skcpl_app/models/cash_transaction_model.dart';
export 'package:skcpl_app/models/user_model.dart';
export 'package:skcpl_app/providers/auth_provider.dart';
export 'package:skcpl_app/providers/cash_provider.dart';
export 'package:skcpl_app/screens/cashbook/expense_form_screen.dart';
export 'package:skcpl_app/services/draft_store.dart';
export 'package:skcpl_app/services/offline_service.dart';
export 'package:skcpl_app/services/submission_support.dart';
export 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
export 'dashboard_widget_test.dart' show FixedAuth;
export 'package:skcpl_app/services/cash_service.dart';
export 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/core/theme/app_theme.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/providers/auth_provider.dart';
import 'package:skcpl_app/providers/cash_provider.dart';
import 'package:skcpl_app/screens/cashbook/expense_form_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'dashboard_widget_test.dart' show FixedAuth;
import 'package:skcpl_app/services/cash_service.dart';
import 'package:skcpl_app/services/submission_support.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';

class FormCash extends CashService {
  Future<CashTransactionModel> Function(CashTransactionModel)? onSubmit;
  FormCash() : super(Supabase.instance.client);
  @override
  Future<CashTransactionModel> submitTransaction(
      CashTransactionModel tx) async {
    final result = onSubmit == null ? tx : await onSubmit!(tx);
    return result.copyWith(id: submissionId(result.id));
  }

  @override
  Future<List<CashTransactionModel>> getAllTransactions(
          {TransactionStatus? status}) async =>
      [];
}

Future<void> settleForm(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> showForm(WidgetTester tester, FormCash service) async {
  await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => FixedAuth(UserRole.worker)),
        cashServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
          theme: AppTheme.darkTheme, home: const ExpenseFormScreen())));
  await settleForm(tester);
}

Future<void> fillExpense(WidgetTester tester) async {
  final category = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(category);
  await tester.tap(category);
  await settleForm(tester);
  await tester.tap(find.text('General').last);
  await settleForm(tester);
  final description =
      find.widgetWithText(TextFormField, 'Description of Expenses *');
  await tester.ensureVisible(description);
  await tester.enterText(description, 'Site transport');
  final amount = find.widgetWithText(TextFormField, 'Expense Amount (₹) *');
  await tester.ensureVisible(amount);
  await tester.enterText(amount, '100');
  tester.testTextInput.hide();
  await settleForm(tester);
}

Future<void> tapAction(WidgetTester tester, String text) async {
  ScaffoldMessenger.of(tester.element(find.byType(ExpenseFormScreen)))
      .clearSnackBars();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.scrollUntilVisible(find.text(text), 250,
      scrollable: find.byType(Scrollable).first);
  await settleForm(tester);
  await Scrollable.ensureVisible(tester.element(find.text(text)),
      alignment: 0.5);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text(text));
  await settleForm(tester);
}
