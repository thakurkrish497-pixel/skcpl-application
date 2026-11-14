import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/role_permissions_model.dart';
import '../services/role_access_service.dart';

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
