import '../services/rejected_entry_service.dart';
import '../services/entry_date_policy.dart';
import 'stock_provider.dart';
import '../services/submission_support.dart';
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
  int _loadRevision = 0;
  void clearSession() {
    ++_loadRevision;
    if (mounted) state = const CashState();
  }

  Future<void> refresh() => loadAllTransactions();

  CashNotifier(this._cashService) : super(const CashState());

  /// Keep a canonical cache. Site loads replace only that site's records.
  Future<void> loadAllTransactions() async {
    final revision = ++_loadRevision;
    if (mounted) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    try {
      final cloud = await _cashService.getAllTransactions();
      final queued = await OfflineService.getQueuedCashTransactions();
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

  Future<void> loadTransactions(String siteId) async {
    // Fetch all accessible records; server policies determine the permitted scope.
    // Views filter the canonical cache instead of changing shared cache scope.
    await loadAllTransactions();
  }

  /// Persist identity and attachments before making any network request.
  Future<bool> submitTransaction(CashTransactionModel transaction) async {
    if (mounted) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    CashTransactionModel? queued;
    try {
      EntryDatePolicy.requireNotFuture(transaction.date);
      queued = await OfflineService.queueCashTransaction(
          transaction.copyWith(id: submissionId(transaction.id)));
      final created = await _cashService.submitTransaction(queued);
      await OfflineService.removeQueuedCashTransaction(queued.id!);
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
        await OfflineService.removeQueuedCashTransaction(queued.id!);
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
          await OfflineService.pauseCash(queued.id!, e);
        } catch (_) {}
      }
      // Permanent errors remain durably preserved, but never pretend to be offline.
      if (mounted) {
        state = state.copyWith(error: e.toString(), isLoading: false);
      }
      return false;
    }
  }

  /// Update an existing cash transaction (handles both online & offline/queued records)
  Future<bool> updateTransaction(CashTransactionModel transaction) async {
    final txId = transaction.id;

    // Handle offline queued transactions
    if (txId != null && await OfflineService.isQueuedCash(txId)) {
      try {
        EntryDatePolicy.requireNotFuture(transaction.date);
        if (transaction.status == TransactionStatus.rejected) {
          if (txId.isNotEmpty) {
            await OfflineService.removeQueuedCashTransaction(txId);
          }
        } else {
          await OfflineService.updateQueuedCashTransaction(transaction);
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
      final updated = await _cashService.updateTransaction(
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

  /// Delete / remove a cash transaction permanently
  Future<bool> deleteTransaction(CashTransactionModel transaction) async {
    final txId = transaction.id;
    try {
      if (txId != null && txId.startsWith('offline_')) {
        await OfflineService.removeQueuedCashTransaction(txId);
      } else {
        if (txId != null && !txId.startsWith('offline_')) {
          await _cashService.deleteTransaction(txId);
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

  /// Accounts approves a cash transaction
  Future<bool> approveByAccounts(
      String transactionId, String reviewedBy) async {
    try {
      await _cashService.approveByAccounts(transactionId, reviewedBy);
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

  /// Admin approves (permanent lock)
  Future<bool> approveByAdmin(String transactionId, String approvedBy) async {
    try {
      await _cashService.approveByAdmin(transactionId, approvedBy);
      if (mounted) {
        state = state.copyWith(
          transactions: state.transactions
              .map((t) => t.id == transactionId
                  ? t.copyWith(status: TransactionStatus.approved)
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

  /// Reject
  Future<bool> rejectTransaction(
    String transactionId,
    String rejectedBy,
    String note, {
    String? remarks,
  }) async {
    try {
      await _cashService.rejectTransaction(transactionId, rejectedBy, note,
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

/// Provider for cash state
final cashProvider = StateNotifierProvider<CashNotifier, CashState>((ref) {
  final notifier = CashNotifier(ref.read(cashServiceProvider));
  ref.listen(authProvider.select((a) => a.user?.id ?? a.activeSite?.id),
      (_, next) => notifier.clearSession());
  return notifier;
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
  filtered
      .sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));
  return filtered;
});

/// Provider for pending-admin cash transactions (latest on top)
final pendingCashAdminProvider =
    FutureProvider.autoDispose<List<CashTransactionModel>>((ref) async {
  final cashService = ref.read(cashServiceProvider);
  final list = await cashService.getPendingForAdmin();
  return list
    ..sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));
});

/// Provider for a specific site's cash summary
final siteCashSummaryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, siteId) async {
  final cashService = ref.read(cashServiceProvider);
  return cashService.getSiteCashSummary(siteId);
});

/// Approved company balances, independent of whichever dashboard loaded history last.
final allSitesFinanceSummaryProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final transactions = await ref
      .watch(cashServiceProvider)
      .getAllTransactions(status: TransactionStatus.approved);
  final sums = <String, Map<String, dynamic>>{};
  for (final tx in transactions) {
    final row = sums.putIfAbsent(
        tx.siteId,
        () => {
              'site_id': tx.siteId,
              'total_received': 0.0,
              'total_expense': 0.0,
              'balance': 0.0
            });
    row['total_received'] =
        (row['total_received'] as double) + tx.amountReceived;
    row['total_expense'] = (row['total_expense'] as double) + tx.expenseAmount;
    row['balance'] =
        (row['total_received'] as double) - (row['total_expense'] as double);
  }
  return sums.values.toList();
});

final recentTransactionActivityProvider =
    FutureProvider.autoDispose<({List<double> cash, List<double> stock})>(
        (ref) async {
  final now = DateTime.now();
  final start =
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
  final cash = await ref.watch(cashServiceProvider).getAllTransactions();
  final stock = await ref.watch(stockServiceProvider).getAllTransactions();
  final cashCounts = List<double>.filled(7, 0);
  final stockCounts = List<double>.filled(7, 0);
  void count(DateTime date, List<double> counts) {
    final d = date.toLocal();
    final index = DateTime(d.year, d.month, d.day).difference(start).inDays;
    if (index >= 0 && index < 7) counts[index]++;
  }

  for (final tx in cash) {
    count(tx.createdAt ?? tx.date, cashCounts);
  }
  for (final tx in stock) {
    count(tx.createdAt ?? tx.date, stockCounts);
  }
  return (cash: cashCounts, stock: stockCounts);
});

/// Operational view of the canonical cloud + durable offline cache. Approval-only
/// accounting providers above remain separate. Realtime/retry updates to the
/// cash notifier immediately recompute this view without extra subscriptions.
final siteOperationalCashSummaryProvider =
    Provider.autoDispose.family<Map<String, double>, String>((ref, siteId) {
  final transactions =
      ref.watch(cashProvider.select((state) => state.transactions));
  double received = 0, spent = 0, approvedReceived = 0, approvedSpent = 0;
  var pending = 0;
  for (final tx in transactions.where((tx) => tx.siteId == siteId)) {
    if (tx.status == TransactionStatus.rejected) continue;
    received += tx.amountReceived;
    spent += tx.expenseAmount;
    if (tx.status == TransactionStatus.approved) {
      approvedReceived += tx.amountReceived;
      approvedSpent += tx.expenseAmount;
    } else {
      pending++;
    }
  }
  return {
    'total_received': received,
    'total_expense': spent,
    'balance': received - spent,
    'approved_balance': approvedReceived - approvedSpent,
    'approved_expense': approvedSpent,
    'pending_count': pending.toDouble(),
  };
});
