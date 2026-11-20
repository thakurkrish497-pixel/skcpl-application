import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/dsr_history_service.dart';
import 'auth_provider.dart';
export '../services/dsr_history_service.dart';

bool canViewDsrHistory(UserRole? role) =>
    role == UserRole.admin ||
    role == UserRole.projectHead ||
    role == UserRole.accounts;
bool canAccessDsrHistory(AuthState auth, {String? siteId}) =>
    canViewDsrHistory(auth.user?.role) ||
    (auth.activeSite != null &&
        (siteId == null || siteId == auth.activeSite!.id));

final dsrHistoryServiceProvider = Provider<DsrHistoryService>(
    (ref) => DsrHistoryService(ref.read(supabaseClientProvider)));
final dsrHistoryProvider =
    FutureProvider.autoDispose<DsrHistorySnapshot>((ref) {
  final auth = ref.watch(authProvider);
  final service = ref.watch(dsrHistoryServiceProvider);
  if (canViewDsrHistory(auth.user?.role)) return service.load();
  final site = auth.activeSite;
  if (site == null) {
    throw StateError(
        'Management sign-in or a site session is required to view DSR history.');
  }
  return service.loadForSite(site.id);
});
