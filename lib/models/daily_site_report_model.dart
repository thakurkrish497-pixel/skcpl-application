import 'dart:convert';

/// Represents a Daily Site Report (DSR) submitted by site supervisors,
/// containing supervisor voice note, site photos, and written notes.
class DailySiteReportModel {
  final String id;
  final String siteId;
  final String? siteName;
  final DateTime date;
  final String? submittedBy;
  final String? audioUrl;
  final List<String> photoUrls;
  final String? notes;
  final String? rawTranscript;
  final List<String> workDone;
  final List<String> tomorrowPlan;
  final String? manpowerDetails;
  final String? materialsUsed;
  final String? remarks;
  final Map<String, dynamic> aiSummary;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DailySiteReportModel({
    required this.id,
    required this.siteId,
    this.siteName,
    required this.date,
    this.submittedBy,
    this.audioUrl,
    this.photoUrls = const [],
    this.notes,
    this.rawTranscript,
    this.workDone = const [],
    this.tomorrowPlan = const [],
    this.manpowerDetails,
    this.materialsUsed,
    this.remarks,
    this.aiSummary = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isSupervisorApproved =>
      (remarks?.contains('[Project Head: Approved') ?? false) ||
      (remarks?.contains('[Supervisor: Approved') ?? false);
  bool get isProjectHeadApproved => isSupervisorApproved;

  bool get isSupervisorRejected =>
      (remarks?.contains('[Project Head: Rejected') ?? false) ||
      (remarks?.contains('[Supervisor: Rejected') ?? false);
  bool get isProjectHeadRejected => isSupervisorRejected;

  bool get isSupervisorReviewed => isSupervisorApproved || isSupervisorRejected;
  bool get isProjectHeadReviewed => isSupervisorReviewed;

  bool get isPendingSupervisorReview => !isSupervisorReviewed;
  bool get isPendingProjectHeadReview => isPendingSupervisorReview;

  String? get supervisorRejectionReason {
    final match = RegExp(r'\[(?:Project Head|Supervisor):\s*Rejected\s*-\s*(.+?)(?:\s+by\s+.+?)?\]').firstMatch(remarks ?? '');
    return match?.group(1)?.trim();
  }
  String? get projectHeadRejectionReason => supervisorRejectionReason;

  String? get projectHeadApproverName {
    final match = RegExp(r'\[(?:Project Head|Supervisor):\s*Approved(?:\s+by\s+(.+?))?\]').firstMatch(remarks ?? '');
    return match?.group(1)?.trim();
  }
  factory DailySiteReportModel.fromJson(Map<String, dynamic> json) {
    // Parse workDone
    List<String> parseList(dynamic field) {
      if (field == null) return [];
      if (field is List) {
        return field.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
      if (field is String) {
        try {
          final decoded = jsonDecode(field);
          if (decoded is List) {
            return decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
          }
        } catch (_) {
          return field
              .split('\n')
              .map((e) => e.replaceAll(RegExp(r'^[-*•\d.]+\s*'), '').trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      }
      return [];
    }

    // Parse photoUrls
    List<String> parsePhotos(dynamic field) {
      if (field == null) return [];
      if (field is List) {
        return field.map((e) => e.toString()).toList();
      }
      if (field is String) {
        if (field.startsWith('[') && field.endsWith(']')) {
          try {
            final decoded = jsonDecode(field);
            if (decoded is List) return decoded.map((e) => e.toString()).toList();
          } catch (_) {}
        }
        return [field];
      }
      return [];
    }

    DateTime parseDate(dynamic d) {
      if (d == null) return DateTime.now();
      if (d is DateTime) return d;
      return DateTime.tryParse(d.toString()) ?? DateTime.now();
    }

    return DailySiteReportModel(
      id: json['id']?.toString() ?? '',
      siteId: json['site_id']?.toString() ?? '',
      siteName: json['sites'] != null ? json['sites']['name'] as String? : json['site_name'] as String?,
      date: parseDate(json['date']),
      submittedBy: json['submitted_by']?.toString(),
      audioUrl: json['audio_url']?.toString(),
      photoUrls: parsePhotos(json['photo_urls']),
      notes: json['notes']?.toString(),
      rawTranscript: json['raw_transcript']?.toString(),
      workDone: parseList(json['work_done']),
      tomorrowPlan: parseList(json['tomorrow_plan']),
      manpowerDetails: json['manpower_details']?.toString(),
      materialsUsed: json['materials_used']?.toString(),
      remarks: json['remarks']?.toString(),
      aiSummary: json['ai_summary'] is Map<String, dynamic>
          ? json['ai_summary'] as Map<String, dynamic>
          : {},
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'site_id': siteId,
      'site_name': siteName,
      'date': date.toIso8601String().split('T').first,
      'submitted_by': submittedBy,
      'audio_url': audioUrl,
      'photo_urls': photoUrls,
      'notes': notes,
      'raw_transcript': rawTranscript,
      'work_done': workDone,
      'tomorrow_plan': tomorrowPlan,
      'manpower_details': manpowerDetails,
      'materials_used': materialsUsed,
      'remarks': remarks,
      'ai_summary': aiSummary,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  DailySiteReportModel copyWith({
    String? id,
    String? siteId,
    String? siteName,
    DateTime? date,
    String? submittedBy,
    String? audioUrl,
    List<String>? photoUrls,
    String? notes,
    String? rawTranscript,
    List<String>? workDone,
    List<String>? tomorrowPlan,
    String? manpowerDetails,
    String? materialsUsed,
    String? remarks,
    Map<String, dynamic>? aiSummary,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DailySiteReportModel(
      id: id ?? this.id,
      siteId: siteId ?? this.siteId,
      siteName: siteName ?? this.siteName,
      date: date ?? this.date,
      submittedBy: submittedBy ?? this.submittedBy,
      audioUrl: audioUrl ?? this.audioUrl,
      photoUrls: photoUrls ?? this.photoUrls,
      notes: notes ?? this.notes,
      rawTranscript: rawTranscript ?? this.rawTranscript,
      workDone: workDone ?? this.workDone,
      tomorrowPlan: tomorrowPlan ?? this.tomorrowPlan,
      manpowerDetails: manpowerDetails ?? this.manpowerDetails,
      materialsUsed: materialsUsed ?? this.materialsUsed,
      remarks: remarks ?? this.remarks,
      aiSummary: aiSummary ?? this.aiSummary,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
