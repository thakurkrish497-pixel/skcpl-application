import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/daily_site_report_model.dart';
import 'package:skcpl_app/services/site_report_service.dart';
import 'package:uuid/uuid.dart';

void main() {
  const testSiteId = '4c9e1f3a-6903-441a-a2aa-37362a13bafe'; // Nissarpur
  const testSiteName = 'Nissarpur';

  test('Test multiple reports submitted on the same day are both preserved and returned', () async {
    final service = SiteReportService();
    final today = DateTime.now();

    // Submit Report #1 (Morning update)
    final report1 = DailySiteReportModel(
      id: const Uuid().v4(),
      siteId: testSiteId,
      siteName: testSiteName,
      date: today,
      submittedBy: 'Supervisor Ramesh',
      audioUrl: null, // Voice-to-Text: No audio stored!
      photoUrls: ['https://example.com/morning_footing.jpg'],
      notes: 'Morning update: Footing excavation completed for grid 1 and 2.',
      createdAt: today.subtract(const Duration(hours: 4)),
      updatedAt: today.subtract(const Duration(hours: 4)),
    );

    // Submit Report #2 (Evening update)
    final report2 = DailySiteReportModel(
      id: const Uuid().v4(),
      siteId: testSiteId,
      siteName: testSiteName,
      date: today,
      submittedBy: 'Supervisor Ramesh',
      audioUrl: null, // Voice-to-Text: No audio stored!
      photoUrls: ['https://example.com/evening_shuttering.jpg'],
      notes: 'Evening update: Shuttering installed for 4 pillars. 35 bags cement used.',
      createdAt: today,
      updatedAt: today,
    );

    // Save both
    final saved1 = await service.saveReport(report1);
    final saved2 = await service.saveReport(report2);

    expect(saved1.id, equals(report1.id));
    expect(saved2.id, equals(report2.id));
    expect(saved1.audioUrl, isNull);
    expect(saved2.audioUrl, isNull);

    // Fetch reports for today
    final reportsToday = await service.getReportsForDate(testSiteId, today);
    expect(reportsToday.length, greaterThanOrEqualTo(2));

    final ids = reportsToday.map((r) => r.id).toList();
    expect(ids.contains(report1.id), isTrue, reason: 'Report 1 must be present');
    expect(ids.contains(report2.id), isTrue, reason: 'Report 2 must be present');

    print('VERIFIED: Multiple updates on same date are preserved! Count=${reportsToday.length}');
  });
}
