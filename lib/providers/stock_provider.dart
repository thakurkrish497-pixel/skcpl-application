import '../services/rejected_entry_service.dart';
import '../services/entry_date_policy.dart';
import '../services/submission_support.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stock_transaction_model.dart';
import '../services/stock_service.dart';
import '../services/offline_service.dart';
import 'auth_provider.dart';
import 'role_access_provider.dart';

/// Provides the StockService
final stockServiceProvider = Provider<StockService>((ref) {
  return StockService(ref.read(supabaseServiceClientProvider));
});

/// State for stock transactions
class StockState {
  final List<StockTransactionModel> transactions;
  final List<Map<String, dynamic>> currentStock;
  final bool isLoading;
  final String? error;

  const StockState({
    this.transactions = const [],
    this.currentStock = const [],
    this.isLoading = false,
    this.error,
  });

  StockState copyWith({
    List<StockTransactionModel>? transactions,
    List<Map<String, dynamic>>? currentStock,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return StockState(
      transactions: transactions ?? this.transactions,
      currentStock: currentStock ?? this.currentStock,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Stock state notifier
class StockNotifier extends StateNotifier<StockState> {
  final StockService _stockService;
  int _loadRevision = 0;
  void clearSession() {
    ++_loadRevision;
    ++_stockRevision;
    if (mounted) state = const StockState();
  }

  int _stockRevision = 0;
  Future<void> refresh() => loadAllTransactions();

  StockNotifier(this._stockService) : super(const StockState());

  /// Keep a canonical cache. Site loads replace only that site's records.
  Future<void> loadAllTransactions({TransactionType? type}) async {
    final revision = ++_loadRevision;
    if (mounted) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    try {
      final cloud = await _stockService.getAllTransactions();
      final queued = await OfflineService.getQueuedStockTransactions();
      if (!mounted || revision != _loadRevision) return;
      final cloudIds = cloud.map((t) => t.id).toSet();
      if (mounted) {
        state = state.copyWith(
            transactions: [
              ...queued.where((t) => !cloudIds.contains(submissionId(t.id))),
              ...cloud,
            ]..sort((a, b) =>
                (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date)),
            isLoading: false);
      }
    } catch (e) {
      if (mounted && revision == _loadRevision) {
        if (mounted) {
          state = state.copyWith(error: e.toString(), isLoading: false);
        }
      }
    }
  }

  Future<void> loadTransactions(String siteId, {TransactionType? type}) async {
    // Fetch all accessible records; server policies determine the permitted scope.
    // Views filter the canonical cache instead of changing shared cache scope.
    await loadAllTransactions();
  }

  /// Load current stock for a site
  Future<void> loadCurrentStock(String siteId) async {
    final revision = ++_stockRevision;
    try {
      final stock = await _stockService.getCurrentStock(siteId);
      if (!mounted || revision != _stockRevision) return;
      if (mounted) {
        state = state.copyWith(currentStock: stock);
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: e.toString());
      }
    }
  }

  /// Persist identity and attachments before making any network request.
  Future<bool> submitTransaction(StockTransactionModel transaction) async {
    if (mounted) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    StockTransactionModel? queued;
    try {
      EntryDatePolicy.requireNotFuture(transaction.date);
      queued = await OfflineService.queueStockTransaction(
          transaction.copyWith(id: submissionId(transaction.id)));
      final created = await _stockService.submitTransaction(queued);
      await OfflineService.removeQueuedStockTransaction(queued.id!);
      if (mounted) {
        state = state.copyWith(transactions: [
          created,
          ...state.transactions
              .where((t) => t.id != created.id && t.id != queued!.id)
        ], isLoading: false);
      }
      // A fetch started before this acknowledgement must not restore stale rows.
      ++_loadRevision;
      if (mounted && state.isLoading) state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      if (e is HandledRejectedSubmission && queued != null) {
        await OfflineService.removeQueuedStockTransaction(queued.id!);
        ++_loadRevision;
        if (mounted) {
          state = state.copyWith(
              transactions: state.transactions
                  .where((t) => submissionId(t.id) != e.id)
                  .toList(),
              isLoading: false,
              error: e.toString());
        }
        return false;
      }

      if (queued != null && isRetryableSubmissionError(e)) {
        if (mounted) {
          state = state.copyWith(transactions: [
            queued,
            ...state.transactions.where((t) => t.id != queued!.id)
          ], isLoading: false, error: 'OFFLINE_SAVED');
        }
        // A fetch started before this acknowledgement must not restore stale rows.
        ++_loadRevision;
        if (mounted && state.isLoading) {
          state = state.copyWith(isLoading: false);
        }
        return true;
      }
      if (queued != null) {
        try {
          await OfflineService.pauseStock(queued.id!, e);
        } catch (_) {}
      }
      // Permanent errors remain durably preserved, but never pretend to be offline.
      if (mounted) {
        state = state.copyWith(error: e.toString(), isLoading: false);
      }
      return false;
    }
  }

  /// Update an existing stock transaction (handles both online & offline/queued records)
  Future<bool> updateTransaction(StockTransactionModel transaction) async {
    final txId = transaction.id;

    // Handle offline queued transactions
    if (txId != null && await OfflineService.isQueuedStock(txId)) {
      try {
        EntryDatePolicy.requireNotFuture(transaction.date);
        if (transaction.status == TransactionStatus.rejected) {
          if (txId.isNotEmpty) {
            await OfflineService.removeQueuedStockTransaction(txId);
          }
        } else {
          await OfflineService.updateQueuedStockTransaction(transaction);
        }
        if (mounted) {
          state = state.copyWith(
            transactions: state.transactions
                .map((t) => t.id == txId ? transaction : t)
                .toList(),
            isLoading: false,
          );
        }
        // A fetch started before this acknowledgement must not restore stale rows.
        ++_loadRevision;
        if (mounted && state.isLoading) {
          state = state.copyWith(isLoading: false);
        }
        return true;
      } catch (e) {
        if (mounted) {
          state = state.copyWith(error: e.toString(), isLoading: false);
        }
        return false;
      }
    }

    if (mounted) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    try {
      final updated = await _stockService.updateTransaction(
        txId!,
        transaction.toJson(),
      );
      if (mounted) {
        state = state.copyWith(
          transactions: state.transactions
              .map((t) => t.id == updated.id ? updated : t)
              .toList(),
          isLoading: false,
        );
      }
      // A fetch started before this acknowledgement must not restore stale rows.
      ++_loadRevision;
      if (mounted && state.isLoading) state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: e.toString(), isLoading: false);
      }
      return false;
    }
  }

  /// Delete / remove a stock transaction permanently
  Future<bool> deleteTransaction(StockTransactionModel transaction) async {
    final txId = transaction.id;
    try {
      if (txId != null && txId.startsWith('offline_')) {
        await OfflineService.removeQueuedStockTransaction(txId);
      } else {
        if (txId != null && !txId.startsWith('offline_')) {
          await _stockService.deleteTransaction(txId);
        }
      }
      if (mounted) {
        state = state.copyWith(
          transactions: state.transactions.where((t) => t.id != txId).toList(),
        );
      }
      // A fetch started before this acknowledgement must not restore stale rows.
      ++_loadRevision;
      if (mounted && state.isLoading) state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: e.toString());
      }
      return false;
    }
  }

  /// Approve a transaction (accounts level)
  Future<bool> approveByAccounts(
      String transactionId, String reviewedBy) async {
    try {
      await _stockService.approveByAccounts(transactionId, reviewedBy);
      // Update local state
      if (mounted) {
        state = state.copyWith(
          transactions: state.transactions
              .map((t) => t.id == transactionId
                  ? t.copyWith(status: TransactionStatus.pendingAdmin)
                  : t)
              .toList(),
        );
      }
      // A fetch started before this acknowledgement must not restore stale rows.
      ++_loadRevision;
      if (mounted && state.isLoading) state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: e.toString());
      }
      return false;
    }
  }

  /// Approve a transaction (admin level)
  Future<bool> approveByAdmin(
      StockTransactionModel transaction, String approvedBy) async {
    try {
      await _stockService.approveByAdmin(transaction.id!, approvedBy);

      if (mounted) {
        state = state.copyWith(
          transactions: state.transactions.map((t) {
            if (t.id == transaction.id!) {
              return t.copyWith(
                status: TransactionStatus.approved,
                approvedBy: approvedBy,
                approvedAt: DateTime.now(),
              );
            }
            return t;
          }).toList(),
        );
      }
      // A fetch started before this acknowledgement must not restore stale rows.
      ++_loadRevision;
      if (mounted && state.isLoading) state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: e.toString());
      }
      return false;
    }
  }

  /// Reject a transaction
  Future<bool> rejectTransaction(
    String transactionId,
    String rejectedBy,
    String note, {
    String? remarks,
  }) async {
    try {
      await _stockService.rejectTransaction(transactionId, rejectedBy, note,
          remarks: remarks);
      if (mounted) {
        state = state.copyWith(
          transactions: state.transactions
              .map((t) => t.id == transactionId
                  ? t.copyWith(status: TransactionStatus.rejected)
                  : t)
              .toList(),
        );
      }
      // A fetch started before this acknowledgement must not restore stale rows.
      ++_loadRevision;
      if (mounted && state.isLoading) state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: e.toString());
      }
      return false;
    }
  }
}

