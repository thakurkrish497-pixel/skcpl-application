import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stock_transaction_model.dart';
import '../services/stock_service.dart';
import '../services/dropdown_service.dart';
import '../services/offline_service.dart';
import 'auth_provider.dart';
import 'dropdown_provider.dart';
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

  StockNotifier(this._stockService) : super(const StockState());

  /// Load stock transactions for all sites (merges any queued offline records, latest on top)
  Future<void> loadAllTransactions({TransactionType? type}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final queued = await OfflineService.getQueuedStockTransactions();

    try {
      final transactions = await _stockService.getAllTransactions(type: type);
      final allList = [...queued, ...transactions]
        ..sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));
      state = state.copyWith(
        transactions: allList,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        transactions: queued,
        error: queued.isNotEmpty ? null : e.toString(),
        isLoading: false,
      );
    }
  }

  /// Load stock transactions for a site (merges any queued offline records)
  Future<void> loadTransactions(String siteId, {TransactionType? type}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final queued = await OfflineService.getQueuedStockTransactions();
    final siteQueued = queued.where((t) => t.siteId == siteId).toList();

    try {
      final transactions = await _stockService.getTransactionsForSite(
        siteId,
        type: type,
      );
      final allList = [...siteQueued, ...transactions]
        ..sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));
      state = state.copyWith(
        transactions: allList,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        transactions: siteQueued,
        error: siteQueued.isNotEmpty ? null : e.toString(),
        isLoading: false,
      );
    }
  }

  /// Load current stock for a site
  Future<void> loadCurrentStock(String siteId) async {
    try {
      final stock = await _stockService.getCurrentStock(siteId);
      state = state.copyWith(currentStock: stock);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Submit a new stock transaction with automatic offline queue fallback
  Future<bool> submitTransaction(StockTransactionModel transaction) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final created = await _stockService.submitTransaction(transaction);
      state = state.copyWith(
        transactions: [created, ...state.transactions],
        isLoading: false,
      );
      return true;
    } catch (e) {
      // Fallback: save to local offline queue
      try {
        final offlineTx = await OfflineService.queueStockTransaction(transaction);
        state = state.copyWith(
          transactions: [offlineTx, ...state.transactions],
          isLoading: false,
          error: 'OFFLINE_SAVED',
        );
        return true;
      } catch (queueErr) {
        state = state.copyWith(error: e.toString(), isLoading: false);
        return false;
      }
    }
  }

  /// Update an existing stock transaction (handles both online & offline/queued records)
  Future<bool> updateTransaction(StockTransactionModel transaction) async {
    final txId = transaction.id;

    // Handle offline queued transactions
    if (txId == null || txId.startsWith('offline_')) {
      try {
        if (transaction.status == TransactionStatus.rejected) {
          if (txId != null) {
            await OfflineService.removeQueuedStockTransaction(txId);
          }
        } else {
          await OfflineService.updateQueuedStockTransaction(transaction);
        }
        state = state.copyWith(
          transactions: state.transactions
              .map((t) => (t.id == txId || (txId == null && t.remarks == transaction.remarks))
                  ? transaction
                  : t)
              .toList(),
          isLoading: false,
        );
        return true;
      } catch (e) {
        state = state.copyWith(error: e.toString(), isLoading: false);
        return false;
      }
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final updated = await _stockService.updateTransaction(
        txId,
        transaction.toJson(),
      );
      state = state.copyWith(
        transactions: state.transactions
            .map((t) => t.id == updated.id ? updated : t)
            .toList(),
        isLoading: false,
      );
      return true;
    } catch (e) {
      // If online update failed, check if it was in local offline queue
      try {
        if (transaction.status == TransactionStatus.rejected) {
          await OfflineService.removeQueuedStockTransaction(txId);
        } else {
          await OfflineService.updateQueuedStockTransaction(transaction);
        }
        state = state.copyWith(
          transactions: state.transactions
              .map((t) => t.id == txId ? transaction : t)
              .toList(),
          isLoading: false,
        );
        return true;
      } catch (_) {}

      state = state.copyWith(error: e.toString(), isLoading: false);
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
      state = state.copyWith(
        transactions: state.transactions
            .where((t) => t.id != txId && !(t.siteId == transaction.siteId && t.remarks == transaction.remarks && t.quantity == transaction.quantity))
            .toList(),
      );
      return true;
    } catch (_) {
      state = state.copyWith(
        transactions: state.transactions.where((t) => t.id != txId).toList(),
      );
      return true;
    }
  }

  /// Approve a transaction (accounts level)
  Future<bool> approveByAccounts(String transactionId, String reviewedBy) async {
    try {
      await _stockService.approveByAccounts(transactionId, reviewedBy);
      // Update local state
      state = state.copyWith(
        transactions: state.transactions
            .map((t) => t.id == transactionId
                ? t.copyWith(status: TransactionStatus.pendingAdmin)
                : t)
            .toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Approve a transaction (admin level)
  Future<bool> approveByAdmin(StockTransactionModel transaction, String approvedBy) async {
    try {
      await _stockService.approveByAdmin(transaction.id!, approvedBy);
      
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
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Reject a transaction
  Future<bool> rejectTransaction(
    String transactionId,
    String rejectedBy,
    String note,
  ) async {
    try {
      await _stockService.rejectTransaction(transactionId, rejectedBy, note);
      state = state.copyWith(
        transactions: state.transactions
            .map((t) => t.id == transactionId
                ? t.copyWith(status: TransactionStatus.rejected)
                : t)
            .toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

/// Provider for stock state
final stockProvider = StateNotifierProvider<StockNotifier, StockState>((ref) {
  return StockNotifier(
    ref.read(stockServiceProvider),
  );
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
  filtered.sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));
  return filtered;
});

/// Provider for pending-admin stock transactions (latest on top)
final pendingStockAdminProvider =
    FutureProvider.autoDispose<List<StockTransactionModel>>((ref) async {
  final stockService = ref.read(stockServiceProvider);
  final list = await stockService.getPendingForAdmin();
  return list..sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));
});

/// Provider for all sites stock overview
final allSitesStockProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final stockService = ref.read(stockServiceProvider);
  return stockService.getAllSitesStock();
});

/// Provider for a specific site's stock overview
final stockOverviewProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, siteId) async {
  final stockService = ref.read(stockServiceProvider);
  return stockService.getCurrentStock(siteId);
});
