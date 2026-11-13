import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../providers/cash_provider.dart';
import '../providers/stock_provider.dart';
import '../providers/site_provider.dart';

/// Service managing Supabase Realtime WebSocket channels
class RealtimeSyncService {
  final Ref _ref;
  final SupabaseClient _client;
  RealtimeChannel? _cashChannel;
  RealtimeChannel? _stockChannel;
  RealtimeChannel? _sitesChannel;

  RealtimeSyncService(this._ref, this._client) {
    _subscribe();
  }

  void _subscribe() {
    try {
      // 1. Live stream on cash_transactions
      _cashChannel = _client.channel('public:realtime_cash').onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'cash_transactions',
        callback: (payload) {
          debugPrint('⚡ [Realtime] Cash transaction event: ${payload.eventType}');
          final activeSiteId = _ref.read(authProvider).activeSite?.id;
          if (activeSiteId != null) {
            _ref.invalidate(siteCashSummaryProvider(activeSiteId));
            _ref.read(cashProvider.notifier).loadTransactions(activeSiteId);
          } else {
            _ref.read(cashProvider.notifier).loadAllTransactions();
          }
        },
      )..subscribe();

      // 2. Live stream on stock_transactions
      _stockChannel = _client.channel('public:realtime_stock').onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'stock_transactions',
        callback: (payload) {
          debugPrint('⚡ [Realtime] Stock transaction event: ${payload.eventType}');
          final activeSiteId = _ref.read(authProvider).activeSite?.id;
          if (activeSiteId != null) {
            _ref.invalidate(stockOverviewProvider(activeSiteId));
            _ref.read(stockProvider.notifier).loadTransactions(activeSiteId);
            _ref.read(stockProvider.notifier).loadCurrentStock(activeSiteId);
          } else {
            _ref.read(stockProvider.notifier).loadAllTransactions();
          }
        },
      )..subscribe();

      // 3. Live stream on sites (new sites, renames, budget changes)
      _sitesChannel = _client.channel('public:realtime_sites').onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'sites',
        callback: (payload) {
          debugPrint('⚡ [Realtime] Site update event: ${payload.eventType}');
          _ref.invalidate(activeSitesProvider);
          _ref.invalidate(allSitesProvider);
        },
      )..subscribe();
    } catch (e) {
      debugPrint('⚠️ [Realtime] Could not subscribe to Realtime streams: $e');
    }
  }

  void dispose() {
    try {
      _cashChannel?.unsubscribe();
      _stockChannel?.unsubscribe();
      _sitesChannel?.unsubscribe();
    } catch (_) {}
  }
}

/// Global provider keeping Realtime WebSocket listeners active
final realtimeSyncProvider = Provider<RealtimeSyncService>((ref) {
  final client = ref.read(supabaseClientProvider);
  final service = RealtimeSyncService(ref, client);
  ref.onDispose(() => service.dispose());
  return service;
});
