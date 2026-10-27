import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/role_permissions_model.dart';
import '../../providers/role_access_provider.dart';

/// Admin Power Screen: Modify login credentials (ID/Password) for Accounts & Project Head,
/// and dynamically grant or extract granular approval powers (e.g. bypass Accounts for Stock).
class RoleAccessManagementScreen extends ConsumerStatefulWidget {
  const RoleAccessManagementScreen({super.key});

  @override
  ConsumerState<RoleAccessManagementScreen> createState() =>
      _RoleAccessManagementScreenState();
}

class _RoleAccessManagementScreenState
    extends ConsumerState<RoleAccessManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Accounts Form Controllers
  final _accountsEmailController = TextEditingController();
  final _accountsPasswordController = TextEditingController();
  bool _obscureAccountsPassword = true;
  bool _accountsCanApproveCash = true;
  bool _accountsCanApproveStock = true;

  // Project Head Form Controllers
  final _projectHeadEmailController = TextEditingController();
  final _projectHeadPasswordController = TextEditingController();
  bool _obscureProjectHeadPassword = true;
  bool _projectHeadCanApproveCash = true;
  bool _projectHeadCanApproveStock = true;
  bool _projectHeadCanApproveAttendance = true;
  bool _projectHeadCanApproveDSR = true;

  bool _isSaving = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _loadCurrentPermissions();
      _isInitialized = true;
    }
  }

  void _loadCurrentPermissions() {
    final permissions = ref.read(roleAccessProvider);
    _accountsEmailController.text = permissions.accountsEmail;
    _accountsPasswordController.text = permissions.accountsPassword;
    _accountsCanApproveCash = permissions.accountsCanApproveCash;
    _accountsCanApproveStock = permissions.accountsCanApproveStock;

    _projectHeadEmailController.text = permissions.projectHeadEmail;
    _projectHeadPasswordController.text = permissions.projectHeadPassword;
    _projectHeadCanApproveCash = permissions.projectHeadCanApproveCash;
    _projectHeadCanApproveStock = permissions.projectHeadCanApproveStock;
    _projectHeadCanApproveAttendance = permissions.projectHeadCanApproveAttendance;
    _projectHeadCanApproveDSR = permissions.projectHeadCanApproveDSR;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _accountsEmailController.dispose();
    _accountsPasswordController.dispose();
    _projectHeadEmailController.dispose();
    _projectHeadPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveAllChanges() async {
    final accountsEmail = _accountsEmailController.text.trim();
    final accountsPassword = _accountsPasswordController.text.trim();
    final phEmail = _projectHeadEmailController.text.trim();
    final phPassword = _projectHeadPasswordController.text.trim();

    if (accountsEmail.isEmpty || accountsPassword.isEmpty) {
      _showSnack('Accounts Email & Password cannot be empty', isError: true);
      return;
    }

    if (phEmail.isEmpty || phPassword.isEmpty) {
      _showSnack('Project Head Email & Password cannot be empty', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    final updatedModel = RolePermissionsModel(
      accountsEmail: accountsEmail,
      accountsPassword: accountsPassword,
      accountsCanApproveCash: _accountsCanApproveCash,
      accountsCanApproveStock: _accountsCanApproveStock,
      projectHeadEmail: phEmail,
      projectHeadPassword: phPassword,
      projectHeadCanApproveCash: _projectHeadCanApproveCash,
      projectHeadCanApproveStock: _projectHeadCanApproveStock,
      projectHeadCanApproveAttendance: _projectHeadCanApproveAttendance,
      projectHeadCanApproveDSR: _projectHeadCanApproveDSR,
    );

    final ok = await ref
        .read(roleAccessProvider.notifier)
        .saveRolePermissions(updatedModel);

    setState(() => _isSaving = false);

    if (mounted) {
      if (ok) {
        _showSnack('Role access & approval routing updated successfully!');
      } else {
        _showSnack('Saved locally. (Sync to remote backend pending)', isError: false);
      }
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.goldAccent),
            SizedBox(width: 8),
            Text('Reset to Defaults?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'This will restore factory default IDs, passwords, and grant all approval powers to Accounts & Project Head.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.goldAccent),
            child: const Text('Reset Defaults', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isSaving = true);
      await ref.read(roleAccessProvider.notifier).resetToDefaults();
      _loadCurrentPermissions();
      setState(() => _isSaving = false);
      _showSnack('Restored system defaults for all roles');
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.rejected : AppColors.approved,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: const Text('Admin Power: Role Control'),
        backgroundColor: AppColors.surfaceDark,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.restore_rounded, color: AppColors.goldAccent),
            tooltip: 'Reset to Factory Defaults',
            onPressed: _isSaving ? null : _resetToDefaults,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.goldAccent,
          labelColor: AppColors.goldAccent,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(
              icon: Icon(Icons.account_balance_rounded),
              text: 'Accounts Control',
            ),
            Tab(
              icon: Icon(Icons.engineering_rounded),
              text: 'Project Head Control',
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            border: Border(top: BorderSide(color: AppColors.cardBorder)),
          ),
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveAllChanges,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.shield_rounded, color: Colors.black),
            label: Text(
              _isSaving ? 'Saving Policy...' : 'Save & Enforce Admin Powers',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.goldAccent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── TAB 1: ACCOUNTS CONTROL ──
          SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRoutingExplanationBanner(
                  title: 'Dynamic Routing & Verification Bypass',
                  description:
                      'If you extract (turn OFF) Stock or Cash approval power from Accounts, those entries will automatically bypass the Accounts queue and flow directly from Project Head to Admin for final approval.',
                  accentColor: AppColors.approved,
                  icon: Icons.alt_route_rounded,
                ),
                const SizedBox(height: 20),

                // Credentials Card
                _buildCredentialsCard(
                  roleName: 'Accounts Officer',
                  roleIcon: Icons.account_balance_rounded,
                  accentColor: AppColors.approved,
                  emailController: _accountsEmailController,
                  passwordController: _accountsPasswordController,
                  obscurePassword: _obscureAccountsPassword,
                  onToggleObscure: () => setState(
                    () => _obscureAccountsPassword = !_obscureAccountsPassword,
                  ),
                ),
                const SizedBox(height: 20),

                // Approval Powers Card
                _buildApprovalPowersCard(
                  title: 'Accounts Verification Powers',
                  subtitle: 'Enable or extract approval authority from the Accounts role',
                  accentColor: AppColors.approved,
                  toggles: [
                    _ApprovalToggleItem(
                      title: 'Stock Entry Approval Power',
                      description: _accountsCanApproveStock
                          ? 'NORMAL FLOW: Project Head → Accounts → Admin'
                          : 'BYPASS ACTIVE: Project Head → Admin directly (Accounts bypassed)',
                      value: _accountsCanApproveStock,
                      icon: Icons.inventory_2_rounded,
                      onChanged: (val) => setState(() => _accountsCanApproveStock = val),
                    ),
                    _ApprovalToggleItem(
                      title: 'Cash Expense Approval Power',
                      description: _accountsCanApproveCash
                          ? 'NORMAL FLOW: Project Head → Accounts → Admin'
                          : 'BYPASS ACTIVE: Project Head → Admin directly (Accounts bypassed)',
                      value: _accountsCanApproveCash,
                      icon: Icons.currency_rupee_rounded,
                      onChanged: (val) => setState(() => _accountsCanApproveCash = val),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),

          // ── TAB 2: PROJECT HEAD CONTROL ──
          SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRoutingExplanationBanner(
                  title: 'Project Head Authority Configuration',
                  description:
                      'Control the initial verification powers of the Project Head. Project Head sits before Accounts & Admin in all operational workflows.',
                  accentColor: AppColors.waveCyan,
                  icon: Icons.engineering_rounded,
                ),
                const SizedBox(height: 20),

                // Credentials Card
                _buildCredentialsCard(
                  roleName: 'Project Head',
                  roleIcon: Icons.engineering_rounded,
                  accentColor: AppColors.waveCyan,
                  emailController: _projectHeadEmailController,
                  passwordController: _projectHeadPasswordController,
                  obscurePassword: _obscureProjectHeadPassword,
                  onToggleObscure: () => setState(
                    () => _obscureProjectHeadPassword = !_obscureProjectHeadPassword,
                  ),
                ),
                const SizedBox(height: 20),

                // Approval Powers Card
                _buildApprovalPowersCard(
                  title: 'Project Head Verification Powers',
                  subtitle: 'Enable or disable Project Head approval in each functional module',
                  accentColor: AppColors.waveCyan,
                  toggles: [
                    _ApprovalToggleItem(
                      title: 'Stock Review & Approval Power',
                      description: _projectHeadCanApproveStock
                          ? 'Project Head must verify & approve site stock entries first'
                          : 'EXTRACTED: Project Head cannot approve stock entries',
                      value: _projectHeadCanApproveStock,
                      icon: Icons.inventory_2_rounded,
                      onChanged: (val) =>
                          setState(() => _projectHeadCanApproveStock = val),
                    ),
                    _ApprovalToggleItem(
                      title: 'Cash Expense Approval Power',
                      description: _projectHeadCanApproveCash
                          ? 'Project Head must review & forward cash expenses first'
                          : 'EXTRACTED: Project Head cannot approve cash expenses',
                      value: _projectHeadCanApproveCash,
                      icon: Icons.account_balance_wallet_rounded,
                      onChanged: (val) =>
                          setState(() => _projectHeadCanApproveCash = val),
                    ),
                    _ApprovalToggleItem(
                      title: 'Staff Attendance Verification Power',
                      description: _projectHeadCanApproveAttendance
                          ? 'Project Head approves daily staff attendance & punch-ins'
                          : 'EXTRACTED: Attendance verification bypassed to Admin',
                      value: _projectHeadCanApproveAttendance,
                      icon: Icons.fact_check_rounded,
                      onChanged: (val) =>
                          setState(() => _projectHeadCanApproveAttendance = val),
                    ),
                    _ApprovalToggleItem(
                      title: 'Daily Site Report (DSR) Approval',
                      description: _projectHeadCanApproveDSR
                          ? 'Project Head reviews and signs off on daily site reports'
                          : 'EXTRACTED: Site reports go directly to Admin',
                      value: _projectHeadCanApproveDSR,
                      icon: Icons.description_rounded,
                      onChanged: (val) =>
                          setState(() => _projectHeadCanApproveDSR = val),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutingExplanationBanner({
    required String title,
    required String description,
    required Color accentColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildCredentialsCard({
    required String roleName,
    required IconData roleIcon,
    required Color accentColor,
    required TextEditingController emailController,
    required TextEditingController passwordController,
    required bool obscurePassword,
    required VoidCallback onToggleObscure,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(roleIcon, color: accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                '$roleName Login Credentials',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Super-Admin Only',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Email / ID
          TextField(
            controller: emailController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Login ID / Email',
              labelStyle: const TextStyle(color: AppColors.textSecondary),
              prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20),
              filled: true,
              fillColor: AppColors.surfaceDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accentColor),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Password
          TextField(
            controller: passwordController,
            obscureText: obscurePassword,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Account Password',
              labelStyle: const TextStyle(color: AppColors.textSecondary),
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                onPressed: onToggleObscure,
              ),
              filled: true,
              fillColor: AppColors.surfaceDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accentColor),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 150.ms);
  }

  Widget _buildApprovalPowersCard({
    required String title,
    required String subtitle,
    required Color accentColor,
    required List<_ApprovalToggleItem> toggles,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: AppColors.goldAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 8),

          ...toggles.map((item) {
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: item.value
                    ? AppColors.surfaceDark
                    : AppColors.rejected.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: item.value
                      ? AppColors.cardBorder
                      : AppColors.rejected.withValues(alpha: 0.35),
                ),
              ),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: item.value
                        ? accentColor.withValues(alpha: 0.15)
                        : AppColors.rejected.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    item.icon,
                    color: item.value ? accentColor : AppColors.rejected,
                    size: 20,
                  ),
                ),
                title: Text(
                  item.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: item.value ? Colors.white : AppColors.rejected,
                    fontSize: 14,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    item.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: item.value
                          ? AppColors.textSecondary
                          : AppColors.rejected.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                activeColor: accentColor,
                value: item.value,
                onChanged: item.onChanged,
              ),
            );
          }),
        ],
      ),
    ).animate().fadeIn(delay: 250.ms);
  }
}

class _ApprovalToggleItem {
  final String title;
  final String description;
  final bool value;
  final IconData icon;
  final ValueChanged<bool> onChanged;

  _ApprovalToggleItem({
    required this.title,
    required this.description,
    required this.value,
    required this.icon,
    required this.onChanged,
  });
}
