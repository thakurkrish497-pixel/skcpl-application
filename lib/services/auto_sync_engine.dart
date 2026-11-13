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

  AutoSyncNotifier(this._ref) : super(const SyncState()) {
    _init();
  }

  void _init() {
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
  Future<SyncResult> syncNow() async {
    if (state.isSyncing) {
      return SyncResult(syncedCount: 0, remainingCount: state.pendingCount);
    }

    final pending = await OfflineService.getPendingSyncCount();
    if (pending == 0) {
      if (mounted) {
        state = state.copyWith(pendingCount: 0, clearError: true);
      }
      return const SyncResult(syncedCount: 0, remainingCount: 0);
    }

    if (mounted) {
      state = state.copyWith(isSyncing: true, pendingCount: pending);
    }

    try {
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
          clearError: true,
        );

        // If any records were successfully pushed to Supabase, refresh caches
        if (result.syncedCount > 0) {
          debugPrint('✅ [AutoSync] Successfully synced ${result.syncedCount} queued records to Supabase');
          _ref.read(cashProvider.notifier).loadAllTransactions();
          _ref.read(stockProvider.notifier).loadAllTransactions();
        }
      }

      return result;
    } catch (e) {
      debugPrint('⚠️ [AutoSync] Background sync hiccup: $e');
      if (mounted) {
        final remaining = await OfflineService.getPendingSyncCount();
        state = state.copyWith(
          isSyncing: false,
          pendingCount: remaining,
          lastError: e.toString(),
        );
      }
      return SyncResult(syncedCount: 0, remainingCount: pending);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _syncTimer?.cancel();
    super.dispose();
  }
}

/// Global provider for background auto-sync state and controls
final autoSyncProvider = StateNotifierProvider<AutoSyncNotifier, SyncState>((ref) {
  return AutoSyncNotifier(ref);
});
