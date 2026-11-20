import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';
import 'attendance_provider.dart';
import 'staff_reminder_provider.dart';

final attendanceSessionRefreshProvider = Provider.autoDispose<void>((ref) {
  final auth =
      ref.watch(authProvider.select((s) => (s.user?.id, s.activeSite?.id)));
  final foreground = ref.watch(staffReminderForegroundProvider);
  if (!foreground || (auth.$1 == null && auth.$2 == null)) return;
  final client = ref.read(supabaseClientProvider);
  var disposed = false;
  Timer? debounce;
  void refresh() {
    if (disposed) return;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), () {
      if (disposed) return;
      ref.invalidate(todayAttendanceForSiteProvider);
      ref.invalidate(attendanceForDateAndSiteProvider);
      ref.invalidate(monthlyAttendanceProvider);
      ref.invalidate(staffReminderCheckProvider);
    });
  }

  final channels = <RealtimeChannel>[];
  for (final table in [
    'skcpl_attendance_sessions',
    'skcpl_attendance_closures'
  ]) {
    final channel = client.channel('skcpl:session-audit:$table');
    channel
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            callback: (_) => refresh())
        .subscribe();
    channels.add(channel);
  }
  ref.onDispose(() {
    disposed = true;
    debounce?.cancel();
    for (final channel in channels) {
      unawaited(
          client.removeChannel(channel).then<void>((_) {}, onError: (_) {}));
    }
  });
});
