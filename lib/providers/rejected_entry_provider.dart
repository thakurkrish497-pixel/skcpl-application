import 'rejected_entry_ownership_provider.dart';
export 'rejected_entry_ownership_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/rejected_entry_service.dart';
import 'auth_provider.dart';
import 'cash_provider.dart';
import 'stock_provider.dart';
import '../services/transaction_refresh.dart';

final rejectedEntryServiceProvider = Provider<RejectedEntryService>(
    (ref) => RejectedEntryService(ref.read(supabaseClientProvider)));
Future<void> refreshRejectedEntries(WidgetRef ref) async {
  ref.invalidate(rejectedResubmissionOwnersProvider);
  invalidateTransactionViews(ref.invalidate);
  await Future.wait([
    ref.read(cashProvider.notifier).refresh(),
    ref.read(stockProvider.notifier).refresh()
  ]);
}
