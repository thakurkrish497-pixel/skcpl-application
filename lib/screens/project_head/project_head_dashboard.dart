import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/cash_transaction_model.dart';
import '../../models/stock_transaction_model.dart';
import '../../models/daily_site_report_model.dart';
import '../../models/attendance_model.dart';
import '../../models/site_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/site_provider.dart';
import '../../providers/site_report_provider.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/role_access_provider.dart';
import '../../providers/locale_provider.dart';
import '../../core/localization/app_strings.dart';
import '../../widgets/language_toggle_button.dart';
import '../../widgets/skcpl_brand_logo.dart';
import '../../widgets/photo_thumbnail_strip.dart';
import '../../widgets/photo_viewer_dialog.dart';
import '../../widgets/entry_detail_dialog.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/sla_notification_bar.dart';
import '../../widgets/skcpl_announcement_bar.dart';
import '../../widgets/notice_board_dialog.dart';
import '../../widgets/notification_bell_button.dart';
import '../home/home_screen.dart';

/// Clean, state-of-the-art Project Head Command Dashboard
/// Hierarchy Workflow:
/// - Cash & Stock: Site Worker ➔ Project Head ➔ Accounts ➔ Admin
/// - Attendance: Site Worker ➔ Project Head ➔ Admin (No Accounts required)
class ProjectHeadDashboard extends ConsumerStatefulWidget {
  const ProjectHeadDashboard({super.key});

  @override
  ConsumerState<ProjectHeadDashboard> createState() => _ProjectHeadDashboardState();
}

