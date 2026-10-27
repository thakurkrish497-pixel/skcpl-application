import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/attendance_model.dart';
import '../core/constants/supabase_constants.dart';
import 'location_service.dart';

/// Service managing attendance, shift policies, and live location tracking
/// with dual-mode resilient persistence.
class AttendanceService {
  final SupabaseClient _client;
  static const _uuid = Uuid();

  AttendanceService([SupabaseClient? client])
      : _client = client ??
            SupabaseClient(
              SupabaseConstants.supabaseUrl,
              SupabaseConstants.supabaseServiceRoleKey,
            );

  // ─────────────────────────────────────────────────────────────
  // 1. Shift Policies (Default + Per-Site / Office Overrides)
  // ─────────────────────────────────────────────────────────────

  /// Fetch shift policy for a site (falls back to global default)
  Future<SiteShiftPolicyModel> getShiftPolicy(String siteId) async {
    try {
      // 1. Check site specific policy
      final res = await _client
          .from('site_shift_policies')
          .select()
          .eq('site_id', siteId)
          .maybeSingle();

      if (res != null) {
        return SiteShiftPolicyModel.fromJson(res);
      }

      // 2. Check global default policy
      final global = await _client
          .from('site_shift_policies')
          .select()
          .eq('site_id', 'global')
          .maybeSingle();

      if (global != null) {
        return SiteShiftPolicyModel.fromJson(global);
      }
    } catch (_) {
      // Fallback via tasks table
      final fallback = await _getPolicyFallback(siteId);
      if (fallback != null) return fallback;
    }

    // Default policy
    final isOffice = siteId == 'office' || siteId == _indoreOfficeSiteId;
    return SiteShiftPolicyModel(
      siteId: siteId,
      siteName: isOffice ? 'Indore Head Office' : 'Default Policy',
      shiftStartTime: '09:00',
      shiftEndTime: '18:00',
      punchOutWindowEnd: '19:00',
      graceMinutes: 15,
      lateCutoffMinutes: 40,
      allowedRadiusMeters: 500,
      latitude: isOffice ? 22.7196 : null,
      longitude: isOffice ? 75.8577 : null,
    );
  }

