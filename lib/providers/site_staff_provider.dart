import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/site_staff_model.dart';
import '../services/site_staff_service.dart';

final siteStaffServiceProvider = Provider<SiteStaffService>((ref) {
  return SiteStaffService();
});

/// State of staff members for a site
class SiteStaffState {
  final List<SiteStaffModel> staffList;
  final bool isLoading;
  final String? error;

  const SiteStaffState({
    this.staffList = const [],
    this.isLoading = false,
    this.error,
  });

  SiteStaffState copyWith({
    List<SiteStaffModel>? staffList,
    bool? isLoading,
    String? error,
  }) {
    return SiteStaffState(
      staffList: staffList ?? this.staffList,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class SiteStaffNotifier extends StateNotifier<SiteStaffState> {
  final SiteStaffService _service;
  final String siteId;

  SiteStaffNotifier(this._service, this.siteId) : super(const SiteStaffState()) {
    loadStaff();
  }

  Future<void> loadStaff() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final list = await _service.getStaffForSite(siteId);
      if (mounted) {
        state = state.copyWith(staffList: list, isLoading: false);
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: e.toString(), isLoading: false);
      }
    }
  }

  Future<void> addStaff(SiteStaffModel staff) async {
    try {
      final created = await _service.createStaff(staff);
      state = state.copyWith(
        staffList: [...state.staffList, created]..sort((a, b) => a.name.compareTo(b.name)),
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> updateStaff(SiteStaffModel staff) async {
    try {
      final updated = await _service.updateStaff(staff);
      state = state.copyWith(
        staffList: state.staffList
            .map((s) => s.id == updated.id ? updated : s)
            .toList(),
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> deleteStaff(String staffId) async {
    try {
      await _service.deleteStaff(staffId, siteId);
      state = state.copyWith(
        staffList: state.staffList.where((s) => s.id != staffId).toList(),
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }
}

final siteStaffProvider =
    StateNotifierProvider.family<SiteStaffNotifier, SiteStaffState, String>(
  (ref, siteId) {
    return SiteStaffNotifier(ref.read(siteStaffServiceProvider), siteId);
  },
);

class ActiveStaffNotifier extends StateNotifier<SiteStaffModel?> {
  final Ref? _ref;
  ActiveStaffNotifier([this._ref]) : super(null);

  static String _prefKey(String siteId, [StaffModule? module]) =>
      module != null ? 'skcpl_active_staff_${siteId}_${module.name}' : 'skcpl_active_staff_$siteId';

  /// Sets the active staff member and optionally remembers them per site and module
  Future<void> setActiveStaff(
    SiteStaffModel? staff, {
    required String siteId,
    StaffModule? module,
    bool remember = true,
  }) async {
    state = staff;
    final prefs = await SharedPreferences.getInstance();
    final effectiveModule = module ?? staff?.module;
    final moduleKey = _prefKey(siteId, effectiveModule);
    final generalKey = _prefKey(siteId, null);

    if (staff != null && remember) {
      final jsonStr = jsonEncode(staff.toJson());
      await prefs.setString(moduleKey, jsonStr);
      // Also update general key for backwards-compatibility
      await prefs.setString(generalKey, jsonStr);
    } else {
      await prefs.remove(moduleKey);
      if (effectiveModule == null) {
        await prefs.remove(generalKey);
      }
    }
  }

  /// Attempts to restore the remembered staff member for this site and module,
  /// strictly verifying they are active and currently authorized for this module.
  Future<SiteStaffModel?> loadRememberedStaff(String siteId, {StaffModule? module}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      SiteStaffModel? staff;

      // Try module-specific key first
      if (module != null) {
        final raw = prefs.getString(_prefKey(siteId, module));
        if (raw != null) {
          final data = jsonDecode(raw);
          staff = SiteStaffModel.fromJson(data);
        }
      }

      // Fallback to general key
      if (staff == null) {
        final generalRaw = prefs.getString(_prefKey(siteId, null));
        if (generalRaw != null) {
          final data = jsonDecode(generalRaw);
          staff = SiteStaffModel.fromJson(data);
        }
      }

      final currentStaff = staff;
      if (currentStaff == null) return null;

      // Verify against live server / database permissions to ensure admin edits take immediate effect
      final r = _ref;
      SiteStaffModel verifiedStaff = currentStaff;
      if (r != null) {
        try {
          final service = r.read(siteStaffServiceProvider);
          final liveList = await service.getStaffForSite(siteId);
          final match = liveList.where((s) => s.id == currentStaff.id);
          if (match.isNotEmpty) {
            verifiedStaff = match.first;
          } else {
            // Staff member deleted or inactive on server
            await clearActiveStaff(siteId, module: module);
            return null;
          }
        } catch (_) {}
      }

      // Strict check: staff must be active and have the required module permission
      if (module != null && !verifiedStaff.hasModule(module)) {
        // Permission was revoked! Clear remembered staff for this module
        await clearActiveStaff(siteId, module: module);
        return null;
      }

      state = verifiedStaff;
      return verifiedStaff;
    } catch (_) {}
    return null;
  }

  /// Logs out / switches the staff member for this site
  Future<void> clearActiveStaff(String siteId, {StaffModule? module}) async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    if (module != null) {
      await prefs.remove(_prefKey(siteId, module));
    }
    await prefs.remove(_prefKey(siteId, null));
  }
}

final activeStaffProvider =
    StateNotifierProvider<ActiveStaffNotifier, SiteStaffModel?>((ref) {
  return ActiveStaffNotifier(ref);
});

/// Checks if a supervisor is allotted and active for a given site and module
final hasSupervisorForSiteModuleProvider =
    Provider.family<bool, ({String siteId, StaffModule module})>((ref, arg) {
  final staffState = ref.watch(siteStaffProvider(arg.siteId));
  return staffState.staffList
      .any((s) => s.isActive && s.isSupervisor && s.hasModule(arg.module));
});

/// Fetches all staff members across all sites for admin overview
final allStaffProvider = FutureProvider<List<SiteStaffModel>>((ref) async {
  final service = ref.read(siteStaffServiceProvider);
  return service.getAllStaff();
});