class _ProjectHeadDashboardState extends ConsumerState<ProjectHeadDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedSiteId = 'all'; // 'all' or specific site UUID

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    Future.microtask(() => _refreshAllData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshAllData() {
    ref.invalidate(activeSitesProvider);
    ref.invalidate(pendingCashAccountsProvider);
    ref.invalidate(pendingStockAccountsProvider);
    ref.invalidate(allDailyReportsProvider);
    ref.invalidate(pendingRegularizationRequestsProvider);
    if (_selectedSiteId == 'all') {
      ref.read(cashProvider.notifier).loadAllTransactions();
      ref.read(stockProvider.notifier).loadAllTransactions();
    } else {
      ref.read(cashProvider.notifier).loadTransactions(_selectedSiteId);
      ref.read(stockProvider.notifier).loadTransactions(_selectedSiteId);
    }
  }

  String get _currentProjectHeadName {
    final user = ref.read(authProvider).user;
    return user?.fullName ?? user?.email.split('@').first ?? 'Project Head';
  }

  String _getSiteName(List<SiteModel> sites, String siteId) {
    for (final s in sites) {
      if (s.id == siteId) return s.name;
    }
    return 'Site';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final authState = ref.watch(authProvider);
    final sitesAsync = ref.watch(activeSitesProvider);
    final sites = sitesAsync.valueOrNull ?? [];

    final roleAccess = ref.watch(roleAccessProvider);

    // Pending Cash Entries (Waiting for Project Head review - latest on top)
    final allCash = ref.watch(cashProvider).transactions;
    final pendingCash = !roleAccess.projectHeadCanApproveCash
        ? <CashTransactionModel>[]
        : (allCash.where((c) {
            final matchesSite = _selectedSiteId == 'all' || c.siteId == _selectedSiteId;
            return matchesSite && c.isPendingSupervisorReview;
          }).toList()
            ..sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date)));

    // Pending Stock Entries (Waiting for Project Head review - latest on top)
    final allStock = ref.watch(stockProvider).transactions;
    final pendingStock = !roleAccess.projectHeadCanApproveStock
        ? <StockTransactionModel>[]
        : (allStock.where((s) {
            final matchesSite = _selectedSiteId == 'all' || s.siteId == _selectedSiteId;
            return matchesSite && s.isPendingSupervisorReview;
          }).toList()
            ..sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date)));

    // Pending Attendance Regularization Requests (Waiting for Project Head verification - latest on top)
    final pendingAttendanceAsync = ref.watch(pendingRegularizationRequestsProvider);
    final allAttendanceReqs = pendingAttendanceAsync.valueOrNull ?? [];
    final pendingAttendance = !roleAccess.projectHeadCanApproveAttendance
        ? <AttendanceRecordModel>[]
        : (allAttendanceReqs.where((a) {
            return _selectedSiteId == 'all' || a.siteId == _selectedSiteId;
          }).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

    // Daily Site Reports (Waiting for Project Head review - latest on top)
    final reportsAsync = ref.watch(allDailyReportsProvider);
    final allReports = reportsAsync.valueOrNull ?? [];
    final pendingReports = !roleAccess.projectHeadCanApproveDSR
        ? <DailySiteReportModel>[]
        : (allReports.where((r) {
            final matchesSite = _selectedSiteId == 'all' || r.siteId == _selectedSiteId;
            return matchesSite && r.isPendingProjectHeadReview;
          }).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            const SkcplBrandLogo(variant: LogoVariant.compact, customSize: 32),
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
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '• Project Head',
                      style: AppTextStyles.h4.copyWith(
                        color: AppColors.waveCyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Central Operations Command & Multi-Tier Approvals',
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
          const NotificationBellButton(),
          IconButton(
            icon: const Icon(Icons.campaign_rounded, color: AppColors.waveCyan),
            tooltip: 'Notice Board & Broadcast Announcements',
            onPressed: () => NoticeBoardDialog.show(context),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: LanguageToggleButton(isCompact: true),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            tooltip: 'Refresh all submissions',
            onPressed: _refreshAllData,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.rejected),
            tooltip: 'Sign Out',
            onPressed: () => _showSignOutDialog(context),
          ),
        ],
      ),
      body: ResponsiveContainer(
        maxWidth: 1200,
        child: SafeArea(
          child: Column(
          children: [
            // ── Birthday & Corporate Announcement Bar ──
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SkcplAnnouncementBar(margin: EdgeInsets.zero),
            ),

            // ── In-App SLA Overdue Notification Bar (>36h) ──
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SlaNotificationBar(),
            ),

            // ── Top Header Controls & Site Filter ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: AppColors.cardDark,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedSiteId,
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceDark,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.waveCyan),
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Row(
                                children: [
                                  Icon(Icons.dashboard_customize_rounded, size: 16, color: AppColors.waveCyan),
                                  SizedBox(width: 8),
                                  Text('All Sites Overview', style: TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            ...sites.map((s) => DropdownMenuItem(
                                  value: s.id,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.location_on_rounded, size: 16, color: AppColors.goldAccent),
                                      const SizedBox(width: 8),
                                      Text(s.name),
                                    ],
                                  ),
                                )),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedSiteId = val);
                              if (val == 'all') {
                                ref.read(cashProvider.notifier).loadAllTransactions();
                                ref.read(stockProvider.notifier).loadAllTransactions();
                              } else {
                                ref.read(cashProvider.notifier).loadTransactions(val);
                                ref.read(stockProvider.notifier).loadTransactions(val);
                              }
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.waveCyan.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.waveCyan.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified_user_rounded, size: 14, color: AppColors.waveCyan),
                        const SizedBox(width: 6),
                        Text(
                          _currentProjectHeadName,
                          style: const TextStyle(
                            color: AppColors.waveCyan,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── KPI Summary Cards ──
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _buildKpiCard(
                    title: 'Cash',
                    count: pendingCash.length,
                    icon: Icons.account_balance_wallet_rounded,
                    color: AppColors.approved,
                    onTap: () => _tabController.animateTo(0),
                  ),
                  const SizedBox(width: 8),
                  _buildKpiCard(
                    title: 'Stock',
                    count: pendingStock.length,
                    icon: Icons.inventory_2_rounded,
                    color: AppColors.waveCyan,
                    onTap: () => _tabController.animateTo(1),
                  ),
                  const SizedBox(width: 8),
                  _buildKpiCard(
                    title: 'Attendance',
                    count: pendingAttendance.length,
                    icon: Icons.how_to_reg_rounded,
                    color: const Color(0xFF14B8A6),
                    onTap: () => _tabController.animateTo(2),
                  ),
                  const SizedBox(width: 8),
                  _buildKpiCard(
                    title: 'DSR',
                    count: pendingReports.length,
                    icon: Icons.record_voice_over_rounded,
                    color: AppColors.goldAccent,
                    onTap: () => _tabController.animateTo(3),
                  ),
                ],
              ),
            ),

            // ── Tab Bar ──
            Container(
              color: AppColors.surfaceDark,
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.waveCyan,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textTertiary,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                tabs: [
                  Tab(
                    text: 'Cash Expenses (${pendingCash.length})',
                    icon: const Icon(Icons.payments_outlined, size: 18),
                  ),
                  Tab(
                    text: 'Stock (${pendingStock.length})',
                    icon: const Icon(Icons.inventory_outlined, size: 18),
                  ),
                  Tab(
                    text: 'Attendance (${pendingAttendance.length})',
                    icon: const Icon(Icons.access_time_rounded, size: 18),
                  ),
                  Tab(
                    text: 'DSR Reports (${pendingReports.length})',
                    icon: const Icon(Icons.summarize_outlined, size: 18),
                  ),
                ],
              ),
            ),

            // ── Tab Views ──
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Cash Expenses
                  _buildCashApprovalsList(pendingCash, sites),

                  // Tab 2: Stock Approvals
                  _buildStockApprovalsList(pendingStock, sites),

                  // Tab 3: Attendance Regularization
                  _buildAttendanceApprovalsList(pendingAttendance),

                  // Tab 4: DSR Reports
                  _buildDsrApprovalsList(pendingReports, sites),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // KPI Mini Card
  // ─────────────────────────────────────────────────────────────
  Widget _buildKpiCard({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: count > 0 ? color.withOpacity(0.4) : AppColors.divider),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 4),
                    Text(
                      '$count',
                      style: AppTextStyles.h3.copyWith(
                        color: count > 0 ? Colors.white : AppColors.textTertiary,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TAB 1: CASH EXPENSE APPROVALS
  // ─────────────────────────────────────────────────────────────
  Widget _buildCashApprovalsList(List<CashTransactionModel> list, List<SiteModel> sites) {
    final roleAccess = ref.watch(roleAccessProvider);
    final accountsCanApproveCash = roleAccess.accountsCanApproveCash;
    final projectHeadCanApproveCash = roleAccess.projectHeadCanApproveCash;

    if (list.isEmpty) {
      return _buildEmptyState(
        title: 'No Pending Cash Expenses',
        subtitle: 'All cash expenses submitted by site staff have been approved or forwarded to Accounts.',
        icon: Icons.check_circle_outline_rounded,
        color: AppColors.approved,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final tx = list[i];
        final siteName = _getSiteName(sites, tx.siteId);

        return Card(
          color: AppColors.cardDark,
          margin: const EdgeInsets.only(bottom: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.approved.withOpacity(0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.goldAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            siteName,
                            style: const TextStyle(color: AppColors.goldAccent, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                        if (DateTime.now().difference(tx.createdAt ?? tx.date).inHours >= 36) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer_outlined, size: 12, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  'OVERDUE (${DateTime.now().difference(tx.createdAt ?? tx.date).inHours}h)',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      DateFormat('dd MMM yyyy').format(tx.date),
                      style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tx.displayExpenseTypeName,
                            style: AppTextStyles.h4.copyWith(color: Colors.white, fontSize: 16),
                          ),
                          if (tx.partyName != null)
                            Text(
                              'Party: ${tx.partyName}',
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                            ),
                          if (tx.billNo != null)
                            Text(
                              'Bill / Voucher #: ${tx.billNo}',
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                            ),
                          if (tx.submitterName != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Submitted By: ${tx.submitterName}',
                                style: const TextStyle(color: AppColors.waveCyan, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${tx.expenseAmount.toStringAsFixed(2)}',
                      style: AppTextStyles.h3.copyWith(color: AppColors.approved, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),

                if (tx.cleanRemarks != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Notes: "${tx.cleanRemarks}"',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                  ),
                ],

                if (tx.photoUrls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  PhotoThumbnailStrip(photoUrls: tx.photoUrls),
                ],

                const SizedBox(height: 14),
                const Divider(color: AppColors.divider, height: 1),
                const SizedBox(height: 12),

                // Approval Action Buttons
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.rejected, size: 20),
                      tooltip: 'Remove Request',
                      onPressed: () => _deleteCashEntry(tx),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.cardBorder),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('View'),
                      onPressed: () => EntryDetailDialog.show(
                        context,
                        cashTransaction: tx,
                        onEdit: projectHeadCanApproveCash ? () => _editAndApproveCash(tx) : null,
                        onApprove: projectHeadCanApproveCash ? () => _approveCashEntry(tx) : null,
                        onReject: projectHeadCanApproveCash ? () => _rejectCashEntry(tx) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.rejected,
                          side: const BorderSide(color: AppColors.rejected),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text('Reject'),
                        onPressed: projectHeadCanApproveCash ? () => _rejectCashEntry(tx) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.waveCyan,
                          side: const BorderSide(color: AppColors.waveCyan),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.edit_note_rounded, size: 16),
                        label: const Text('Edit & OK'),
                        onPressed: projectHeadCanApproveCash ? () => _editAndApproveCash(tx) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: projectHeadCanApproveCash ? AppColors.approved : AppColors.cardBorder,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(projectHeadCanApproveCash ? Icons.check_circle_rounded : Icons.lock_rounded, size: 18),
                        label: Text(
                          !projectHeadCanApproveCash
                              ? 'Extracted by Admin'
                              : (accountsCanApproveCash ? 'Approve ➔ Accounts' : 'Approve ➔ Admin (Direct)'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: projectHeadCanApproveCash ? () => _approveCashEntry(tx) : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TAB 2: STOCK APPROVALS
  // ─────────────────────────────────────────────────────────────
  Widget _buildStockApprovalsList(List<StockTransactionModel> list, List<SiteModel> sites) {
    final roleAccess = ref.watch(roleAccessProvider);
    final accountsCanApproveStock = roleAccess.accountsCanApproveStock;
    final projectHeadCanApproveStock = roleAccess.projectHeadCanApproveStock;

    if (list.isEmpty) {
      return _buildEmptyState(
        title: 'No Pending Stock Entries',
        subtitle: 'All materials added or consumed have been approved or forwarded to Accounts.',
        icon: Icons.inventory_rounded,
        color: AppColors.waveCyan,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final tx = list[i];
        final siteName = _getSiteName(sites, tx.siteId);
        final isInbound = tx.type == TransactionType.inbound;

        return Card(
          color: AppColors.cardDark,
          margin: const EdgeInsets.only(bottom: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isInbound ? AppColors.waveCyan.withOpacity(0.35) : AppColors.primary.withOpacity(0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isInbound ? AppColors.approved.withOpacity(0.15) : AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(isInbound ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 14, color: isInbound ? AppColors.approved : AppColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                isInbound ? 'Inward' : 'Usage',
                                style: TextStyle(color: isInbound ? AppColors.approved : AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.goldAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            siteName,
                            style: const TextStyle(color: AppColors.goldAccent, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                        if (DateTime.now().difference(tx.createdAt ?? tx.date).inHours >= 36) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer_outlined, size: 12, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  'OVERDUE (${DateTime.now().difference(tx.createdAt ?? tx.date).inHours}h)',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      DateFormat('dd MMM yyyy').format(tx.date),
                      style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tx.displayProductName,
                            style: AppTextStyles.h4.copyWith(color: Colors.white, fontSize: 16),
                          ),
                          Text(
                            'Quantity: ${tx.quantity} ${tx.displayMetricUnitName}',
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                          ),
                          if (tx.rate != null && tx.rate! > 0)
                            Text(
                              'Rate: ₹${tx.rate!.toStringAsFixed(2)} / ${tx.displayMetricUnitName}',
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                            ),
                          if (tx.displayVendorName.isNotEmpty && tx.displayVendorName != 'None')
                            Text(
                              'Vendor: ${tx.displayVendorName}',
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                            ),
                          if (tx.submitterName != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Submitted By: ${tx.submitterName}',
                                style: const TextStyle(color: AppColors.waveCyan, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (tx.calculatedFinalAmount > 0)
                      Text(
                        '₹${tx.calculatedFinalAmount.toStringAsFixed(2)}',
                        style: AppTextStyles.h3.copyWith(color: AppColors.waveCyan, fontWeight: FontWeight.bold),
                      ),
                  ],
                ),

                if (tx.cleanRemarks != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Notes: "${tx.cleanRemarks}"',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                  ),
                ],

                if (tx.photoUrls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  PhotoThumbnailStrip(photoUrls: tx.photoUrls),
                ],

                const SizedBox(height: 14),
                const Divider(color: AppColors.divider, height: 1),
                const SizedBox(height: 12),

                // Approval Action Buttons
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.rejected, size: 20),
                      tooltip: 'Remove Request',
                      onPressed: () => _deleteStockEntry(tx),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.cardBorder),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('View'),
                      onPressed: () => EntryDetailDialog.show(
                        context,
                        stockTransaction: tx,
                        onEdit: projectHeadCanApproveStock ? () => _editAndApproveStock(tx) : null,
                        onApprove: projectHeadCanApproveStock ? () => _approveStockEntry(tx) : null,
                        onReject: projectHeadCanApproveStock ? () => _rejectStockEntry(tx) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.rejected,
                          side: const BorderSide(color: AppColors.rejected),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text('Reject'),
                        onPressed: projectHeadCanApproveStock ? () => _rejectStockEntry(tx) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.waveCyan,
                          side: const BorderSide(color: AppColors.waveCyan),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.edit_note_rounded, size: 16),
                        label: const Text('Edit & OK'),
                        onPressed: projectHeadCanApproveStock ? () => _editAndApproveStock(tx) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: projectHeadCanApproveStock ? AppColors.approved : AppColors.cardBorder,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(projectHeadCanApproveStock ? Icons.check_circle_rounded : Icons.lock_rounded, size: 18),
                        label: Text(
                          !projectHeadCanApproveStock
                              ? 'Extracted by Admin'
                              : (accountsCanApproveStock ? 'Approve ➔ Accounts' : 'Approve ➔ Admin (Direct)'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: projectHeadCanApproveStock ? () => _approveStockEntry(tx) : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TAB 3: ATTENDANCE REGULARIZATION (Site Staff ➔ Project Head ➔ Admin)
  // ─────────────────────────────────────────────────────────────
  Widget _buildAttendanceApprovalsList(List<AttendanceRecordModel> list) {
    final roleAccess = ref.watch(roleAccessProvider);
    final canApproveAttendance = roleAccess.projectHeadCanApproveAttendance;

    if (list.isEmpty) {
      return _buildEmptyState(
        title: 'No Pending Regularization Requests',
        subtitle: 'All late arrivals (>40m) or punch requests have been reviewed and forwarded to Admin.',
        icon: Icons.how_to_reg_rounded,
        color: const Color(0xFF14B8A6),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final req = list[i];
        final inTimeStr = req.punchInTime != null ? DateFormat('hh:mm a').format(req.punchInTime!) : '--:--';

        return Card(
          color: AppColors.cardDark,
          margin: const EdgeInsets.only(bottom: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF14B8A6), width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14B8A6).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        req.siteName,
                        style: const TextStyle(color: Color(0xFF14B8A6), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    Text(
                      DateFormat('dd MMM yyyy').format(req.date),
                      style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF14B8A6).withOpacity(0.15),
                      child: const Icon(Icons.person_outline_rounded, color: Color(0xFF14B8A6)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            req.staffName,
                            style: AppTextStyles.h4.copyWith(color: Colors.white, fontSize: 16),
                          ),
                          Text(
                            'Punched In: $inTimeStr • ${req.lateMinutes} mins late',
                            style: const TextStyle(color: AppColors.pending, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reason for Delay:',
                        style: TextStyle(color: AppColors.goldAccent, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        req.regularizationReason ?? 'No reason provided',
                        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                      ),
                    ],
                  ),
                ),

                if (req.distanceMeters != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'GPS Distance from Site: ${req.distanceMeters!.toStringAsFixed(0)} meters (${req.isWithinSite ? "Inside Geofence" : "Outside Geofence"})',
                    style: AppTextStyles.caption.copyWith(color: req.isWithinSite ? AppColors.approved : AppColors.pending),
                  ),
                ],

                const SizedBox(height: 14),
                const Divider(color: AppColors.divider, height: 1),
                const SizedBox(height: 12),

                // Attendance Review Actions (Project Head ➔ Admin)
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.cardBorder),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('View'),
                      onPressed: () => EntryDetailDialog.show(
                        context,
                        attendanceRecord: req,
                        onApprove: canApproveAttendance ? () => _approveAttendance(req, halfDay: false) : null,
                        onReject: canApproveAttendance ? () => _rejectAttendance(req) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.rejected,
                          side: const BorderSide(color: AppColors.rejected),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: canApproveAttendance ? () => _rejectAttendance(req) : null,
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.pending,
                          side: const BorderSide(color: AppColors.pending),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: canApproveAttendance ? () => _approveAttendance(req, halfDay: true) : null,
                        child: const Text('Half Day'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canApproveAttendance ? const Color(0xFF14B8A6) : AppColors.cardBorder,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(canApproveAttendance ? Icons.check_circle_rounded : Icons.lock_rounded, size: 18),
                        label: Text(
                          canApproveAttendance ? 'Verify ➔ Admin' : 'Extracted by Admin',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: canApproveAttendance ? () => _approveAttendance(req, halfDay: false) : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TAB 4: DAILY SITE REPORTS (DSR)
  // ─────────────────────────────────────────────────────────────
  Widget _buildDsrApprovalsList(List<DailySiteReportModel> list, List<SiteModel> sites) {
    final roleAccess = ref.watch(roleAccessProvider);
    final canApproveDSR = roleAccess.projectHeadCanApproveDSR;

    if (list.isEmpty) {
      return _buildEmptyState(
        title: 'No Pending Daily Reports',
        subtitle: 'All daily work reports have been reviewed and approved.',
        icon: Icons.record_voice_over_rounded,
        color: AppColors.goldAccent,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final r = list[i];
        final siteName = _getSiteName(sites, r.siteId);

        return Card(
          color: AppColors.cardDark,
          margin: const EdgeInsets.only(bottom: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.goldAccent.withOpacity(0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.goldAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        siteName,
                        style: const TextStyle(color: AppColors.goldAccent, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    Text(
                      DateFormat('dd MMM yyyy').format(r.date),
                      style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.waveCyan.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.waveCyan.withOpacity(0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_rounded, size: 14, color: AppColors.waveCyan),
                      const SizedBox(width: 6),
                      Text(
                        'Submitted by: ${r.submittedBy != null && r.submittedBy!.isNotEmpty ? r.submittedBy : "Site Worker"}',
                        style: const TextStyle(color: AppColors.waveCyan, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                if (r.rawTranscript != null && r.rawTranscript!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.mic_rounded, size: 14, color: AppColors.goldAccent),
                            SizedBox(width: 6),
                            Text('Voice Note Transcript:', style: TextStyle(color: AppColors.goldAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(r.rawTranscript!, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3)),
                      ],
                    ),
                  ),
                ],

                if (r.workDone.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('Work Executed Today:', style: TextStyle(color: AppColors.waveCyan, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ...r.workDone.map((w) => Padding(
                        padding: const EdgeInsets.only(left: 6, bottom: 2),
                        child: Text('• $w', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      )),
                ],

                if (r.photoUrls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  PhotoThumbnailStrip(photoUrls: r.photoUrls),
                ],

                const SizedBox(height: 14),
                const Divider(color: AppColors.divider, height: 1),
                const SizedBox(height: 12),

                // Report Approval Actions
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.cardBorder),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('View'),
                      onPressed: () => EntryDetailDialog.show(
                        context,
                        dailyReport: r,
                        onApprove: canApproveDSR ? () => _approveReport(r) : null,
                        onReject: canApproveDSR ? () => _rejectReport(r) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.rejected,
                          side: const BorderSide(color: AppColors.rejected),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: canApproveDSR ? () => _rejectReport(r) : null,
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canApproveDSR ? AppColors.goldAccent : AppColors.cardBorder,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(canApproveDSR ? Icons.verified_rounded : Icons.lock_rounded, size: 18),
                        label: Text(
                          canApproveDSR ? 'Verify & Approve DSR' : 'Extracted by Admin',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: canApproveDSR ? () => _approveReport(r) : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Empty State Widget
  // ─────────────────────────────────────────────────────────────
  Widget _buildEmptyState({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: color),
            ),
            const SizedBox(height: 20),
            Text(title, style: AppTextStyles.h3.copyWith(color: Colors.white)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Actions: CASH APPROVAL / REJECTION / EDIT
  // ─────────────────────────────────────────────────────────────
  Future<void> _approveCashEntry(CashTransactionModel tx) async {
    final roleAccess = ref.read(roleAccessProvider);
    final bypassAccounts = !roleAccess.accountsCanApproveCash;
    final targetStatus =
        bypassAccounts ? TransactionStatus.pendingAdmin : TransactionStatus.pendingAccounts;
    final bypassTag =
        bypassAccounts ? ' [Accounts Verification: Bypassed by Admin Policy]' : '';

    final cleaned = (tx.remarks ?? '')
        .replaceAll('[Project Head Review: Pending]', '')
        .replaceAll('[Supervisor Review: Pending]', '')
        .trim();
    final updatedRemarks =
        '$cleaned [Project Head: Approved by $_currentProjectHeadName]$bypassTag'.trim();

    final updated = tx.copyWith(
      remarks: updatedRemarks,
      status: targetStatus,
    );

    final ok = await ref.read(cashProvider.notifier).updateTransaction(updated);
    if (mounted) {
      final err = ref.read(cashProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? (bypassAccounts
                  ? 'Cash expense approved! Bypassed Accounts & forwarded directly to Admin.'
                  : 'Cash expense approved! Forwarded to Accounts.')
              : 'Failed to approve expense${err != null ? ": $err" : ""}'),
          backgroundColor: ok ? AppColors.approved : AppColors.rejected,
        ),
      );
      if (ok) _refreshAllData();
    }
  }

  void _editAndApproveCash(CashTransactionModel tx) {
    final amountController = TextEditingController(text: tx.expenseAmount.toString());
    final remarksController = TextEditingController(text: tx.cleanRemarks ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit & Approve Expense', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Amount (₹)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: remarksController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Project Head Guidance Note'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final roleAccess = ref.read(roleAccessProvider);
              final bypassAccounts = !roleAccess.accountsCanApproveCash;
              final targetStatus = bypassAccounts
                  ? TransactionStatus.pendingAdmin
                  : TransactionStatus.pendingAccounts;
              final bypassTag = bypassAccounts
                  ? ' [Accounts Verification: Bypassed by Admin Policy]'
                  : '';

              final newAmt = double.tryParse(amountController.text) ?? tx.expenseAmount;
              final cleaned = (tx.remarks ?? '')
                  .replaceAll('[Project Head Review: Pending]', '')
                  .replaceAll('[Supervisor Review: Pending]', '')
                  .trim();
              final note = remarksController.text.trim();
              final updatedRemarks =
                  '$cleaned [Project Head: Edited & Approved by $_currentProjectHeadName] ${note.isNotEmpty ? "Note: $note" : ""}$bypassTag'
                      .trim();

              final updated = tx.copyWith(
                expenseAmount: newAmt,
                remarks: updatedRemarks,
                status: targetStatus,
              );

              final ok = await ref.read(cashProvider.notifier).updateTransaction(updated);
              if (mounted) {
                final err = ref.read(cashProvider).error;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? (bypassAccounts
                            ? 'Expense updated! Bypassed Accounts & forwarded directly to Admin.'
                            : 'Expense updated & forwarded to Accounts!')
                        : 'Update failed${err != null ? ": $err" : ""}'),
                    backgroundColor: ok ? AppColors.approved : AppColors.rejected,
                  ),
                );
                if (ok) _refreshAllData();
              }
            },
            child: const Text('Save & Forward'),
          ),
        ],
      ),
    );
  }

  void _rejectCashEntry(CashTransactionModel tx) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Cash Expense', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: reasonController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Reason for rejection *',
            hintText: 'e.g. Bill photo not clear, mismatch with site ledger',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rejected),
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.pop(ctx);

              final reason = reasonController.text.trim();
              final updatedRemarks = '${tx.remarks ?? ""} [Project Head: Rejected - $reason by $_currentProjectHeadName]'.trim();
              final updated = tx.copyWith(
                remarks: updatedRemarks,
                status: TransactionStatus.rejected,
                rejectionNote: reason,
              );

              final ok = await ref.read(cashProvider.notifier).updateTransaction(updated);
              if (mounted) {
                final err = ref.read(cashProvider).error;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Expense marked rejected.' : 'Failed to reject${err != null ? ": $err" : ""}'),
                    backgroundColor: ok ? AppColors.rejected : Colors.grey,
                  ),
                );
                if (ok) _refreshAllData();
              }
            },
            child: const Text('Confirm Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCashEntry(CashTransactionModel tx) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Expense Request', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to permanently remove this ${tx.displayExpenseTypeName} (₹${tx.expenseAmount.toStringAsFixed(2)}) request?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rejected),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final ok = await ref.read(cashProvider.notifier).deleteTransaction(tx);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Expense request removed.' : 'Failed to remove expense.'),
          backgroundColor: ok ? AppColors.approved : AppColors.rejected,
        ),
      );
      _refreshAllData();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Actions: STOCK APPROVAL / REJECTION / EDIT
  // ─────────────────────────────────────────────────────────────
  Future<void> _approveStockEntry(StockTransactionModel tx) async {
    final roleAccess = ref.read(roleAccessProvider);
    final bypassAccounts = !roleAccess.accountsCanApproveStock;
    final targetStatus =
        bypassAccounts ? TransactionStatus.pendingAdmin : TransactionStatus.pendingAccounts;
    final bypassTag =
        bypassAccounts ? ' [Accounts Verification: Bypassed by Admin Policy]' : '';

    final cleaned = (tx.remarks ?? '')
        .replaceAll('[Project Head Review: Pending]', '')
        .replaceAll('[Supervisor Review: Pending]', '')
        .trim();
    final updatedRemarks =
        '$cleaned [Project Head: Approved by $_currentProjectHeadName]$bypassTag'.trim();

    final updated = tx.copyWith(
      remarks: updatedRemarks,
      status: targetStatus,
    );

    final ok = await ref.read(stockProvider.notifier).updateTransaction(updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? (bypassAccounts
                  ? 'Stock entry approved! Bypassed Accounts & forwarded directly to Admin.'
                  : 'Stock entry approved! Forwarded to Accounts.')
              : 'Failed to approve stock entry'),
          backgroundColor: ok ? AppColors.approved : AppColors.rejected,
        ),
      );
      if (ok) _refreshAllData();
    }
  }

  void _editAndApproveStock(StockTransactionModel tx) {
    final qtyController = TextEditingController(text: tx.quantity.toString());
    final rateController = TextEditingController(text: tx.rate?.toString() ?? '0');
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit & Approve Stock Entry', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(labelText: 'Quantity (${tx.displayMetricUnitName})'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rateController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Rate (₹)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Project Head Note'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final roleAccess = ref.read(roleAccessProvider);
              final bypassAccounts = !roleAccess.accountsCanApproveStock;
              final targetStatus = bypassAccounts
                  ? TransactionStatus.pendingAdmin
                  : TransactionStatus.pendingAccounts;
              final bypassTag = bypassAccounts
                  ? ' [Accounts Verification: Bypassed by Admin Policy]'
                  : '';

              final newQty = double.tryParse(qtyController.text) ?? tx.quantity;
              final newRate = double.tryParse(rateController.text) ?? (tx.rate ?? 0);
              final cleaned = (tx.remarks ?? '')
                  .replaceAll('[Project Head Review: Pending]', '')
                  .replaceAll('[Supervisor Review: Pending]', '')
                  .trim();
              final note = noteController.text.trim();
              final updatedRemarks =
                  '$cleaned [Project Head: Edited & Approved by $_currentProjectHeadName] ${note.isNotEmpty ? "Note: $note" : ""}$bypassTag'
                      .trim();

              final updated = tx.copyWith(
                quantity: newQty,
                rate: newRate,
                remarks: updatedRemarks,
                status: targetStatus,
              );

              final ok = await ref.read(stockProvider.notifier).updateTransaction(updated);
              if (mounted) {
                final err = ref.read(stockProvider).error;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? (bypassAccounts
                            ? 'Stock updated! Bypassed Accounts & forwarded directly to Admin.'
                            : 'Stock updated & forwarded to Accounts!')
                        : 'Update failed${err != null ? ": $err" : ""}'),
                    backgroundColor: ok ? AppColors.approved : AppColors.rejected,
                  ),
                );
                if (ok) _refreshAllData();
              }
            },
            child: const Text('Save & Forward'),
          ),
        ],
      ),
    );
  }

  void _rejectStockEntry(StockTransactionModel tx) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Stock Entry', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: reasonController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Reason for rejection *',
            hintText: 'e.g. Challan missing, incorrect grade delivered',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rejected),
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.pop(ctx);

              final reason = reasonController.text.trim();
              final updatedRemarks = '${tx.remarks ?? ""} [Project Head: Rejected - $reason by $_currentProjectHeadName]'.trim();
              final updated = tx.copyWith(
                remarks: updatedRemarks,
                status: TransactionStatus.rejected,
                rejectionNote: reason,
              );

              final ok = await ref.read(stockProvider.notifier).updateTransaction(updated);
              if (mounted) {
                final err = ref.read(stockProvider).error;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Stock entry rejected.' : 'Failed to reject${err != null ? ": $err" : ""}'),
                    backgroundColor: ok ? AppColors.rejected : Colors.grey,
                  ),
                );
                if (ok) _refreshAllData();
              }
            },
            child: const Text('Confirm Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteStockEntry(StockTransactionModel tx) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Stock Entry', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to permanently remove this stock entry for ${tx.displayProductName}?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rejected),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final ok = await ref.read(stockProvider.notifier).deleteTransaction(tx);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Stock entry removed.' : 'Failed to remove stock entry.'),
          backgroundColor: ok ? AppColors.approved : AppColors.rejected,
        ),
      );
      _refreshAllData();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Actions: ATTENDANCE VERIFICATION (Project Head ➔ Admin)
  // ─────────────────────────────────────────────────────────────
  Future<void> _approveAttendance(AttendanceRecordModel req, {required bool halfDay}) async {
    final note = '[Project Head: Verified & Recommended ${halfDay ? "Half Day" : "Present"} by $_currentProjectHeadName]';

    try {
      await ref.read(attendanceServiceProvider).reviewRegularizationRequest(
            attendanceId: req.id,
            approve: true,
            halfDay: halfDay,
            note: note,
            reviewedBy: 'Project Head: $_currentProjectHeadName',
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Attendance verified & forwarded to Admin (${halfDay ? "Half Day" : "Full Day"})'),
            backgroundColor: const Color(0xFF14B8A6),
          ),
        );
        _refreshAllData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.rejected),
        );
      }
    }
  }

  void _rejectAttendance(AttendanceRecordModel req) {
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Regularization', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: noteController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Reason for rejection *',
            hintText: 'e.g. Unjustified absence, did not inform site manager',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rejected),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(attendanceServiceProvider).reviewRegularizationRequest(
                      attendanceId: req.id,
                      approve: false,
                      note: '[Project Head: Rejected - ${noteController.text.trim()} by $_currentProjectHeadName]',
                      reviewedBy: 'Project Head: $_currentProjectHeadName',
                    );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Regularization request rejected.'), backgroundColor: AppColors.rejected),
                  );
                  _refreshAllData();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.rejected),
                  );
                }
              }
            },
            child: const Text('Confirm Reject'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Actions: DSR VERIFICATION
  // ─────────────────────────────────────────────────────────────
  Future<void> _approveReport(DailySiteReportModel r) async {
    final cleaned = (r.remarks ?? '')
        .replaceAll('[Project Head Review: Pending]', '')
        .replaceAll('[Project Head: Review Pending]', '')
        .replaceAll('[Supervisor Review: Pending]', '')
        .replaceAll('[Supervisor: Review Pending]', '')
        .trim();
    final updatedRemarks = '$cleaned [Project Head: Approved by $_currentProjectHeadName]'.trim();
    final updated = r.copyWith(remarks: updatedRemarks);

    await ref.read(siteReportServiceProvider).saveReport(updated);
    ref.invalidate(allDailyReportsProvider);
    ref.invalidate(siteReportsForDateProvider);
    ref.invalidate(siteReportsForSiteProvider);
    _refreshAllData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Daily site report verified & approved! Forwarded to Admin.'),
          backgroundColor: AppColors.approved,
        ),
      );
    }
  }

  void _rejectReport(DailySiteReportModel r) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Daily Site Report', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: reasonController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Reason for rejection *',
            hintText: 'e.g. Work quantities incomplete, missing mandatory photo evidence',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rejected),
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.pop(ctx);

              final reason = reasonController.text.trim();
              final cleaned = (r.remarks ?? '')
                  .replaceAll('[Project Head Review: Pending]', '')
                  .replaceAll('[Project Head: Review Pending]', '')
                  .replaceAll('[Supervisor Review: Pending]', '')
                  .replaceAll('[Supervisor: Review Pending]', '')
                  .trim();
              final updatedRemarks = '$cleaned [Project Head: Rejected - $reason by $_currentProjectHeadName]'.trim();
              final updated = r.copyWith(remarks: updatedRemarks);

              await ref.read(siteReportServiceProvider).saveReport(updated);
              ref.invalidate(allDailyReportsProvider);
              ref.invalidate(siteReportsForDateProvider);
              ref.invalidate(siteReportsForSiteProvider);
              _refreshAllData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Report marked rejected.'), backgroundColor: AppColors.rejected),
                );
              }
            },
            child: const Text('Confirm Reject'),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to sign out from the Project Head dashboard?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rejected),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authProvider.notifier).signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}
