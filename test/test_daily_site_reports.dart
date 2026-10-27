import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/daily_site_report_model.dart';
import 'package:skcpl_app/services/site_report_service.dart';
import 'package:skcpl_app/services/excel_service.dart';
import 'package:excel/excel.dart';

void main() {
  const testSiteId = '4c9e1f3a-6903-441a-a2aa-37362a13bafe'; // Nissarpur
  const testSiteName = 'Nissarpur';

  test('Step 1: Test DailySiteReportModel serialization and properties', () {
    final report = DailySiteReportModel(
      id: 'rep-test-01',
      siteId: testSiteId,
      siteName: testSiteName,
      date: DateTime(2026, 10, 19),
      submittedBy: 'Ramesh Supervisor',
      audioUrl: 'https://example.com/audio/voice_123.m4a',
      photoUrls: ['https://example.com/p1.jpg', 'https://example.com/p2.jpg'],
      notes: 'Footing excavation done on grid 2. Shuttering ready for tomorrow.',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final json = report.toJson();
    expect(json['site_id'], equals(testSiteId));
    expect(json['audio_url'], contains('voice_123.m4a'));
    expect(json['photo_urls'], hasLength(2));
    expect(json['notes'], contains('Footing excavation'));

    final restored = DailySiteReportModel.fromJson(json);
    expect(restored.id, equals('rep-test-01'));
    expect(restored.notes, equals(report.notes));
    expect(restored.photoUrls.length, equals(2));
  });

  test('Step 2: Test SiteReportService save and fetch workflow', () async {
    final service = SiteReportService();
    final testReport = DailySiteReportModel(
      id: 'test-dsr-${DateTime.now().millisecondsSinceEpoch}',
      siteId: testSiteId,
      siteName: testSiteName,
      date: DateTime.now(),
      submittedBy: 'Nissarpur Team',
      audioUrl: 'https://buqonyuojtvxanuautan.supabase.co/storage/v1/object/public/site_reports/sample_voice.m4a',
      photoUrls: ['https://example.com/p1.jpg'],
      notes: 'Aaj grid 2 pe kaam hua. 45 bag cement use hua.',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final saved = await service.saveReport(testReport);
    expect(saved.id, equals(testReport.id));

    final fetched = await service.getReportsForSite(testSiteId);
    expect(fetched, isNotEmpty);
    print('Successfully verified SiteReportService report: notes="${testReport.notes}"');
  });

  test('Step 3: Test Dad\'s Excel Daily Work Report Generation', () async {
    final reports = [
      DailySiteReportModel(
        id: 'rep-1',
        siteId: testSiteId,
        siteName: testSiteName,
        date: DateTime.now(),
        submittedBy: 'Ramesh Supervisor',
        audioUrl: 'https://buqonyuojtvxanuautan.supabase.co/storage/v1/object/public/site_reports/sample_voice.m4a',
        photoUrls: ['https://example.com/p1.jpg', 'https://example.com/p2.jpg'],
        notes: 'Casting 8 footings (grid 2). Shuttering ready for tomorrow.',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    final bytes = ExcelService.generateDailyWorkReportsWorkbookBytes(
      siteName: testSiteName,
      reports: reports,
      startDate: DateTime.now(),
      endDate: DateTime.now(),
    );

    expect(bytes, isNotEmpty);
    print('SUCCESS: Generated Dad\'s Daily Work Report Excel (${bytes.length} bytes)');

    final excel = Excel.decodeBytes(bytes);
    expect(excel.tables.containsKey('DAILY WORK REPORT'), isTrue);
    print('Sheet 1: DAILY WORK REPORT (Rows: ${excel.tables['DAILY WORK REPORT']!.rows.length})');
  });

  test('Step 4: Test Project Head review status getters and rejection reason parsing', () {
    // Unreviewed / null remarks -> should be pending review
    final unreviewedReport = DailySiteReportModel(
      id: 'r-0',
      siteId: testSiteId,
      date: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    expect(unreviewedReport.isProjectHeadApproved, isFalse);
    expect(unreviewedReport.isProjectHeadRejected, isFalse);
    expect(unreviewedReport.isPendingProjectHeadReview, isTrue);

    // Tagged pending
    final pendingReport = DailySiteReportModel(
      id: 'r-1',
      siteId: testSiteId,
      date: DateTime.now(),
      remarks: '[Project Head Review: Pending]',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    expect(pendingReport.isPendingProjectHeadReview, isTrue);

    // Project Head approved
    final approvedReport = DailySiteReportModel(
      id: 'r-2',
      siteId: testSiteId,
      date: DateTime.now(),
      remarks: '[Project Head: Approved by Vikas]',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    expect(approvedReport.isProjectHeadApproved, isTrue);
    expect(approvedReport.isPendingProjectHeadReview, isFalse);

    // Project Head rejected with reason
    final rejectedReport = DailySiteReportModel(
      id: 'r-3',
      siteId: testSiteId,
      date: DateTime.now(),
      remarks: '[Project Head: Rejected - Missing mandatory photo evidence by Vikas]',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    expect(rejectedReport.isProjectHeadRejected, isTrue);
    expect(rejectedReport.isPendingProjectHeadReview, isFalse);
    expect(rejectedReport.projectHeadRejectionReason, equals('Missing mandatory photo evidence'));

    // Backward compatibility with legacy supervisor approved / rejected tags
    final legacyApproved = DailySiteReportModel(
      id: 'r-4',
      siteId: testSiteId,
      date: DateTime.now(),
      remarks: '[Supervisor: Approved by Mohan]',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    expect(legacyApproved.isProjectHeadApproved, isTrue);
    expect(legacyApproved.isPendingProjectHeadReview, isFalse);

    final legacyRejected = DailySiteReportModel(
      id: 'r-5',
      siteId: testSiteId,
      date: DateTime.now(),
      remarks: '[Supervisor: Rejected - Incomplete measurements by Mohan]',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    expect(legacyRejected.isProjectHeadRejected, isTrue);
    expect(legacyRejected.projectHeadRejectionReason, equals('Incomplete measurements'));
  });

  test('Step 5: Test SiteReportService.getReportsForSite("all")', () async {
    final service = SiteReportService();
    final allReports = await service.getReportsForSite('all');
    // Ensure getReportsForSite('all') runs successfully without error and fetches reports across all sites
    expect(allReports, isA<List<DailySiteReportModel>>());
    print('SUCCESS: getReportsForSite("all") returned ${allReports.length} reports');
  });
}