  /// Save or override shift policy for a site or global company default
  Future<SiteShiftPolicyModel> saveShiftPolicy(SiteShiftPolicyModel policy) async {
    try {
      final payload = policy.toJson();
      final res = await _client
          .from('site_shift_policies')
          .upsert(payload, onConflict: 'site_id')
          .select()
          .single();
      return SiteShiftPolicyModel.fromJson(res);
    } catch (_) {
      return _savePolicyFallback(policy);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 2. Attendance Records (Punch In / Punch Out / Regularize)
  // ─────────────────────────────────────────────────────────────

  /// Fetch today's attendance records for a site (or all sites if siteId == 'all')
  Future<List<AttendanceRecordModel>> getTodayAttendance(
    String siteId,
    DateTime date,
  ) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    List<AttendanceRecordModel> list;
    try {
      var query = _client.from('attendance').select().eq('date', dateStr);
      if (siteId != 'all') {
        query = query.eq('site_id', siteId);
      }
      final data = await query.order('punch_in_time', ascending: true);

      list = (data as List)
          .map((json) => AttendanceRecordModel.fromJson(json))
          .toList();
    } catch (_) {
      list = await _getAttendanceFallback(siteId, dateStr);
    }
    return await _hydrateAttendance(list);
  }

  /// Fetch attendance records for a date range (for monthly export and reports)
  Future<List<AttendanceRecordModel>> getAttendanceRange({
    String? siteId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final startStr = DateFormat('yyyy-MM-dd').format(startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(endDate);
    List<AttendanceRecordModel> list;
    try {
      var query = _client
          .from('attendance')
          .select()
          .gte('date', startStr)
          .lte('date', endStr);

      if (siteId != null && siteId != 'all') {
        query = query.eq('site_id', siteId);
      }

      final data = await query
          .order('date', ascending: true)
          .order('punch_in_time', ascending: true);

      list = (data as List)
          .map((json) => AttendanceRecordModel.fromJson(json))
          .toList();
    } catch (_) {
      list = await _getAttendanceRangeFallback(
        siteId: siteId,
        startDate: startDate,
        endDate: endDate,
      );
    }
    return await _hydrateAttendance(list);
  }

  /// Fetch all pending attendance regularization requests for Admin
  Future<List<AttendanceRecordModel>> getPendingRegularizationRequests() async {
    List<AttendanceRecordModel> list;
    try {
      final data = await _client
          .from('attendance')
          .select()
          .eq('status', AttendanceStatus.regularizationPending.name)
          .order('date', ascending: false);

      list = (data as List)
          .map((json) => AttendanceRecordModel.fromJson(json))
          .toList();
    } catch (_) {
      list = await _getPendingRequestsFallback();
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return await _hydrateAttendance(list);
  }

  /// Record Punch-In for staff member
  Future<AttendanceRecordModel> punchIn({
    required String siteId,
    required String siteName,
    required String staffId,
    required String staffName,
    required String staffRole,
    required DateTime date,
    required DateTime punchTime,
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    final policy = await getShiftPolicy(siteId);

    // Calculate late minutes based on policy shiftStartTime (HH:mm)
    final startParts = policy.shiftStartTime.split(':');
    final shiftStartHour = int.tryParse(startParts[0]) ?? 9;
    final shiftStartMinute = startParts.length > 1 ? (int.tryParse(startParts[1]) ?? 0) : 0;

    final scheduledStartTime = DateTime(
      punchTime.year,
      punchTime.month,
      punchTime.day,
      shiftStartHour,
      shiftStartMinute,
    );

    final diffMinutes = punchTime.difference(scheduledStartTime).inMinutes;

    AttendanceStatus status;
    int lateMinutes = 0;

    if (diffMinutes <= policy.graceMinutes) {
      status = AttendanceStatus.presentOnTime;
    } else if (diffMinutes <= policy.lateCutoffMinutes) {
      status = AttendanceStatus.presentLate;
      lateMinutes = diffMinutes;
    } else {
      // More than 40 minutes late -> Automatically marked Absent with lockout
      status = AttendanceStatus.absentLateLockout;
      lateMinutes = diffMinutes;
    }

    // Check geofence if coordinates are provided
    bool isWithinSite = true;
    double? distanceMeters;
    if (latitude != null && longitude != null && policy.latitude != null && policy.longitude != null) {
      distanceMeters = LocationService.calculateDistanceMeters(
        userLat: latitude,
        userLng: longitude,
        siteLat: policy.latitude!,
        siteLng: policy.longitude!,
      );
      isWithinSite = distanceMeters <= policy.allowedRadiusMeters;
    }

    final record = AttendanceRecordModel(
      id: _uuid.v4(),
      siteId: siteId,
      siteName: siteName,
      staffId: staffId,
      staffName: staffName,
      staffRole: staffRole,
      date: date,
      punchInTime: punchTime,
      punchInLatitude: latitude,
      punchInLongitude: longitude,
      punchInAddress: address,
      status: status,
      lateMinutes: lateMinutes > 0 ? lateMinutes : 0,
      isWithinSite: isWithinSite,
      distanceMeters: distanceMeters,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      final res = await _client
          .from('attendance')
          .insert(record.toJson())
          .select()
          .single();
      return AttendanceRecordModel.fromJson(res);
    } catch (_) {
      return _saveAttendanceFallback(record);
    }
  }

  /// Record Punch-Out for staff member
  Future<AttendanceRecordModel> punchOut({
    required String attendanceId,
    required DateTime punchOutTime,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final res = await _client
          .from('attendance')
          .update({
            'punch_out_time': punchOutTime.toIso8601String(),
            'punch_out_latitude': latitude,
            'punch_out_longitude': longitude,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', attendanceId)
          .select()
          .single();

      return AttendanceRecordModel.fromJson(res);
    } catch (_) {
      return _punchOutFallback(attendanceId, punchOutTime, latitude, longitude);
    }
  }

  /// Staff submits late regularization request with written reason
  Future<AttendanceRecordModel> submitRegularizationRequest({
    required String attendanceId,
    required String reason,
  }) async {
    try {
      final res = await _client
          .from('attendance')
          .update({
            'status': AttendanceStatus.regularizationPending.name,
            'regularization_reason': reason,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', attendanceId)
          .select()
          .single();

      return AttendanceRecordModel.fromJson(res);
    } catch (_) {
      return _updateStatusFallback(
        attendanceId,
        AttendanceStatus.regularizationPending,
        reason: reason,
      );
    }
  }

  /// Admin approves or rejects attendance regularization request
  Future<AttendanceRecordModel> reviewRegularizationRequest({
    required String attendanceId,
    required bool approve,
    bool halfDay = false,
    String? note,
    required String reviewedBy,
  }) async {
    final newStatus = !approve
        ? AttendanceStatus.rejected
        : (halfDay
            ? AttendanceStatus.regularizedHalfDay
            : AttendanceStatus.regularizedPresent);

    final validReviewerId = (reviewedBy != null &&
            RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
                .hasMatch(reviewedBy.trim()))
        ? reviewedBy.trim()
        : _defaultAdminUserId;

    try {
      final res = await _client
          .from('attendance')
          .update({
            'status': newStatus.name,
            'admin_decision_note': note,
            'reviewed_by': validReviewerId,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', attendanceId)
          .select()
          .single();

      return AttendanceRecordModel.fromJson(res);
    } catch (_) {
      return _updateStatusFallback(
        attendanceId,
        newStatus,
        adminNote: note,
        reviewedBy: reviewedBy,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 3. Live Location Tracking
  // ─────────────────────────────────────────────────────────────

  /// Transmit live location ping
  Future<void> updateLiveLocation(StaffLiveLocationModel ping) async {
    try {
      await _client.from('staff_live_locations').upsert(
            ping.toJson(),
            onConflict: 'staff_id',
          );
    } catch (_) {
      _saveLiveLocFallback(ping);
    }
  }

  /// Fetch all active live staff locations
  Future<List<StaffLiveLocationModel>> getLiveStaffLocations([String? siteId]) async {
    List<StaffLiveLocationModel> list;
    try {
      var query = _client.from('staff_live_locations').select();
      if (siteId != null && siteId != 'all') {
        query = query.eq('site_id', siteId);
      }
      final data = await query.order('timestamp', ascending: false);
      list = (data as List)
          .map((json) => StaffLiveLocationModel.fromJson(json))
          .toList();
    } catch (_) {
      list = await _getLiveLocFallback(siteId);
    }
    return await _hydrateLiveLocations(list);
  }

  // ─────────────────────────────────────────────────────────────
  // Real-Time Staff Metadata Hydration (prevents name desync)
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, Map<String, String>>> _getStaffInfoMap() async {
    final map = <String, Map<String, String>>{};
    try {
      final rows = await _client.from('site_staff').select('id, name, role');
      for (final r in (rows as List)) {
        if (r['id'] != null && r['name'] != null) {
          map[r['id'] as String] = {
            'name': r['name'] as String,
            'role': r['role']?.toString() ?? '',
          };
        }
      }
    } catch (_) {}

    try {
      final rows = await _client
          .from('tasks')
          .select('description')
          .like('title', 'STAFF:%');
      for (final r in (rows as List)) {
        final desc = r['description'] as String?;
        if (desc != null && desc.startsWith('{')) {
          final parsed = jsonDecode(desc);
          if (parsed['id'] != null && parsed['name'] != null) {
            map[parsed['id'] as String] = {
              'name': parsed['name'] as String,
              'role': parsed['role']?.toString() ?? '',
            };
          }
        }
      }
    } catch (_) {}
    return map;
  }

  Future<List<StaffLiveLocationModel>> _hydrateLiveLocations(
    List<StaffLiveLocationModel> list,
  ) async {
    try {
      final staffMap = await _getStaffInfoMap();
      if (staffMap.isEmpty) return list;
      return list.map((loc) {
        final info = staffMap[loc.staffId];
        if (info != null && info['name'] != null && info['name']!.isNotEmpty) {
          return loc.copyWith(
            staffName: info['name'],
            staffRole: (info['role'] != null && info['role']!.isNotEmpty)
                ? info['role']
                : loc.staffRole,
          );
        }
        return loc;
      }).toList();
    } catch (_) {
      return list;
    }
  }

  Future<List<AttendanceRecordModel>> _hydrateAttendance(
    List<AttendanceRecordModel> list,
  ) async {
    try {
      final staffMap = await _getStaffInfoMap();
      if (staffMap.isEmpty) return list;
      return list.map((rec) {
        final info = staffMap[rec.staffId];
        if (info != null && info['name'] != null && info['name']!.isNotEmpty) {
          return rec.copyWith(
            staffName: info['name'],
            staffRole: (info['role'] != null && info['role']!.isNotEmpty)
                ? info['role']
                : rec.staffRole,
          );
        }
        return rec;
      }).toList();
    } catch (_) {
      return list;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Resilient Fallback Storage (Tasks Table)
  // ─────────────────────────────────────────────────────────────

  static const _defaultAdminUserId = '84b7c957-e145-446a-9a31-051f2cb9b3af';
  static const _indoreOfficeSiteId = 'bdb1478e-4fa9-4873-9804-864b0952fa4d';

  String _resolveSiteId(String rawSiteId) {
    if (rawSiteId == 'office' || rawSiteId == 'global') {
      return _indoreOfficeSiteId;
    }
    return rawSiteId;
  }

  Future<SiteShiftPolicyModel?> _getPolicyFallback(String siteId) async {
    try {
      final tag = 'SHIFT_POLICY:$siteId';
      final rows = await _client.from('tasks').select().eq('title', tag).limit(1);
      if ((rows as List).isNotEmpty) {
        final desc = rows.first['description'] as String?;
        if (desc != null) return SiteShiftPolicyModel.fromJson(jsonDecode(desc));
      }
    } catch (_) {}
    return null;
  }

  Future<SiteShiftPolicyModel> _savePolicyFallback(SiteShiftPolicyModel policy) async {
    final tag = 'SHIFT_POLICY:${policy.siteId}';
    final payload = jsonEncode(policy.toJson());
    try {
      final validSiteId = _resolveSiteId(policy.siteId);
      final existing = await _client.from('tasks').select('id').eq('title', tag).limit(1);
      if ((existing as List).isNotEmpty) {
        await _client.from('tasks').update({'description': payload}).eq('id', existing.first['id']);
      } else {
        await _client.from('tasks').insert({
          'site_id': validSiteId,
          'created_by': _defaultAdminUserId,
          'title': tag,
          'description': payload,
          'status': 'completed',
          'priority': 'low',
        });
      }
    } catch (_) {}
    return policy;
  }

  Future<List<AttendanceRecordModel>> _getAttendanceFallback(String siteId, String dateStr) async {
    try {
      final tagPrefix = siteId == 'all' ? 'ATTENDANCE:$dateStr:' : 'ATTENDANCE:$dateStr:$siteId:';
      final rows = await _client.from('tasks').select().like('title', '$tagPrefix%');
      final list = <AttendanceRecordModel>[];
      for (final r in (rows as List)) {
        final desc = r['description'] as String?;
        if (desc != null && desc.startsWith('{')) {
          try {
            list.add(AttendanceRecordModel.fromJson(jsonDecode(desc)));
          } catch (_) {}
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<List<AttendanceRecordModel>> _getPendingRequestsFallback() async {
    try {
      final rows = await _client.from('tasks').select().like('title', 'ATTENDANCE:%');
      final list = <AttendanceRecordModel>[];
      for (final r in (rows as List)) {
        final desc = r['description'] as String?;
        if (desc != null && desc.startsWith('{')) {
          try {
            final rec = AttendanceRecordModel.fromJson(jsonDecode(desc));
            if (rec.status == AttendanceStatus.regularizationPending) {
              list.add(rec);
            }
          } catch (_) {}
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<AttendanceRecordModel> _saveAttendanceFallback(AttendanceRecordModel record) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(record.date);
    final tag = 'ATTENDANCE:$dateStr:${record.siteId}:${record.staffId}';
    final payload = jsonEncode(record.toJson());
    try {
      final validSiteId = _resolveSiteId(record.siteId);
      final existing = await _client.from('tasks').select('id').eq('title', tag).limit(1);
      if ((existing as List).isNotEmpty) {
        await _client.from('tasks').update({'description': payload}).eq('id', existing.first['id']);
      } else {
        await _client.from('tasks').insert({
          'site_id': validSiteId,
          'created_by': _defaultAdminUserId,
          'title': tag,
          'description': payload,
          'status': 'completed',
          'priority': 'low',
        });
      }
    } catch (_) {}
    return record;
  }

  Future<AttendanceRecordModel> _punchOutFallback(
    String attendanceId,
    DateTime punchOutTime,
    double? latitude,
    double? longitude,
  ) async {
    final rows = await _client.from('tasks').select().like('title', 'ATTENDANCE:%');
    for (final r in (rows as List)) {
      final desc = r['description'] as String?;
      if (desc != null && desc.startsWith('{')) {
        try {
          final rec = AttendanceRecordModel.fromJson(jsonDecode(desc));
          if (rec.id == attendanceId) {
            final updated = rec.copyWith(
              punchOutTime: punchOutTime,
              punchOutLatitude: latitude,
              punchOutLongitude: longitude,
              updatedAt: DateTime.now(),
            );
            await _client.from('tasks').update({
              'description': jsonEncode(updated.toJson()),
            }).eq('id', r['id']);
            return updated;
          }
        } catch (_) {}
      }
    }
    throw Exception('Attendance record not found');
  }

  Future<AttendanceRecordModel> _updateStatusFallback(
    String attendanceId,
    AttendanceStatus newStatus, {
    String? reason,
    String? adminNote,
    String? reviewedBy,
  }) async {
    final rows = await _client.from('tasks').select().like('title', 'ATTENDANCE:%');
    for (final r in (rows as List)) {
      final desc = r['description'] as String?;
      if (desc != null && desc.startsWith('{')) {
        try {
          final rec = AttendanceRecordModel.fromJson(jsonDecode(desc));
          if (rec.id == attendanceId) {
            final updated = rec.copyWith(
              status: newStatus,
              regularizationReason: reason ?? rec.regularizationReason,
              adminDecisionNote: adminNote ?? rec.adminDecisionNote,
              reviewedBy: reviewedBy ?? rec.reviewedBy,
              updatedAt: DateTime.now(),
            );
            await _client.from('tasks').update({
              'description': jsonEncode(updated.toJson()),
            }).eq('id', r['id']);
            return updated;
          }
        } catch (_) {}
      }
    }
    throw Exception('Attendance record not found');
  }

  Future<void> _saveLiveLocFallback(StaffLiveLocationModel ping) async {
    final tag = 'LIVELOC:${ping.siteId}:${ping.staffId}';
    final payload = jsonEncode(ping.toJson());
    try {
      final validSiteId = _resolveSiteId(ping.siteId);
      final existing = await _client.from('tasks').select('id').eq('title', tag).limit(1);
      if ((existing as List).isNotEmpty) {
        await _client.from('tasks').update({'description': payload}).eq('id', existing.first['id']);
      } else {
        await _client.from('tasks').insert({
          'site_id': validSiteId,
          'created_by': _defaultAdminUserId,
          'title': tag,
          'description': payload,
          'status': 'completed',
          'priority': 'low',
        });
      }
    } catch (_) {}
  }

  Future<List<StaffLiveLocationModel>> _getLiveLocFallback(String? siteId) async {
    try {
      final tagPrefix = siteId != null && siteId != 'all' ? 'LIVELOC:$siteId:' : 'LIVELOC:';
      final rows = await _client.from('tasks').select().like('title', '$tagPrefix%');
      final list = <StaffLiveLocationModel>[];
      for (final r in (rows as List)) {
        final desc = r['description'] as String?;
        if (desc != null && desc.startsWith('{')) {
          try {
            list.add(StaffLiveLocationModel.fromJson(jsonDecode(desc)));
          } catch (_) {}
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<List<AttendanceRecordModel>> _getAttendanceRangeFallback({
    String? siteId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final rows = await _client.from('tasks').select().like('title', 'ATTENDANCE:%');
      final list = <AttendanceRecordModel>[];
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

      for (final r in (rows as List)) {
        final desc = r['description'] as String?;
        if (desc != null && desc.startsWith('{')) {
          try {
            final rec = AttendanceRecordModel.fromJson(jsonDecode(desc));
            if (siteId != null && siteId != 'all' && rec.siteId != siteId) {
              continue;
            }
            if (rec.date.isAfter(start.subtract(const Duration(seconds: 1))) &&
                rec.date.isBefore(end.add(const Duration(seconds: 1)))) {
              list.add(rec);
            }
          } catch (_) {}
        }
      }
      list.sort((a, b) => a.date.compareTo(b.date));
      return list;
    } catch (_) {
      return [];
    }
  }
}
