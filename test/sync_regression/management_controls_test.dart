import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:skcpl_app/models/role_permissions_model.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/providers/auth_provider.dart';
import 'package:skcpl_app/providers/role_access_provider.dart';
import 'package:skcpl_app/screens/admin/role_access_management_screen.dart';
import 'package:skcpl_app/services/auth_service.dart';
import 'package:skcpl_app/services/management_account_service.dart';
import 'package:skcpl_app/services/role_access_service.dart';
import '../support/erp_test_backend.dart';

const policy = RolePermissionsModel();
const snapshot = ManagementSnapshot(
    policy: policy,
    accounts: ManagementAccount(
        userId: ErpTestBackend.accountsId,
        loginId: 'accounts',
        email: 'accounts@skcpl.com',
        credentialRevision: 0),
    projectHead: ManagementAccount(
        userId: ErpTestBackend.headId,
        loginId: 'project',
        email: 'projecthead@skcpl.com',
        credentialRevision: 0));
Map<String, dynamic> snapshotJson() => {
      'policy': policy.toJson(),
      'roles': {
        'accounts': {
          'user_id': snapshot.accounts.userId,
          'login_id': 'accounts',
          'email': 'accounts@skcpl.com',
          'credential_revision': 0
        },
        'project_head': {
          'user_id': snapshot.projectHead.userId,
          'login_id': 'project',
          'email': 'projecthead@skcpl.com',
          'credential_revision': 0
        }
      }
    };

class FixedAuth extends AuthNotifier {
  FixedAuth(String role) : super(AuthService()) {
    state = AuthState(
        user: UserModel.fromJson(ErpTestBackend.instance.tables['users']!
            .firstWhere((r) => r['role'] == role)));
  }
  @override
  Future<void> checkSession() async {}
}

class FixedPolicy extends RoleAccessService {
  @override
  Future<RolePermissionsModel> getPermissions(
          {bool forceRefresh = false}) async =>
      policy;
}

class FakeManagement extends ManagementAccountService {
  int loads = 0, saves = 0;
  String? loadError;
  final operations = <String>[];
  String? password;
  Completer<ManagementSaveResult>? pending;
  ManagementSaveResult result = const ManagementSaveResult(snapshot: snapshot);
  @override
  Future<ManagementSnapshot> load() async {
    loads++;
    if (loadError != null) throw StateError(loadError!);
    return snapshot;
  }

  @override
  Future<ManagementSaveResult> save(
      {required String operationId,
      required ManagementSnapshot current,
      required RolePermissionsModel policy,
      required String accountsLogin,
      required String accountsEmail,
      String accountsPassword = '',
      required String projectHeadLogin,
      required String projectHeadEmail,
      String projectHeadPassword = ''}) async {
    saves++;
    operations.add(operationId);
    password = accountsPassword;
    if (pending != null) return await pending!.future;
    return result;
  }
}

Future<void> render(WidgetTester tester, FakeManagement service,
    {String role = 'admin', Size size = const Size(390, 844)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: [
    authProvider.overrideWith((ref) => FixedAuth(role)),
    roleAccessServiceProvider.overrideWithValue(FixedPolicy()),
    managementAccountServiceProvider.overrideWithValue(service)
  ], child: const MaterialApp(home: RoleAccessManagementScreen())));
  await tester.pumpAndSettle();
}

