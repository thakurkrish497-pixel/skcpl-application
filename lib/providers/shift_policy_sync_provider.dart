import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';
import 'attendance_provider.dart';
import 'staff_reminder_provider.dart';
import '../services/shift_policy_resolver.dart';

/// An isolated read-refresh layer; never touches attendance records or queues.
class ShiftPolicyObserver {
  final SupabaseClient client;
  final void Function() refresh;
  final void Function()? refreshReminders;
  bool _notifyReminders = false;
  final bool Function() foreground;
  final List<RealtimeChannel> _channels = [];
  StreamSubscription<String>? _saved;
  Timer? _debounce, _poll;
  bool _disposed = false;
  ShiftPolicyObserver(this.client,
      {required this.refresh,
      this.refreshReminders,
      required this.foreground,
      bool connect = true}) {
    _saved = shiftPolicySaved.stream.listen((_) => changed());
    if (connect) {
      for (final table in ['site_shift_policies', 'tasks']) {
        final channel = client.channel('skcpl:shift-policy:$table');
        channel
            .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: table,
                callback: (payload) {
                  if (table == 'site_shift_policies' ||
                      relevantTask(payload.newRecord, payload.oldRecord)) {
                    changed();
                  }
                })
            .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) changed();
        });
        _channels.add(channel);
      }
    }
    _poll = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_disposed && foreground()) changed(reminders: false);
    });
  }
  static bool relevantTask(
          Map<String, dynamic> next, Map<String, dynamic> old) =>
      [next['title'], old['title']]
          .any((t) => t is String && t.startsWith('SHIFT_POLICY:'));
  void changed({bool reminders = true}) {
    if (_disposed || !foreground()) return;
    _notifyReminders = _notifyReminders || reminders;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!_disposed && foreground()) {
        refresh();
        if (_notifyReminders) refreshReminders?.call();
        _notifyReminders = false;
      }
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _debounce?.cancel();
    _poll?.cancel();
    await _saved?.cancel();
    for (final channel in _channels) {
      try {
        await client.removeChannel(channel);
      } catch (_) {/* Local timers and listeners are already stopped. */}
    }
  }
}

final shiftPolicySyncProvider = Provider.autoDispose<void>((ref) {
  final session =
      ref.watch(authProvider.select((a) => (a.user?.id, a.activeSite?.id)));
  final active = ref.watch(staffReminderForegroundProvider);
  if (!active || (session.$1 == null && session.$2 == null)) return;
  final observer = ShiftPolicyObserver(ref.read(supabaseClientProvider),
      foreground: () => active,
      refresh: () {
        ref.invalidate(shiftPolicyForSiteProvider);
      },
      refreshReminders: () => ref.invalidate(staffReminderCheckProvider));
  ref.onDispose(() => unawaited(observer.dispose()));
});
