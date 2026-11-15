import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/role_permissions_model.dart';
import '../services/role_access_service.dart';
import 'auth_provider.dart';

final roleAccessServiceProvider = Provider<RoleAccessService>((ref) {
  return RoleAccessService();
});

class RoleAccessNotifier extends StateNotifier<RolePermissionsModel> {
  final RoleAccessService _service;

  RoleAccessNotifier(this._service) : super(const RolePermissionsModel()) {
    loadPermissions(forceRefresh: true);
  }

  Future<void> loadPermissions({bool forceRefresh = true}) async {
    try {
      final perms = await _service.getPermissions(forceRefresh: forceRefresh);
      if (mounted) state = perms;
    } catch (_) {}
  }

  void applyServerPolicy(RolePermissionsModel policy) {
    if (mounted) state = policy;
  }

  Future<bool> saveRolePermissions(RolePermissionsModel updated) async {
    try {
      await _service.savePermissions(updated);
      if (mounted) state = updated;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resetToDefaults() =>
      saveRolePermissions(const RolePermissionsModel());
}

final roleAccessProvider =
    StateNotifierProvider<RoleAccessNotifier, RolePermissionsModel>((ref) {
  return RoleAccessNotifier(ref.read(roleAccessServiceProvider));
});

/// Credential changes refresh authentication without clearing any offline data.
final managementSessionGuardProvider = Provider<void>((ref) {
  bool disposed = false;
  void check() {
    if (disposed) return;
    final notifier = ref.read(authProvider.notifier);
    notifier.enforceCredentialRevision(ref.read(roleAccessProvider));
  }

  ref.listen<RolePermissionsModel>(roleAccessProvider, (_, __) => check());
  ref.listen(
      authProvider.select((value) => value.user?.id), (_, __) => check());
  Future.microtask(check);
  ref.onDispose(() => disposed = true);
});
