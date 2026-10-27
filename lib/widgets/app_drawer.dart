import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../core/localization/app_strings.dart';
import '../models/user_model.dart';
import 'cache_manager_dialog.dart';
import 'language_toggle_button.dart';
import 'notice_board_dialog.dart';
import 'skcpl_brand_logo.dart';
import 'theme_toggle_button.dart';

/// Adaptive navigation drawer that changes based on the user's role
class AppDrawer extends StatelessWidget {
  final UserModel? user;
  final VoidCallback? onHome;
  final VoidCallback? onStock;
  final VoidCallback? onCashBook;
  final VoidCallback? onDashboard;
  final VoidCallback? onManageSites;
  final VoidCallback? onSignOut;

  const AppDrawer({
    super.key,
    this.user,
    this.onHome,
    this.onStock,
    this.onCashBook,
    this.onDashboard,
    this.onManageSites,
    this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surfaceDark,
      child: Column(
        children: [
          // Header with 3D Brand Logo
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppColors.isLight
                    ? [const Color(0xFF1E3A8A), const Color(0xFF0284C7)]
                    : [const Color(0xFF0F2042), const Color(0xFF091224)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(
                bottom: BorderSide(color: AppColors.cardBorder, width: 1.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkcplBrandLogo(
                  variant: LogoVariant.standard,
                  showTagline: true,
                  textColor: Colors.white,
                ),
                if (user != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified_user_rounded, color: AppColors.waveCyan, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${user!.role.displayName} • ${user!.email}',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                  label: context.tr('home', defaultText: 'Home'),
                  onTap: onHome,
                ),
                _DrawerItem(
                  icon: Icons.inventory_2_rounded,
                  label: context.tr('stock_management'),
                  onTap: onStock,
                ),
                _DrawerItem(
                  icon: Icons.account_balance_wallet_rounded,
                  label: context.tr('cash_book'),
                  onTap: onCashBook,
                ),
                _DrawerItem(
                  icon: Icons.record_voice_over_rounded,
                  label: context.tr('daily_site_report'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/daily-site-reports');
                  },
                ),
                _DrawerItem(
                  icon: Icons.campaign_rounded,
                  label: context.tr('notice_board'),
                  onTap: () {
                    Navigator.pop(context);
                    NoticeBoardDialog.show(context);
                  },
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
                    label: context.tr('dashboard', defaultText: 'Dashboard'),
                    onTap: onDashboard,
                  ),
                ],

                // Admin-only items
                if (user != null && user!.isAdmin) ...[
                  _DrawerItem(
                    icon: Icons.how_to_reg_rounded,
                    label: context.tr('attendance_punch'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/admin-attendance');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.location_city_rounded,
                    label: context.tr('manage_sites'),
                    onTap: onManageSites,
                  ),
                ],

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Divider(color: AppColors.divider),
                ),
                _DrawerItem(
                  icon: Icons.cleaning_services_rounded,
                  label: context.tr('storage_cache', defaultText: 'Storage & Cache'),
                  onTap: () => CacheManagerDialog.show(context),
                ),
              ],
            ),
          ),

          // Language Switcher Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.language_rounded,
                      color: AppColors.waveCyan,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      context.tr('language', defaultText: 'Language'),
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const LanguageToggleButton(isCompact: true),
              ],
            ),
          ),

          // Theme Mode Switcher (Dark vs Light: White & Blue)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      AppColors.isLight ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                      color: AppColors.isLight ? AppColors.primary : AppColors.waveCyan,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      AppColors.isLight ? 'Light Mode' : 'Dark Mode',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const ThemeToggleButton(isCompact: true),
              ],
            ),
          ),

          // Sign out
          Divider(color: AppColors.divider, height: 1),
          _DrawerItem(
            icon: Icons.logout_rounded,
            label: context.tr('sign_out', defaultText: 'Sign Out'),
            onTap: onSignOut,
            isDestructive: true,
          ),
          const SizedBox(height: 12),

          // Developer Credit Badge
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.isLight
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.isLight
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : AppColors.waveCyan.withValues(alpha: 0.18),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.code_rounded,
                        size: 13,
                        color: AppColors.isLight ? AppColors.primary : AppColors.waveCyan,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Made by — Krish Thakur',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.isLight ? AppColors.primary : AppColors.waveCyan,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'SKCPL Operations ERP • v1.0.0',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
