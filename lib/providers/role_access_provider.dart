import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/role_permissions_model.dart';
import '../services/role_access_service.dart';

final roleAccessServiceProvider = Provider<RoleAccessService>((ref) {
  return RoleAccessService();
});

class RoleAccessNotifier extends StateNotifier<RolePermissionsModel> {
  final RoleAccessService _service;

  RoleAccessNotifier(this._service) : super(const RolePermissionsModel()) {
    loadPermissions();
  }

  Future<void> loadPermissions() async {
    try {
      final perms = await _service.getPermissions();
      state = perms;
    } catch (_) {}
  }

  Future<bool> saveRolePermissions(RolePermissionsModel updated) async {
    state = updated;
    try {
      await _service.savePermissions(updated);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> resetToDefaults() async {
    const defaultModel = RolePermissionsModel();
    state = defaultModel;
    try {
      await _service.resetToDefaults();
    } catch (_) {}
  }
}

final roleAccessProvider =
    StateNotifierProvider<RoleAccessNotifier, RolePermissionsModel>((ref) {
  return RoleAccessNotifier(ref.read(roleAccessServiceProvider));
});
