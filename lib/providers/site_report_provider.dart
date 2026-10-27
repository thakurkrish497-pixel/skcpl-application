import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/daily_site_report_model.dart';
import '../services/site_report_service.dart';

final siteReportServiceProvider = Provider<SiteReportService>((ref) {
  return SiteReportService();
});

/// Fetches reports for a site
final siteReportsForSiteProvider = FutureProvider.family<List<DailySiteReportModel>, String>((ref, siteId) async {
  final service = ref.watch(siteReportServiceProvider);
  return service.getReportsForSite(siteId);
});

/// Fetches all reports across all sites
final allDailyReportsProvider = FutureProvider.autoDispose<List<DailySiteReportModel>>((ref) async {
  final service = ref.watch(siteReportServiceProvider);
  return service.getReportsForSite('all');
});

/// Fetches all reports for a specific site on a given date (e.g. morning + evening updates)
final siteReportsForDateProvider = FutureProvider.family<List<DailySiteReportModel>, ({String siteId, DateTime date})>((ref, arg) async {
  final service = ref.watch(siteReportServiceProvider);
  return service.getReportsForDate(arg.siteId, arg.date);
});

/// Fetches report for a specific site & date (backward compatibility)
final siteReportForDateProvider = FutureProvider.family<DailySiteReportModel?, ({String siteId, DateTime date})>((ref, arg) async {
  final service = ref.watch(siteReportServiceProvider);
  return service.getReportForDate(arg.siteId, arg.date);
});

/// State for submitting a report (Voice, Photos, Notes)
class ReportSubmissionState {
  final bool isUploadingAudio;
  final bool isUploadingPhotos;
  final bool isSaving;
  final String? error;
  final DailySiteReportModel? result;

  const ReportSubmissionState({
    this.isUploadingAudio = false,
    this.isUploadingPhotos = false,
    this.isSaving = false,
    this.error,
    this.result,
  });

  bool get isLoading => isUploadingAudio || isUploadingPhotos || isSaving;

  String get loadingStatusText {
    if (isUploadingAudio) return 'Uploading voice note...';
    if (isUploadingPhotos) return 'Uploading site photos...';
    if (isSaving) return 'Saving daily site report...';
    return '';
  }

  ReportSubmissionState copyWith({
    bool? isUploadingAudio,
    bool? isUploadingPhotos,
    bool? isSaving,
    String? error,
    DailySiteReportModel? result,
  }) {
    return ReportSubmissionState(
      isUploadingAudio: isUploadingAudio ?? this.isUploadingAudio,
      isUploadingPhotos: isUploadingPhotos ?? this.isUploadingPhotos,
      isSaving: isSaving ?? this.isSaving,
      error: error,
      result: result ?? this.result,
    );
  }
}

class ReportSubmissionNotifier extends StateNotifier<ReportSubmissionState> {
  final Ref _ref;
  final SiteReportService _service;

  ReportSubmissionNotifier(this._ref, this._service) : super(const ReportSubmissionState());

  Future<DailySiteReportModel?> submitDailyReport({
    required String siteId,
    required String siteName,
    required DateTime date,
    required String submittedBy,
    Uint8List? audioBytes,
    String? audioFileName,
    List<Uint8List> photoBytesList = const [],
    String? textNotes,
    String? remarks,
  }) async {
    try {
      state = state.copyWith(isUploadingAudio: audioBytes != null, error: null);

      String? audioUrl;
      if (audioBytes != null && audioBytes.isNotEmpty) {
        audioUrl = await _service.uploadAudio(
          audioBytes: audioBytes,
          siteId: siteId,
          fileName: audioFileName ?? 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        );
      }

      state = state.copyWith(
        isUploadingAudio: false,
        isUploadingPhotos: photoBytesList.isNotEmpty,
      );

      final photoUrls = <String>[];
      for (int i = 0; i < photoBytesList.length; i++) {
        final pUrl = await _service.uploadPhoto(
          photoBytes: photoBytesList[i],
          siteId: siteId,
          fileName: 'photo_${i}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        photoUrls.add(pUrl);
      }

      state = state.copyWith(
        isUploadingPhotos: false,
        isSaving: true,
      );

      final report = DailySiteReportModel(
        id: const Uuid().v4(),
        siteId: siteId,
        siteName: siteName,
        date: date,
        submittedBy: submittedBy,
        audioUrl: audioUrl,
        photoUrls: photoUrls,
        notes: textNotes,
        remarks: remarks,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final saved = await _service.saveReport(report);

      // Invalidate relevant providers to trigger instant UI refresh
      _ref.invalidate(allDailyReportsProvider);
      _ref.invalidate(siteReportsForSiteProvider(siteId));
      _ref.invalidate(siteReportsForDateProvider((siteId: siteId, date: date)));
      _ref.invalidate(siteReportForDateProvider((siteId: siteId, date: date)));

      state = state.copyWith(
        isSaving: false,
        result: saved,
      );

      return saved;
    } catch (e) {
      state = state.copyWith(
        isUploadingAudio: false,
        isUploadingPhotos: false,
        isSaving: false,
        error: e.toString(),
      );
      return null;
    }
  }
}

final reportSubmissionProvider = StateNotifierProvider<ReportSubmissionNotifier, ReportSubmissionState>((ref) {
  final service = ref.watch(siteReportServiceProvider);
  return ReportSubmissionNotifier(ref, service);
});
