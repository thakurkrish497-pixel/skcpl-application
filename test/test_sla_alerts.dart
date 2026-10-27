import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/site_model.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/providers/stock_provider.dart';
import 'package:skcpl_app/providers/cash_provider.dart';
import 'package:skcpl_app/providers/site_provider.dart';
import 'package:skcpl_app/providers/auth_provider.dart';
import 'package:skcpl_app/providers/sla_alert_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('36-Hour Approval SLA Alerts & Role Targeting Tests', () {
    final now = DateTime.now();
    final overdueDate = now.subtract(const Duration(hours: 40));
    final freshDate = now.subtract(const Duration(hours: 10));

    final overdueStockTx = StockTransactionModel(
      id: 'tx-overdue-1',
      siteId: 'site-hatpipliya',
      type: TransactionType.inbound,
      date: overdueDate,
      createdAt: overdueDate,
      productId: 'prod-cement',
      productName: 'Cement UltraTech',
      metricUnitId: 'unit-bag',
      metricUnitName: 'Bags',
      quantity: 50,
      sgst: 0,
      igst: 0,
      photoUrls: const [],
      status: TransactionStatus.pendingAccounts,
    );

    final freshStockTx = StockTransactionModel(
      id: 'tx-fresh-2',
      siteId: 'site-hatpipliya',
      type: TransactionType.inbound,
      date: freshDate,
      createdAt: freshDate,
      productId: 'prod-sand',
      productName: 'River Sand',
      metricUnitId: 'unit-ton',
      metricUnitName: 'Tons',
      quantity: 10,
      sgst: 0,
      igst: 0,
      photoUrls: const [],
      status: TransactionStatus.pendingAccounts,
    );

    final site = SiteModel(
      id: 'site-hatpipliya',
      name: 'Hatpipliya',
      address: 'Hatpipliya Site',
      siteLoginId: 'hp_01',
      createdAt: now.subtract(const Duration(days: 30)),
      updatedAt: now.subtract(const Duration(days: 30)),
    );

    test('Project Head receives alerts for pending stock approvals older than 36h', () {
      final projectHeadUser = UserModel(
        id: 'user-ph-1',
        email: 'ph@skcpl.com',
        role: UserRole.projectHead,
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => AuthNotifierMock(projectHeadUser)),
          stockProvider.overrideWith((ref) => StockNotifierMock([overdueStockTx, freshStockTx])),
          cashProvider.overrideWith((ref) => CashNotifierMock([])),
          activeSitesProvider.overrideWith((ref) => [site]),
        ],
      );

      final alerts = container.read(slaAlertsProvider);
      expect(alerts.length, 1);
      expect(alerts.first.siteName, 'Hatpipliya');
      expect(alerts.first.hoursElapsed, greaterThanOrEqualTo(36));
      expect(alerts.first.message, contains('Cement UltraTech'));
    });

    test('Site Worker NEVER receives approval SLA alerts (not worker task)', () {
      final workerUser = UserModel(
        id: 'user-worker-1',
        email: 'daksh@skcpl.com',
        role: UserRole.worker,
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => AuthNotifierMock(workerUser)),
          stockProvider.overrideWith((ref) => StockNotifierMock([overdueStockTx])),
          cashProvider.overrideWith((ref) => CashNotifierMock([])),
          activeSitesProvider.overrideWith((ref) => [site]),
        ],
      );

      final alerts = container.read(slaAlertsProvider);
      expect(alerts, isEmpty); // Strict guarantee: workers get 0 approval alerts
    });

    test('Accounts and Admin receive alerts for pending approvals older than 36h', () {
      final accountsUser = UserModel(
        id: 'user-acc-1',
        email: 'accounts@skcpl.com',
        role: UserRole.accounts,
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => AuthNotifierMock(accountsUser)),
          stockProvider.overrideWith((ref) => StockNotifierMock([overdueStockTx])),
          cashProvider.overrideWith((ref) => CashNotifierMock([])),
          activeSitesProvider.overrideWith((ref) => [site]),
        ],
      );

      final alerts = container.read(slaAlertsProvider);
      expect(alerts.length, 1);
    });
  });
}

class AuthNotifierMock extends StateNotifier<AuthState> implements AuthNotifier {
  AuthNotifierMock(UserModel user) : super(AuthState(user: user, isLoading: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StockNotifierMock extends StateNotifier<StockState> implements StockNotifier {
  StockNotifierMock(List<StockTransactionModel> initial)
      : super(StockState(transactions: initial));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CashNotifierMock extends StateNotifier<CashState> implements CashNotifier {
  CashNotifierMock(List<CashTransactionModel> initial)
      : super(CashState(transactions: initial));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
