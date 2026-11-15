import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_colors.dart';
import '../../models/role_permissions_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/role_access_provider.dart';
import '../../services/management_account_service.dart';
import '../../widgets/responsive_layout.dart';

/// Existing Auth accounts keep their UUIDs; only the protected server changes logins.
class RoleAccessManagementScreen extends ConsumerStatefulWidget {
  const RoleAccessManagementScreen({super.key});
  @override
  ConsumerState<RoleAccessManagementScreen> createState() =>
      _RoleAccessManagementScreenState();
}

class _RoleAccessManagementScreenState
    extends ConsumerState<RoleAccessManagementScreen> {
  final _accountsLogin = TextEditingController();
  final _accountsEmail = TextEditingController();
  final _accountsPassword = TextEditingController();
  final _headLogin = TextEditingController();
  final _headEmail = TextEditingController();
  final _headPassword = TextEditingController();
  ManagementSnapshot? _snapshot;
  RolePermissionsModel _policy = const RolePermissionsModel();
  bool _loading = true,
      _saving = false,
      _dirty = false,
      _externalChange = false;
  bool _hideAccounts = true, _hideHead = true;
  String? _error, _operation;
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  void _changed() {
    setState(() {
      _dirty = true;
      _operation = null;
    });
  }

  void _fill(ManagementSnapshot snapshot) {
    _snapshot = snapshot;
    _policy = snapshot.policy;
    _accountsLogin.text = snapshot.accounts.loginId;
    _accountsEmail.text = snapshot.accounts.email;
    _headLogin.text = snapshot.projectHead.loginId;
    _headEmail.text = snapshot.projectHead.email;
    _accountsPassword.clear();
    _headPassword.clear();
    _dirty = false;
    _externalChange = false;
    _operation = null;
    _error = null;
  }

  Future<void> _load() async {
    if (!mounted || !ref.read(authProvider).isAdmin) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await ref.read(managementAccountServiceProvider).load();
      if (!mounted) return;
      setState(() => _fill(snapshot));
      ref.read(roleAccessProvider.notifier).applyServerPolicy(snapshot.policy);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reload() async {
    if (_dirty) {
      final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('Reload saved settings?'),
                  content: const Text(
                      'This discards only your unsaved changes on this settings screen.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Keep editing')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Reload'))
                  ]));
      if (confirm != true || !mounted) return;
    }
    await _load();
  }

  void _notice(String text, {bool failed = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: failed ? AppColors.rejected : AppColors.approved,
        duration: Duration(seconds: failed ? 10 : 5)));
  }

  Future<void> _save() async {
    if (_saving || _snapshot == null || !ref.read(authProvider).isAdmin) return;
    final errors = [
      ManagementAccountService.validateLogin(_accountsLogin.text),
      ManagementAccountService.validateEmail(_accountsEmail.text),
      ManagementAccountService.validatePassword(_accountsPassword.text),
      ManagementAccountService.validateLogin(_headLogin.text),
      ManagementAccountService.validateEmail(_headEmail.text),
      ManagementAccountService.validatePassword(_headPassword.text)
    ].whereType<String>();
    if (errors.isNotEmpty) {
      _notice(errors.first, failed: true);
      return;
    }
    if (_accountsLogin.text.trim().toLowerCase() ==
            _headLogin.text.trim().toLowerCase() ||
        _accountsEmail.text.trim().toLowerCase() ==
            _headEmail.text.trim().toLowerCase()) {
      _notice('Each role needs a different Login ID and email.', failed: true);
      return;
    }
    _operation ??= const Uuid().v4();
    setState(() => _saving = true);
    try {
      final result = await ref.read(managementAccountServiceProvider).save(
          operationId: _operation!,
          current: _snapshot!,
          policy: _policy,
          accountsLogin: _accountsLogin.text,
          accountsEmail: _accountsEmail.text,
          accountsPassword: _accountsPassword.text,
          projectHeadLogin: _headLogin.text,
          projectHeadEmail: _headEmail.text,
          projectHeadPassword: _headPassword.text);
      if (!mounted) return;
      if (result.saved) {
        setState(() => _fill(result.snapshot!));
        ref
            .read(roleAccessProvider.notifier)
            .applyServerPolicy(result.snapshot!.policy);
        _notice('Login details and approval powers saved centrally.');
      } else {
        setState(() => _error = result.error);
        _notice(result.error ?? 'Save was not confirmed. Please retry.',
            failed: true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
        _notice(error.toString(), failed: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _accountsLogin,
      _accountsEmail,
      _accountsPassword,
      _headLogin,
      _headEmail,
      _headPassword
    ]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(String label, String key, TextEditingController controller,
          {bool password = false, bool hidden = true, VoidCallback? toggle}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
              key: ValueKey(key),
              controller: controller,
              enabled: !_saving,
              obscureText: password && hidden,
              autocorrect: false,
              enableSuggestions: !password,
              onChanged: (_) => _changed(),
              decoration: InputDecoration(
                  labelText: label,
                  helperText: password
                      ? 'Leave blank to keep the current password. 8+ characters for a new password.'
                      : null,
                  helperMaxLines: 3,
                  suffixIcon: password
                      ? IconButton(
                          onPressed: _saving ? null : toggle,
                          tooltip: hidden
                              ? 'Show new password'
                              : 'Hide new password',
                          icon: Icon(
                              hidden ? Icons.visibility : Icons.visibility_off))
                      : null)));
  Widget _power(String label, bool value, ValueChanged<bool> change) =>
      SwitchListTile(
          title: Text(label),
          value: value,
          onChanged: _saving
              ? null
              : (val) {
                  setState(() => change(val));
                  _changed();
                });
  Widget _card({required bool accounts}) {
    final title = accounts ? 'Accounts' : 'Project Head';
    return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$title login', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          _field('Login ID', accounts ? 'accounts-login' : 'project-head-login',
              accounts ? _accountsLogin : _headLogin),
          _field('Email', accounts ? 'accounts-email' : 'project-head-email',
              accounts ? _accountsEmail : _headEmail),
          _field(
              'New password (optional)',
              accounts ? 'accounts-password' : 'project-head-password',
              accounts ? _accountsPassword : _headPassword,
              password: true,
              hidden: accounts ? _hideAccounts : _hideHead,
              toggle: () => setState(() {
                    if (accounts) {
                      _hideAccounts = !_hideAccounts;
                    } else {
                      _hideHead = !_hideHead;
                    }
                  })),
          const Text(
              'Changing the login keeps the same account and its existing entries. Passwords are never displayed or stored in role settings.'),
          const SizedBox(height: 20),
          Text('$title approval powers',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (accounts) ...[
            _power('Cash approval', _policy.accountsCanApproveCash,
                (v) => _policy = _policy.copyWith(accountsCanApproveCash: v)),
            _power('Stock approval', _policy.accountsCanApproveStock,
                (v) => _policy = _policy.copyWith(accountsCanApproveStock: v)),
            _power(
                'Attendance approval',
                _policy.accountsCanApproveAttendance,
                (v) => _policy =
                    _policy.copyWith(accountsCanApproveAttendance: v)),
            _power('DSR approval', _policy.accountsCanApproveDSR,
                (v) => _policy = _policy.copyWith(accountsCanApproveDSR: v)),
          ] else ...[
            _power(
                'Cash approval',
                _policy.projectHeadCanApproveCash,
                (v) =>
                    _policy = _policy.copyWith(projectHeadCanApproveCash: v)),
            _power(
                'Stock approval',
                _policy.projectHeadCanApproveStock,
                (v) =>
                    _policy = _policy.copyWith(projectHeadCanApproveStock: v)),
            _power(
                'Attendance approval',
                _policy.projectHeadCanApproveAttendance,
                (v) => _policy =
                    _policy.copyWith(projectHeadCanApproveAttendance: v)),
            _power('DSR approval', _policy.projectHeadCanApproveDSR,
                (v) => _policy = _policy.copyWith(projectHeadCanApproveDSR: v)),
          ],
          const SizedBox(height: 14),
          const Text(
              'OFF bypasses that review checkpoint. Admin keeps final approval. Connected devices refresh from the server; offline devices catch up when they reconnect.'),
          const SizedBox(height: 24),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(authProvider).isAdmin;
    ref.listen<RolePermissionsModel>(roleAccessProvider, (_, next) {
      if (mounted &&
          _snapshot != null &&
          next.revision > _snapshot!.policy.revision) {
        setState(() => _externalChange = true);
      }
    });
    if (!admin) {
      return const Scaffold(
          body: Center(child: Text('Admin access is required.')));
    }
    return PopScope(
        canPop: !_saving,
        child: DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                  title: const Text('Admin: Logins & Approval Powers'),
                  actions: [
                    IconButton(
                        tooltip: 'Reload saved settings',
                        onPressed: _saving || _loading ? null : _reload,
                        icon: const Icon(Icons.refresh))
                  ],
                  bottom: const TabBar(tabs: [
                    Tab(text: 'Accounts'),
                    Tab(text: 'Project Head')
                  ])),
              body: ResponsiveContainer(
                  maxWidth: 950,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _snapshot == null
                          ? Center(
                              child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(_error ??
                                            'Secure server controls are unavailable.'),
                                        const SizedBox(height: 16),
                                        ElevatedButton(
                                            onPressed: _load,
                                            child: const Text('Retry'))
                                      ])))
                          : Column(children: [
                              if (_externalChange)
                                MaterialBanner(
                                    content: const Text(
                                        'Settings changed on another device. Reload before saving.'),
                                    actions: [
                                      TextButton(
                                          onPressed: _saving ? null : _reload,
                                          child: const Text('Reload'))
                                    ]),
                              if (_error != null)
                                Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Text(_error!,
                                        style: const TextStyle(
                                            color: AppColors.rejected))),
                              Expanded(
                                  child: TabBarView(children: [
                                _card(accounts: true),
                                _card(accounts: false)
                              ])),
                            ])),
              bottomNavigationBar: SafeArea(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ElevatedButton.icon(
                          onPressed: _saving || _loading || _snapshot == null
                              ? null
                              : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.save),
                          label: Text(_saving
                              ? 'Saving on server…'
                              : 'Save login details & approval powers')))),
            )));
  }
}
