import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../models/user_model.dart';

/// Adaptive navigation drawer that changes based on the user's role
class AppDrawer extends StatelessWidget {
  final UserModel? user;
  final VoidCallback? onHome;
  final VoidCallback? onStock;
  final VoidCallback? onCashBook;
  final VoidCallback? onDashboard;
  final VoidCallback? onManageSites;
  final VoidCallback? onManageDropdowns;
  final VoidCallback? onSignOut;

  const AppDrawer({
    super.key,
    this.user,
    this.onHome,
    this.onStock,
    this.onCashBook,
    this.onDashboard,
    this.onManageSites,
    this.onManageDropdowns,
    this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surfaceDark,
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo / App icon
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.construction_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'SKCPL',
                  style: AppTextStyles.h2.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                if (user != null)
                  Text(
                    '${user!.role.displayName} • ${user!.email}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
              ],
            ),
          ),

          // Menu items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _DrawerItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  onTap: onHome,
                ),
                _DrawerItem(
                  icon: Icons.inventory_2_rounded,
                  label: 'Stock Management',
                  onTap: onStock,
                ),
                _DrawerItem(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Cash Book',
                  onTap: onCashBook,
                ),

                // Accounts & Admin items
                if (user != null &&
                    (user!.isAccounts || user!.isAdmin)) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Divider(color: AppColors.divider),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 20, bottom: 4),
                    child: Text(
                      'MANAGEMENT',
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.dashboard_rounded,
                    label: 'Dashboard',
                    onTap: onDashboard,
                  ),
                ],

                // Admin-only items
                if (user != null && user!.isAdmin) ...[
                  _DrawerItem(
                    icon: Icons.location_city_rounded,
                    label: 'Manage Sites',
                    onTap: onManageSites,
                  ),
                  _DrawerItem(
                    icon: Icons.tune_rounded,
                    label: 'Manage Dropdowns',
                    onTap: onManageDropdowns,
                  ),
                ],
              ],
            ),
          ),

          // Sign out
          const Divider(color: AppColors.divider, height: 1),
          _DrawerItem(
            icon: Icons.logout_rounded,
            label: 'Sign Out',
            onTap: onSignOut,
            isDestructive: true,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;

  const _DrawerItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.rejected : AppColors.textSecondary;

    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(
        label,
        style: AppTextStyles.bodyMedium.copyWith(color: color),
      ),
      onTap: () {
        Navigator.of(context).pop(); // close drawer
        onTap?.call();
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      hoverColor: AppColors.primarySurface,
    );
  }
}
