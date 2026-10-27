import 'package:flutter/material.dart';

/// Announcement category
enum AnnouncementCategory {
  general,
  meeting,
  urgent,
  celebration;

  String get displayName {
    switch (this) {
      case AnnouncementCategory.general:
        return 'General Notice';
      case AnnouncementCategory.meeting:
        return 'Meeting / Zoom Call';
      case AnnouncementCategory.urgent:
        return 'Urgent Alert';
      case AnnouncementCategory.celebration:
        return 'Milestone / Event';
    }
  }

  IconData get icon {
    switch (this) {
      case AnnouncementCategory.general:
        return Icons.campaign_rounded;
      case AnnouncementCategory.meeting:
        return Icons.video_camera_front_rounded;
      case AnnouncementCategory.urgent:
        return Icons.warning_amber_rounded;
      case AnnouncementCategory.celebration:
        return Icons.celebration_rounded;
    }
  }

  Color get color {
    switch (this) {
      case AnnouncementCategory.general:
        return const Color(0xFF00E5FF); // Wave Cyan
      case AnnouncementCategory.meeting:
        return const Color(0xFF3B82F6); // Blue / Zoom
      case AnnouncementCategory.urgent:
        return const Color(0xFFEF4444); // Red
      case AnnouncementCategory.celebration:
        return const Color(0xFFFBBF24); // Gold
    }
  }

  static AnnouncementCategory fromString(String? value) {
    if (value == null) return AnnouncementCategory.general;
    final clean = value.toLowerCase().trim();
    switch (clean) {
      case 'meeting':
      case 'zoom':
        return AnnouncementCategory.meeting;
      case 'urgent':
      case 'alert':
        return AnnouncementCategory.urgent;
      case 'celebration':
      case 'milestone':
        return AnnouncementCategory.celebration;
      default:
        return AnnouncementCategory.general;
    }
  }
}

/// Model representing a company-wide or site-specific broadcast announcement.
/// Authorized creators: Admin, Project Head, Accounts.
class SiteAnnouncementModel {
  final String id;
  final String title;
  final String message;
  final AnnouncementCategory category;
  final String? targetSiteId; // null or 'all' for company-wide
  final String? targetSiteName; // e.g. "All Sites" or "Hatpipliya"
  final String? meetingLink; // Optional Zoom / Meet / Teams URL
  final DateTime? scheduledAt; // Optional scheduled meeting / event time
  final String createdByName;
  final String createdByRole; // Admin, Project Head, Accounts
  final String? createdById;
  final DateTime createdAt;
  final bool isActive;

  const SiteAnnouncementModel({
    required this.id,
    required this.title,
    required this.message,
    this.category = AnnouncementCategory.general,
    this.targetSiteId,
    this.targetSiteName,
    this.meetingLink,
    this.scheduledAt,
    required this.createdByName,
    required this.createdByRole,
    this.createdById,
    required this.createdAt,
    this.isActive = true,
  });

  bool get isAllSites =>
      targetSiteId == null || targetSiteId == 'all' || targetSiteId!.trim().isEmpty;

  bool get hasMeetingLink =>
      meetingLink != null && meetingLink!.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'category': category.name,
      'target_site_id': targetSiteId,
      'target_site_name': targetSiteName,
      'meeting_link': meetingLink,
      'scheduled_at': scheduledAt?.toIso8601String(),
      'created_by_name': createdByName,
      'created_by_role': createdByRole,
      'created_by_id': createdById,
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive,
    };
  }

  factory SiteAnnouncementModel.fromJson(Map<String, dynamic> json) {
    return SiteAnnouncementModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      category: AnnouncementCategory.fromString(json['category']?.toString()),
      targetSiteId: json['target_site_id']?.toString(),
      targetSiteName: json['target_site_name']?.toString(),
      meetingLink: json['meeting_link']?.toString(),
      scheduledAt: json['scheduled_at'] != null
          ? DateTime.tryParse(json['scheduled_at'].toString())
          : null,
      createdByName: json['created_by_name']?.toString() ?? 'SKCPL Management',
      createdByRole: json['created_by_role']?.toString() ?? 'Admin',
      createdById: json['created_by_id']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  SiteAnnouncementModel copyWith({
    String? id,
    String? title,
    String? message,
    AnnouncementCategory? category,
    String? targetSiteId,
    String? targetSiteName,
    String? meetingLink,
    DateTime? scheduledAt,
    String? createdByName,
    String? createdByRole,
    String? createdById,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return SiteAnnouncementModel(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      category: category ?? this.category,
      targetSiteId: targetSiteId ?? this.targetSiteId,
      targetSiteName: targetSiteName ?? this.targetSiteName,
      meetingLink: meetingLink ?? this.meetingLink,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      createdByName: createdByName ?? this.createdByName,
      createdByRole: createdByRole ?? this.createdByRole,
      createdById: createdById ?? this.createdById,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }
}
