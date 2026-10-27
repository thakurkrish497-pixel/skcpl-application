import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/localization/app_strings.dart';
import '../../models/site_model.dart';
import '../../providers/site_provider.dart';
import '../../widgets/language_toggle_button.dart';
import '../../widgets/site_card.dart';
import '../../widgets/skcpl_brand_logo.dart';
import '../auth/site_login_screen.dart';

/// Displays a grid of construction sites for Stock, Cashbook, and Daily Site Reports,
/// and includes Indore Head Office exclusively for Attendance.
class SiteListScreen extends ConsumerWidget {
  final String module; // 'stock', 'cashbook', 'report', 'attendance'

  const SiteListScreen({super.key, required this.module});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sitesAsync = ref.watch(activeSitesProvider);
    final isAttendance = module == 'attendance';

    String screenTitle;
    if (module == 'stock') {
      screenTitle = '${context.tr('select_site')} — ${context.tr('stock_management')}';
    } else if (module == 'report') {
      screenTitle = '${context.tr('select_site')} — ${context.tr('daily_site_report')}';
    } else if (isAttendance) {
      screenTitle = '${context.tr('select_location')} — ${context.tr('attendance_punch')}';
    } else {
      screenTitle = '${context.tr('select_site')} — ${context.tr('cash_book')}';
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Row(
          children: [
            const SkcplBrandLogo(variant: LogoVariant.compact, customSize: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                screenTitle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: LanguageToggleButton(isCompact: true),
          ),
        ],
      ),
      body: sitesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.rejected, size: 48),
              const SizedBox(height: 16),
              Text(
                'Failed to load sites',
                style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => ref.refresh(activeSitesProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (sites) {
          // Allow Head Office for Attendance and Daily Site Reports
          final allowOffice = isAttendance || module == 'report';
          final constructionSites = sites.where((s) => !s.isHeadOffice).toList();
          final headOffices = sites.where((s) => s.isHeadOffice).toList();

          if (constructionSites.isEmpty && (!allowOffice || headOffices.isEmpty)) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_off_rounded, color: AppColors.textTertiary, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'No Active Sites',
                    style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Contact your Admin to create a new site.',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Dedicated Head Office Section (Attendance & Daily Reports) ──
              if (allowOffice && headOffices.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.apartment_rounded, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      module == 'report'
                          ? context.tr('indore_office_reports', defaultText: 'HEAD OFFICE (INDORE OFFICE REPORTS)')
                          : context.tr('indore_office_attendance', defaultText: 'HEAD OFFICE (OFFICE ATTENDANCE)'),
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...headOffices.map((office) => _buildOfficeCard(context, office)),
                const SizedBox(height: 24),
              ],

              // ── Construction Sites Section ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.construction_rounded, size: 18, color: AppColors.secondary),
                      const SizedBox(width: 8),
                      Text(
                        context.tr('construction_sites', defaultText: 'CONSTRUCTION SITES'),
                        style: AppTextStyles.overline.copyWith(
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${constructionSites.length} ${context.tr('active_badge', defaultText: 'Active')}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                ),
                itemCount: constructionSites.length,
                itemBuilder: (context, index) {
                  final site = constructionSites[index];
                  return SiteCard(
                    site: site,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SiteLoginScreen(
                            site: site,
                            module: module,
                          ),
                        ),
                      );
                    },
                  ).animate().fadeIn(delay: Duration(milliseconds: 60 * index));
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOfficeCard(BuildContext context, SiteModel office) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SiteLoginScreen(
              site: office,
              module: module,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withOpacity(0.15),
              AppColors.cardDark,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.apartment_rounded, color: AppColors.primary, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        office.name,
                        style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          module == 'report'
                              ? context.tr('office_reports_badge', defaultText: 'Office Reports')
                              : context.tr('office_attendance_badge', defaultText: 'Office Attendance'),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    module == 'report'
                        ? 'Login ID: ${office.siteLoginId} • Indore Head Office Daily Progress Reports'
                        : 'Login ID: ${office.siteLoginId} • Indore Head Office Staff & Executives',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
