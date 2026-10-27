import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/localization/app_strings.dart';
import '../../providers/locale_provider.dart';
import '../../widgets/language_toggle_button.dart';
import '../../widgets/theme_toggle_button.dart';
import '../../widgets/skcpl_brand_logo.dart';
import '../../widgets/skcpl_wave_widgets.dart';
import '../../widgets/skcpl_announcement_bar.dart';
import '../../widgets/responsive_layout.dart';

/// Entry screen — Four main worker/site paths: Stock, Cash Book, DSR, Attendance & Admin
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      body: SafeArea(
        child: ResponsiveContainer(
          maxWidth: 1100,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // ── Top Header with 3D Logo & Language Switcher ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SkcplBrandLogo(
                    variant: LogoVariant.standard,
                    showTagline: true,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ThemeToggleButton(isCompact: true),
                      const SizedBox(width: 8),
                      const LanguageToggleButton(isCompact: false),
                    ],
                  ),
                ],
              ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1),

              const SizedBox(height: 14),

              // ── In-App Birthday / Corporate Announcement Bar ──
              const SkcplAnnouncementBar(),

              const SizedBox(height: 6),

              // ── Hero Banner: "Connect to Waves" ──
              SkcplHeroBanner(
                onQuickAction: () {
                  Navigator.pushNamed(context, '/sites', arguments: 'attendance');
                },
                quickActionLabel: context.tr('attendance_punch'),
              ).animate().fadeIn(delay: 150.ms).scale(begin: const Offset(0.97, 0.97)),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.tr('welcome_msg'),
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.waveCyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.waveCyan.withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      'ERP v1.0',
                      style: TextStyle(
                        color: AppColors.waveCyan,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 250.ms),

              const SizedBox(height: 14),

              // ── Module Cards (Responsive Grid: 1 col on mobile, 2 col on tablet/desktop) ──
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      ResponsiveGrid(
                        mobileColumns: 1,
                        tabletColumns: 2,
                        desktopColumns: 2,
                        spacing: 16,
                        runSpacing: 14,
                        children: [
                          // Stock Management Card
                          _ModuleCard(
                            title: context.tr('stock_management'),
                            subtitle: context.tr('stock_management_sub'),
                            icon: Icons.inventory_2_rounded,
                            gradient: AppColors.stockGradient,
                            accentColor: AppColors.waveCyan,
                            onTap: () {
                              Navigator.pushNamed(context, '/sites', arguments: 'stock');
                            },
                          ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.08),

                          // Cash Book Card
                          _ModuleCard(
                            title: context.tr('cash_book'),
                            subtitle: context.tr('cash_book_sub'),
                            icon: Icons.account_balance_wallet_rounded,
                            gradient: AppColors.cashGradient,
                            accentColor: AppColors.approved,
                            onTap: () {
                              Navigator.pushNamed(context, '/sites', arguments: 'cashbook');
                            },
                          ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.08),

                          // Daily Site Report Card (Voice + Photos)
                          _ModuleCard(
                            title: context.tr('daily_site_report'),
                            subtitle: context.tr('daily_site_report_sub'),
                            icon: Icons.record_voice_over_rounded,
                            gradient: AppColors.reportGradient,
                            accentColor: AppColors.goldAccent,
                            onTap: () {
                              Navigator.pushNamed(context, '/sites', arguments: 'report');
                            },
                          ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.08),

                          // Daily Attendance Card (GPS Punch-In)
                          _ModuleCard(
                            title: context.tr('attendance_punch'),
                            subtitle: context.tr('attendance_punch_sub'),
                            icon: Icons.how_to_reg_rounded,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                            ),
                            accentColor: const Color(0xFF14B8A6),
                            onTap: () {
                              Navigator.pushNamed(context, '/sites', arguments: 'attendance');
                            },
                          ).animate().fadeIn(delay: 450.ms).slideY(begin: 0.08),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Admin & Accounts Master Portal Tile
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: AppColors.goldAccent.withValues(alpha: 0.35),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.goldAccent.withValues(alpha: 0.1),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.pushNamed(context, '/role-login');
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.goldAccent.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.admin_panel_settings_rounded,
                                      color: AppColors.goldAccent,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          context.tr('admin_portal'),
                                          style: AppTextStyles.labelLarge.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          context.tr('admin_portal_sub'),
                                          style: AppTextStyles.caption.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: AppColors.goldAccent,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ).animate().fadeIn(delay: 650.ms),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // Footer & Developer Credit
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.isLight
                              ? AppColors.primary.withValues(alpha: 0.08)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.isLight
                                ? AppColors.primary.withValues(alpha: 0.2)
                                : AppColors.waveCyan.withValues(alpha: 0.25),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.code_rounded,
                              size: 14,
                              color: AppColors.isLight ? AppColors.primary : AppColors.waveCyan,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Made by — Krish Thakur',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.isLight ? AppColors.primary : AppColors.waveCyan,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'v1.0.0 • S. Kumar Creation Pvt. Ltd.',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Gradient gradient;
  final Color? accentColor;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppColors.waveCyan;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent.withValues(alpha: 0.28),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Gradient Icon Container
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),

                // Title & Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.h3.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.divider,
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: accent,
                    size: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
