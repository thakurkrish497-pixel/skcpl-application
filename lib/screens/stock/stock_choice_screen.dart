import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/localization/app_strings.dart';
import '../../models/site_staff_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/site_staff_provider.dart';
import '../../widgets/language_toggle_button.dart';
import '../../widgets/skcpl_brand_logo.dart';
import '../auth/site_staff_selection_screen.dart';
import '../attendance/punch_attendance_screen.dart';
import '../../widgets/offline_indicator.dart';

/// Screen presenting choices: Add Product (Inbound) and Use Product (Outbound)
class StockChoiceScreen extends ConsumerWidget {
  const StockChoiceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSite = ref.watch(authProvider).activeSite;
    final activeStaff = ref.watch(activeStaffProvider);
    final hasStockPermission =
        activeStaff == null || activeStaff.hasModule(StaffModule.stock);

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Row(
          children: [
            const SkcplBrandLogo(variant: LogoVariant.compact, customSize: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                activeSite != null
                    ? '${activeSite.name} — ${context.tr('stock_management')}'
                    : context.tr('stock_management'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: LanguageToggleButton(isCompact: true),
          ),
          OfflineSyncButton(),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Active Staff Banner
              if (ref.watch(activeStaffProvider) != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: ref.watch(activeStaffProvider)!.isSupervisor
                            ? AppColors.primary.withOpacity(0.2)
                            : AppColors.secondary.withOpacity(0.2),
                        child: Icon(
                          ref.watch(activeStaffProvider)!.isSupervisor
                              ? Icons.admin_panel_settings_rounded
                              : Icons.person_rounded,
                          size: 16,
                          color: ref.watch(activeStaffProvider)!.isSupervisor
                              ? AppColors.primary
                              : AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Entering as: ${ref.watch(activeStaffProvider)!.name} (${ref.watch(activeStaffProvider)!.role.displayName})',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (activeSite != null) {
                            await ref.read(activeStaffProvider.notifier).clearActiveStaff(activeSite.id);
                            if (context.mounted) {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SiteStaffSelectionScreen(
                                    site: activeSite,
                                    module: 'stock',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Switch', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Attendance Quick Punch Card
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PunchAttendanceScreen(
                          site: activeSite,
                          staff: ref.read(activeStaffProvider)!,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF14B8A6).withOpacity(0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.how_to_reg_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Daily Attendance Punch',
                                style: AppTextStyles.labelLarge
                                    .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Punch in/out with GPS live verification',
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: Colors.white.withOpacity(0.85)),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
                      ],
                    ),
                  ),
                ).animate().fadeIn(),

                const SizedBox(height: 20),
              ],

              // Access Denied Warning Banner if Stock toggle was turned off
              if (!hasStockPermission) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.rejected.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.rejected.withOpacity(0.5), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.block_rounded, color: AppColors.rejected, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stock Permission Disabled',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.rejected,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Stock module access has been turned off for ${activeStaff?.name}. Inward and Outward stock operations are locked.',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.rejected,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: () async {
                          if (activeSite != null) {
                            await ref.read(activeStaffProvider.notifier).clearActiveStaff(activeSite.id, module: StaffModule.stock);
                            if (context.mounted) {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SiteStaffSelectionScreen(
                                    site: activeSite,
                                    module: 'stock',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Switch Staff', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ],
                  ),
                ).animate().shake(),
              ],

              Text(
                'What would you like to do?',
                style: AppTextStyles.h2.copyWith(color: AppColors.textPrimary),
              ).animate().fadeIn(),
              const SizedBox(height: 6),
              Text(
                'Select an operation to record inventory movements',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 24),

              // Add Product card
              Opacity(
                opacity: hasStockPermission ? 1.0 : 0.5,
                child: _ChoiceCard(
                  title: context.tr('stock_inward'),
                  subtitle: hasStockPermission ? context.tr('stock_inward_sub') : 'Locked: Stock access disabled for current staff',
                  icon: hasStockPermission ? Icons.add_circle_rounded : Icons.lock_outline_rounded,
                  gradient: hasStockPermission
                      ? const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)])
                      : const LinearGradient(colors: [Colors.grey, Color(0xFF4B5563)]),
                  onTap: () {
                    if (hasStockPermission) {
                      Navigator.pushNamed(context, '/add-product');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Access Denied: Stock module access is turned off for ${activeStaff?.name}.',
                          ),
                          backgroundColor: AppColors.rejected,
                        ),
                      );
                    }
                  },
                ),
              ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.05),

              const SizedBox(height: 16),

              // Use Product card
              Opacity(
                opacity: hasStockPermission ? 1.0 : 0.5,
                child: _ChoiceCard(
                  title: context.tr('stock_outward'),
                  subtitle: hasStockPermission ? context.tr('stock_outward_sub') : 'Locked: Stock access disabled for current staff',
                  icon: hasStockPermission ? Icons.remove_circle_rounded : Icons.lock_outline_rounded,
                  gradient: hasStockPermission
                      ? const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)])
                      : const LinearGradient(colors: [Colors.grey, Color(0xFF4B5563)]),
                  onTap: () {
                    if (hasStockPermission) {
                      Navigator.pushNamed(context, '/use-product');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Access Denied: Stock module access is turned off for ${activeStaff?.name}.',
                          ),
                          backgroundColor: AppColors.rejected,
                        ),
                      );
                    }
                  },
                ),
              ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.05),

              const SizedBox(height: 24),

              // View History Button
              OutlinedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/stock-history'),
                icon: const Icon(Icons.history_rounded),
                label: Text(context.tr('stock_history')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.divider),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ).animate().fadeIn(delay: 500.ms),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: (gradient as LinearGradient).colors.first.withOpacity(0.25),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.h4.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white.withOpacity(0.7), size: 16),
          ],
        ),
      ),
    );
  }
}
