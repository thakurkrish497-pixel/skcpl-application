import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/localization/app_strings.dart';
import '../../models/attendance_model.dart';
import '../../models/site_model.dart';
import '../../models/site_staff_model.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/site_provider.dart';
import '../../providers/site_staff_provider.dart';
import '../../services/attendance_excel_service.dart';
import '../../services/location_service.dart';
import '../../widgets/language_toggle_button.dart';

/// Admin Command Center for Attendance:
/// 1. Attendance Calendar & Daily Roster (with Automatic Absence Detection)
/// 2. Live Staff Tracker
/// 3. Late Arrival Regularization Requests (Approve / Half-day / Reject)
/// 4. Shift Timings & Geofencing (Company Default + Per-Site / Office Overrides)
class AdminAttendanceScreen extends ConsumerStatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  ConsumerState<AdminAttendanceScreen> createState() =>
      _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends ConsumerState<AdminAttendanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedSiteFilter = 'all';
  String _selectedLiveSiteFilter = 'all';
  DateTime _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _isMonthCalendarExpanded = false;
  String _rosterStatusFilter = 'all'; // 'all', 'present', 'absent', 'pending'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showEditShiftDialog(SiteShiftPolicyModel policy, [SiteModel? site]) {
    final startTimeController =
        TextEditingController(text: policy.shiftStartTime);
    final endTimeController = TextEditingController(text: policy.shiftEndTime);
    final graceController =
        TextEditingController(text: policy.graceMinutes.toString());
    final lateCutoffController =
        TextEditingController(text: policy.lateCutoffMinutes.toString());
    final radiusController =
        TextEditingController(text: policy.allowedRadiusMeters.toString());
    final latController =
        TextEditingController(text: policy.latitude?.toString() ?? '');
    final lngController =
        TextEditingController(text: policy.longitude?.toString() ?? '');

    final isDefault = site == null && policy.siteId == 'global';
    final title = isDefault
        ? 'Company Default Shift'
        : 'Shift Policy: ${site?.name ?? policy.siteName}';

    bool isCapturingGps = false;
    String? gpsCaptureStatus;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.access_time_filled_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: AppTextStyles.h4)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: startTimeController,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Start Time (HH:mm)',
                          hintText: '09:00',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: endTimeController,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'End Time (HH:mm)',
                          hintText: '18:00',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: graceController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Grace (mins)',
                          hintText: '15',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: lateCutoffController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Late Cutoff (mins)',
                          hintText: '40',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: radiusController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Allowed Radius (meters)',
                    hintText: '500',
                    helperText: 'Radius circle within which staff is considered On-Site',
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: AppColors.divider),
                const SizedBox(height: 8),

                // Geofence GPS Coordinates Header & Explanation
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Site / Office GPS Pin',
                      style: AppTextStyles.bodyMedium
                          .copyWith(fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                    if (latController.text.isNotEmpty && lngController.text.isNotEmpty)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 14, color: AppColors.primary),
                        label: const Text('View Pin on Map', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          final lat = double.tryParse(latController.text.trim());
                          final lng = double.tryParse(lngController.text.trim());
                          if (lat != null && lng != null) {
                            launchUrl(
                              Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'How it works: Punch-in & live tracking use this GPS pin to calculate exact distance. Staff within radius are marked "On-Site".',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                ),
                const SizedBox(height: 10),

                // 1-Click "Capture Current GPS Pin" Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary.withOpacity(0.15),
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: isCapturingGps
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          )
                        : const Icon(Icons.my_location_rounded, size: 18),
                    label: Text(
                      isCapturingGps
                          ? 'Detecting GPS from Device...'
                          : '📍 Capture My Current Location as Pin',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    onPressed: isCapturingGps
                        ? null
                        : () async {
                            setDialogState(() {
                              isCapturingGps = true;
                              gpsCaptureStatus = null;
                            });

                            final res = await LocationService.getCurrentLocationDetailed();

                            setDialogState(() {
                              isCapturingGps = false;
                              if (res.position != null) {
                                latController.text =
                                    res.position!.latitude.toStringAsFixed(6);
                                lngController.text =
                                    res.position!.longitude.toStringAsFixed(6);
                                gpsCaptureStatus =
                                    '✅ Captured: ${latController.text}, ${lngController.text} (±${res.position!.accuracy.toStringAsFixed(0)}m accuracy)';
                              } else {
                                gpsCaptureStatus =
                                    '⚠️ ${res.errorMessage ?? "Failed to acquire GPS."}';
                              }
                            });
                          },
                  ),
                ),
                if (gpsCaptureStatus != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    gpsCaptureStatus!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: gpsCaptureStatus!.startsWith('✅')
                          ? AppColors.approved
                          : AppColors.rejected,
                    ),
                  ),
                ],
                const SizedBox(height: 12),

                // Manual Coordinates Entry
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: latController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                          hintText: '22.719600',
                          prefixIcon: Icon(Icons.explore_outlined, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: lngController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                          hintText: '75.857700',
                          prefixIcon: Icon(Icons.explore_outlined, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () async {
                Navigator.pop(ctx);
                final updated = policy.copyWith(
                  shiftStartTime: startTimeController.text.trim(),
                  shiftEndTime: endTimeController.text.trim(),
                  graceMinutes:
                      int.tryParse(graceController.text.trim()) ?? 15,
                  lateCutoffMinutes:
                      int.tryParse(lateCutoffController.text.trim()) ?? 40,
                  allowedRadiusMeters:
                      double.tryParse(radiusController.text.trim()) ?? 500.0,
                  latitude: double.tryParse(latController.text.trim()),
                  longitude: double.tryParse(lngController.text.trim()),
                );

                await ref.read(attendanceServiceProvider).saveShiftPolicy(updated);
                ref.invalidate(shiftPolicyForSiteProvider(updated.siteId));

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Shift timing & GPS pin saved for ${updated.siteName}!'),
                      backgroundColor: AppColors.approved,
                    ),
                  );
                }
              },
              child: const Text('Save Policy'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleReviewRequest(
    AttendanceRecordModel request, {
    required bool approve,
    bool halfDay = false,
  }) async {
    final noteController = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          approve
              ? (halfDay ? 'Approve as Half Day' : 'Approve as Present')
              : 'Reject Late Attendance Request',
          style: AppTextStyles.h4,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Employee: ${request.staffName} (${request.staffRole})',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              'Reason: "${request.regularizationReason ?? "No reason"}"',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: noteController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Admin Note (Optional)',
                hintText: 'e.g. Approved due to site transport breakdown',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: approve ? AppColors.approved : AppColors.rejected,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? 'Confirm Approval' : 'Confirm Rejection'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final currentAdmin = ref.read(authProvider).user?.fullName ?? 'Admin';
      await ref.read(attendanceServiceProvider).reviewRegularizationRequest(
            attendanceId: request.id,
            approve: approve,
            halfDay: halfDay,
            note: noteController.text.trim().isEmpty
                ? null
                : noteController.text.trim(),
            reviewedBy: currentAdmin,
          );

      ref.invalidate(pendingRegularizationRequestsProvider);
      ref.invalidate(todayAttendanceForSiteProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve
                ? 'Request approved for ${request.staffName}!'
                : 'Request rejected.'),
            backgroundColor: approve ? AppColors.approved : AppColors.rejected,
          ),
        );
      }
    }
  }

  void _showExportExcelDialog() async {
    final sites = ref.read(activeSitesProvider).valueOrNull ?? [];
    String selectedSiteId = _selectedSiteFilter;
    DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    bool isExporting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.file_download_rounded, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text('Monthly Attendance Register',
                    style: TextStyle(color: Colors.white, fontSize: 18)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select month and site to download a clean, payroll-ready Excel spreadsheet.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              // Month selector
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month_rounded, color: AppColors.primary),
                title: Text(DateFormat('MMMM yyyy').format(selectedMonth),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Tap to change month',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedMonth,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                    initialDatePickerMode: DatePickerMode.year,
                  );
                  if (picked != null) {
                    setDialogState(() {
                      selectedMonth = DateTime(picked.year, picked.month, 1);
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              // Site selector
              DropdownButtonFormField<String>(
                value: selectedSiteId,
                dropdownColor: AppColors.cardDark,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(labelText: 'Site / Office Filter'),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All Sites & Indore Office')),
                  ...sites.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedSiteId = val);
                },
              ),
              if (isExporting) ...[
                const SizedBox(height: 20),
                const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download Excel'),
              onPressed: isExporting
                  ? null
                  : () async {
                      setDialogState(() => isExporting = true);
                      try {
                        final startDate = selectedMonth;
                        final daysInMonth = DateTime(selectedMonth.year, selectedMonth.month + 1, 0).day;
                        final endDate = DateTime(selectedMonth.year, selectedMonth.month, daysInMonth, 23, 59, 59);

                        final records = await ref
                            .read(attendanceServiceProvider)
                            .getAttendanceRange(
                              siteId: selectedSiteId,
                              startDate: startDate,
                              endDate: endDate,
                            );

                        String? siteName;
                        if (selectedSiteId != 'all') {
                          siteName = sites.where((s) => s.id == selectedSiteId).firstOrNull?.name;
                        }

                        await AttendanceExcelService.exportMonthlyAttendanceExcel(
                          title: 'Staff Attendance Register',
                          month: selectedMonth,
                          records: records,
                          siteFilterName: siteName,
                        );

                        if (context.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setDialogState(() => isExporting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Export failed: $e'),
                                backgroundColor: AppColors.rejected),
                          );
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingRequestsAsync =
        ref.watch(pendingRegularizationRequestsProvider);
    final pendingCount = pendingRequestsAsync.valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Text(context.tr('attendance_punch')),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: LanguageToggleButton(isCompact: true),
          ),
          IconButton(
            icon: const Icon(Icons.people_alt_rounded),
            tooltip: context.tr('all_staff'),
            onPressed: () => Navigator.pushNamed(context, '/admin-staff'),
          ),
          IconButton(
            icon: const Icon(Icons.file_download_rounded),
            tooltip: context.tr('export_excel'),
            onPressed: _showExportExcelDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(todayAttendanceForSiteProvider);
              ref.invalidate(pendingRegularizationRequestsProvider);
              ref.invalidate(liveStaffLocationsProvider);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          isScrollable: true,
          tabs: [
            const Tab(icon: Icon(Icons.calendar_month_rounded), text: 'Calendar & Roster'),
            Tab(icon: const Icon(Icons.share_location_rounded), text: context.tr('live_location')),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.pending_actions_rounded, size: 18),
                  const SizedBox(width: 6),
                  Text(context.tr('review_approvals')),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.rejected,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$pendingCount',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(icon: Icon(Icons.tune_rounded), text: 'Shift Timings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCalendarRosterTab(),
          _buildLiveLocationTrackerTab(),
          _buildLateRequestsTab(pendingRequestsAsync),
          _buildShiftTimingsTab(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Tab 1: Attendance Calendar & Daily Roster (Simplified & Site-Filtered)
  // ─────────────────────────────────────────────────────────────

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _getSiteName(List<SiteModel> sites, String siteId) {
    if (siteId == 'office' || siteId == 'bdb1478e-4fa9-4873-9804-864b0952fa4d') {
      return 'Indore Head Office';
    }
    final s = sites.where((item) => item.id == siteId).firstOrNull;
    return s?.name ?? 'Site';
  }

  bool _matchesSite(String itemSiteId, String filterSiteId, List<SiteModel> sites) {
    if (filterSiteId == 'all') return true;
    if (itemSiteId == filterSiteId) return true;

    // Check if either is the head office
    final filterSite = sites.where((s) => s.id == filterSiteId).firstOrNull;
    final isFilterOffice = filterSiteId == 'office' ||
        filterSite?.isHeadOffice == true ||
        filterSiteId == 'bdb1478e-4fa9-4873-9804-864b0952fa4d';

    final itemSite = sites.where((s) => s.id == itemSiteId).firstOrNull;
    final isItemOffice = itemSiteId == 'office' ||
        itemSite?.isHeadOffice == true ||
        itemSiteId == 'bdb1478e-4fa9-4873-9804-864b0952fa4d';

    if (isFilterOffice && isItemOffice) return true;

    return false;
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
        _calendarMonth = DateTime(picked.year, picked.month, 1);
      });
    }
  }

  Widget _buildCalendarRosterTab() {
    final sitesAsync = ref.watch(activeSitesProvider);

    return sitesAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('Error loading sites: $e')),
      data: (sites) {
        final filterOptions = [
          (id: 'all', name: 'All Locations'),
          ...sites.map((s) => (id: s.id, name: s.isHeadOffice ? 'Indore Head Office' : s.name)),
        ];

        final currentSiteId = _selectedSiteFilter;
        final staffAsync = ref.watch(allStaffProvider);
        final attendanceAsync = ref.watch(attendanceForDateAndSiteProvider(
            (siteId: currentSiteId, date: _selectedDate)));
        final monthlyAsync = ref.watch(monthlyAttendanceProvider(
            (siteId: currentSiteId, year: _calendarMonth.year, month: _calendarMonth.month)));

        final monthlyRecords = monthlyAsync.valueOrNull ?? [];
        final staffList = staffAsync.valueOrNull ?? [];
        final recordedList = attendanceAsync.valueOrNull ?? [];

        // 1. Filter staff belonging strictly to the selected site
        final activeStaffList = staffList.where((s) => s.isActive).where((s) {
          return _matchesSite(s.siteId, currentSiteId, sites);
        }).toList();

        // 2. Filter attendance punches belonging strictly to the selected site
        final filteredRecordedList = recordedList.where((r) {
          return _matchesSite(r.siteId, currentSiteId, sites);
        }).toList();

        final effectiveRoster = <AttendanceRecordModel>[];
        final recordedStaffIds = <String>{};
        final recordedStaffNames = <String>{};

        for (final r in filteredRecordedList) {
          effectiveRoster.add(r);
          if (r.staffId.isNotEmpty) recordedStaffIds.add(r.staffId);
          if (r.staffName.isNotEmpty) {
            recordedStaffNames.add(r.staffName.trim().toLowerCase());
          }
        }

        // 3. Any active staff member of this site without a punch is marked Absent
        for (final staff in activeStaffList) {
          final isAlreadyMarked = recordedStaffIds.contains(staff.id) ||
              recordedStaffNames.contains(staff.name.trim().toLowerCase());
          if (!isAlreadyMarked) {
            final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
            effectiveRoster.add(AttendanceRecordModel(
              id: 'unmarked-${staff.id}-$dateStr',
              siteId: staff.siteId,
              siteName: _getSiteName(sites, staff.siteId),
              staffId: staff.id,
              staffName: staff.name,
              staffRole: staff.designation?.isNotEmpty == true
                  ? staff.designation!
                  : staff.role.displayName,
              date: _selectedDate,
              punchInTime: null,
              punchOutTime: null,
              status: AttendanceStatus.absent,
              adminDecisionNote: 'Unmarked Attendance • Considered Absent',
              isWithinSite: false,
              lateMinutes: 0,
              createdAt: _selectedDate,
              updatedAt: _selectedDate,
            ));
          }
        }

        // Summary Counts
        final totalStaff = activeStaffList.isNotEmpty
            ? activeStaffList.length
            : effectiveRoster.length;
        final presentCount = effectiveRoster.where((r) => r.isPresent).length;
        final absentCount = effectiveRoster.where((r) => r.isAbsent).length;
        final pendingCount =
            effectiveRoster.where((r) => r.isPendingAdminReview).length;

        // Apply roster status filter
        final filteredRoster = effectiveRoster.where((r) {
          if (_rosterStatusFilter == 'present') return r.isPresent;
          if (_rosterStatusFilter == 'absent') return r.isAbsent;
          if (_rosterStatusFilter == 'pending') return r.isPendingAdminReview;
          return true;
        }).toList();

        // Sort: Pending review first, then Present, then Absent
        filteredRoster.sort((a, b) {
          if (a.isPendingAdminReview && !b.isPendingAdminReview) return -1;
          if (!a.isPendingAdminReview && b.isPendingAdminReview) return 1;
          if (a.isPresent && !b.isPresent) return -1;
          if (!a.isPresent && b.isPresent) return 1;
          return a.staffName.compareTo(b.staffName);
        });

        return Column(
          children: [
            // ── Clean Location Bar ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.surfaceDark,
              child: Row(
                children: [
                  const Icon(Icons.place_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'Site:',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: filterOptions.any((f) => f.id == currentSiteId)
                              ? currentSiteId
                              : 'all',
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceDark,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          items: filterOptions.map((f) => DropdownMenuItem(
                            value: f.id,
                            child: Text(f.name, overflow: TextOverflow.ellipsis),
                          )).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedSiteFilter = val);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                children: [
                  // ── Clean Compact Calendar Header & Week Bar ──
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      children: [
                        // Calendar Header
                        _buildCalendarHeader(context),
                        const SizedBox(height: 8),

                        // Week Strip or Month Grid
                        if (_isMonthCalendarExpanded)
                          _buildMonthCalendarGrid(monthlyRecords)
                        else
                          _buildWeekStrip(monthlyRecords),
                      ],
                    ),
                  ),

                  // ── Unified Interactive Stat Bar ──
                  Row(
                    children: [
                      _buildStatFilterTab('all', 'All Staff', totalStaff, Colors.white),
                      const SizedBox(width: 8),
                      _buildStatFilterTab('present', 'Present', presentCount, AppColors.approved),
                      const SizedBox(width: 8),
                      _buildStatFilterTab('absent', 'Absent', absentCount, AppColors.rejected),
                      if (pendingCount > 0) ...[
                        const SizedBox(width: 8),
                        _buildStatFilterTab('pending', 'Requests', pendingCount, AppColors.pending),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Staff List for Selected Date & Filter ──
                  if (filteredRoster.isEmpty)
                    _buildEmptyCard(_rosterStatusFilter == 'absent'
                        ? 'No absent staff on this day!'
                        : (_rosterStatusFilter == 'present'
                            ? 'No punches recorded on this day.'
                            : 'No staff found for selected site.'))
                  else
                    ...filteredRoster.map((r) {
                      final staffInfo = staffList.where((s) => s.id == r.staffId).firstOrNull;
                      return _buildAttendanceRecordCard(r, staffInfo: staffInfo);
                    }),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Calendar Header with Navigation Controls
  // ─────────────────────────────────────────────────────────────

  Widget _buildCalendarHeader(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = _calendarMonth.year == now.year && _calendarMonth.month == now.month;

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 22),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'Previous Month',
          onPressed: () {
            setState(() {
              _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1, 1);
            });
          },
        ),
        const SizedBox(width: 6),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _pickDate(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                Text(
                  DateFormat('MMMM yyyy').format(_calendarMonth),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_drop_down_rounded, color: AppColors.primary, size: 20),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'Next Month',
          onPressed: () {
            setState(() {
              _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1);
            });
          },
        ),
        const Spacer(),

        // Snap to Today Button
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: isCurrentMonth && _isSameDay(_selectedDate, now)
                ? AppColors.primary.withOpacity(0.15)
                : AppColors.surfaceDark,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          onPressed: () {
            setState(() {
              _selectedDate = DateTime(now.year, now.month, now.day);
              _calendarMonth = DateTime(now.year, now.month, 1);
            });
          },
          child: const Text(
            'Today',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
          ),
        ),
        const SizedBox(width: 8),

        // Toggle Month Grid / Week Strip
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            setState(() => _isMonthCalendarExpanded = !_isMonthCalendarExpanded);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _isMonthCalendarExpanded
                  ? AppColors.primary.withOpacity(0.2)
                  : AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isMonthCalendarExpanded ? AppColors.primary : AppColors.divider,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isMonthCalendarExpanded
                      ? Icons.view_week_rounded
                      : Icons.calendar_month_rounded,
                  size: 13,
                  color: _isMonthCalendarExpanded ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  _isMonthCalendarExpanded ? 'Week' : 'Month',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _isMonthCalendarExpanded ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Full Month Calendar Grid (when expanded)
  // ─────────────────────────────────────────────────────────────

  Widget _buildMonthCalendarGrid(List<AttendanceRecordModel> monthlyRecords) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final firstDay = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final daysInMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    final startOffset = (firstDay.weekday - 1);
    final totalCells = startOffset + daysInMonth;
    final rowCount = (totalCells / 7).ceil();

    return Column(
      children: [
        Row(
          children: weekdays.map((w) {
            return Expanded(
              child: Center(
                child: Text(
                  w,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),

        ...List.generate(rowCount, (rowIndex) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(
              children: List.generate(7, (colIndex) {
                final cellIndex = rowIndex * 7 + colIndex;
                if (cellIndex < startOffset || cellIndex >= totalCells) {
                  return const Expanded(child: SizedBox(height: 32));
                }

                final dayNum = cellIndex - startOffset + 1;
                final cellDate = DateTime(_calendarMonth.year, _calendarMonth.month, dayNum);
                final isSelected = _isSameDay(cellDate, _selectedDate);
                final isToday = _isSameDay(cellDate, DateTime.now());

                final dayPunches = monthlyRecords
                    .where((r) => _isSameDay(r.date, cellDate))
                    .toList();
                final hasPresents = dayPunches.any((r) => r.isPresent);
                final hasAbsents = dayPunches.any((r) => r.isAbsent);

                return Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() => _selectedDate = cellDate);
                    },
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : (isToday ? AppColors.primary.withOpacity(0.15) : Colors.transparent),
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected
                            ? Border.all(color: AppColors.waveCyan, width: 1.5)
                            : (isToday ? Border.all(color: AppColors.primary) : null),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$dayNum',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                              color: isSelected
                                  ? Colors.white
                                  : (isToday ? AppColors.primary : AppColors.textPrimary),
                            ),
                          ),
                          if (hasPresents || hasAbsents) ...[
                            const SizedBox(height: 1),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (hasPresents)
                                  Container(
                                    width: 3.5,
                                    height: 3.5,
                                    margin: const EdgeInsets.symmetric(horizontal: 0.5),
                                    decoration: const BoxDecoration(
                                      color: AppColors.approved,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                if (hasAbsents)
                                  Container(
                                    width: 3.5,
                                    height: 3.5,
                                    margin: const EdgeInsets.symmetric(horizontal: 0.5),
                                    decoration: const BoxDecoration(
                                      color: AppColors.rejected,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Horizontal Week Strip View (Default, Compact & Clean)
  // ─────────────────────────────────────────────────────────────

  Widget _buildWeekStrip(List<AttendanceRecordModel> monthlyRecords) {
    const weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final startOfWeek = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));

    return Row(
      children: List.generate(7, (i) {
        final dayDate = startOfWeek.add(Duration(days: i));
        final isSelected = _isSameDay(dayDate, _selectedDate);
        final isToday = _isSameDay(dayDate, DateTime.now());

        final dayPunches =
            monthlyRecords.where((r) => _isSameDay(r.date, dayDate)).toList();
        final hasPresents = dayPunches.any((r) => r.isPresent);
        final hasAbsents = dayPunches.any((r) => r.isAbsent);

        return Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() {
                _selectedDate = dayDate;
                if (dayDate.month != _calendarMonth.month) {
                  _calendarMonth = DateTime(dayDate.year, dayDate.month, 1);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : (isToday ? AppColors.primary.withOpacity(0.12) : AppColors.surfaceDark),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? AppColors.waveCyan
                      : (isToday ? AppColors.primary.withOpacity(0.5) : AppColors.divider),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    weekdayLabels[i],
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white70 : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${dayDate.day}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (hasPresents)
                        Container(
                          width: 3.5,
                          height: 3.5,
                          margin: const EdgeInsets.symmetric(horizontal: 0.5),
                          decoration: const BoxDecoration(
                            color: AppColors.approved,
                            shape: BoxShape.circle,
                          ),
                        ),
                      if (hasAbsents)
                        Container(
                          width: 3.5,
                          height: 3.5,
                          margin: const EdgeInsets.symmetric(horizontal: 0.5),
                          decoration: const BoxDecoration(
                            color: AppColors.rejected,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Unified Interactive Stat Filter Tab
  // ─────────────────────────────────────────────────────────────

  Widget _buildStatFilterTab(String filterId, String label, int count, Color color) {
    final isSelected = _rosterStatusFilter == filterId;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() => _rosterStatusFilter = filterId);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.18) : AppColors.cardDark,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : AppColors.divider,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? color : Colors.white,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? color : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Simple, Clean Attendance Card
  // ─────────────────────────────────────────────────────────────

  Widget _buildAttendanceRecordCard(AttendanceRecordModel r, {SiteStaffModel? staffInfo}) {
    final isUnmarked = r.isUnmarkedAbsent;
    final inStr = r.punchInTime != null
        ? DateFormat('hh:mm a').format(r.punchInTime!)
        : null;
    final outStr = r.punchOutTime != null
        ? DateFormat('hh:mm a').format(r.punchOutTime!)
        : (r.isPunchedIn ? 'Active' : null);

    final phone = staffInfo?.phone;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isUnmarked
            ? AppColors.rejected.withOpacity(0.05)
            : AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUnmarked
              ? AppColors.rejected.withOpacity(0.3)
              : (r.isPendingAdminReview
                  ? AppColors.pending.withOpacity(0.4)
                  : AppColors.divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Circle Avatar
              CircleAvatar(
                radius: 16,
                backgroundColor: isUnmarked
                    ? AppColors.rejected.withOpacity(0.18)
                    : (r.isPresent
                        ? AppColors.approved.withOpacity(0.18)
                        : AppColors.pending.withOpacity(0.18)),
                child: Icon(
                  isUnmarked
                      ? Icons.close_rounded
                      : (r.isPresent ? Icons.check_rounded : Icons.pending_rounded),
                  size: 16,
                  color: isUnmarked
                      ? AppColors.rejected
                      : (r.isPresent ? AppColors.approved : AppColors.pending),
                ),
              ),
              const SizedBox(width: 10),

              // Staff Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.staffName,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${r.staffRole} • ${r.siteName}',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),

              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isUnmarked
                      ? AppColors.rejected.withOpacity(0.15)
                      : (r.isPresent
                          ? AppColors.approved.withOpacity(0.15)
                          : AppColors.pending.withOpacity(0.15)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isUnmarked
                      ? 'Absent'
                      : (r.isPendingAdminReview
                          ? 'Review'
                          : (r.lateMinutes > 0 ? '+${r.lateMinutes}m Late' : 'Present')),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isUnmarked
                        ? AppColors.rejected
                        : (r.isPresent ? AppColors.approved : AppColors.pending),
                  ),
                ),
              ),
            ],
          ),

          // Sub-row: Punch Time or Direct Call option
          const SizedBox(height: 6),
          Row(
            children: [
              if (isUnmarked) ...[
                const Icon(Icons.info_outline_rounded, size: 12, color: AppColors.rejected),
                const SizedBox(width: 4),
                const Text(
                  'Did not mark attendance',
                  style: TextStyle(fontSize: 11, color: AppColors.rejected),
                ),
                if (phone != null && phone.isNotEmpty) ...[
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => launchUrl(Uri.parse('tel:$phone')),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.call_rounded, size: 12, color: AppColors.approved),
                          const SizedBox(width: 4),
                          Text(phone, style: const TextStyle(fontSize: 11, color: AppColors.approved, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ] else ...[
                const Icon(Icons.login_rounded, size: 12, color: AppColors.approved),
                const SizedBox(width: 4),
                Text('In: ${inStr ?? "--"}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                const SizedBox(width: 12),
                const Icon(Icons.logout_rounded, size: 12, color: AppColors.secondary),
                const SizedBox(width: 4),
                Text('Out: ${outStr ?? "--"}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
              ],
            ],
          ),

          // If pending regularization request
          if (r.isPendingAdminReview) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Reason: ${r.regularizationReason ?? "Late arrival"}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.approved,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: const Size(54, 26),
                  ),
                  onPressed: () => _handleReviewRequest(r, approve: true),
                  child: const Text('Approve', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.rejected,
                    side: const BorderSide(color: AppColors.rejected),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: const Size(50, 26),
                  ),
                  onPressed: () => _handleReviewRequest(r, approve: false),
                  child: const Text('Reject', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Tab 2: WhatsApp-Style Live Location Tracker
  // ─────────────────────────────────────────────────────────────

  Widget _buildLiveLocationTrackerTab() {
    final liveLocsAsync = ref.watch(liveStaffLocationsProvider(null));
    final sitesAsync = ref.watch(activeSitesProvider);

    return liveLocsAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (allPings) {
        // Filter by selected site if specified
        final pings = _selectedLiveSiteFilter == 'all'
            ? allPings
            : allPings.where((p) => p.siteId == _selectedLiveSiteFilter).toList();

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(liveStaffLocationsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Top Control Bar: Site Filter + Live Status Indicator + Refresh
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedLiveSiteFilter,
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceDark,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 13),
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Text('All Sites & Indore Office'),
                            ),
                            const DropdownMenuItem(
                              value: 'office',
                              child: Text('🏢 Indore Head Office'),
                            ),
                            if (sitesAsync.hasValue)
                              ...sitesAsync.value!.map(
                                (s) => DropdownMenuItem(
                                  value: s.id,
                                  child: Text('🏗 ${s.name}'),
                                ),
                              ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedLiveSiteFilter = val);
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
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF25D366),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${pings.length} Live',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
                    tooltip: 'Refresh Live Locations',
                    onPressed: () {
                      ref.invalidate(liveStaffLocationsProvider);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),

              if (pings.isEmpty)
                _buildEmptyCard('No active live location pings reported today for selected filter.')
              else
                ...pings.map((ping) {
                  final isInside = ping.isWithinSite;
                  final timeDiff = DateTime.now().difference(ping.timestamp);
                  final isLiveNow = timeDiff.inMinutes <= 15;
                  final relativeTimeStr = timeDiff.inMinutes < 1
                      ? 'Just now'
                      : (timeDiff.inMinutes < 60
                          ? '${timeDiff.inMinutes}m ago'
                          : '${timeDiff.inHours}h ago');
                  final clockTime = DateFormat('hh:mm a').format(ping.timestamp);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isInside
                            ? const Color(0xFF25D366).withOpacity(0.4)
                            : AppColors.pending.withOpacity(0.4),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isInside ? const Color(0xFF25D366) : AppColors.pending)
                              .withOpacity(0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Card Header: Staff Identity + Pulse Indicator + Timestamp
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: isInside
                                        ? const Color(0xFF25D366).withOpacity(0.18)
                                        : AppColors.pending.withOpacity(0.18),
                                    child: Text(
                                      ping.staffName.isNotEmpty
                                          ? ping.staffName[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: isInside
                                            ? const Color(0xFF25D366)
                                            : AppColors.pending,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: isLiveNow
                                            ? const Color(0xFF25D366)
                                            : AppColors.textTertiary,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: AppColors.cardDark, width: 2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          ping.staffName,
                                          style: AppTextStyles.bodyMedium.copyWith(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isLiveNow
                                                ? const Color(0xFF25D366)
                                                    .withOpacity(0.15)
                                                : Colors.grey.withOpacity(0.15),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            isLiveNow
                                                ? '🟢 LIVE • $relativeTimeStr'
                                                : '⏱ $relativeTimeStr ($clockTime)',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isLiveNow
                                                  ? const Color(0xFF25D366)
                                                  : AppColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${ping.staffRole} • ${ping.siteName}',
                                      style: AppTextStyles.caption.copyWith(
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // WhatsApp-Style Geotag Coordinates Box
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF131C24),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.06),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Coordinates Row + Quick Copy
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on_rounded,
                                          size: 16, color: Color(0xFF25D366)),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${ping.latitude.toStringAsFixed(6)}°, ${ping.longitude.toStringAsFixed(6)}°',
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                  InkWell(
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(
                                          text:
                                              '${ping.latitude},${ping.longitude}'));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'GPS coordinates copied to clipboard!'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.copy_rounded,
                                              size: 13,
                                              color: AppColors.primary),
                                          SizedBox(width: 4),
                                          Text('Copy',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.primary)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),

                              // Geofence Proximity Status
                              Row(
                                children: [
                                  Icon(
                                    isInside
                                        ? Icons.verified_rounded
                                        : Icons.warning_amber_rounded,
                                    size: 14,
                                    color: isInside
                                        ? const Color(0xFF25D366)
                                        : AppColors.pending,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      isInside
                                          ? 'On-Site • Within ${(ping.distanceMeters).toStringAsFixed(0)}m of ${ping.siteName}'
                                          : 'Outside Site Perimeter • ${(ping.distanceMeters / 1000).toStringAsFixed(2)} km away from ${ping.siteName}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isInside
                                            ? const Color(0xFF25D366)
                                            : AppColors.pending,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              // GPS Accuracy
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.gps_fixed_rounded,
                                      size: 13,
                                      color: AppColors.textTertiary),
                                  const SizedBox(width: 6),
                                  Text(
                                    'GPS Accuracy: ±${ping.accuracyMeters != null ? ping.accuracyMeters!.toStringAsFixed(0) : '5'} meters',
                                    style: AppTextStyles.caption.copyWith(
                                        color: AppColors.textTertiary,
                                        fontSize: 11),
                                  ),
                                ],
                              ),

                              if (ping.address != null &&
                                  ping.address!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.place_outlined,
                                        size: 13,
                                        color: AppColors.textTertiary),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        ping.address!,
                                        style: AppTextStyles.caption.copyWith(
                                            color: AppColors.textSecondary,
                                            fontSize: 11),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                        // WhatsApp Action Buttons: "Open in Google Maps" + "Directions"
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF25D366),
                                    foregroundColor: Colors.black,
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    elevation: 2,
                                  ),
                                  icon: const Icon(Icons.map_rounded, size: 18),
                                  label: const Text(
                                    'Open in Google Maps',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  onPressed: () {
                                    final mapsUrl =
                                        'https://www.google.com/maps/search/?api=1&query=${ping.latitude},${ping.longitude}';
                                    launchUrl(
                                      Uri.parse(mapsUrl),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                        color: Colors.white.withOpacity(0.3)),
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(Icons.directions_rounded,
                                      size: 17, color: AppColors.primary),
                                  label: const Text(
                                    'Directions',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  onPressed: () {
                                    final dirUrl =
                                        'https://www.google.com/maps/dir/?api=1&destination=${ping.latitude},${ping.longitude}';
                                    launchUrl(
                                      Uri.parse(dirUrl),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Tab 3: Late Requests (Regularization)
  // ─────────────────────────────────────────────────────────────

  Widget _buildLateRequestsTab(
      AsyncValue<List<AttendanceRecordModel>> requestsAsync) {
    return requestsAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (requests) {
        final sorted = [...requests]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (sorted.isEmpty) {
          return _buildEmptyCard('No pending late arrival requests.');
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, idx) {
            final req = sorted[idx];
            final dateStr = DateFormat('dd MMM yyyy').format(req.date);

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.pending.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(req.staffName,
                          style: AppTextStyles.h4.copyWith(fontSize: 16)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.rejected.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '+${req.lateMinutes} mins Late',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.rejected),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${req.staffRole} • ${req.siteName} • $dateStr',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textTertiary)),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Reason Given:',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.pending)),
                        const SizedBox(height: 2),
                        Text(
                          req.regularizationReason ?? 'No reason provided',
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (req.adminDecisionNote != null && req.adminDecisionNote!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14B8A6).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF14B8A6).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_rounded, size: 14, color: Color(0xFF14B8A6)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              req.adminDecisionNote!,
                              style: const TextStyle(color: Color(0xFF14B8A6), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.rejected,
                            side: const BorderSide(color: AppColors.rejected),
                          ),
                          onPressed: () =>
                              _handleReviewRequest(req, approve: false),
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.pending,
                            side: const BorderSide(color: AppColors.pending),
                          ),
                          onPressed: () => _handleReviewRequest(req,
                              approve: true, halfDay: true),
                          child: const Text('Half Day'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.approved),
                          onPressed: () => _handleReviewRequest(req,
                              approve: true, halfDay: false),
                          child: const Text('Present'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Tab 4: Shift Timings & Geofencing (Default + Overrides)
  // ─────────────────────────────────────────────────────────────

  Widget _buildShiftTimingsTab() {
    final sitesAsync = ref.watch(activeSitesProvider);
    final globalPolicyAsync = ref.watch(shiftPolicyForSiteProvider('global'));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Company Default Timing Card
        globalPolicyAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => const SizedBox(),
          data: (policy) => Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.18),
                  AppColors.cardDark,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.business_rounded, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text('Company Default Shift', style: AppTextStyles.h4),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          color: AppColors.primary),
                      onPressed: () => _showEditShiftDialog(policy),
                      tooltip: 'Edit Default Timing',
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Timing: ${policy.shiftStartTime} – ${policy.shiftEndTime}  •  Grace: ${policy.graceMinutes}m  •  Late Cutoff: ${policy.lateCutoffMinutes}m',
                  style: AppTextStyles.bodyMedium
                      .copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'All sites use this timing unless overridden individually below.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Per-Site & Office Overrides', style: AppTextStyles.h4),
            Text('Tap edit to customize',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textTertiary)),
          ],
        ),
        const SizedBox(height: 10),

        // List of sites + Indore Office
        sitesAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Text('Error: $e'),
          data: (sites) {
            final list = [
              SiteModel(
                id: 'office',
                name: 'Indore Head Office',
                siteLoginId: 'indore-office',
                allocatedBudget: 0,
                createdAt: DateTime(2026, 1, 1),
                updatedAt: DateTime(2026, 1, 1),
              ),
              ...sites,
            ];

            return Column(
              children: list.map((site) {
                final sitePolicyAsync =
                    ref.watch(shiftPolicyForSiteProvider(site.id));
                final policy = sitePolicyAsync.valueOrNull;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: site.id == 'office'
                            ? AppColors.primary.withOpacity(0.15)
                            : AppColors.secondary.withOpacity(0.15),
                        child: Icon(
                          site.id == 'office'
                              ? Icons.apartment_rounded
                              : Icons.foundation_rounded,
                          color: site.id == 'office'
                              ? AppColors.primary
                              : AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(site.name,
                                style: AppTextStyles.bodyMedium
                                    .copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(
                              policy != null
                                  ? 'Shift: ${policy.shiftStartTime} – ${policy.shiftEndTime} (Cutoff: ${policy.lateCutoffMinutes}m)'
                                  : 'Using Company Default',
                              style: AppTextStyles.caption
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 3),
                            if (policy?.latitude != null && policy?.longitude != null)
                              Row(
                                children: [
                                  const Icon(Icons.location_on_rounded, size: 12, color: AppColors.approved),
                                  const SizedBox(width: 4),
                                  Text(
                                    'GPS: ${policy!.latitude!.toStringAsFixed(4)}, ${policy.longitude!.toStringAsFixed(4)} (Radius: ${policy.allowedRadiusMeters.toStringAsFixed(0)}m)',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.approved,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            else
                              const Row(
                                children: [
                                  Icon(Icons.location_off_rounded, size: 12, color: AppColors.pending),
                                  SizedBox(width: 4),
                                  Text(
                                    'No GPS Pin Set (Tap Edit to pin location)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.pending,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            size: 20, color: AppColors.primary),
                        onPressed: () {
                          if (policy != null) {
                            _showEditShiftDialog(policy, site);
                          }
                        },
                        tooltip: 'Customize Timing',
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmptyCard(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
