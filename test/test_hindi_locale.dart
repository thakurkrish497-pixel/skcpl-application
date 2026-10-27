import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skcpl_app/core/localization/app_strings.dart';
import 'package:skcpl_app/providers/locale_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Hindi Localization & New Addons Tests', () {
    test('English dictionary contains all core & addon keys', () {
      expect(AppStrings.tr('daily_work_report', 'en'), 'Daily Work Report');
      expect(AppStrings.tr('reporting_staff', 'en'), 'REPORTING STAFF (SUBMITTED BY)');
      expect(AppStrings.tr('notice_board', 'en'), 'Notice Board & Broadcasts');
      expect(AppStrings.tr('indore_head_office', 'en'), 'Indore Head Office');
      expect(AppStrings.tr('view_todays_reports', 'en'), "View Today's Reports");
      expect(AppStrings.tr('check_yesterday_reports', 'en'), "Check Yesterday's Reports");
      expect(AppStrings.tr('project_head_approved', 'en'), 'Project Head Approved');
      expect(AppStrings.tr('voice_to_text', 'en'), 'Voice-to-Text');
      expect(AppStrings.tr('all_notices', 'en'), 'All Notices');
      expect(AppStrings.tr('broadcast_to_all', 'en'), 'Broadcast to All Staff & Sites');
    });

    test('Hindi dictionary returns proper Hindi translations for addons', () {
      expect(AppStrings.tr('daily_work_report', 'hi'), 'दैनिक कार्य प्रगति रिपोर्ट');
      expect(AppStrings.tr('reporting_staff', 'hi'), 'रिपोर्टिंग कर्मचारी (प्रस्तुतकर्ता)');
      expect(AppStrings.tr('select_reporting_staff', 'hi'), 'दैनिक रिपोर्ट दर्ज करने वाले कर्मचारी को चुनें। स्वीकृत रिपोर्ट पर इस कर्मचारी का नाम दर्ज होगा।');
      expect(AppStrings.tr('notice_board', 'hi'), 'सूचना पट्ट एवं प्रसारण');
      expect(AppStrings.tr('post_notice', 'hi'), 'सूचना जारी करें');
      expect(AppStrings.tr('indore_head_office', 'hi'), 'इंदौर प्रधान कार्यालय');
      expect(AppStrings.tr('view_todays_reports', 'hi'), 'आज की रिपोर्ट देखें');
      expect(AppStrings.tr('check_yesterday_reports', 'hi'), 'कल की रिपोर्ट देखें');
      expect(AppStrings.tr('yesterday', 'hi'), 'कल');
      expect(AppStrings.tr('today', 'hi'), 'आज');
      expect(AppStrings.tr('project_head_approved', 'hi'), 'प्रोजेक्ट हेड द्वारा स्वीकृत');
      expect(AppStrings.tr('voice_to_text', 'hi'), 'बोलकर लिखें (वॉइस टू टेक्स्ट)');
      expect(AppStrings.tr('whisper_ai', 'hi'), 'व्हिस्पर एआई (अत्यधिक सटीक)');
      expect(AppStrings.tr('live_dictation', 'hi'), 'लाइव डिक्टेशन');
      expect(AppStrings.tr('site_photos_evidence', 'hi'), 'साइट तस्वीरें (प्रमाण)');
      expect(AppStrings.tr('speak_work_update', 'hi'), 'आज किए गए कार्य की जानकारी बोलें या लिखें...');
      expect(AppStrings.tr('all_notices', 'hi'), 'सभी सूचनाएं');
      expect(AppStrings.tr('broadcast_to_all', 'hi'), 'सभी कर्मचारियों व साइट्स को प्रसारित');
    });

    test('LocaleNotifier toggles and switches properly', () async {
      final notifier = LocaleNotifier();
      // Allow initial load to finish
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await notifier.setLocale(const Locale('hi'));
      expect(notifier.isHindi, isTrue);
      expect(notifier.state.languageCode, 'hi');

      await notifier.setLocale(const Locale('en'));
      expect(notifier.isHindi, isFalse);
      expect(notifier.state.languageCode, 'en');

      await notifier.toggleLocale();
      expect(notifier.isHindi, isTrue);
      expect(notifier.state.languageCode, 'hi');
    });
  });
}
