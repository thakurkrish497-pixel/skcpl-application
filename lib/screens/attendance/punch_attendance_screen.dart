import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/localization/app_strings.dart';
import '../../models/attendance_model.dart';
import '../../models/site_model.dart';
import '../../models/site_staff_model.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/site_staff_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/location_service.dart';
import '../../widgets/language_toggle_button.dart';
import '../../widgets/skcpl_brand_logo.dart';

/// Screen where site workers, supervisors, and office staff punch their daily attendance
/// with GPS verification and late lockout / regularization requests.
class PunchAttendanceScreen extends ConsumerStatefulWidget {
  final SiteModel? site;
  final SiteStaffModel? staff;

  const PunchAttendanceScreen({
    super.key,
    this.site,
    this.staff,
  });

  @override
  ConsumerState<PunchAttendanceScreen> createState() =>
      _PunchAttendanceScreenState();
}

class _PunchAttendanceScreenState extends ConsumerState<PunchAttendanceScreen> {
  Position? _currentPosition;
  bool _isLoadingLocation = false;
  String? _locationError;
  Timer? _clockTimer;
  Timer? _locationPingTimer;
  DateTime _now = DateTime.now();

  SiteModel? get _site => widget.site ?? ref.read(authProvider).activeSite;
  SiteStaffModel? get _staff => widget.staff ?? ref.read(activeStaffProvider);

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    Future.microtask(() {
      _fetchLocation();
      final currentSite = _site;
      final currentStaff = _staff;
      if (currentSite != null && currentStaff != null) {
        ref.read(staffPunchProvider.notifier).loadTodayRecord(
              siteId: currentSite.id,
              staffId: currentStaff.id,
            ).then((_) {
              final rec = ref.read(staffPunchProvider).todayRecord;
              if (rec?.punchInTime != null && rec?.punchOutTime == null) {
                _startPeriodicLocationPing(currentSite, currentStaff);
              }
            });
      }
    });
  }

  void _startPeriodicLocationPing(SiteModel site, SiteStaffModel staff) {
    _locationPingTimer?.cancel();
    // Periodically update live location every 5 minutes while shift is active
    _locationPingTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      try {
        final pos = await LocationService.getCurrentLocation();
        if (pos != null) {
          final policy = await ref.read(attendanceServiceProvider).getShiftPolicy(site.id);
          double? dist;
          bool isWithin = true;
          if (policy.latitude != null && policy.longitude != null) {
            dist = LocationService.calculateDistanceMeters(
              userLat: pos.latitude,
              userLng: pos.longitude,
              siteLat: policy.latitude!,
              siteLng: policy.longitude!,
            );
            isWithin = dist <= policy.allowedRadiusMeters;
          }
          await ref.read(attendanceServiceProvider).updateLiveLocation(
            StaffLiveLocationModel(
              staffId: staff.id,
              staffName: staff.name,
              staffRole: staff.role.displayName,
              siteId: site.id,
              siteName: site.name,
              latitude: pos.latitude,
              longitude: pos.longitude,
              accuracyMeters: pos.accuracy,
              isWithinSite: isWithin,
              distanceMeters: dist ?? 0,
              timestamp: DateTime.now(),
            ),
          );
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _locationPingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    final result = await LocationService.getCurrentLocationDetailed();
    if (mounted) {
      setState(() {
        _currentPosition = result.position;
        _isLoadingLocation = false;
        if (result.position == null) {
          _locationError = result.errorMessage ?? 'GPS signal unavailable or location permission denied';
        }
      });
    }
  }

  void _showGpsHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.help_outline_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(kIsWeb ? 'Enabling GPS in Browser' : 'Enabling GPS on Your Device'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To enable live GPS verification for attendance:',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            if (kIsWeb) ...[
              _buildHelpStep(
                '1',
                'Click the site settings / tune icon in your browser address bar.',
              ),
              const SizedBox(height: 8),
              _buildHelpStep(
                '2',
                'Change Location from "Block" to "Allow".',
              ),
              const SizedBox(height: 8),
              _buildHelpStep(
                '3',
                'Ensure Location Services are turned ON in your operating system settings.',
              ),
              const SizedBox(height: 8),
              _buildHelpStep(
                '4',
                'Tap the blue Retry GPS button.',
              ),
            ] else ...[
              _buildHelpStep(
                '1',
                'Swipe down your quick settings bar and make sure "Location / GPS" is turned ON.',
              ),
              const SizedBox(height: 8),
              _buildHelpStep(
                '2',
                'Ensure SKCPL has Location Permission enabled ("While using the app").',
              ),
              const SizedBox(height: 8),
              _buildHelpStep(
                '3',
                'If permission was denied, tap "Open Settings" below to grant it instantly.',
              ),
              const SizedBox(height: 8),
              _buildHelpStep(
                '4',
                'Tap "Retry GPS Now" to verify your site presence.',
              ),
            ],
          ],
        ),
        actions: [
          if (!kIsWeb)
            TextButton.icon(
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('Open Settings'),
              onPressed: () {
                LocationService.openAppSettings();
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Navigator.pop(ctx);
              _fetchLocation();
            },
            child: const Text('Retry GPS Now'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpStep(String num, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: AppColors.primary.withOpacity(0.2),
          child: Text(num, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  void _showRegularizationDialog(AttendanceRecordModel record) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.report_problem_rounded, color: AppColors.pending),
            SizedBox(width: 8),
            Text('Request Late Attendance'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You arrived more than 40 minutes after shift start time and were marked Absent.\n\nPlease enter the reason for your delay for Admin approval:',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              maxLines: 3,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'e.g. Site vehicle breakdown, heavy rain on highway...',
                labelText: 'Reason for Late Arrival *',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please write your reason'),
                    backgroundColor: AppColors.rejected,
                  ),
                );
                return;
              }

              Navigator.pop(ctx);

              await ref
                  .read(staffPunchProvider.notifier)
                  .submitRegularizationRequest(
                    attendanceId: record.id,
                    reason: reason,
                  );

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Late attendance request sent to Admin for review.'),
                    backgroundColor: AppColors.approved,
                  ),
                );
              }
            },
            child: const Text('Submit Request'),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePunchIn() async {
    final currentSite = _site;
    final currentStaff = _staff;
    if (currentSite == null || currentStaff == null) return;

    if (!currentStaff.hasModule(StaffModule.attendance)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Access Denied: Attendance tracking is turned off for ${currentStaff.name}.'),
          backgroundColor: AppColors.rejected,
        ),
      );
      return;
    }

    // 1. Validate Geofence before Punch-In
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS Signal Required: Please allow Location Services and tap "Retry GPS" to verify you are on site before punching in.'),
          backgroundColor: AppColors.rejected,
          duration: Duration(seconds: 4),
        ),
      );
      _fetchLocation();
      return;
    }

    try {
      final policy = await ref.read(attendanceServiceProvider).getShiftPolicy(currentSite.id);
      final isHeadOffice = currentSite.isHeadOffice ||
          currentSite.name.toLowerCase().contains('head office') ||
          currentSite.name.toLowerCase().contains('indore office') ||
          currentSite.name.toLowerCase().trim() == 'indore';

      final double? siteLat = policy.latitude ?? (isHeadOffice ? 22.719600 : null);
      final double? siteLng = policy.longitude ?? (isHeadOffice ? 75.857700 : null);
      final double allowedRadius = policy.allowedRadiusMeters > 0 ? policy.allowedRadiusMeters : 10000.0;

      if (siteLat == null || siteLng == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Site Location Not Configured: Admin must set GPS coordinates or Google Maps link for "${currentSite.name}" in Manage Sites before staff can punch attendance.'),
            backgroundColor: AppColors.rejected,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      final distance = LocationService.calculateDistanceMeters(
        userLat: _currentPosition!.latitude,
        userLng: _currentPosition!.longitude,
        siteLat: siteLat,
        siteLng: siteLng,
      );

      if (distance > allowedRadius) {
        final distStr = distance >= 1000
            ? '${(distance / 1000).toStringAsFixed(1)} km'
            : '${distance.toStringAsFixed(0)} meters';
        final radStr = allowedRadius >= 1000
            ? '${(allowedRadius / 1000).toStringAsFixed(0)} km'
            : '${allowedRadius.toStringAsFixed(0)}m';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot Punch In: You are $distStr away from ${currentSite.name}. Attendance requires you to be within $radStr of the site location.'),
            backgroundColor: AppColors.rejected,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Geofence verification error: $e'),
          backgroundColor: AppColors.rejected,
        ),
      );
      return;
    }

    try {
      final record = await ref.read(staffPunchProvider.notifier).punchIn(
            siteId: currentSite.id,
            siteName: currentSite.name,
            staffId: currentStaff.id,
            staffName: currentStaff.name,
            staffRole: currentStaff.role.displayName,
            latitude: _currentPosition?.latitude,
            longitude: _currentPosition?.longitude,
          );

      // Start periodic live location pings
      _startPeriodicLocationPing(currentSite, currentStaff);

      // Transmit initial live location ping
      if (_currentPosition != null) {
        ref.read(attendanceServiceProvider).updateLiveLocation(
              StaffLiveLocationModel(
                staffId: currentStaff.id,
                staffName: currentStaff.name,
                staffRole: currentStaff.role.displayName,
                siteId: currentSite.id,
                siteName: currentSite.name,
                latitude: _currentPosition!.latitude,
                longitude: _currentPosition!.longitude,
                accuracyMeters: _currentPosition!.accuracy,
                isWithinSite: record.isWithinSite,
                distanceMeters: record.distanceMeters ?? 0,
                timestamp: DateTime.now(),
              ),
            );
      }

      if (mounted) {
        if (record.status == AttendanceStatus.absentLateLockout) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Punched in >40m late. Marked as Absent. Please request regularization.'),
              backgroundColor: AppColors.rejected,
              duration: Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(record.status == AttendanceStatus.presentOnTime
                  ? 'Punch-In Successful! Marked Present (On-Time).'
                  : 'Punch-In Successful! Marked Present (Late: ${record.lateMinutes} mins).'),
              backgroundColor: AppColors.approved,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.rejected),
        );
      }
    }
  }

  Future<void> _handlePunchOut(AttendanceRecordModel record) async {
    try {
      await ref.read(staffPunchProvider.notifier).punchOut(
            attendanceId: record.id,
            latitude: _currentPosition?.latitude,
            longitude: _currentPosition?.longitude,
          );

      _locationPingTimer?.cancel();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Punch-Out Successful! Shift closed for today.'),
            backgroundColor: AppColors.approved,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.rejected),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSite = _site;
    final currentStaff = _staff;

    if (currentSite == null || currentStaff == null) {
      return Scaffold(
        backgroundColor: AppColors.scaffoldDark,
        appBar: AppBar(title: const Text('Attendance Punch')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_off_rounded, size: 48, color: AppColors.textTertiary),
              const SizedBox(height: 16),
              const Text('No Site or Staff Member Selected',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/role-login'),
                child: const Text('Go to Login'),
              ),
            ],
          ),
        ),
      );
    }

    final punchState = ref.watch(staffPunchProvider);
    final policyAsync = ref.watch(shiftPolicyForSiteProvider(currentSite.id));
    final policy = policyAsync.valueOrNull;
    final todayRecord = punchState.todayRecord;

    final holidays = ref.watch(holidaysProvider).valueOrNull ?? [];
    final isHeadOffice = currentSite.isHeadOffice;
    final isSundayOff = _now.weekday == DateTime.sunday && isHeadOffice;
    HolidayModel? declaredHoliday;
    for (final h in holidays) {
      if (h.date.year == _now.year && h.date.month == _now.month && h.date.day == _now.day) {
        if (h.appliesTo(currentSite.id, isHeadOffice: isHeadOffice)) {
          declaredHoliday = h;
          break;
        }
      }
    }
    final isHolidayToday = isSundayOff || declaredHoliday != null;
    final holidayName = isSundayOff ? 'Sunday Off (Head Office)' : (declaredHoliday?.title ?? 'Holiday');

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Row(
          children: [
            const SkcplBrandLogo(variant: LogoVariant.compact, customSize: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${currentSite.name} — ${context.tr('attendance_punch')}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: LanguageToggleButton(isCompact: true),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: context.tr('refresh', defaultText: 'Refresh'),
            onPressed: () {
              _fetchLocation();
              ref.read(staffPunchProvider.notifier).loadTodayRecord(
                    siteId: currentSite.id,
                    staffId: currentStaff.id,
                  );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Staff Profile Card
              _buildStaffHeaderCard(currentSite, currentStaff),

              const SizedBox(height: 16),

              // Holiday Announcement Banner
              if (isHolidayToday) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.beach_access_rounded, color: Color(0xFF38BDF8), size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Today is a Holiday — $holidayName',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Attendance is optional today. You are not marked absent. If you are working today, you may still punch in below.',
                              style: TextStyle(color: Color(0xFFBAE6FD), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Live Digital Clock & Date
              _buildLiveClockCard(),

              const SizedBox(height: 16),

              // Shift Timing & Policy Card
              if (policy != null) _buildPolicyCard(policy),

              const SizedBox(height: 16),

              // GPS Geofence Status Card
              _buildLocationStatusCard(policy),

              const SizedBox(height: 24),

              // Attendance Status & Big Action Button
              if (punchState.isLoading)
                const Center(child: CircularProgressIndicator(color: AppColors.primary))
              else
                _buildPunchActionButton(todayRecord, policy),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStaffHeaderCard(SiteModel site, SiteStaffModel staff) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: staff.isSupervisor
                ? AppColors.primary.withOpacity(0.2)
                : AppColors.secondary.withOpacity(0.2),
            child: Icon(
              staff.isSupervisor
                  ? Icons.admin_panel_settings_rounded
                  : Icons.person_rounded,
              color: staff.isSupervisor ? AppColors.primary : AppColors.secondary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  staff.name,
                  style: AppTextStyles.h4,
                ),
                const SizedBox(height: 2),
                Text(
                  '${staff.role.displayName} • ${site.name}',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveClockCard() {
    final timeStr = DateFormat('hh:mm:ss a').format(_now);
    final dateStr = DateFormat('EEEE, dd MMMM yyyy').format(_now);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.18),
            AppColors.cardDark,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            timeStr,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dateStr,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyCard(SiteShiftPolicyModel policy) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildPolicyItem(
            'Shift Start',
            policy.shiftStartTime,
            Icons.wb_sunny_outlined,
            AppColors.primary,
          ),
          Container(width: 1, height: 35, color: AppColors.divider),
          _buildPolicyItem(
            'Shift End',
            policy.shiftEndTime,
            Icons.nightlight_outlined,
            AppColors.secondary,
          ),
          Container(width: 1, height: 35, color: AppColors.divider),
          _buildPolicyItem(
            'Late Cutoff',
            '>${policy.lateCutoffMinutes} min',
            Icons.timer_outlined,
            AppColors.pending,
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary)),
      ],
    );
  }

  Widget _buildLocationStatusCard(SiteShiftPolicyModel? policy) {
    final hasPos = _currentPosition != null;
    final isHeadOffice = _site?.isHeadOffice == true ||
        _site?.name.toLowerCase().contains('head office') == true ||
        _site?.name.toLowerCase().contains('indore office') == true ||
        _site?.name.toLowerCase().trim() == 'indore';

    final double? siteLat = policy?.latitude ?? (isHeadOffice ? 22.719600 : null);
    final double? siteLng = policy?.longitude ?? (isHeadOffice ? 75.857700 : null);
    final double allowedRadius = (policy?.allowedRadiusMeters ?? 0) > 0 ? policy!.allowedRadiusMeters : 10000.0;
    final hasSitePin = siteLat != null && siteLng != null;

    bool isInside = false;
    double? distance;

    if (hasPos && hasSitePin) {
      distance = LocationService.calculateDistanceMeters(
        userLat: _currentPosition!.latitude,
        userLng: _currentPosition!.longitude,
        siteLat: siteLat,
        siteLng: siteLng,
      );
      isInside = distance <= allowedRadius;
    }

    final String statusText;
    final Color statusColor;

    if (_isLoadingLocation) {
      statusText = 'Fetching Live GPS...';
      statusColor = AppColors.pending;
    } else if (!hasPos) {
      statusText = _locationError ?? 'Location Unavailable (Tap Retry GPS)';
      statusColor = AppColors.rejected;
    } else if (!hasSitePin) {
      statusText = 'Site Pin Not Set (Admin must configure coordinates in Manage Sites)';
      statusColor = AppColors.pending;
    } else if (isInside) {
      statusText = 'Inside Geofence (${distance?.toStringAsFixed(0)}m from site center)';
      statusColor = AppColors.approved;
    } else {
      final distKm = (distance! / 1000).toStringAsFixed(1);
      final maxKm = (allowedRadius / 1000).toStringAsFixed(0);
      statusText = 'Outside Boundary ($distKm km away — Max allowed: $maxKm km)';
      statusColor = AppColors.rejected;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusColor.withOpacity(0.4),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: statusColor.withOpacity(0.15),
            child: Icon(
              hasPos
                  ? (isInside ? Icons.my_location_rounded : Icons.location_off_rounded)
                  : Icons.location_disabled_rounded,
              size: 18,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
                if (hasPos) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Your GPS: ${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)} (±${_currentPosition!.accuracy.toStringAsFixed(0)}m)',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                  ),
                  if (hasSitePin) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Site Pin: ${siteLat.toStringAsFixed(5)}, ${siteLng.toStringAsFixed(5)} • Radius: ${(allowedRadius / 1000).toStringAsFixed(0)} km',
                      style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontSize: 11),
                    ),
                  ],
                ],
              ],
            ),
          ),
          if (!hasPos && !_isLoadingLocation) ...[
            IconButton(
              icon: const Icon(Icons.help_outline_rounded, size: 20, color: AppColors.secondary),
              tooltip: 'How to enable GPS in browser',
              onPressed: _showGpsHelpDialog,
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20, color: AppColors.primary),
            onPressed: _fetchLocation,
            tooltip: 'Retry GPS',
          ),
        ],
      ),
    );
  }

  Widget _buildPunchActionButton(AttendanceRecordModel? record, SiteShiftPolicyModel? policy) {
    if (record == null) {
      // Not punched in yet
      final isHeadOffice = _site?.isHeadOffice == true ||
          _site?.name.toLowerCase().contains('head office') == true ||
          _site?.name.toLowerCase().contains('indore office') == true ||
          _site?.name.toLowerCase().trim() == 'indore';

      final double? siteLat = policy?.latitude ?? (isHeadOffice ? 22.719600 : null);
      final double? siteLng = policy?.longitude ?? (isHeadOffice ? 75.857700 : null);
      final double allowedRadius = (policy?.allowedRadiusMeters ?? 0) > 0 ? policy!.allowedRadiusMeters : 10000.0;
      final hasSitePin = siteLat != null && siteLng != null;
      final hasPos = _currentPosition != null;

      bool isOutside = false;
      double? distance;
      if (hasSitePin && hasPos) {
        distance = LocationService.calculateDistanceMeters(
          userLat: _currentPosition!.latitude,
          userLng: _currentPosition!.longitude,
          siteLat: siteLat,
          siteLng: siteLng,
        );
        isOutside = distance > allowedRadius;
      }

      final String buttonText;
      final IconData buttonIcon;
      final Color buttonBg;

      if (!hasPos) {
        buttonText = 'GPS SIGNAL REQUIRED (TAP TO RETRY)';
        buttonIcon = Icons.location_disabled_rounded;
        buttonBg = AppColors.rejected.withOpacity(0.85);
      } else if (!hasSitePin) {
        buttonText = 'SITE LOCATION NOT CONFIGURED';
        buttonIcon = Icons.map_rounded;
        buttonBg = AppColors.rejected.withOpacity(0.85);
      } else if (isOutside) {
        final distKm = (distance! / 1000).toStringAsFixed(1);
        buttonText = 'OUTSIDE SITE BOUNDARY ($distKm KM AWAY)';
        buttonIcon = Icons.location_off_rounded;
        buttonBg = AppColors.rejected.withOpacity(0.85);
      } else {
        buttonText = 'PUNCH IN NOW';
        buttonIcon = Icons.fingerprint_rounded;
        buttonBg = AppColors.primary;
      }

      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonBg,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: _handlePunchIn,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(buttonIcon, size: 26, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              buttonText,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      );
    }

    // Punched in! Let's display status details
    final inTimeStr = record.punchInTime != null
        ? DateFormat('hh:mm a').format(record.punchInTime!)
        : '--';
    final outTimeStr = record.punchOutTime != null
        ? DateFormat('hh:mm a').format(record.punchOutTime!)
        : null;

    final isLockout = record.status == AttendanceStatus.absentLateLockout;
    final isRegularizationPending = record.status == AttendanceStatus.regularizationPending;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLockout ? AppColors.rejected : AppColors.approved,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Today\'s Attendance Status', style: AppTextStyles.bodyMedium),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isLockout
                      ? AppColors.rejected.withOpacity(0.18)
                      : (isRegularizationPending
                          ? AppColors.pending.withOpacity(0.18)
                          : AppColors.approved.withOpacity(0.18)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  record.status.displayName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isLockout
                        ? AppColors.rejected
                        : (isRegularizationPending ? AppColors.pending : AppColors.approved),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Timestamps row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  const Text('Punched In', style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(inTimeStr, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(width: 1, height: 25, color: AppColors.divider),
              Column(
                children: [
                  const Text('Punched Out', style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(outTimeStr ?? 'Shift Active', style: TextStyle(color: outTimeStr != null ? Colors.white : AppColors.primary, fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),

          if (isLockout) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.rejected.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.rejected.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: AppColors.rejected, size: 18),
                      SizedBox(width: 6),
                      Text('Late Arrival (>40 min late)', style: TextStyle(color: AppColors.rejected, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'You arrived more than 40 minutes late and have been marked Absent. You can submit an attendance regularization request to Admin.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.pending,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _showRegularizationDialog(record),
                    icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                    label: const Text('Send Request to Admin', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ] else if (isRegularizationPending) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.pending.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Regularization reason submitted: "${record.regularizationReason}". Awaiting Admin review.',
                style: const TextStyle(color: AppColors.pending, fontSize: 11),
              ),
            ),
          ],

          if (record.punchOutTime == null && !isLockout) ...[
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => _handlePunchOut(record),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, color: Colors.white),
                  SizedBox(width: 8),
                  Text('PUNCH OUT (END SHIFT)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
