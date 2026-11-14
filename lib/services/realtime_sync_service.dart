import 'transaction_refresh.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../providers/cash_provider.dart';
import '../providers/stock_provider.dart';
import '../providers/site_provider.dart';
import '../providers/role_access_provider.dart';

/// Service managing Supabase Realtime WebSocket channels
class RealtimeSyncService {
  final Ref _ref;
  final SupabaseClient _client;
  bool _disposed = false;
  RealtimeChannel? _cashChannel;
  RealtimeChannel? _stockChannel;
  RealtimeChannel? _sitesChannel;
  RealtimeChannel? _permsChannel;

  RealtimeSyncService(this._ref, this._client, {bool enabled = true}) {
    if (enabled) _subscribe();
  }

  void _subscribe() {
    try {
      // 1. Live stream on cash_transactions
      _cashChannel = _client.channel('public:realtime_cash').onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'cash_transactions',
            callback: (payload) {
              if (_disposed) return;
              debugPrint(
                  '⚡ [Realtime] Cash transaction event: ${payload.eventType}');
              invalidateTransactionViews(_ref.invalidate);
              _ref.read(cashProvider.notifier).refresh();
            },
          )..subscribe((status, error) {
          if (!_disposed && status == RealtimeSubscribeStatus.subscribed) {
            invalidateTransactionViews(_ref.invalidate);
            _ref.read(cashProvider.notifier).refresh();
            _ref.read(stockProvider.notifier).refresh();
          } else if (error != null) {
            debugPrint('Realtime subscription unavailable: $status');
          }
        });

      // 2. Live stream on stock_transactions
      _stockChannel = _client
          .channel('public:realtime_stock')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'stock_transactions',
            callback: (payload) {
              if (_disposed) return;
              debugPrint(
                  '⚡ [Realtime] Stock transaction event: ${payload.eventType}');
              invalidateTransactionViews(_ref.invalidate);
              _ref.read(stockProvider.notifier).refresh();
              final siteId =
                  payload.newRecord['site_id'] ?? payload.oldRecord['site_id'];
              if (siteId is String &&
                  siteId == _ref.read(authProvider).activeSite?.id) {
                _ref.read(stockProvider.notifier).loadCurrentStock(siteId);
              }
            },
          )..subscribe((status, error) {
          if (!_disposed && status == RealtimeSubscribeStatus.subscribed) {
            invalidateTransactionViews(_ref.invalidate);
            _ref.read(cashProvider.notifier).refresh();
            _ref.read(stockProvider.notifier).refresh();
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
                  invalidateTransactionViews(_ref.invalidate);
                  _ref.invalidate(activeSitesProvider);
                  _ref.invalidate(allSitesProvider);
                },
              )..subscribe((status, error) {
              if (!_disposed && status == RealtimeSubscribeStatus.subscribed) {
                invalidateTransactionViews(_ref.invalidate);
                _ref.read(cashProvider.notifier).refresh();
                _ref.read(stockProvider.notifier).refresh();
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
                  invalidateTransactionViews(_ref.invalidate);
                  debugPrint('Realtime permissions refresh');
                  _ref
                      .read(roleAccessProvider.notifier)
                      .loadPermissions(forceRefresh: true);
                },
              )..subscribe((status, error) {
              if (!_disposed && status == RealtimeSubscribeStatus.subscribed) {
                invalidateTransactionViews(_ref.invalidate);
                _ref.read(cashProvider.notifier).refresh();
                _ref.read(stockProvider.notifier).refresh();
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
    for (final channel in [
      _cashChannel,
      _stockChannel,
      _sitesChannel,
      _permsChannel
    ]) {
      if (channel != null) await _client.removeChannel(channel);
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
