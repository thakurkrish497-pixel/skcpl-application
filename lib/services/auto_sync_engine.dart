import '../providers/auth_provider.dart';
import 'transaction_refresh.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'offline_service.dart';
import '../providers/stock_provider.dart';
import '../providers/cash_provider.dart';

/// State of background cloud synchronization
class SyncState {
  final bool isSyncing;
  final int pendingCount;
  final DateTime? lastSyncTime;
  final String? lastError;

  const SyncState({
    this.isSyncing = false,
    this.pendingCount = 0,
    this.lastSyncTime,
    this.lastError,
  });

  SyncState copyWith({
    bool? isSyncing,
    int? pendingCount,
    DateTime? lastSyncTime,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Riverpod notifier managing continuous background sync
class AutoSyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  Timer? _syncTimer;
  bool _isDisposed = false;
  Future<SyncResult>? _flight;

  AutoSyncNotifier(this._ref) : super(const SyncState()) {
    _init();
  }

  Future<void> _updateQueueCount() async {
    try {
      final count = await OfflineService.getPendingSyncCount();
      if (mounted) state = state.copyWith(pendingCount: count);
    } catch (e) {
      if (mounted) state = state.copyWith(lastError: '$e');
    }
  }

  void _queueChanged() {
    _updateQueueCount();
  }

  void _init() {
    OfflineService.queueRevision.addListener(_queueChanged);
    // 1. Immediate sync check on app launch
    syncNow();

    // 2. Periodic background sync every 30 seconds
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_isDisposed) {
        syncNow();
      }
    });
  }

  /// Triggers a silent or active sync attempt
  Future<SyncResult> syncNow() => _flight ??= _syncOnce().whenComplete(() {
        _flight = null;
      });

  Future<SyncResult> _syncOnce() async {
    state = state.copyWith(isSyncing: true);
    int pending = 0;
    try {
      pending = await OfflineService.getPendingSyncCount();
      if (pending == 0) {
        if (mounted) {
          state = state.copyWith(
              isSyncing: false, pendingCount: 0, clearError: true);
        }
        return const SyncResult(syncedCount: 0, remainingCount: 0);
      }

      if (!mounted) return SyncResult(syncedCount: 0, remainingCount: pending);
      final session = _ref.read(authProvider);
      if (!session.isAuthenticated && !session.hasSiteSession) {
        state = state.copyWith(
            isSyncing: false,
            pendingCount: pending,
            lastError: 'Sign in before syncing device records.');
        return SyncResult(
            syncedCount: 0,
            remainingCount: pending,
            errors: const ['Sign in before syncing device records.']);
      }
      state = state.copyWith(isSyncing: true, pendingCount: pending);
      final stockService = _ref.read(stockServiceProvider);
      final cashService = _ref.read(cashServiceProvider);

      final result = await OfflineService.syncAllQueued(
        stockService: stockService,
        cashService: cashService,
      );

      final remaining = await OfflineService.getPendingSyncCount();

      if (mounted) {
        state = state.copyWith(
          isSyncing: false,
          pendingCount: remaining,
          lastSyncTime: DateTime.now(),
          clearError: result.errors.isEmpty,
          lastError: result.errors.isEmpty ? null : result.errors.first,
        );

        // If any records were successfully pushed to Supabase, refresh caches
        if (result.syncedCount > 0) {
          invalidateTransactionViews(_ref.invalidate);
          _ref.read(cashProvider.notifier).loadAllTransactions();
          _ref.read(stockProvider.notifier).loadAllTransactions();
        }
      }

      return result;
    } catch (e) {
      debugPrint('⚠️ [AutoSync] Background sync hiccup: $e');
      if (mounted) {
        state = state.copyWith(
            isSyncing: false, pendingCount: pending, lastError: e.toString());
      }
      return SyncResult(
          syncedCount: 0, remainingCount: pending, errors: [e.toString()]);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    OfflineService.queueRevision.removeListener(_queueChanged);
    _syncTimer?.cancel();
    super.dispose();
  }
}

/// Global provider for background auto-sync state and controls
final autoSyncProvider =
    StateNotifierProvider<AutoSyncNotifier, SyncState>((ref) {
  return AutoSyncNotifier(ref);
});
