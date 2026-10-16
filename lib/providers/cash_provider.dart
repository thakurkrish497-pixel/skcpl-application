import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cash_transaction_model.dart';
import '../models/stock_transaction_model.dart'; // for TransactionStatus
import '../services/cash_service.dart';
import 'auth_provider.dart';

/// Provides the CashService
final cashServiceProvider = Provider<CashService>((ref) {
  return CashService(ref.read(supabaseClientProvider));
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

  /// Load cash transactions for a site
  Future<void> loadTransactions(String siteId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final transactions = await _cashService.getTransactionsForSite(siteId);
      state = state.copyWith(transactions: transactions, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// Submit a new cash transaction
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
      state = state.copyWith(error: e.toString(), isLoading: false);
      return false;
    }
  }

  /// Update an existing cash transaction
  Future<bool> updateTransaction(CashTransactionModel transaction) async {
    if (transaction.id == null) return false;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final updated = await _cashService.updateTransaction(
        transaction.id!,
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
      state = state.copyWith(error: e.toString(), isLoading: false);
      return false;
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
  return cashService.getPendingForAccounts();
});

/// Provider for pending-admin cash transactions
final pendingCashAdminProvider =
    FutureProvider.autoDispose<List<CashTransactionModel>>((ref) async {
  final cashService = ref.read(cashServiceProvider);
  return cashService.getPendingForAdmin();
});

/// Provider for a specific site's cash summary
final siteCashSummaryProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, siteId) async {
  final cashService = ref.read(cashServiceProvider);
  return cashService.getSiteCashSummary(siteId);
});
