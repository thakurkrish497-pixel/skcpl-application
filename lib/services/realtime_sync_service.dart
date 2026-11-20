import 'package:flutter/widgets.dart';
import 'live_refresh_scheduler.dart';
import 'auto_sync_engine.dart';
import 'dart:async';
import 'transaction_refresh.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../providers/cash_provider.dart';
import '../providers/stock_provider.dart';
import '../providers/site_provider.dart';
import '../providers/role_access_provider.dart';

/// Service managing Supabase Realtime WebSocket channels
class RealtimeSyncService with WidgetsBindingObserver {
  final Ref _ref;
  final SupabaseClient _client;
  bool _disposed = false;
  bool _foreground = true;
  late final LiveRefreshScheduler _refresh;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !_disposed) {
      _refresh.request();
      unawaited(_ref.read(autoSyncProvider.notifier).syncNow());
    }
  }

  Future<void> _refreshGraph() async {
    if (_disposed || !_foreground) return;
    invalidateTransactionViews(_ref.invalidate);
    _ref.invalidate(activeSitesProvider);
    _ref.invalidate(allSitesProvider);
    final siteId = _ref.read(authProvider).activeSite?.id;
    await Future.wait([
      _ref.read(cashProvider.notifier).refresh(),
      _ref.read(stockProvider.notifier).refresh(),
      if (siteId != null)
        _ref.read(stockProvider.notifier).loadCurrentStock(siteId),
    ]);
  }

  RealtimeChannel? _cashChannel;
  RealtimeChannel? _stockChannel;
  RealtimeChannel? _sitesChannel;
  RealtimeChannel? _permsChannel;
  RealtimeChannel? _managementChannel;
  Timer? _policyPoll;
  final _reviewChannels = <RealtimeChannel>[];

  RealtimeSyncService(this._ref, this._client, {bool enabled = true}) {
    _refresh = LiveRefreshScheduler(
        refresh: _refreshGraph, active: () => !_disposed && _foreground);
    if (enabled) {
      _foreground = WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      WidgetsBinding.instance.addObserver(this);
      _subscribe();
    }
  }

  void _refreshPolicy() {
    if (_disposed || !_foreground) return;
    _ref.read(roleAccessProvider.notifier).loadPermissions(forceRefresh: true);
    _refresh.request();
  }

  void _subscribe() {
    _policyPoll =
        Timer.periodic(const Duration(seconds: 30), (_) => _refreshPolicy());
    try {
      _managementChannel = _client
          .channel('public:skcpl_management_state')
          .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'skcpl_management_state',
              callback: (_) => _refreshPolicy())
        ..subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) _refreshPolicy();
        });
      for (final table in [
        'attendance',
        'daily_site_reports',
        'skcpl_entry_reviews'
      ]) {
        _reviewChannels
            .add(_client.channel('public:reviews:$table').onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: table,
                callback: (_) {
                  if (!_disposed) _refresh.request();
                })
              ..subscribe());
      }
      // 1. Live stream on cash_transactions
      _cashChannel = _client.channel('public:realtime_cash').onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'cash_transactions',
            callback: (payload) {
              if (_disposed) return;
              debugPrint(
                  '⚡ [Realtime] Cash transaction event: ${payload.eventType}');
              _refresh.request();
            },
          )..subscribe((status, error) {
          if (!_disposed && status == RealtimeSubscribeStatus.subscribed) {
            _refresh.request();
          } else if (error != null) {
            debugPrint('Realtime subscription unavailable: $status');
          }
        });

      // 2. Live stream on stock_transactions
      _stockChannel =
          _client.channel('public:realtime_stock').onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'stock_transactions',
                callback: (payload) {
                  if (_disposed) return;
                  debugPrint(
                      '⚡ [Realtime] Stock transaction event: ${payload.eventType}');
                  _refresh.request();
                },
              )..subscribe((status, error) {
              if (!_disposed && status == RealtimeSubscribeStatus.subscribed) {
                _refresh.request();
              } else if (error != null) {
                debugPrint('Realtime subscription unavailable: $status');
              }
            });

      // 3. Live stream on sites (new sites, renames, budget changes)
      _sitesChannel =
          _client.channel('public:realtime_sites').onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'sites',
                callback: (payload) {
                  if (_disposed) return;
                  debugPrint(
                      '⚡ [Realtime] Site update event: ${payload.eventType}');
                  _refresh.request();
                },
              )..subscribe((status, error) {
              if (!_disposed && status == RealtimeSubscribeStatus.subscribed) {
                _refresh.request();
              } else if (error != null) {
                debugPrint('Realtime subscription unavailable: $status');
              }
            });

      // 4. Live stream on permissions & admin role configs
      _permsChannel =
          _client.channel('public:realtime_perms').onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'tasks',
                callback: (payload) {
                  if (_disposed) return;
                  final title =
                      payload.newRecord['title'] ?? payload.oldRecord['title'];
                  if (title is String && title.startsWith('LIVELOC:')) return;
                  debugPrint('Realtime permissions refresh');
                  _refreshPolicy();
                },
              )..subscribe((status, error) {
              if (!_disposed && status == RealtimeSubscribeStatus.subscribed) {
                _refresh.request();
              } else if (error != null) {
                debugPrint('Realtime subscription unavailable: $status');
              }
            });
    } catch (e) {
      debugPrint('⚠️ [Realtime] Could not subscribe to Realtime streams: $e');
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _refresh.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _policyPoll?.cancel();
    for (final channel in [
      _cashChannel,
      _stockChannel,
      _sitesChannel,
      _permsChannel,
      _managementChannel,
      ..._reviewChannels,
    ]) {
      if (channel != null) {
        try {
          await _client.removeChannel(channel);
        } catch (_) {/* Continue cleanup. */}
      }
    }
  }
}

/// Global provider keeping Realtime WebSocket listeners active
final realtimeSyncProvider = Provider<RealtimeSyncService>((ref) {
  final client = ref.read(supabaseClientProvider);
  final session =
      ref.watch(authProvider.select((a) => (a.user?.id, a.activeSite?.id)));
  final service = RealtimeSyncService(ref, client,
      enabled: session.$1 != null || session.$2 != null);
  ref.onDispose(() => service.dispose());
  return service;
});
