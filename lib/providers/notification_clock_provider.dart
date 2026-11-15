import 'auth_provider.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';

/// Re-evaluate notification dates and overdue thresholds while the app is open.
/// Independent of operational sync and queue timers.
final notificationClockProvider = StreamProvider.autoDispose<DateTime>((ref) {
  final controller = StreamController<DateTime>();
  void tick() => controller.add(DateTime.now());
  tick();
  final timer = Timer.periodic(const Duration(minutes: 1), (_) => tick());
  final permission =
      NotificationService.permissionChanges.listen((_) => tick());
  ref.onDispose(() {
    timer.cancel();
    permission.cancel();
    controller.close();
  });
  return controller.stream;
});
final notificationNowProvider = Provider<DateTime>((ref) =>
    ref.watch(notificationClockProvider).valueOrNull ?? DateTime.now());

/// First-use native permission prompt; no permission request during a mere check.
final notificationStartupProvider = Provider<void>((ref) {
  final session =
      ref.watch(authProvider.select((a) => (a.user?.id, a.activeSite?.id)));
  if (session.$1 != null || session.$2 != null) {
    unawaited(NotificationService.requestPermissionOnFirstUse());
  }
});
