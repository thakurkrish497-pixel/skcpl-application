import 'package:flutter/material.dart';

/// Shift policy for a site or head office
class SiteShiftPolicyModel {
  final String siteId; // 'global', 'office', or specific site UUID
  final String siteName;
  final String shiftStartTime; // e.g. "09:00"
  final String shiftEndTime; // e.g. "18:00"
  final String punchOutWindowEnd; // e.g. "19:00"
  final int graceMinutes; // e.g. 15 mins
  final int lateCutoffMinutes; // e.g. 40 mins
  final double? latitude;
  final double? longitude;
  final double allowedRadiusMeters; // e.g. 500 meters

  const SiteShiftPolicyModel({
    required this.siteId,
    required this.siteName,
    this.shiftStartTime = '09:00',
    this.shiftEndTime = '18:00',
    this.punchOutWindowEnd = '19:00',
    this.graceMinutes = 15,
    this.lateCutoffMinutes = 40,
    this.latitude,
    this.longitude,
    this.allowedRadiusMeters = 500.0,
  });

  /// Parse HH:mm to TimeOfDay
  TimeOfDay get startTimeOfDay {
    final parts = shiftStartTime.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
  }

  TimeOfDay get endTimeOfDay {
    final parts = shiftEndTime.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 18,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
  }

  factory SiteShiftPolicyModel.fromJson(Map<String, dynamic> json) {
    return SiteShiftPolicyModel(
      siteId: json['site_id'] as String? ?? 'global',
      siteName: json['site_name'] as String? ?? 'Company Default',
      shiftStartTime: json['shift_start_time'] as String? ?? '09:00',
      shiftEndTime: json['shift_end_time'] as String? ?? '18:00',
      punchOutWindowEnd: json['punch_out_window_end'] as String? ?? '19:00',
      graceMinutes: (json['grace_minutes'] as num?)?.toInt() ?? 15,
      lateCutoffMinutes: (json['late_cutoff_minutes'] as num?)?.toInt() ?? 40,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      allowedRadiusMeters: (json['allowed_radius_meters'] as num?)?.toDouble() ?? 500.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'site_id': siteId,
      'site_name': siteName,
      'shift_start_time': shiftStartTime,
      'shift_end_time': shiftEndTime,
      'punch_out_window_end': punchOutWindowEnd,
      'grace_minutes': graceMinutes,
      'late_cutoff_minutes': lateCutoffMinutes,
      'latitude': latitude,
      'longitude': longitude,
      'allowed_radius_meters': allowedRadiusMeters,
    };
  }

  SiteShiftPolicyModel copyWith({
    String? siteId,
    String? siteName,
    String? shiftStartTime,
    String? shiftEndTime,
    String? punchOutWindowEnd,
    int? graceMinutes,
    int? lateCutoffMinutes,
    double? latitude,
    double? longitude,
    double? allowedRadiusMeters,
  }) {
    return SiteShiftPolicyModel(
      siteId: siteId ?? this.siteId,
      siteName: siteName ?? this.siteName,
      shiftStartTime: shiftStartTime ?? this.shiftStartTime,
      shiftEndTime: shiftEndTime ?? this.shiftEndTime,
      punchOutWindowEnd: punchOutWindowEnd ?? this.punchOutWindowEnd,
      graceMinutes: graceMinutes ?? this.graceMinutes,
      lateCutoffMinutes: lateCutoffMinutes ?? this.lateCutoffMinutes,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      allowedRadiusMeters: allowedRadiusMeters ?? this.allowedRadiusMeters,
    );
  }
}

/// Status of an attendance record
enum AttendanceStatus {
  presentOnTime,
  presentLate,
  absentLateLockout,
  regularizationPending,
  regularizedPresent,
  regularizedHalfDay,
  rejected,
  absent;

  String get displayName {
    switch (this) {
      case AttendanceStatus.presentOnTime:
        return 'Present (On-Time)';
      case AttendanceStatus.presentLate:
        return 'Present (Late)';
      case AttendanceStatus.absentLateLockout:
        return 'Absent (>40m Late)';
      case AttendanceStatus.regularizationPending:
        return 'Late Request Pending';
      case AttendanceStatus.regularizedPresent:
        return 'Regularized (Present)';
      case AttendanceStatus.regularizedHalfDay:
        return 'Regularized (Half Day)';
      case AttendanceStatus.rejected:
        return 'Request Rejected';
      case AttendanceStatus.absent:
        return 'Absent';
    }
  }

