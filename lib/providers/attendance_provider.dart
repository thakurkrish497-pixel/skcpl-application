import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/attendance_model.dart';
import '../services/attendance_service.dart';

final attendanceServiceProvider = Provider<AttendanceService>((ref) {
  return AttendanceService();
});

/// Fetch shift policy for a specific site or company default
final shiftPolicyForSiteProvider =
    FutureProvider.family<SiteShiftPolicyModel, String>((ref, siteId) async {
  final service = ref.read(attendanceServiceProvider);
  return service.getShiftPolicy(siteId);
});

/// Fetch today's attendance for a given site (or 'all' for company-wide)
final todayAttendanceForSiteProvider = FutureProvider.family<
    List<AttendanceRecordModel>,
    String>((ref, siteId) async {
  final service = ref.read(attendanceServiceProvider);
  return service.getTodayAttendance(siteId, DateTime.now());
});

/// Fetch attendance for an arbitrary date and site (or 'all' for company-wide)
final attendanceForDateAndSiteProvider = FutureProvider.family<
    List<AttendanceRecordModel>,
    ({String siteId, DateTime date})>((ref, arg) async {
  final service = ref.read(attendanceServiceProvider);
  return service.getTodayAttendance(arg.siteId, arg.date);
});

/// Fetch monthly attendance for dot indicators and calendar summaries
final monthlyAttendanceProvider = FutureProvider.family<
    List<AttendanceRecordModel>,
    ({String siteId, int year, int month})>((ref, arg) async {
  final service = ref.read(attendanceServiceProvider);
  final start = DateTime(arg.year, arg.month, 1);
  final end = DateTime(arg.year, arg.month + 1, 0, 23, 59, 59);
  return service.getAttendanceRange(
    siteId: arg.siteId == 'all' ? null : arg.siteId,
    startDate: start,
    endDate: end,
  );
});

/// Fetch all pending regularization requests (latest on top)
final pendingRegularizationRequestsProvider =
    FutureProvider<List<AttendanceRecordModel>>((ref) async {
  final service = ref.read(attendanceServiceProvider);
  final list = await service.getPendingRegularizationRequests();
  return list..sort((a, b) => b.createdAt.compareTo(a.createdAt));
});

/// Fetch live staff locations (all or filtered by site)
final liveStaffLocationsProvider = FutureProvider.family<
    List<StaffLiveLocationModel>, String?>((ref, siteId) async {
  final service = ref.read(attendanceServiceProvider);
  return service.getLiveStaffLocations(siteId);
});

/// State of current punch session for the staff member on this device
class StaffPunchState {
  final AttendanceRecordModel? todayRecord;
  final bool isLoading;
  final String? error;

  const StaffPunchState({
    this.todayRecord,
    this.isLoading = false,
    this.error,
  });

  StaffPunchState copyWith({
    AttendanceRecordModel? todayRecord,
    bool? isLoading,
    String? error,
  }) {
    return StaffPunchState(
      todayRecord: todayRecord ?? this.todayRecord,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class StaffPunchNotifier extends StateNotifier<StaffPunchState> {
  final AttendanceService _service;
  final Ref _ref;

  StaffPunchNotifier(this._service, this._ref) : super(const StaffPunchState());

  /// Load today's punch record for this staff member
  Future<void> loadTodayRecord({
    required String siteId,
    required String staffId,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final records = await _service.getTodayAttendance(siteId, DateTime.now());
      final myRecord = records.where((r) => r.staffId == staffId).firstOrNull;
      state = state.copyWith(todayRecord: myRecord, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// Punch in
  Future<AttendanceRecordModel> punchIn({
    required String siteId,
    required String siteName,
    required String staffId,
    required String staffName,
    required String staffRole,
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final record = await _service.punchIn(
        siteId: siteId,
        siteName: siteName,
        staffId: staffId,
        staffName: staffName,
        staffRole: staffRole,
        date: DateTime.now(),
        punchTime: DateTime.now(),
        latitude: latitude,
        longitude: longitude,
        address: address,
      );

      state = state.copyWith(todayRecord: record, isLoading: false);

      // Invalidate relevant providers
      _ref.invalidate(todayAttendanceForSiteProvider);
      _ref.invalidate(pendingRegularizationRequestsProvider);

      return record;
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
      rethrow;
    }
  }

  /// Punch out
  Future<AttendanceRecordModel> punchOut({
    required String attendanceId,
    double? latitude,
    double? longitude,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final record = await _service.punchOut(
        attendanceId: attendanceId,
        punchOutTime: DateTime.now(),
        latitude: latitude,
        longitude: longitude,
      );

      state = state.copyWith(todayRecord: record, isLoading: false);

      _ref.invalidate(todayAttendanceForSiteProvider);

      return record;
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
      rethrow;
    }
  }

  /// Submit late regularization request
  Future<AttendanceRecordModel> submitRegularizationRequest({
    required String attendanceId,
    required String reason,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final record = await _service.submitRegularizationRequest(
        attendanceId: attendanceId,
        reason: reason,
      );

      state = state.copyWith(todayRecord: record, isLoading: false);

      _ref.invalidate(todayAttendanceForSiteProvider);
      _ref.invalidate(pendingRegularizationRequestsProvider);

      return record;
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
      rethrow;
    }
  }
}

final staffPunchProvider =
    StateNotifierProvider<StaffPunchNotifier, StaffPunchState>((ref) {
  return StaffPunchNotifier(ref.read(attendanceServiceProvider), ref);
});
