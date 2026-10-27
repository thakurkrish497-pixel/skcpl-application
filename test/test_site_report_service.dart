import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/daily_site_report_model.dart';
import 'package:skcpl_app/services/site_report_service.dart';

void main() {
  test('Test SiteReportService upload, save and retrieve', () async {
    final service = SiteReportService();
    const siteId = '4c9e1f3a-6903-441a-a2aa-37362a13bafe'; // Nissarpur

    // 1. Test audio upload
    final dummyAudio = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    final audioUrl = await service.uploadAudio(
      audioBytes: dummyAudio,
      siteId: siteId,
      fileName: 'nissarpur_voice_test.m4a',
    );
    print('Uploaded audio URL: $audioUrl');
    expect(audioUrl.contains('site_reports'), isTrue);

    // 2. Test report creation
    final testReport = DailySiteReportModel(
      id: 'test-dsr-${DateTime.now().millisecondsSinceEpoch}',
      siteId: siteId,
      siteName: 'Nissarpur',
      date: DateTime.now(),
      submittedBy: 'Test Supervisor',
      audioUrl: audioUrl,
      photoUrls: ['https://example.com/site_photo1.jpg'],
      notes: 'Aaj grid 1 pe footing casting hui, 40 bag cement laga, kal column shuttering hoga',
      rawTranscript: 'Aaj grid 1 pe footing casting hui, 40 bag cement laga, kal column shuttering hoga',
      workDone: ['Footing casting grid 1-4 completed (9 units)', 'Earth leveling in progress'],
      tomorrowPlan: ['Column bar binding and shuttering on grid 1'],
      manpowerDetails: '5 Masons, 12 Helpers, 1 JCB (6 hrs)',
      materialsUsed: '40 bags cement, 1 dumper sand',
      remarks: 'Normal site weather, work progressing on schedule',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final saved = await service.saveReport(testReport);
    print('Saved report: id=${saved.id}, workItems=${saved.workDone.length}');
    expect(saved.workDone.isNotEmpty, isTrue);

    // 3. Test report retrieval
    final list = await service.getReportsForSite(siteId);
    print('Retrieved reports count: ${list.length}');
    expect(list.isNotEmpty, isTrue);
  });
}