  static AttendanceStatus fromString(String? value) {
    if (value == null) return AttendanceStatus.absent;
    final clean = value.toLowerCase().trim();
    if (clean == 'presentontime' || clean == 'present_on_time' || clean == 'present') {
      return AttendanceStatus.presentOnTime;
    }
    if (clean == 'presentlate' || clean == 'present_late' || clean == 'late') {
      return AttendanceStatus.presentLate;
    }
    if (clean == 'absentlatelockout' || clean == 'late_lockout') {
      return AttendanceStatus.absentLateLockout;
    }
    if (clean == 'regularizationpending' || clean == 'pending') {
      return AttendanceStatus.regularizationPending;
    }
    if (clean == 'regularizedpresent' || clean == 'regularized') {
      return AttendanceStatus.regularizedPresent;
    }
    if (clean == 'regularizedhalfday' || clean == 'half_day') {
      return AttendanceStatus.regularizedHalfDay;
    }
    if (clean == 'rejected') return AttendanceStatus.rejected;
    return AttendanceStatus.absent;
  }
}

/// Attendance record for a specific employee on a given date
class AttendanceRecordModel {
  final String id;
  final String siteId;
  final String siteName;
  final String staffId;
  final String staffName;
  final String staffRole;
  final DateTime date;
  final DateTime? punchInTime;
  final DateTime? punchOutTime;
  final double? punchInLatitude;
  final double? punchInLongitude;
  final String? punchInAddress;
  final double? punchOutLatitude;
  final double? punchOutLongitude;
  final AttendanceStatus status;
  final int lateMinutes;
  final bool isWithinSite;
  final double? distanceMeters;
  final String? regularizationReason;
  final String? adminDecisionNote;
  final String? reviewedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AttendanceRecordModel({
    required this.id,
    required this.siteId,
    required this.siteName,
    required this.staffId,
    required this.staffName,
    required this.staffRole,
    required this.date,
    this.punchInTime,
    this.punchOutTime,
    this.punchInLatitude,
    this.punchInLongitude,
    this.punchInAddress,
    this.punchOutLatitude,
    this.punchOutLongitude,
    this.status = AttendanceStatus.absent,
    this.lateMinutes = 0,
    this.isWithinSite = true,
    this.distanceMeters,
    this.regularizationReason,
    this.adminDecisionNote,
    this.reviewedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPunchedIn => punchInTime != null;
  bool get isPunchedOut => punchOutTime != null;
  bool get isPresent =>
      status == AttendanceStatus.presentOnTime ||
      status == AttendanceStatus.presentLate ||
      status == AttendanceStatus.regularizedPresent;
  bool get isHalfDay => status == AttendanceStatus.regularizedHalfDay;
  bool get isPendingAdminReview => status == AttendanceStatus.regularizationPending;
  bool get isAbsent =>
      status == AttendanceStatus.absent ||
      status == AttendanceStatus.absentLateLockout ||
      status == AttendanceStatus.rejected;
  bool get isUnmarkedAbsent =>
      status == AttendanceStatus.absent && punchInTime == null;

  String get displayStatusName {
    if (isUnmarkedAbsent) return 'Absent (Not Marked)';
    return status.displayName;
  }

  Duration? get totalWorkingDuration {
    if (punchInTime == null) return null;
    final end = punchOutTime ?? DateTime.now();
    return end.difference(punchInTime!);
  }

  double? get totalHoursWorked {
    final duration = totalWorkingDuration;
    if (duration == null) return null;
    return duration.inMinutes / 60.0;
  }

  factory AttendanceRecordModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val is DateTime) return val;
      return DateTime.tryParse(val?.toString() ?? '') ?? DateTime.now();
    }

