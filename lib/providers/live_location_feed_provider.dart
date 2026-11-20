import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';
import 'attendance_provider.dart';
import 'staff_reminder_provider.dart';

final liveLocationFeedProvider = Provider.autoDispose<void>((ref) {
  final user = ref.watch(authProvider.select((a) => a.user));
  final foreground = ref.watch(staffReminderForegroundProvider);
  if (user == null || user.role == UserRole.worker || !foreground) return;
  var disposed = false;
  Timer? debounce;
  void refresh() {
    if (disposed) return;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), () {
      if (!disposed) ref.invalidate(liveStaffLocationsProvider);
    });
  }

  final client = ref.read(supabaseClientProvider);
  final channels = <RealtimeChannel>[];
  for (final table in ['staff_live_locations', 'tasks']) {
    final channel = client.channel('skcpl:live-staff-location:$table');
    channel
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            callback: (payload) {
              if (table == 'staff_live_locations' ||
                  '${payload.newRecord['title']}'.startsWith('LIVELOC:') ||
                  '${payload.oldRecord['title']}'.startsWith('LIVELOC:')) {
                refresh();
              }
            })
        .subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) refresh();
    });
    channels.add(channel);
  }
  final poll = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  ref.onDispose(() {
    disposed = true;
    debounce?.cancel();
    poll.cancel();
    for (final channel in channels) {
      unawaited(
          client.removeChannel(channel).then<void>((_) {}, onError: (_) {}));
    }
  });
});
