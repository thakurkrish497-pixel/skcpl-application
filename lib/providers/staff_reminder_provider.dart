import '../models/user_model.dart';
import '../models/staff_reminder_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import 'site_staff_provider.dart';
import 'attendance_provider.dart';
import 'site_report_provider.dart';
import '../services/staff_reminder_service.dart';
export '../services/staff_reminder_service.dart';

final staffReminderForegroundProvider = StateProvider<bool>((ref) => true);
final staffReminderIdentityProvider =
    Provider<({String siteId, String staffId})?>((ref) {
  final auth = ref.watch(authProvider);
  final staff = ref.watch(activeStaffProvider);
  if ((auth.user != null && auth.user!.role != UserRole.worker) ||
      auth.activeSite == null ||
      staff == null ||
      !staff.isActive ||
      staff.id.isEmpty ||
      !sameReminderSite(staff.siteId, auth.activeSite!.id)) {
    return null;
  }
  return (siteId: staff.siteId, staffId: staff.id);
});
final staffReminderServiceProvider = Provider<StaffReminderService>(
    (ref) => StaffReminderService(ref.read(supabaseClientProvider)));
final staffReminderCheckProvider =
    FutureProvider.autoDispose<StaffReminderCheck>((ref) async {
  final identity = ref.watch(staffReminderIdentityProvider);
  final foreground = ref.watch(staffReminderForegroundProvider);
  if (identity == null || !foreground) return const StaffReminderCheck([]);
  final punch = ref.watch(staffPunchProvider
      .select((s) => (s.isLoading, s.todayRecord?.updatedAt)));
  final dsr = ref.watch(
      reportSubmissionProvider.select((s) => (s.isLoading, s.result?.id)));
  if (punch.$1 || dsr.$1) return const StaffReminderCheck([]);
  try {
    return await ref
        .watch(staffReminderServiceProvider)
        .check(identity.siteId, identity.staffId, DateTime.now().toUtc());
  } catch (_) {
    return const StaffReminderCheck([],
        notice:
            'Reminder checks are paused until today’s records and shift settings can be verified. Your entries are unaffected.');
  }
});
