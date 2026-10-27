import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/site_model.dart';
import '../../models/daily_site_report_model.dart';
import '../../providers/site_provider.dart';
import '../../providers/site_report_provider.dart';
import '../../services/excel_service.dart';
import '../../widgets/language_toggle_button.dart';
import '../../core/localization/app_strings.dart';

/// Clean & Uncluttered Daily Site Report Review Screen for Dad & Admin.
/// Focused strictly on: Voice-to-Text Transcribed Work Notes, Project Head Approval Status,
/// Submitted By details, and Attached Construction Photos.
/// Day-wise viewing with Today as default and intuitive previous-day / next-day navigation.
class DailySiteReportsScreen extends ConsumerStatefulWidget {
  final String? initialSiteId;

  const DailySiteReportsScreen({super.key, this.initialSiteId});

  @override
  ConsumerState<DailySiteReportsScreen> createState() => _DailySiteReportsScreenState();
}

class _DailySiteReportsScreenState extends ConsumerState<DailySiteReportsScreen> {
  String? _selectedSiteId;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.initialSiteId != null && widget.initialSiteId!.isNotEmpty) {
      _selectedSiteId = widget.initialSiteId!;
    }
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  void _changeDateBy(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
  }

  void _resetToToday() {
    setState(() {
      _selectedDate = DateTime.now();
    });
  }

  void _refreshReports() {
    ref.invalidate(siteReportsForDateProvider);
    ref.invalidate(allDailyReportsProvider);
  }

  void _exportToExcel(List<DailySiteReportModel> reports, String siteName) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generating Excel Daily Work Report...')),
      );

      await ExcelService.exportDailyWorkReportsExcel(
        siteName: siteName,
        reports: reports,
        startDate: _selectedDate,
        endDate: _selectedDate,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel export error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sitesAsync = ref.watch(activeSitesProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Text(context.tr('daily_site_report', defaultText: 'Daily Site Reports')),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: LanguageToggleButton(isCompact: true),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: context.tr('refresh', defaultText: 'Refresh Reports'),
            onPressed: _refreshReports,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: sitesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error loading sites: $e', style: const TextStyle(color: Colors.red))),
        data: (sites) {
          if (sites.isEmpty) {
            return const Center(child: Text('No active sites found', style: TextStyle(color: Colors.white)));
          }

          _selectedSiteId ??= sites.first.id;
          final currentSite = sites.firstWhere((s) => s.id == _selectedSiteId, orElse: () => sites.first);
          final effectiveSiteName = currentSite.name;

          return Column(
            children: [
              // ── Top Selector Bar: Site Dropdown & Date Navigation ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: AppColors.cardDark,
                child: Column(
                  children: [
                    // Site Dropdown for selecting site to view DSR
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedSiteId,
                          dropdownColor: AppColors.surfaceDark,
                          isExpanded: true,
                          icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary),
                          items: sites.map((s) {
                            final isOffice = s.isHeadOffice;
                            return DropdownMenuItem(
                              value: s.id,
                              child: Row(
                                children: [
                                  Icon(
                                    isOffice ? Icons.apartment_rounded : Icons.construction_rounded,
                                    color: isOffice ? AppColors.waveCyan : AppColors.primary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isOffice ? '${s.name} (Office)' : s.name,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedSiteId = val);
                            }
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Date Navigator: < Yesterday | Formatted Date | Next Day >
                    Row(
                      children: [
                        // Previous Day (Yesterday) Button
                        InkWell(
                          onTap: () => _changeDateBy(-1),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceDark,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 20),
                                Text(
                                  context.tr('yesterday', defaultText: 'Yesterday'),
                                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Date Picker Button
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime(2024),
                                lastDate: DateTime.now().add(const Duration(days: 1)),
                              );
                              if (picked != null) {
                                setState(() => _selectedDate = picked);
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
                              decoration: BoxDecoration(
                                color: _isToday
                                    ? AppColors.primary.withOpacity(0.15)
                                    : AppColors.surfaceDark,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _isToday ? AppColors.primary : AppColors.divider,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.calendar_today_rounded,
                                    color: _isToday ? AppColors.primary : Colors.white70,
                                    size: 15,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      DateFormat('dd MMMM yyyy (EEEE)').format(_selectedDate),
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _isToday ? AppColors.primary : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                  if (_isToday) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.approved,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        context.tr('today', defaultText: 'Today'),
                                        style: const TextStyle(color: Colors.black, fontSize: 9.5, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Next Day Button
                        InkWell(
                          onTap: () => _changeDateBy(1),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceDark,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  context.tr('next_day', defaultText: 'Next'),
                                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                                const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (!_isToday) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _resetToToday,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.today_rounded, size: 14, color: AppColors.primary),
                          label: Text(context.tr('back_to_today', defaultText: 'Back to Today'), style: const TextStyle(color: AppColors.primary, fontSize: 11.5, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Report Content Body ──
              Expanded(
                child: _buildReportBody(effectiveSiteName),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReportBody(String siteName) {
    if (_selectedSiteId == null) return const SizedBox.shrink();

    final reportsAsync = ref.watch(siteReportsForDateProvider(
      (siteId: _selectedSiteId!, date: _selectedDate),
    ));

    return reportsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Error loading reports: $e', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _refreshReports,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (allReports) {
        // Strictly filter to ONLY Project Head approved reports for Admin (hide rejected & pending)
        final reports = allReports.where((r) => r.isProjectHeadApproved).toList();

        if (reports.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.verified_outlined, size: 64, color: AppColors.textTertiary),
                  const SizedBox(height: 16),
                  Text(
                    'No Approved Reports for ${DateFormat('dd MMM yyyy').format(_selectedDate)}',
                    style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isToday
                        ? 'No daily site reports have been approved by the Project Head yet today for $siteName.\n(Non-approved and pending reports are waiting for Project Head verification).'
                        : 'No approved daily site reports found for $siteName on this date.',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (!_isToday)
                    ElevatedButton.icon(
                      onPressed: _resetToToday,
                      icon: const Icon(Icons.today_rounded),
                      label: const Text('View Today\'s Reports'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => _changeDateBy(-1),
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('Check Yesterday\'s Reports'),
                    ),
                ],
              ),
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Banner with Summary & Excel Export
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          siteName.toUpperCase(),
                          style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${reports.length} ${reports.length == 1 ? "Report" : "Reports"} Logged on ${DateFormat('dd MMM yyyy').format(_selectedDate)}',
                          style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _exportToExcel(reports, siteName),
                    icon: const Icon(Icons.file_download_outlined, color: AppColors.primary, size: 18),
                    label: const Text('Export Excel', style: TextStyle(color: AppColors.primary, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── List of All Updates For This Date ──
              ...reports.asMap().entries.map((entry) {
                final idx = entry.key + 1;
                final report = entry.value;
                final timeStr = DateFormat('hh:mm a').format(report.createdAt);

                return Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: report.isProjectHeadApproved
                          ? AppColors.approved.withOpacity(0.4)
                          : report.isProjectHeadRejected
                              ? AppColors.rejected.withOpacity(0.4)
                              : AppColors.divider,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sub-Header: Update Number & Time & Site
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                                ),
                                child: Text(
                                  'UPDATE #$idx  •  $timeStr',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (report.siteName != null && report.siteName!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceDark,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.divider),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.location_on_rounded, size: 12, color: AppColors.waveCyan),
                                      const SizedBox(width: 4),
                                      Text(
                                        report.siteName!,
                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),

                          // Project Head Status Badge
                          _buildApprovalStatusBadge(report),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Submitter Information: Submitted By Whom
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.waveCyan.withOpacity(0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_rounded, size: 15, color: AppColors.waveCyan),
                            const SizedBox(width: 6),
                            Text(
                              'Submitted by: ',
                              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                            ),
                            Text(
                              report.submittedBy != null && report.submittedBy!.isNotEmpty
                                  ? report.submittedBy!
                                  : 'Site Worker',
                              style: const TextStyle(
                                color: AppColors.waveCyan,
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // 1. Pure Voice-to-Text Work Report
                      Row(
                        children: [
                          const Icon(Icons.record_voice_over_rounded, size: 16, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(
                            'DAILY WORK REPORT (VOICE-TO-TEXT)',
                            style: AppTextStyles.overline.copyWith(color: AppColors.textTertiary, letterSpacing: 0.8),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.divider.withOpacity(0.5)),
                        ),
                        child: Text(
                          (report.notes != null && report.notes!.trim().isNotEmpty)
                              ? report.notes!
                              : (report.rawTranscript != null && report.rawTranscript!.trim().isNotEmpty)
                                  ? report.rawTranscript!
                                  : 'No written notes provided with this update.',
                          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
                        ),
                      ),

                      // 2. Project Head Review Remarks
                      if (report.remarks != null && report.remarks!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: report.isProjectHeadApproved
                                ? AppColors.approved.withOpacity(0.10)
                                : report.isProjectHeadRejected
                                    ? AppColors.rejected.withOpacity(0.10)
                                    : AppColors.surfaceDark,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: report.isProjectHeadApproved
                                  ? AppColors.approved.withOpacity(0.3)
                                  : report.isProjectHeadRejected
                                      ? AppColors.rejected.withOpacity(0.3)
                                      : AppColors.divider,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                report.isProjectHeadApproved
                                    ? Icons.verified_rounded
                                    : report.isProjectHeadRejected
                                        ? Icons.info_outline_rounded
                                        : Icons.rate_review_rounded,
                                size: 16,
                                color: report.isProjectHeadApproved
                                    ? AppColors.approved
                                    : report.isProjectHeadRejected
                                        ? AppColors.rejected
                                        : AppColors.goldAccent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  report.remarks!,
                                  style: TextStyle(
                                    color: report.isProjectHeadApproved
                                        ? AppColors.approved
                                        : report.isProjectHeadRejected
                                            ? AppColors.rejected
                                            : AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // 3. Attached Site Photos
                      if (report.photoUrls.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          'ATTACHED PHOTOS (${report.photoUrls.length})',
                          style: AppTextStyles.overline.copyWith(color: AppColors.textTertiary),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 110,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: report.photoUrls.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 10),
                            itemBuilder: (context, pIdx) {
                              final pUrl = report.photoUrls[pIdx];
                              return GestureDetector(
                                onTap: () => _openFullScreenImage(pUrl),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: 130,
                                    color: AppColors.surfaceDark,
                                    child: Image.network(
                                      pUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Center(
                                        child: Icon(Icons.broken_image, color: Colors.white30),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ).animate().fadeIn();
              }),

              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }

  Widget _buildApprovalStatusBadge(DailySiteReportModel report) {
    if (report.isProjectHeadApproved) {
      final approver = report.projectHeadApproverName;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.approved.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.approved.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 13, color: AppColors.approved),
            const SizedBox(width: 4),
            Text(
              approver != null ? 'Project Head Approved ($approver)' : 'Project Head Approved',
              style: const TextStyle(
                color: AppColors.approved,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else if (report.isProjectHeadRejected) {
      final reason = report.projectHeadRejectionReason;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.rejected.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.rejected.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cancel_rounded, size: 13, color: AppColors.rejected),
            const SizedBox(width: 4),
            Text(
              reason != null ? 'Rejected: $reason' : 'Project Head Rejected',
              style: const TextStyle(
                color: AppColors.rejected,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.pending.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.pending.withOpacity(0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 13, color: AppColors.pending),
            SizedBox(width: 4),
            Text(
              'Pending Project Head Approval',
              style: TextStyle(
                color: AppColors.pending,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
  }

  void _openFullScreenImage(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
