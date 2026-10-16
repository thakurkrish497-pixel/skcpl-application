import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/cash_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/stat_card.dart';

/// Admin master dashboard — Overview, approvals, and management
class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingStockAsync = ref.watch(pendingStockAdminProvider);
    final pendingCashAsync = ref.watch(pendingCashAdminProvider);
    final allStockAsync = ref.watch(allSitesStockProvider);
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      drawer: AppDrawer(
        user: authState.user,
        onManageSites: () =>
            Navigator.pushNamed(context, '/manage-sites'),
        onManageDropdowns: () =>
            Navigator.pushNamed(context, '/manage-dropdowns'),
        onSignOut: () => ref.read(authProvider.notifier).signOut(),
      ),
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome header
            Text(
              'Welcome, Admin',
              style: AppTextStyles.h2.copyWith(color: AppColors.textPrimary),
            ).animate().fadeIn(),
            const SizedBox(height: 4),
            Text(
              'Review pending approvals and manage your sites',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 24),

            // ── Stat Cards ──
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.05,
              children: [
                pendingStockAsync.when(
                  loading: () => const StatCard(
                    title: 'Pending Stock',
                    value: '...',
                    icon: Icons.inventory_2,
                    accentColor: AppColors.pending,
                  ),
                  error: (_, __) => const StatCard(
                    title: 'Pending Stock',
                    value: 'Error',
                    icon: Icons.error,
                    accentColor: AppColors.rejected,
                  ),
                  data: (list) => StatCard(
                    title: 'Pending Stock',
                    value: '${list.length}',
                    icon: Icons.inventory_2,
                    accentColor: AppColors.pending,
                    onTap: () => Navigator.pushNamed(context, '/admin-review'),
                  ),
                ).animate().fadeIn(delay: 200.ms).scale(begin: const Offset(0.95, 0.95)),

                pendingCashAsync.when(
                  loading: () => const StatCard(
                    title: 'Pending Cash',
                    value: '...',
                    icon: Icons.account_balance_wallet,
                    accentColor: Color(0xFF8B5CF6),
                  ),
                  error: (_, __) => const StatCard(
                    title: 'Pending Cash',
                    value: 'Error',
                    icon: Icons.error,
                    accentColor: AppColors.rejected,
                  ),
                  data: (list) => StatCard(
                    title: 'Pending Cash',
                    value: '${list.length}',
                    icon: Icons.account_balance_wallet,
                    accentColor: const Color(0xFF8B5CF6),
                  ),
                ).animate().fadeIn(delay: 300.ms).scale(begin: const Offset(0.95, 0.95)),

                allStockAsync.when(
                  loading: () => const StatCard(
                    title: 'Products Tracked',
                    value: '...',
                    icon: Icons.category,
                    accentColor: AppColors.secondary,
                  ),
                  error: (_, __) => const StatCard(
                    title: 'Products Tracked',
                    value: 'Error',
                    icon: Icons.error,
                    accentColor: AppColors.rejected,
                  ),
                  data: (list) => StatCard(
                    title: 'Products Tracked',
                    value: '${list.length}',
                    icon: Icons.category,
                    accentColor: AppColors.secondary,
                  ),
                ).animate().fadeIn(delay: 400.ms).scale(begin: const Offset(0.95, 0.95)),

                StatCard(
                  title: 'Manage Sites',
                  value: '→',
                  icon: Icons.location_city,
                  accentColor: AppColors.primary,
                  onTap: () => Navigator.pushNamed(context, '/manage-sites'),
                ).animate().fadeIn(delay: 500.ms).scale(begin: const Offset(0.95, 0.95)),
              ],
            ),

            const SizedBox(height: 28),

            // ── Quick Actions ──
            Text(
              'QUICK ACTIONS',
              style: AppTextStyles.overline.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 12),

            _QuickActionTile(
              icon: Icons.approval_rounded,
              label: 'Review Pending Approvals',
              subtitle: 'Stock & Cash awaiting your sign-off',
              onTap: () => Navigator.pushNamed(context, '/admin-review'),
            ).animate().fadeIn(delay: 550.ms),

            const SizedBox(height: 10),

            _QuickActionTile(
              icon: Icons.tune_rounded,
              label: 'Manage Dropdowns',
              subtitle: 'Vendors, Products, Units, Expense Types',
              onTap: () => Navigator.pushNamed(context, '/manage-dropdowns'),
            ).animate().fadeIn(delay: 650.ms),

            const SizedBox(height: 10),

            _QuickActionTile(
              icon: Icons.location_city_rounded,
              label: 'Manage Construction Sites',
              subtitle: 'Create sites, generate credentials',
              onTap: () => Navigator.pushNamed(context, '/manage-sites'),
            ).animate().fadeIn(delay: 750.ms),

            const SizedBox(height: 10),

            _QuickActionTile(
              icon: Icons.account_balance_wallet_rounded,
              label: 'Cashflow Management',
              subtitle: 'Monitor site budgets and expenses',
              onTap: () => Navigator.pushNamed(context, '/admin-cashflow'),
            ).animate().fadeIn(delay: 800.ms),

            const SizedBox(height: 10),

            _QuickActionTile(
              icon: Icons.assignment_rounded,
              label: 'Manage Tasks & Chat',
              subtitle: 'Assign tasks and communicate with site teams',
              onTap: () => Navigator.pushNamed(context, '/tasks'),
            ).animate().fadeIn(delay: 900.ms),
          ],
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTextStyles.labelLarge
                          .copyWith(color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textTertiary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}
