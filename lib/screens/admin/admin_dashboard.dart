import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/localization/app_strings.dart';
import '../../models/site_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/cash_provider.dart';
import '../../providers/site_provider.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/site_staff_provider.dart';
import '../../providers/locale_provider.dart';
import '../../widgets/language_toggle_button.dart';
import '../../widgets/theme_toggle_button.dart';
import '../../widgets/skcpl_brand_logo.dart';
import '../../widgets/skcpl_wave_widgets.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/sla_notification_bar.dart';
import '../../widgets/skcpl_announcement_bar.dart';
import '../../widgets/notice_board_dialog.dart';
import '../../widgets/notification_bell_button.dart';
import '../home/home_screen.dart';

/// Next-Generation Admin Master Dashboard
/// Directly inspired by the SKCPL SaaS Dashboard (Dark Mode) design mockup:
/// - Official 3D Skcpl branding & Wave theme
/// - High-impact 4-KPI SaaS metrics row
/// - Smooth cyan/gold Activity & Connectivity Wave graph
/// - Fast, intuitive one-tap operational module tiles
/// - Live site status & geofence pulse
class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    final pendingStockAsync = ref.watch(pendingStockAdminProvider);
    final pendingCashAsync = ref.watch(pendingCashAdminProvider);
    final sitesAsync = ref.watch(activeSitesProvider);
    final staffAsync = ref.watch(allStaffProvider);
    final todayAttendanceAsync = ref.watch(todayAttendanceForSiteProvider('all'));
    final authState = ref.watch(authProvider);

    final pendingStockCount = pendingStockAsync.valueOrNull?.length ?? 0;
    final pendingCashCount = pendingCashAsync.valueOrNull?.length ?? 0;
    final totalPendingApprovals = pendingStockCount + pendingCashCount;
    final sitesCount = sitesAsync.valueOrNull?.length ?? 0;
    final staffCount = staffAsync.valueOrNull?.length ?? 0;
    final todayAttendanceCount = todayAttendanceAsync.valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      drawer: AppDrawer(
        user: authState.user,
        onManageSites: () => Navigator.pushNamed(context, '/manage-sites'),
        onSignOut: () async {
          await ref.read(authProvider.notifier).signOut();
          if (context.mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
              (route) => false,
            );
          }
        },
      ),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            const SkcplBrandLogo(variant: LogoVariant.compact, customSize: 34),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'SKCPL',
                      style: AppTextStyles.h4.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '• Dashboard',
                      style: AppTextStyles.h4.copyWith(
                        color: AppColors.waveCyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Connect to Waves • Operations Command',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: ThemeToggleButton(isCompact: true),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: LanguageToggleButton(isCompact: true),
          ),
          const NotificationBellButton(),
          IconButton(
            icon: const Icon(Icons.campaign_rounded, color: AppColors.waveCyan),
            tooltip: 'Notice Board & Broadcast Announcements',
            onPressed: () => NoticeBoardDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.shield_rounded, color: AppColors.waveCyan),
            tooltip: 'Data Loss Protection & Backups',
            onPressed: () => Navigator.pushNamed(context, '/admin-backup'),
          ),
          IconButton(
            icon: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.goldAccent),
            tooltip: 'Role Access & Approval Powers',
            onPressed: () => Navigator.pushNamed(context, '/admin-role-access'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            tooltip: 'Refresh live data',
            onPressed: () {
              ref.invalidate(pendingStockAdminProvider);
              ref.invalidate(pendingCashAdminProvider);
              ref.invalidate(activeSitesProvider);
              ref.invalidate(allStaffProvider);
              ref.invalidate(todayAttendanceForSiteProvider);
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.rejected),
            tooltip: context.tr('logout'),
            onPressed: () async {
              await ref.read(authProvider.notifier).signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                );
              }
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ResponsiveContainer(
        maxWidth: 1200,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Birthday & Corporate Announcement Bar ──
              const SkcplAnnouncementBar(),

              // ── In-App SLA Overdue Notification Bar (>36h) ──
              const SlaNotificationBar(),

              // ── Live System Status & Greeting ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.approved,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.approved.withValues(alpha: 0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'System Status: All Services Live & Connected',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Cloud Sync Active • Geofencing Enforced',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.waveCyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.waveCyan.withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        'ADMIN',
                        style: TextStyle(
                          color: AppColors.waveCyan,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 350.ms).slideY(begin: -0.05),

              const SizedBox(height: 18),

              // ── 4 SaaS High-Impact Metric Cards ──
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 650;
                  return GridView.count(
                    crossAxisCount: isWide ? 4 : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: isWide ? 1.5 : 1.35,
                    children: [
                      // Metric 1: Pending Approvals
                      _SaaSMetricCard(
                        label: 'Pending Approvals',
                        value: '$totalPendingApprovals',
                        subtext: totalPendingApprovals > 0 ? 'Action Needed' : 'All Clear',
                        icon: Icons.approval_rounded,
                        accentColor: AppColors.goldAccent,
                        onTap: () => Navigator.pushNamed(context, '/admin-review'),
                      ),

                      // Metric 2: Today's Attendance Pulse
                      _SaaSMetricCard(
                        label: 'Today\'s Attendance',
                        value: '$todayAttendanceCount',
                        subtext: 'Punched In Today',
                        icon: Icons.how_to_reg_rounded,
                        accentColor: AppColors.waveCyan,
                        onTap: () => Navigator.pushNamed(context, '/admin-attendance'),
                      ),

                      // Metric 3: Active Locations
                      _SaaSMetricCard(
                        label: 'Active Sites',
                        value: '$sitesCount',
                        subtext: 'Including Head Office',
                        icon: Icons.location_city_rounded,
                        accentColor: AppColors.approved,
                        onTap: () => Navigator.pushNamed(context, '/manage-sites'),
                      ),

                      // Metric 4: Total Managed Staff
                      _SaaSMetricCard(
                        label: 'Managed Staff',
                        value: '$staffCount',
                        subtext: 'Across All Roles',
                        icon: Icons.people_alt_rounded,
                        accentColor: AppColors.primaryLight,
                        onTap: () => Navigator.pushNamed(context, '/admin-staff'),
                      ),
                    ],
                  );
                },
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 20),

              // ── The Signature "Connectivity & Activity Pulse" Chart ──
              const SkcplConnectivityWaveChart(
                height: 140,
                title: 'Activity Waves & Throughput',
                subtitle: 'Weekly pulse of inventory movements, expenses & attendance',
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.05),

              const SizedBox(height: 24),

              // ── Section Title: Core Operations Command ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'OPERATIONAL COMMAND',
                    style: AppTextStyles.overline.copyWith(
                      color: AppColors.goldAccent,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    '7 Modules Active',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Operational Module Cards (Responsive Grid: 1 col on mobile, 2 col on tablet & desktop) ──
              ResponsiveGrid(
                mobileColumns: 1,
                tabletColumns: 2,
                desktopColumns: 2,
                spacing: 14,
                runSpacing: 14,
                children: [
                  _CommandModuleTile(
                    icon: Icons.campaign_rounded,
                    title: 'Notice Board & Broadcasts',
                    subtitle: 'Post company-wide announcements, Zoom meeting invites & push alerts',
                    accentColor: AppColors.goldAccent,
                    badgeText: 'Instant Alert',
                    badgeColor: AppColors.primary,
                    onTap: () => NoticeBoardDialog.show(context),
                  ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.04),

                  _CommandModuleTile(
                    icon: Icons.badge_rounded,
                    title: context.tr('all_staff'),
                    subtitle: 'Staff profiles, PIN passwords, module permissions & 360° reports',
                    accentColor: AppColors.primaryLight,
                    badgeText: '$staffCount Staff',
                    onTap: () => Navigator.pushNamed(context, '/admin-staff'),
                  ).animate().fadeIn(delay: 350.ms).slideX(begin: -0.04),

                  _CommandModuleTile(
                    icon: Icons.how_to_reg_rounded,
                    title: context.tr('attendance_punch'),
                    subtitle: 'Today\'s pulse, live GPS radar, late requests queue & monthly Excel',
                    accentColor: AppColors.waveCyan,
                    badgeText: 'Live GPS',
                    onTap: () => Navigator.pushNamed(context, '/admin-attendance'),
                  ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.04),

                  _CommandModuleTile(
                    icon: Icons.fact_check_rounded,
                    title: context.tr('review_approvals'),
                    subtitle: 'Sign off site worker inward stock and cash expenses',
                    accentColor: AppColors.goldAccent,
                    badgeText: totalPendingApprovals > 0 ? '$totalPendingApprovals Pending' : 'Approved',
                    badgeColor: totalPendingApprovals > 0 ? AppColors.rejected : AppColors.approved,
                    onTap: () => Navigator.pushNamed(context, '/admin-review'),
                  ).animate().fadeIn(delay: 450.ms).slideX(begin: -0.04),

                  _CommandModuleTile(
                    icon: Icons.location_city_rounded,
                    title: context.tr('manage_sites'),
                    subtitle: 'Create sites, set Google Maps attendance area & "Set to My Location"',
                    accentColor: AppColors.approved,
                    badgeText: '$sitesCount Sites',
                    onTap: () => Navigator.pushNamed(context, '/manage-sites'),
                  ).animate().fadeIn(delay: 500.ms).slideX(begin: -0.04),

                  _CommandModuleTile(
                    icon: Icons.record_voice_over_rounded,
                    title: context.tr('daily_site_report'),
                    subtitle: 'Voice-to-text notes, site construction photos & daily progress',
                    accentColor: const Color(0xFFF97316),
                    badgeText: 'AI Powered',
                    onTap: () => Navigator.pushNamed(context, '/daily-site-reports'),
                  ).animate().fadeIn(delay: 550.ms).slideX(begin: -0.04),

                  _CommandModuleTile(
                    icon: Icons.account_balance_wallet_rounded,
                    title: context.tr('cashflow_summary'),
                    subtitle: 'Imprest book, site cash-in-hand, category budgets & audits',
                    accentColor: const Color(0xFF10B981),
                    badgeText: 'Audit Ready',
                    onTap: () => Navigator.pushNamed(context, '/admin-cashflow'),
                  ).animate().fadeIn(delay: 600.ms).slideX(begin: -0.04),

                  _CommandModuleTile(
                    icon: Icons.admin_panel_settings_rounded,
                    title: 'Role Access & Approval Powers',
                    subtitle: 'Configure IDs, passwords & granular approval routing (Bypass Accounts/Project Head)',
                    accentColor: AppColors.goldAccent,
                    badgeText: 'Admin Power',
                    onTap: () => Navigator.pushNamed(context, '/admin-role-access'),
                  ).animate().fadeIn(delay: 700.ms).slideX(begin: -0.04),

                  _CommandModuleTile(
                    icon: Icons.shield_rounded,
                    title: 'Data Protection & Master Backups',
                    subtitle: '1-Click Master Excel & JSON backup, media catalog, automated cloud sync & emergency vault',
                    accentColor: AppColors.waveCyan,
                    badgeText: 'Zero Loss',
                    onTap: () => Navigator.pushNamed(context, '/admin-backup'),
                  ).animate().fadeIn(delay: 750.ms).slideX(begin: -0.04),
                ],
              ),

              const SizedBox(height: 24),

              // ── Live Site Radar & Geofence Status Strip ──
              Text(
                'LIVE SITE RADAR & GEOFENCE STATUS',
                style: AppTextStyles.overline.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),

              sitesAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(color: AppColors.waveCyan, strokeWidth: 2),
                  ),
                ),
                error: (_, __) => const SizedBox(),
                data: (sites) {
                  if (sites.isEmpty) return const SizedBox();
                  return ResponsiveGrid(
                    mobileColumns: 1,
                    tabletColumns: 2,
                    desktopColumns: 3,
                    spacing: 12,
                    runSpacing: 12,
                    children: sites.map((site) => _SiteQuickPulseCard(site: site)).toList(),
                  );
                },
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aesthetic KPI Metric Card
class _SaaSMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtext;
  final IconData icon;
  final Color accentColor;
  final VoidCallback? onTap;

  const _SaaSMetricCard({
    required this.label,
    required this.value,
    required this.subtext,
    required this.icon,
    required this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: accentColor, size: 18),
                    ),
                    Icon(
                      Icons.arrow_outward_rounded,
                      color: accentColor.withValues(alpha: 0.6),
                      size: 14,
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: AppTextStyles.h2.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtext,
                      style: AppTextStyles.caption.copyWith(
                        color: accentColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Command Module Action Card
class _CommandModuleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final String? badgeText;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _CommandModuleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    this.badgeText,
    this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.cardBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Icon(icon, color: accentColor, size: 22),
                ),
                const SizedBox(width: 14),

                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: AppTextStyles.labelLarge.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (badgeText != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: (badgeColor ?? accentColor).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: (badgeColor ?? accentColor).withValues(alpha: 0.4),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                badgeText!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: badgeColor ?? accentColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textTertiary,
                    size: 18,
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

/// Quick live pulse card for each site
class _SiteQuickPulseCard extends ConsumerWidget {
  final SiteModel site;

  const _SiteQuickPulseCard({required this.site});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policyAsync = ref.watch(shiftPolicyForSiteProvider(site.id));
    final policy = policyAsync.valueOrNull;
    final hasArea = policy?.latitude != null && policy?.longitude != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider, width: 0.8),
      ),
      child: Row(
        children: [
          Icon(
            site.isHeadOffice ? Icons.apartment_rounded : Icons.construction_rounded,
            color: site.isHeadOffice ? AppColors.waveCyan : AppColors.goldAccent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  site.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  site.isHeadOffice
                      ? 'Head Office • Attendance Only'
                      : 'Construction Site • Stock, Cash & DSR',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: hasArea
                  ? AppColors.approved.withValues(alpha: 0.15)
                  : AppColors.pending.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasArea
                    ? AppColors.approved.withValues(alpha: 0.35)
                    : AppColors.pending.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasArea ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                  size: 11,
                  color: hasArea ? AppColors.approved : AppColors.pending,
                ),
                const SizedBox(width: 4),
                Text(
                  hasArea ? '${policy!.allowedRadiusMeters.toInt()}m Geofence' : 'Area Not Set',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: hasArea ? AppColors.approved : AppColors.pending,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
