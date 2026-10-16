import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stock_transaction_model.dart';
import '../models/dropdown_item_model.dart';
import '../services/stock_service.dart';
import '../services/dropdown_service.dart';
import 'auth_provider.dart';
import 'dropdown_provider.dart';

/// Provides the StockService
final stockServiceProvider = Provider<StockService>((ref) {
  return StockService(ref.read(supabaseClientProvider));
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
  final DropdownService _dropdownService;

  StockNotifier(this._stockService, this._dropdownService) : super(const StockState());

  /// Load stock transactions for a site
  Future<void> loadTransactions(String siteId, {TransactionType? type}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final transactions = await _stockService.getTransactionsForSite(
        siteId,
        type: type,
      );
      state = state.copyWith(transactions: transactions, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
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

  /// Submit a new stock transaction
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
      state = state.copyWith(error: e.toString(), isLoading: false);
      return false;
    }
  }

  /// Update an existing stock transaction
  Future<bool> updateTransaction(StockTransactionModel transaction) async {
    if (transaction.id == null) return false;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final updated = await _stockService.updateTransaction(
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
      
      // If there's an unregistered vendor, add it to the dropdowns table automatically
      if (transaction.unregisteredVendor != null && transaction.unregisteredVendor!.trim().isNotEmpty) {
        try {
          await _dropdownService.addDropdown(
            category: DropdownCategory.vendor,
            value: transaction.unregisteredVendor!.trim(),
            siteId: transaction.siteId,
          );
        } catch (e) {
          // Already exists or other error, ignore so we don't fail the approval
        }
      }
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
    ref.read(dropdownServiceProvider),
  );
});

/// Provider for pending stock transactions (accounts view)
final pendingStockAccountsProvider =
    FutureProvider.autoDispose<List<StockTransactionModel>>((ref) async {
  final stockService = ref.read(stockServiceProvider);
  return stockService.getPendingForAccounts();
});

/// Provider for pending-admin stock transactions
final pendingStockAdminProvider =
    FutureProvider.autoDispose<List<StockTransactionModel>>((ref) async {
  final stockService = ref.read(stockServiceProvider);
  return stockService.getPendingForAdmin();
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
