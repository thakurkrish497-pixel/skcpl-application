import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/providers/cash_provider.dart';
import 'package:skcpl_app/providers/stock_provider.dart';
import 'package:skcpl_app/providers/auth_provider.dart';
import 'package:skcpl_app/providers/role_access_provider.dart';
import 'package:skcpl_app/widgets/workflow_monitor_panel.dart';
import 'package:skcpl_app/services/cash_service.dart';
import 'package:skcpl_app/services/stock_service.dart';
import 'workflow_monitor_test.dart' show FixedMonitorPolicy;
import 'dashboard_widget_test.dart' show FixedAuth;
import 'package:skcpl_app/models/user_model.dart';

class CountCash extends CashService {
  int calls = 0;
  @override
  Future<List<CashTransactionModel>> getPendingForAccounts() async {
    calls++;
    return [];
  }
}

class CountStock extends StockService {
  int calls = 0;
  @override
  Future<List<StockTransactionModel>> getPendingForAccounts() async {
    calls++;
    return [];
  }
}

class Signals extends StateNotifier<CashState> implements CashNotifier {
  Signals() : super(const CashState());
  void event() {
    state = CashState(
        transactions: List<CashTransactionModel>.empty(growable: true));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final unmount in [false, true]) {
    testWidgets(
        unmount
            ? 'Unmounting before debounce makes no workflow reads'
            : 'Rapid realtime signals coalesce into one workflow read',
        (t) async {
      final cash = CountCash();
      final stock = CountStock();
      final signals = Signals();
      await t.pumpWidget(ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => FixedAuth(UserRole.accounts)),
            roleAccessProvider.overrideWith((ref) => FixedMonitorPolicy()),
            cashServiceProvider.overrideWithValue(cash),
            stockServiceProvider.overrideWithValue(stock),
            cashProvider.overrideWith((ref) => signals),
          ],
          child:
              const MaterialApp(home: Scaffold(body: WorkflowMonitorPanel()))));
      for (var i = 0; i < 5; i++) {
        signals.event();
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(cash.calls, 0);
      expect(stock.calls, 0);
      if (unmount) {
        await t.pumpWidget(const SizedBox());
      }
      await t.pump(const Duration(milliseconds: 450));
      await t.pump();
      expect(cash.calls, unmount ? 0 : 1);
      expect(stock.calls, unmount ? 0 : 1);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
    });
  }
}
