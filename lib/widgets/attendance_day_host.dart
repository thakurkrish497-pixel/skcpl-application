import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/site_staff_provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/staff_reminder_provider.dart';
import '../services/attendance_session_policy.dart';
import '../services/entry_date_policy.dart';

/// Exact day/overnight boundary plus resume check; never writes a punch-out.
class AttendanceDayHost extends ConsumerStatefulWidget {
  final Widget child;
  const AttendanceDayHost({super.key, required this.child});
  @override
  ConsumerState<AttendanceDayHost> createState() => _AttendanceDayHostState();
}

class _AttendanceDayHostState extends ConsumerState<AttendanceDayHost>
    with WidgetsBindingObserver {
  Timer? _boundary;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _boundary?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _check() {
    if (!mounted || !_foreground) return;
    final staff = ref.read(activeStaffProvider);
    if (staff == null) return;
    final policy =
        ref.read(shiftPolicyForSiteProvider(staff.siteId)).valueOrNull;
    if (policy != null) {
      ref
          .read(staffPunchProvider.notifier)
          .refreshDay(siteId: staff.siteId, staffId: staff.id, policy: policy);
    }
    ref.invalidate(staffReminderCheckProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _check();
      if (mounted) setState(() {});
    } else {
      _boundary?.cancel();
      _boundary = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(activeStaffProvider);
    final auth = ref.watch(authProvider);
    final allowed = staff != null &&
        (auth.user == null || auth.user!.role.name == 'worker');
    final policy = allowed
        ? ref.watch(shiftPolicyForSiteProvider(staff.siteId)).valueOrNull
        : null;
    final punch = ref.watch(staffPunchProvider);
    _boundary?.cancel();
    _boundary = null;
    if (allowed && policy != null && _foreground) {
      final now = DateTime.now().toUtc();
      var next = AttendanceSessionPolicy.midnightAfter(
          EntryDatePolicy.today(now: now));
      final day = AttendanceSessionPolicy.workDay(now, policy);
      final expiry = punch.todayRecord?.sessionExpiresAt ??
          AttendanceSessionPolicy.expiry(day, policy);
      if (expiry.isAfter(now) && expiry.isBefore(next)) next = expiry;
      if (punch.isLoading) next = now.add(const Duration(seconds: 2));
      _boundary =
          Timer(next.difference(now) + const Duration(milliseconds: 20), () {
        _check();
        if (mounted) setState(() {});
      });
      final record = punch.todayRecord;
      if (record != null &&
          !punch.isLoading &&
          (record.staffId != staff.id ||
              !AttendanceSessionPolicy.current(record, now, policy))) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _check();
        });
      }
    }
    return widget.child;
  }
}
