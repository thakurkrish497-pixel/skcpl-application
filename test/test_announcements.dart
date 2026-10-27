import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/site_announcement_model.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/providers/site_announcement_provider.dart';

void main() {
  group('Site Announcement Model & Permission Tests', () {
    test('Site-specific meeting announcement with Zoom link serialization', () {
      final scheduled = DateTime(2026, 10, 26, 16, 0); // 4:00 PM
      final notice = SiteAnnouncementModel(
        id: 'announcement-1',
        title: 'Hatpipliya Zoom Meeting at 4:00 PM',
        message: 'Reviewing daily stock usage and progress.',
        category: AnnouncementCategory.meeting,
        targetSiteId: 'site-hatpipliya',
        targetSiteName: 'Hatpipliya',
        meetingLink: 'https://zoom.us/j/987654321',
        scheduledAt: scheduled,
        createdByName: 'Daksh Sharma',
        createdByRole: 'Project Head',
        createdAt: DateTime(2026, 10, 26, 12, 0),
        isActive: true,
      );

      expect(notice.isAllSites, isFalse);
      expect(notice.hasMeetingLink, isTrue);
      expect(notice.meetingLink, contains('zoom.us'));
      expect(notice.targetSiteName, equals('Hatpipliya'));
      expect(notice.category, equals(AnnouncementCategory.meeting));

      // Test JSON roundtrip
      final json = notice.toJson();
      expect(json['target_site_id'], equals('site-hatpipliya'));
      expect(json['category'], equals('meeting'));
      expect(json['meeting_link'], equals('https://zoom.us/j/987654321'));

      final restored = SiteAnnouncementModel.fromJson(json);
      expect(restored.id, equals(notice.id));
      expect(restored.title, equals(notice.title));
      expect(restored.category, equals(AnnouncementCategory.meeting));
      expect(restored.isAllSites, isFalse);
      expect(restored.hasMeetingLink, isTrue);
      expect(restored.scheduledAt?.hour, equals(16));
    });

    test('Company-wide Saturday announcement flags isAllSites as true', () {
      final notice = SiteAnnouncementModel(
        id: 'announcement-2',
        title: 'Saturday All-Hands Review',
        message: 'Weekly company-wide milestone review.',
        category: AnnouncementCategory.general,
        targetSiteId: 'all',
        targetSiteName: 'All Sites',
        createdByName: 'Admin',
        createdByRole: 'Admin',
        createdAt: DateTime.now(),
      );

      expect(notice.isAllSites, isTrue);
      expect(notice.hasMeetingLink, isFalse);
      expect(notice.category, equals(AnnouncementCategory.general));
    });

    test('Role restriction: strictly Admin, Project Head, and Accounts can post notices', () {
      expect(canUserPostAnnouncements(UserRole.admin), isTrue);
      expect(canUserPostAnnouncements(UserRole.projectHead), isTrue);
      expect(canUserPostAnnouncements(UserRole.accounts), isTrue);
      expect(canUserPostAnnouncements(UserRole.worker), isFalse);
      expect(canUserPostAnnouncements(null), isFalse);
    });

    test('Category parsing handles variations gracefully', () {
      expect(AnnouncementCategory.fromString('meeting'), equals(AnnouncementCategory.meeting));
      expect(AnnouncementCategory.fromString('zoom'), equals(AnnouncementCategory.meeting));
      expect(AnnouncementCategory.fromString('urgent'), equals(AnnouncementCategory.urgent));
      expect(AnnouncementCategory.fromString('celebration'), equals(AnnouncementCategory.celebration));
      expect(AnnouncementCategory.fromString('general'), equals(AnnouncementCategory.general));
      expect(AnnouncementCategory.fromString(null), equals(AnnouncementCategory.general));
      expect(AnnouncementCategory.fromString('unknown_value'), equals(AnnouncementCategory.general));
    });
  });
}
