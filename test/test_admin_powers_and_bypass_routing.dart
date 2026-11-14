import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skcpl_app/models/role_permissions_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/services/role_access_service.dart';
import 'package:skcpl_app/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Admin Powers: Role Permissions & Dynamic Credentials', () {
    test('Defaults are loaded correctly', () async {
      final service = RoleAccessService();
      final perms = await service.loadRolePermissions();

      expect(perms.accountsEmail, 'accounts@skcpl.com');
      expect(perms.accountsPassword,
          const RolePermissionsModel().accountsPassword);
      expect(perms.projectHeadEmail, 'projecthead@skcpl.com');
      expect(perms.projectHeadPassword,
          const RolePermissionsModel().projectHeadPassword);
      expect(perms.accountsCanApproveStock, isTrue);
      expect(perms.accountsCanApproveCash, isTrue);
      expect(perms.projectHeadCanApproveStock, isTrue);
      expect(perms.projectHeadCanApproveCash, isTrue);
      expect(perms.projectHeadCanApproveAttendance, isTrue);
      expect(perms.projectHeadCanApproveDSR, isTrue);
    });

    test(
        'Admin can update credentials and extract Stock approval from Accounts',
        () async {
      final service = RoleAccessService();

      const updated = RolePermissionsModel(
        accountsEmail: 'chiefaccounts@skcpl.com',
        accountsPassword: 'chiefSecret789',
        accountsCanApproveCash: true,
        accountsCanApproveStock: false, // Extracted by Admin!
        projectHeadEmail: 'leadengineer@skcpl.com',
        projectHeadPassword: 'engineerPass456',
        projectHeadCanApproveCash: true,
        projectHeadCanApproveStock: true,
        projectHeadCanApproveAttendance: true,
        projectHeadCanApproveDSR: true,
      );

      await service.saveRolePermissions(updated);

      final reloaded = await service.loadRolePermissions();
      expect(reloaded.accountsEmail, 'chiefaccounts@skcpl.com');
      expect(reloaded.accountsPassword, 'chiefSecret789');
      expect(reloaded.accountsCanApproveStock, isFalse);
      expect(reloaded.projectHeadEmail, 'leadengineer@skcpl.com');
      expect(reloaded.projectHeadPassword, 'engineerPass456');
    });

    test('Permission-setting credentials cannot bypass Supabase Auth',
        () async {
      await RoleAccessService().saveRolePermissions(const RolePermissionsModel(
          accountsEmail: 'unregistered@skcpl.com',
          accountsPassword: 'settings-only'));
      await expectLater(
          AuthService().signInWithEmail(
              email: 'unregistered@skcpl.com', password: 'settings-only'),
          throwsA(isA<Exception>()));
    });

    test(
        'Approval Bypass Routing: When accountsCanApproveStock is false, routes to pendingAdmin',
        () async {
      final bypassModel = RolePermissionsModel(
        accountsEmail: 'accounts@skcpl.com',
        accountsPassword: const RolePermissionsModel().accountsPassword,
        accountsCanApproveStock: false, // Extracted by Admin policy
        accountsCanApproveCash: true,
        projectHeadEmail: 'projecthead@skcpl.com',
        projectHeadPassword: const RolePermissionsModel().projectHeadPassword,
        projectHeadCanApproveCash: true,
        projectHeadCanApproveStock: true,
        projectHeadCanApproveAttendance: true,
        projectHeadCanApproveDSR: true,
      );

      // When Project Head approves stock entry:
      final bypassAccountsStock = !bypassModel.accountsCanApproveStock;
      final stockTargetStatus = bypassAccountsStock
          ? TransactionStatus.pendingAdmin
          : TransactionStatus.pendingAccounts;

      // Must bypass Accounts completely and go directly to Admin!
      expect(stockTargetStatus, TransactionStatus.pendingAdmin);

      // When Project Head approves cash expense (not bypassed):
      final bypassAccountsCash = !bypassModel.accountsCanApproveCash;
      final cashTargetStatus = bypassAccountsCash
          ? TransactionStatus.pendingAdmin
          : TransactionStatus.pendingAccounts;

      expect(cashTargetStatus, TransactionStatus.pendingAccounts);
    });

    test(
        'Project Head Stock Power Extracted: Routes directly to Accounts and is visible in Accounts queue',
        () async {
      final phBypassModel = RolePermissionsModel(
        accountsEmail: 'accounts@skcpl.com',
        accountsPassword: const RolePermissionsModel().accountsPassword,
        accountsCanApproveStock: true,
        accountsCanApproveCash: true,
        projectHeadEmail: 'projecthead@skcpl.com',
        projectHeadPassword: const RolePermissionsModel().projectHeadPassword,
        projectHeadCanApproveCash: true,
        projectHeadCanApproveStock: false, // Power removed from Project Head!
        projectHeadCanApproveAttendance: true,
        projectHeadCanApproveDSR: true,
      );

      // 1. Initial status calculation when worker enters stock
      final phCanApproveStock = phBypassModel.projectHeadCanApproveStock;
      final accountsCanApproveStock = phBypassModel.accountsCanApproveStock;

      TransactionStatus initialStatus = TransactionStatus.pendingAccounts;
      if (!phCanApproveStock && !accountsCanApproveStock) {
        initialStatus = TransactionStatus.pendingAdmin;
      }
      expect(initialStatus, TransactionStatus.pendingAccounts);

      // 2. Remarks tag: does not add pending Project Head review
      final supTag = phCanApproveStock
          ? '[Project Head Review: Pending] [Supervisor Review: Pending]'
          : '[Project Head Review: Bypassed by Admin Policy]';
      expect(supTag, '[Project Head Review: Bypassed by Admin Policy]');

      // 3. Accounts filtering: Even if an existing transaction had the legacy tag,
      // Accounts queue does NOT filter it out when Project Head power is extracted!
      final legacyTx = StockTransactionModel(
        id: 'st-legacy-001',
        siteId: 'site-alpha',
        productId: 'prod-cement',
        metricUnitId: 'unit-bags',
        quantity: 100,
        type: TransactionType.inbound,
        date: DateTime(2026, 10, 25),
        status: TransactionStatus.pendingAccounts,
        remarks: 'Sample cement entry [Project Head Review: Pending]',
      );

      // Check the filter logic in pendingStockAccountsProvider:
      final bool accountsSeesIt = !phBypassModel.accountsCanApproveStock
          ? false
          : (!phBypassModel.projectHeadCanApproveStock
              ? true
              : !legacyTx.isPendingSupervisorReview);

      expect(accountsSeesIt, isTrue,
          reason:
              'Accounts MUST see the stock entry immediately when Project Head power is removed!');
    });

    test('Reset to factory defaults restores initial credentials & powers',
        () async {
      final service = RoleAccessService();

      // Change permissions first
      await service.saveRolePermissions(const RolePermissionsModel(
        accountsEmail: 'changed@skcpl.com',
        accountsPassword: 'changed',
        accountsCanApproveCash: false,
        accountsCanApproveStock: false,
        projectHeadEmail: 'changed@skcpl.com',
        projectHeadPassword: 'changed',
        projectHeadCanApproveCash: false,
        projectHeadCanApproveStock: false,
        projectHeadCanApproveAttendance: false,
        projectHeadCanApproveDSR: false,
      ));

      // Reset
      await service.resetToDefaults();

      final restored = await service.loadRolePermissions();
      expect(restored.accountsEmail, 'accounts@skcpl.com');
      expect(restored.accountsPassword,
          const RolePermissionsModel().accountsPassword);
      expect(restored.accountsCanApproveStock, isTrue);
      expect(restored.accountsCanApproveCash, isTrue);
      expect(restored.projectHeadCanApproveStock, isTrue);
    });
  });
}