/// Provider for stock state
final stockProvider = StateNotifierProvider<StockNotifier, StockState>((ref) {
  final notifier = StockNotifier(ref.read(stockServiceProvider));
  ref.listen(authProvider.select((a) => a.user?.id ?? a.activeSite?.id),
      (_, next) => notifier.clearSession());
  return notifier;
});

/// Provider for pending stock transactions (accounts view)
final pendingStockAccountsProvider =
    FutureProvider.autoDispose<List<StockTransactionModel>>((ref) async {
  final stockService = ref.read(stockServiceProvider);
  final roleAccess = ref.watch(roleAccessProvider);
  if (!roleAccess.accountsCanApproveStock) {
    return [];
  }
  final list = await stockService.getPendingForAccounts();
  final filtered = list.where((t) {
    // If Project Head approval power is extracted by Admin, bypass Project Head review!
    if (!roleAccess.projectHeadCanApproveStock) {
      return true;
    }
    return !t.isPendingSupervisorReview;
  }).toList();
  filtered
      .sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));
  return filtered;
});

/// Provider for pending-admin stock transactions (latest on top)
final pendingStockAdminProvider =
    FutureProvider.autoDispose<List<StockTransactionModel>>((ref) async {
  final stockService = ref.read(stockServiceProvider);
  final list = await stockService.getPendingForAdmin();
  return list
    ..sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));
});

/// Provider for all sites stock overview
final allSitesStockProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final stockService = ref.read(stockServiceProvider);
  return stockService.getAllSitesStock();
});

/// Provider for a specific site's stock overview
final stockOverviewProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, siteId) async {
  final stockService = ref.read(stockServiceProvider);
  return stockService.getCurrentStock(siteId);
});

final allSitesStockSummaryProvider = allSitesStockProvider;
