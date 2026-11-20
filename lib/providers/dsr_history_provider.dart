import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/dsr_history_service.dart';
import 'auth_provider.dart';
export '../services/dsr_history_service.dart';

bool canViewDsrHistory(UserRole? role) =>
    role == UserRole.admin ||
    role == UserRole.projectHead ||
    role == UserRole.accounts;
final dsrHistoryServiceProvider = Provider<DsrHistoryService>(
    (ref) => DsrHistoryService(ref.read(supabaseClientProvider)));
final dsrHistoryProvider =
    FutureProvider.autoDispose<DsrHistorySnapshot>((ref) {
  final auth =
      ref.watch(authProvider.select((a) => (a.user?.id, a.user?.role)));
  if (!canViewDsrHistory(auth.$2)) {
    throw StateError('Management sign-in is required to view DSR history.');
  }
  return ref.watch(dsrHistoryServiceProvider).load();
});
