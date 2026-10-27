import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cash_transaction_model.dart';
import '../models/stock_transaction_model.dart'; // for TransactionStatus
import '../services/cash_service.dart';
import '../services/offline_service.dart';
import 'auth_provider.dart';
import 'role_access_provider.dart';

/// Provides the CashService
final cashServiceProvider = Provider<CashService>((ref) {
  return CashService(ref.read(supabaseServiceClientProvider));
});

/// State for cash transactions
class CashState {
  final List<CashTransactionModel> transactions;
  final bool isLoading;
  final String? error;

  const CashState({
    this.transactions = const [],
    this.isLoading = false,
    this.error,
  });

  CashState copyWith({
    List<CashTransactionModel>? transactions,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return CashState(
      transactions: transactions ?? this.transactions,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Cash state notifier
class CashNotifier extends StateNotifier<CashState> {
  final CashService _cashService;

  CashNotifier(this._cashService) : super(const CashState());

  /// Load cash transactions for all sites (merges any queued offline records, latest on top)
  Future<void> loadAllTransactions() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final queued = await OfflineService.getQueuedCashTransactions();

    try {
      final transactions = await _cashService.getAllTransactions();
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

  /// Load cash transactions for a site (merges any queued offline records)
  Future<void> loadTransactions(String siteId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final queued = await OfflineService.getQueuedCashTransactions();
    final siteQueued = queued.where((c) => c.siteId == siteId).toList();

    try {
      final transactions = await _cashService.getTransactionsForSite(siteId);
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

  /// Submit a new cash transaction with automatic offline queue fallback
  Future<bool> submitTransaction(CashTransactionModel transaction) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final created = await _cashService.submitTransaction(transaction);
      state = state.copyWith(
        transactions: [created, ...state.transactions],
        isLoading: false,
      );
      return true;
    } catch (e) {
      // Fallback: save to local offline queue
      try {
        final offlineTx = await OfflineService.queueCashTransaction(transaction);
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

  /// Update an existing cash transaction (handles both online & offline/queued records)
  Future<bool> updateTransaction(CashTransactionModel transaction) async {
    final txId = transaction.id;

    // Handle offline queued transactions
    if (txId == null || txId.startsWith('offline_')) {
      try {
        if (transaction.status == TransactionStatus.rejected) {
          if (txId != null) {
            await OfflineService.removeQueuedCashTransaction(txId);
          }
        } else {
          await OfflineService.updateQueuedCashTransaction(transaction);
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
      final updated = await _cashService.updateTransaction(
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
      // If online update failed, check if it was actually in local offline queue
      try {
        if (transaction.status == TransactionStatus.rejected) {
          await OfflineService.removeQueuedCashTransaction(txId);
        } else {
          await OfflineService.updateQueuedCashTransaction(transaction);
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

  /// Delete / remove a cash transaction permanently
  Future<bool> deleteTransaction(CashTransactionModel transaction) async {
    final txId = transaction.id;
    try {
      if (txId != null && txId.startsWith('offline_')) {
        await OfflineService.removeQueuedCashTransaction(txId);
      } else {
        await OfflineService.removeQueuedCashTransactionMatching(
          siteId: transaction.siteId,
          remarks: transaction.remarks,
          amount: transaction.expenseAmount,
        );
        if (txId != null && !txId.startsWith('offline_')) {
          await _cashService.deleteTransaction(txId);
        }
      }
      state = state.copyWith(
        transactions: state.transactions
            .where((t) => t.id != txId && !(t.siteId == transaction.siteId && t.remarks == transaction.remarks && t.expenseAmount == transaction.expenseAmount))
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

  /// Accounts approves a cash transaction
  Future<bool> approveByAccounts(String transactionId, String reviewedBy) async {
    try {
      await _cashService.approveByAccounts(transactionId, reviewedBy);
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

  /// Admin approves (permanent lock)
  Future<bool> approveByAdmin(String transactionId, String approvedBy) async {
    try {
      await _cashService.approveByAdmin(transactionId, approvedBy);
      state = state.copyWith(
        transactions: state.transactions
            .map((t) => t.id == transactionId
                ? t.copyWith(status: TransactionStatus.approved)
                : t)
            .toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Reject
  Future<bool> rejectTransaction(
    String transactionId,
    String rejectedBy,
    String note,
  ) async {
    try {
      await _cashService.rejectTransaction(transactionId, rejectedBy, note);
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

/// Provider for cash state
final cashProvider = StateNotifierProvider<CashNotifier, CashState>((ref) {
  return CashNotifier(ref.read(cashServiceProvider));
});

/// Provider for pending cash (accounts)
final pendingCashAccountsProvider =
    FutureProvider.autoDispose<List<CashTransactionModel>>((ref) async {
  final cashService = ref.read(cashServiceProvider);
  final roleAccess = ref.watch(roleAccessProvider);
  if (!roleAccess.accountsCanApproveCash) {
    return [];
  }
  final list = await cashService.getPendingForAccounts();
  final filtered = list.where((t) {
    // If Project Head approval power is extracted by Admin, bypass Project Head review!
    if (!roleAccess.projectHeadCanApproveCash) {
      return true;
    }
    return !t.isPendingSupervisorReview;
  }).toList();
  filtered.sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));
  return filtered;
});

/// Provider for pending-admin cash transactions (latest on top)
final pendingCashAdminProvider =
    FutureProvider.autoDispose<List<CashTransactionModel>>((ref) async {
  final cashService = ref.read(cashServiceProvider);
  final list = await cashService.getPendingForAdmin();
  return list..sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));
});

/// Provider for a specific site's cash summary
final siteCashSummaryProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, siteId) async {
  final cashService = ref.read(cashServiceProvider);
  return cashService.getSiteCashSummary(siteId);
});