Finder saveButton() => find.text('Save login details & approval powers');
void main() {
  test(
      'All eight powers round-trip; new Accounts checkpoints preserve previous defaults',
      () {
    expect(policy.accountsCanApproveAttendance, isFalse);
    expect(policy.accountsCanApproveDSR, isFalse);
    final data = policy.toJson();
    for (final key
        in data.keys.where((k) => k.contains('_can_approve_')).toList()) {
      data[key] = false;
    }
    final round = RolePermissionsModel.fromJson(data).toJson();
    expect(
        round.entries.where((e) => e.key.contains('_can_approve_')).length, 8);
    expect(
        round.entries
            .where((e) => e.key.contains('_can_approve_'))
            .every((e) => e.value == false),
        isTrue);
  });
  test('Historical plaintext passwords are discarded from serialization', () {
    final value = RolePermissionsModel.fromJson({
      ...policy.toJson(),
      'accounts_password': 'old-secret',
      'project_head_password': 'other-secret'
    });
    expect(value.accountsPassword, isEmpty);
    expect(value.projectHeadPassword, isEmpty);
    expect(jsonEncode(value.toJson()), isNot(contains('secret')));
  });
  test(
      'Login and password validation covers reserved IDs, whitespace and UTF8 limits',
      () {
    for (final id in [
      'admin',
      'ADMIN',
      'administrator',
      'a',
      'bad id',
      'bad@email.com'
    ]) {
      expect(ManagementAccountService.validateLogin(id), isNotNull);
    }
    expect(ManagementAccountService.validateLogin('finance.team_01'), isNull);
    expect(ManagementAccountService.validatePassword(''), isNull);
    expect(ManagementAccountService.validatePassword('        '), isNotNull);
    expect(ManagementAccountService.validatePassword('123456'), isNotNull);
    expect(ManagementAccountService.validatePassword(' Good pass '), isNull);
    expect(
        ManagementAccountService.validatePassword(List.filled(25, '₹').join()),
        isNotNull);
    expect(ManagementAccountService.validateEmail('invalid'), isNotNull);
  });
  test(
      'Service sends stable identities, all powers and raw password only to protected function',
      () async {
    late Map<String, dynamic> sent;
    final client = SupabaseClient('http://management.invalid', 'fixture',
        httpClient: MockClient((r) async {
      expect(r.url.path, endsWith('/skcpl-management-control'));
      sent = jsonDecode(r.body);
      return http.Response(
          jsonEncode({'state': 'saved', 'snapshot': snapshotJson()}), 200,
          headers: {'content-type': 'application/json'});
    }));
    final service = ManagementAccountService(client);
    final result = await service.save(
        operationId: 'operation',
        current: snapshot,
        policy: policy,
        accountsLogin: ' FINANCE ',
        accountsEmail: ' FINANCE@SKCPL.COM ',
        accountsPassword: ' New secret ',
        projectHeadLogin: 'project',
        projectHeadEmail: 'projecthead@skcpl.com');
    expect(result.saved, isTrue);
    expect(sent['roles']['accounts']['user_id'], ErpTestBackend.accountsId);
    expect(sent['roles']['accounts']['login_id'], 'finance');
    expect(sent['roles']['accounts']['new_password'], ' New secret ');
    expect(sent['roles']['project_head'].containsKey('new_password'), isFalse);
    expect((sent['permissions'] as Map).length, 8);
    await client.dispose();
  });
  test('Partial server reply is never treated as a saved policy', () async {
    final client = SupabaseClient('http://management.invalid', 'fixture',
        httpClient: MockClient((r) async => http.Response(
            jsonEncode({'state': 'partial', 'error': 'Retry this Save'}), 207,
            headers: {'content-type': 'application/json'})));
    final result = await ManagementAccountService(client).save(
        operationId: 'operation',
        current: snapshot,
        policy: policy,
        accountsLogin: 'accounts',
        accountsEmail: 'accounts@skcpl.com',
        projectHeadLogin: 'project',
        projectHeadEmail: 'projecthead@skcpl.com');
    expect(result.saved, isFalse);
    expect(result.partial, isTrue);
    expect(result.error, 'Retry this Save');
    await client.dispose();
  });
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1440, 900)
  ]) {
    testWidgets('Admin form fits ${size.width} x ${size.height}',
        (tester) async {
      await render(tester, FakeManagement(), size: size);
      expect(find.byKey(const ValueKey('accounts-login')), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNWidgets(4));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Project Head').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('project-head-login')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'Save disables controls and shows spinner until acknowledged; success clears password',
      (tester) async {
    final service = FakeManagement()
      ..pending = Completer<ManagementSaveResult>();
    await render(tester, service);
    await tester.enterText(
        find.byKey(const ValueKey('accounts-password')), ' New secret ');
    await tester.tap(saveButton());
    await tester.pump();
    expect(find.text('Saving on server…'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('accounts-login')))
            .enabled,
        isFalse);
    expect(service.saves, 1);
    service.pending!.complete(const ManagementSaveResult(snapshot: snapshot));
    await tester.pumpAndSettle();
    expect(find.text('Login details and approval powers saved centrally.'),
        findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('accounts-password')))
            .controller!
            .text,
        isEmpty);
    expect(service.password, ' New secret ');
  });
  testWidgets(
      'Failed partial Save keeps edits and retries the same operation safely',
      (tester) async {
    final service = FakeManagement()
      ..result = const ManagementSaveResult(
          error: 'Partial server save. Retry.', partial: true);
    await render(tester, service);
    await tester.enterText(
        find.byKey(const ValueKey('accounts-password')), 'New secret');
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(find.text('Login details and approval powers saved centrally.'),
        findsNothing);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('accounts-password')))
            .controller!
            .text,
        'New secret');
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(service.operations[0], service.operations[1]);
  });
  testWidgets('Duplicate aliases are blocked before contacting server',
      (tester) async {
    final service = FakeManagement();
    await render(tester, service);
    await tester.enterText(
        find.byKey(const ValueKey('accounts-login')), 'project');
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(service.saves, 0);
    expect(find.text('Each role needs a different Login ID and email.'),
        findsOneWidget);
  });
  testWidgets('Non Admin cannot load or save credentials', (tester) async {
    final service = FakeManagement();
    await render(tester, service, role: 'accounts');
    expect(service.loads, 0);
    expect(service.saves, 0);
    expect(find.text('Admin access is required.'), findsOneWidget);
  });
  testWidgets(
      'Missing backend gives explicit error and Retry without false success',
      (tester) async {
    final service = FakeManagement()
      ..loadError = 'Secure backend needs deployment';
    await render(tester, service);
    expect(
        find.textContaining('Secure backend needs deployment'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(
                ElevatedButton, 'Save login details & approval powers'))
            .onPressed,
        isNull);
  });
  test('Credential-revision signout leaves offline data untouched', () async {
    SharedPreferences.setMockInitialValues({
      'pending_cash_transactions': '["cash"]',
      'pending_stock_transactions': '["stock"]',
      'expense_draft_v1_site': 'saved-draft',
      'skcpl_management_session_revision_v1_${ErpTestBackend.accountsId}': 0
    });
    final auth = AuthService();
    expect(await auth.acceptsCredentialRevision(ErpTestBackend.accountsId, 0),
        isTrue);
    expect(await auth.acceptsCredentialRevision(ErpTestBackend.accountsId, 1),
        isFalse);
    await auth.signOutForCredentialChange();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pending_cash_transactions'), '["cash"]');
    expect(prefs.getString('pending_stock_transactions'), '["stock"]');
    expect(prefs.getString('expense_draft_v1_site'), 'saved-draft');
  });
  test(
      'Configured Login ID resolves centrally and keeps the original account UUID',
      () async {
    final backend = ErpTestBackend.instance;
    backend.tables['users']!
            .firstWhere((r) => r['role'] == 'accounts')['email'] =
        'finance@skcpl.com';
    final client =
        SupabaseClient('http://erp.test.invalid', 'fixture-public-key',
            httpClient: MockClient((r) async {
      if (r.url.path.endsWith('/rpc/skcpl_resolve_management_login')) {
        expect(jsonDecode(r.body)['p_login'], 'finance.team');
        return backend.response(r, 'finance@skcpl.com');
      }
      return backend.handle(r);
    }));
    final user = await AuthService(client)
        .signInWithEmail(email: ' FINANCE.TEAM ', password: 'new-password');
    expect(user.id, ErpTestBackend.accountsId);
    expect(user.isAccounts, isTrue);
    await client.dispose();
  });
  test(
      'A renamed old Login ID cannot fall back to a hardcoded management email',
      () async {
    var authCalls = 0;
    final client =
        SupabaseClient('http://erp.test.invalid', 'fixture-public-key',
            httpClient: MockClient((r) async {
      if (r.url.path.endsWith('/rpc/skcpl_resolve_management_login')) {
        return ErpTestBackend.instance.response(r, null);
      }
      authCalls++;
      return ErpTestBackend.instance.handle(r);
    }));
    await expectLater(
        AuthService(client)
            .signInWithEmail(email: 'accounts', password: 'old-password'),
        throwsA(isA<AuthException>()));
    expect(authCalls, 0);
    await client.dispose();
  });
  test('A permission failure never falls back to an offline approval policy',
      () async {
    final client = SupabaseClient(
        'http://erp.test.invalid', 'fixture-public-key',
        httpClient: MockClient((r) async => ErpTestBackend.instance.response(
            r, {'code': '42501', 'message': 'Not authorized'},
            status: 403)));
    await expectLater(RoleAccessService(client).getVerifiedPermissions(),
        throwsA(isA<PostgrestException>()));
    await client.dispose();
  });
  testWidgets(
      'A newer central revision warns Admin without erasing unsaved edits',
      (tester) async {
    await render(tester, FakeManagement());
    await tester.enterText(
        find.byKey(const ValueKey('accounts-login')), 'unsaved.finance');
    final container = ProviderScope.containerOf(
        tester.element(find.byType(RoleAccessManagementScreen)));
    container
        .read(roleAccessProvider.notifier)
        .applyServerPolicy(policy.copyWith(revision: 1));
    await tester.pumpAndSettle();
    expect(
        find.text('Settings changed on another device. Reload before saving.'),
        findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('accounts-login')))
            .controller!
            .text,
        'unsaved.finance');
  });
  test(
      'Credential change signs out the old role session while preserving queued work',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_cash_transactions', 'retained-queue');
    await prefs.setString('expense_draft_v1_site', 'retained-draft');
    final notifier = FixedAuth('accounts');
    addTearDown(notifier.dispose);
    await notifier.enforceCredentialRevision(
        policy.copyWith(accountsCredentialRevision: 1));
    expect(notifier.state.user, isNull);
    expect(notifier.state.error, contains('changed by Admin'));
    expect(prefs.getString('pending_cash_transactions'), 'retained-queue');
    expect(prefs.getString('expense_draft_v1_site'), 'retained-draft');
  });
}
