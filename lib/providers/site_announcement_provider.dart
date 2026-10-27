import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/site_announcement_model.dart';
import '../models/user_model.dart';
import '../services/site_announcement_service.dart';
import '../services/notification_service.dart';

final siteAnnouncementServiceProvider = Provider<SiteAnnouncementService>((ref) {
  return SiteAnnouncementService();
});

class AnnouncementsNotifier
    extends StateNotifier<AsyncValue<List<SiteAnnouncementModel>>> {
  final SiteAnnouncementService _service;
  Timer? _pollTimer;

  AnnouncementsNotifier(this._service) : super(const AsyncValue.loading()) {
    loadAnnouncements();
    // Poll every 45 seconds so all connected devices (phone & desktop) receive new announcements automatically
    _pollTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _pollAnnouncements();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollAnnouncements() async {
    try {
      final list = await _service.getAnnouncements();
      state = AsyncValue.data(list);
      _triggerNotificationsForRecent(list);
    } catch (_) {}
  }

  Future<void> loadAnnouncements() async {
    try {
      final list = await _service.getAnnouncements();
      state = AsyncValue.data(list);
      _triggerNotificationsForRecent(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void _triggerNotificationsForRecent(List<SiteAnnouncementModel> list) {
    if (list.isEmpty) return;
    final now = DateTime.now();
    // Notify for recent notices posted in the last 24 hours (deduplicated by NotificationService)
    for (final notice in list.take(5)) {
      final age = now.difference(notice.createdAt);
      if (age.inHours < 24) {
        NotificationService.showAnnouncementNotification(
          announcementId: notice.id,
          title: notice.title,
          body: notice.message,
          targetSiteName: notice.targetSiteName,
        );
      }
    }
  }

  Future<void> postAnnouncement(SiteAnnouncementModel model) async {
    try {
      final created = await _service.createAnnouncement(model);
      final currentList = state.value ?? [];
      state = AsyncValue.data([created, ...currentList]);

      // Immediately trigger push notification
      await NotificationService.showAnnouncementNotification(
        announcementId: created.id,
        title: created.title,
        body: created.message,
        targetSiteName: created.targetSiteName,
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> removeAnnouncement(String id) async {
    try {
      await _service.deleteAnnouncement(id);
      final currentList = state.value ?? [];
      state = AsyncValue.data(currentList.where((a) => a.id != id).toList());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

final announcementsProvider = StateNotifierProvider<AnnouncementsNotifier,
    AsyncValue<List<SiteAnnouncementModel>>>((ref) {
  return AnnouncementsNotifier(ref.watch(siteAnnouncementServiceProvider));
});

/// Returns the most relevant active announcement for display in the top bar (if created within the last 48 hours)
final activeAnnouncementProvider = Provider<SiteAnnouncementModel?>((ref) {
  final asyncValue = ref.watch(announcementsProvider);
  return asyncValue.when(
    data: (list) {
      if (list.isEmpty) return null;
      final now = DateTime.now();
      for (final a in list) {
        if (!a.isActive) continue;
        // If scheduled in future or within past 48 hours
        if (a.scheduledAt != null && a.scheduledAt!.isAfter(now.subtract(const Duration(hours: 6)))) {
          return a;
        }
        if (now.difference(a.createdAt).inHours <= 48) {
          return a;
        }
      }
      return null;
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

/// Security verification: strictly Project Head, Accounts, and Admin can create notices.
bool canUserPostAnnouncements(UserRole? role) {
  return role == UserRole.admin ||
      role == UserRole.projectHead ||
      role == UserRole.accounts;
}
