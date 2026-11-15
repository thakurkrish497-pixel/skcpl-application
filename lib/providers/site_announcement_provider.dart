import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/site_announcement_model.dart';
import '../models/user_model.dart';
import '../services/site_announcement_service.dart';
import '../services/notification_service.dart';
import 'auth_provider.dart';
import 'notification_clock_provider.dart';

final siteAnnouncementServiceProvider =
    Provider<SiteAnnouncementService>((ref) => SiteAnnouncementService());

bool noticeMatchesAudience(SiteAnnouncementModel notice,
        {required bool management, String? siteId}) =>
    notice.isActive &&
    (notice.isAllSites || management || notice.targetSiteId == siteId);

class AnnouncementsNotifier
    extends StateNotifier<AsyncValue<List<SiteAnnouncementModel>>> {
  final SiteAnnouncementService _service;
  final bool Function(SiteAnnouncementModel) _visible;
  final bool Function()? _canPost;
  Timer? _pollTimer;
  int _revision = 0;
  bool _posting = false;
  Future<void>? _flight;

  AnnouncementsNotifier(this._service,
      {bool Function(SiteAnnouncementModel)? visible,
      bool Function()? canPost,
      bool poll = true})
      : _visible = visible ?? ((_) => true),
        _canPost = canPost,
        super(const AsyncValue.loading()) {
    loadAnnouncements();
    if (poll) {
      _pollTimer = Timer.periodic(
          const Duration(seconds: 45), (_) => loadAnnouncements());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    ++_revision;
    super.dispose();
  }

  Future<void> loadAnnouncements() =>
      _flight ??= _load().whenComplete(() => _flight = null);
  Future<void> _load() async {
    final revision = _revision;
    try {
      final list = await _service.getAnnouncements();
      if (!mounted || revision != _revision) return;
      state = AsyncValue.data(list);
      for (final notice in list.where(_visible)) {
        final age = DateTime.now().difference(notice.createdAt);
        if (!age.isNegative && age < const Duration(hours: 24)) {
          unawaited(NotificationService.showAnnouncementNotification(
              announcementId: notice.id,
              title: notice.title,
              body: notice.message,
              targetSiteName: notice.targetSiteName));
        }
      }
    } catch (e, st) {
      if (mounted && revision == _revision && !state.hasValue) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> postAnnouncement(SiteAnnouncementModel model) async {
    if (_canPost?.call() == false) {
      throw StateError('Only management can publish notices.');
    }
    if (_posting) throw StateError('A notice is already being published.');
    _posting = true;
    ++_revision;
    try {
      final created = await _service.createAnnouncement(model);
      if (!mounted) return;
      ++_revision;
      state = AsyncValue.data(
          [created, ...?state.valueOrNull?.where((a) => a.id != created.id)]);
      if (_visible(created)) {
        unawaited(NotificationService.showAnnouncementNotification(
            announcementId: created.id,
            title: created.title,
            body: created.message,
            targetSiteName: created.targetSiteName));
      }
    } finally {
      _posting = false;
    }
  }

  Future<void> removeAnnouncement(String id) async {
    if (_canPost?.call() == false) {
      throw StateError('Only management can remove notices.');
    }
    ++_revision;
    await _service.deleteAnnouncement(id);
    if (!mounted) return;
    ++_revision;
    state = AsyncValue.data(
        (state.valueOrNull ?? []).where((a) => a.id != id).toList());
  }
}

final announcementsProvider = StateNotifierProvider<AnnouncementsNotifier,
    AsyncValue<List<SiteAnnouncementModel>>>((ref) {
  // Recreate only for a session change, not on ordinary dashboard rebuilds.
  ref.watch(authProvider.select((a) => (a.user?.id, a.activeSite?.id)));
  return AnnouncementsNotifier(ref.watch(siteAnnouncementServiceProvider),
      canPost: () =>
          canUserPostAnnouncements(ref.read(authProvider).user?.role),
      visible: (notice) {
        final auth = ref.read(authProvider);
        return noticeMatchesAudience(notice,
            management: canUserPostAnnouncements(auth.user?.role),
            siteId: auth.activeSite?.id);
      });
});

final visibleAnnouncementsProvider =
    Provider<AsyncValue<List<SiteAnnouncementModel>>>((ref) {
  final auth = ref.watch(authProvider);
  return ref.watch(announcementsProvider).whenData((list) => list
      .where((n) => noticeMatchesAudience(n,
          management: canUserPostAnnouncements(auth.user?.role),
          siteId: auth.activeSite?.id))
      .toList());
});

/// Dedicated notice channels; never invalidates operational providers or queues.
final noticeRealtimeProvider = Provider<void>((ref) {
  final session =
      ref.watch(authProvider.select((a) => (a.user?.id, a.activeSite?.id)));
  if (session.$1 == null && session.$2 == null) return;
  var disposed = false;
  final stop = ref.watch(siteAnnouncementServiceProvider).watchChanges(() {
    if (!disposed) {
      unawaited(ref.read(announcementsProvider.notifier).loadAnnouncements());
    }
  });
  ref.onDispose(() {
    disposed = true;
    stop();
  });
});

final activeAnnouncementProvider = Provider<SiteAnnouncementModel?>((ref) {
  final list = ref.watch(visibleAnnouncementsProvider).valueOrNull ?? [];
  final now = ref.watch(notificationNowProvider);
  final active = list
      .where((a) =>
          !a.createdAt.isAfter(now) &&
          (now.difference(a.createdAt) <= const Duration(hours: 48) ||
              (a.scheduledAt != null &&
                  a.scheduledAt!
                      .isAfter(now.subtract(const Duration(hours: 6))))))
      .toList();
  active.sort((a, b) {
    int priority(SiteAnnouncementModel n) =>
        n.category == AnnouncementCategory.urgent
            ? 2
            : n.category == AnnouncementCategory.important
                ? 1
                : 0;
    final urgency = priority(b).compareTo(priority(a));
    return urgency != 0 ? urgency : b.createdAt.compareTo(a.createdAt);
  });
  return active.isEmpty ? null : active.first;
});

bool canUserPostAnnouncements(UserRole? role) =>
    role == UserRole.admin ||
    role == UserRole.projectHead ||
    role == UserRole.accounts;

class NoticeReadNotifier extends StateNotifier<Set<String>?> {
  final String scope;
  NoticeReadNotifier(this.scope) : super(null) {
    _load();
  }
  String get _key => 'skcpl_notice_reads_v1_$scope';
  Future<void> _tail = Future.value();
  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted) state = (p.getStringList(_key) ?? []).toSet();
    } catch (_) {
      if (mounted) state = {};
    }
  }

  Future<void> markRead(Iterable<String> ids) {
    final added = ids.toSet();
    return _tail = _tail.then((_) async {
      final p = await SharedPreferences.getInstance();
      final updated = {...?p.getStringList(_key), ...?state, ...added};
      await p.setStringList(_key, updated.toList());
      if (mounted) state = updated;
    }).catchError((Object _) {});
  }
}

final noticeReadProvider =
    StateNotifierProvider.family<NoticeReadNotifier, Set<String>?, String>(
        (ref, scope) => NoticeReadNotifier(scope));
final noticeReaderScopeProvider = Provider<String>((ref) {
  final auth = ref.watch(authProvider);
  return auth.user?.id ?? auth.activeSite?.id ?? 'guest';
});
final unreadNoticeCountProvider = Provider<int>((ref) {
  final read =
      ref.watch(noticeReadProvider(ref.watch(noticeReaderScopeProvider)));
  if (read == null) return 0;
  return (ref.watch(visibleAnnouncementsProvider).valueOrNull ?? [])
      .where((n) => !read.contains(n.id))
      .length;
});