    return AttendanceRecordModel(
      id: json['id'] as String? ?? '',
      siteId: json['site_id'] as String? ?? '',
      siteName: json['site_name'] as String? ?? '',
      staffId: json['staff_id'] as String? ?? '',
      staffName: json['staff_name'] as String? ?? '',
      staffRole: json['staff_role'] as String? ?? 'Worker',
      date: parseDate(json['date']),
      punchInTime: json['punch_in_time'] != null ? parseDate(json['punch_in_time']) : null,
      punchOutTime: json['punch_out_time'] != null ? parseDate(json['punch_out_time']) : null,
      punchInLatitude: (json['punch_in_latitude'] as num?)?.toDouble(),
      punchInLongitude: (json['punch_in_longitude'] as num?)?.toDouble(),
      punchInAddress: json['punch_in_address'] as String?,
      punchOutLatitude: (json['punch_out_latitude'] as num?)?.toDouble(),
      punchOutLongitude: (json['punch_out_longitude'] as num?)?.toDouble(),
      status: AttendanceStatus.fromString(json['status'] as String?),
      lateMinutes: (json['late_minutes'] as num?)?.toInt() ?? 0,
      isWithinSite: json['is_within_site'] as bool? ?? true,
      distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
      regularizationReason: json['regularization_reason'] as String?,
      adminDecisionNote: json['admin_decision_note'] as String?,
      reviewedBy: json['reviewed_by'] as String?,
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'site_id': siteId,
      'site_name': siteName,
      'staff_id': staffId,
      'staff_name': staffName,
      'staff_role': staffRole,
      'date': date.toIso8601String().split('T').first,
      'punch_in_time': punchInTime?.toIso8601String(),
      'punch_out_time': punchOutTime?.toIso8601String(),
      'punch_in_latitude': punchInLatitude,
      'punch_in_longitude': punchInLongitude,
      'punch_in_address': punchInAddress,
      'punch_out_latitude': punchOutLatitude,
      'punch_out_longitude': punchOutLongitude,
      'status': status.name,
      'late_minutes': lateMinutes,
      'is_within_site': isWithinSite,
      'distance_meters': distanceMeters,
      'regularization_reason': regularizationReason,
      'admin_decision_note': adminDecisionNote,
      'reviewed_by': reviewedBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  AttendanceRecordModel copyWith({
    String? id,
    String? siteId,
    String? siteName,
    String? staffId,
    String? staffName,
    String? staffRole,
    DateTime? date,
    DateTime? punchInTime,
    DateTime? punchOutTime,
    double? punchInLatitude,
    double? punchInLongitude,
    String? punchInAddress,
    double? punchOutLatitude,
    double? punchOutLongitude,
    AttendanceStatus? status,
    int? lateMinutes,
    bool? isWithinSite,
    double? distanceMeters,
    String? regularizationReason,
    String? adminDecisionNote,
    String? reviewedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AttendanceRecordModel(
      id: id ?? this.id,
      siteId: siteId ?? this.siteId,
      siteName: siteName ?? this.siteName,
      staffId: staffId ?? this.staffId,
      staffName: staffName ?? this.staffName,
      staffRole: staffRole ?? this.staffRole,
      date: date ?? this.date,
      punchInTime: punchInTime ?? this.punchInTime,
      punchOutTime: punchOutTime ?? this.punchOutTime,
      punchInLatitude: punchInLatitude ?? this.punchInLatitude,
      punchInLongitude: punchInLongitude ?? this.punchInLongitude,
      punchInAddress: punchInAddress ?? this.punchInAddress,
      punchOutLatitude: punchOutLatitude ?? this.punchOutLatitude,
      punchOutLongitude: punchOutLongitude ?? this.punchOutLongitude,
      status: status ?? this.status,
      lateMinutes: lateMinutes ?? this.lateMinutes,
      isWithinSite: isWithinSite ?? this.isWithinSite,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      regularizationReason: regularizationReason ?? this.regularizationReason,
      adminDecisionNote: adminDecisionNote ?? this.adminDecisionNote,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Live location ping sent during work shift
class StaffLiveLocationModel {
  final String staffId;
  final String staffName;
  final String staffRole;
  final String siteId;
  final String siteName;
  final double latitude;
  final double longitude;
  final bool isWithinSite;
  final double distanceMeters;
  final DateTime timestamp;
  final double? accuracyMeters;
  final String? address;

  const StaffLiveLocationModel({
    required this.staffId,
    required this.staffName,
    required this.staffRole,
    required this.siteId,
    required this.siteName,
    required this.latitude,
    required this.longitude,
    required this.isWithinSite,
    required this.distanceMeters,
    required this.timestamp,
    this.accuracyMeters,
    this.address,
  });

  StaffLiveLocationModel copyWith({
    String? staffId,
    String? staffName,
    String? staffRole,
    String? siteId,
    String? siteName,
    double? latitude,
    double? longitude,
    bool? isWithinSite,
    double? distanceMeters,
    DateTime? timestamp,
    double? accuracyMeters,
    String? address,
  }) {
    return StaffLiveLocationModel(
      staffId: staffId ?? this.staffId,
      staffName: staffName ?? this.staffName,
      staffRole: staffRole ?? this.staffRole,
      siteId: siteId ?? this.siteId,
      siteName: siteName ?? this.siteName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isWithinSite: isWithinSite ?? this.isWithinSite,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      timestamp: timestamp ?? this.timestamp,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      address: address ?? this.address,
    );
  }

  factory StaffLiveLocationModel.fromJson(Map<String, dynamic> json) {
    return StaffLiveLocationModel(
      staffId: json['staff_id'] as String? ?? '',
      staffName: json['staff_name'] as String? ?? '',
      staffRole: json['staff_role'] as String? ?? 'Staff',
      siteId: json['site_id'] as String? ?? '',
      siteName: json['site_name'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      isWithinSite: json['is_within_site'] as bool? ?? true,
      distanceMeters: (json['distance_meters'] as num?)?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      accuracyMeters: (json['accuracy_meters'] as num?)?.toDouble(),
      address: json['address'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'staff_id': staffId,
      'staff_name': staffName,
      'staff_role': staffRole,
      'site_id': siteId,
      'site_name': siteName,
      'latitude': latitude,
      'longitude': longitude,
      'is_within_site': isWithinSite,
      'distance_meters': distanceMeters,
      'timestamp': timestamp.toIso8601String(),
      if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
      if (address != null) 'address': address,
    };
  }
}
