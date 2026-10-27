import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/daily_site_report_model.dart';
import '../../models/site_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/site_report_provider.dart';
import '../../providers/site_staff_provider.dart';
import '../../models/site_staff_model.dart';
import '../../providers/site_provider.dart';
import '../../services/whisper_service.dart';
import '../../services/speech/speech_service.dart';
import '../../widgets/whisper_settings_dialog.dart';
import '../../widgets/language_toggle_button.dart';
import '../../core/localization/app_strings.dart';

/// Low-Friction Daily Site Report screen for Project Heads and Workers.
/// Converts voice to text with extreme accuracy (via Live Speech Recognition or Whisper AI),
/// attaches site photos, and submits clean text with zero storage clutter.
class RecordSiteReportScreen extends ConsumerStatefulWidget {
  final SiteModel? site;

  const RecordSiteReportScreen({super.key, this.site});

  @override
  ConsumerState<RecordSiteReportScreen> createState() => _RecordSiteReportScreenState();
}

class _RecordSiteReportScreenState extends ConsumerState<RecordSiteReportScreen> {
  final _notesController = TextEditingController();
  final _picker = ImagePicker();
  final _whisperService = WhisperService();
  late final SpeechRecognitionBase _speechRecognition;
  late final AudioRecorder _audioRecorder;

  // Voice-to-Text State
  bool _useWhisperEngine = true; // Extreme accuracy via Groq Whisper by default
  bool _isListening = false;
  bool _isTranscribing = false;
  String _selectedLanguage = 'hindi'; // 'hindi' | 'hinglish' | 'english'
  String _liveSpokenBuffer = '';
  int _recordDurationSeconds = 0;
  Timer? _recordTimer;

  // Photos State
  final List<XFile> _selectedPhotos = [];
  final List<Uint8List> _photoBytesList = [];

  DateTime _selectedDate = DateTime.now();
  SiteModel? _selectedSite;
  SiteStaffModel? _selectedStaff;

  @override
  void initState() {
    super.initState();
    _speechRecognition = createSpeechRecognition();
    _audioRecorder = AudioRecorder();
    _selectedSite = widget.site;
    _selectedStaff = ref.read(activeStaffProvider);
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _speechRecognition.stop();
    _audioRecorder.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── 1. Live Voice-to-Text (SpeechRecognition) ──
  void _toggleLiveVoiceToText() {
    if (_isListening) {
      _stopLiveListening();
    } else {
      _startLiveListening();
    }
  }

  void _startLiveListening() {
    setState(() {
      _isListening = true;
      _liveSpokenBuffer = '';
      _recordDurationSeconds = 0;
    });

    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _recordDurationSeconds++);
    });

    // Append existing text as baseline
    final initialPrefix = _notesController.text.trim().isNotEmpty
        ? '${_notesController.text.trim()} '
        : '';

    final liveLang = _selectedLanguage == 'hindi'
        ? 'hi-IN'
        : (_selectedLanguage == 'english' ? 'en-US' : 'en-IN');

    _speechRecognition.start(
      lang: liveLang,
      onResult: (text, isFinal) {
        if (mounted) {
          setState(() {
            _liveSpokenBuffer = text;
            _notesController.text = '$initialPrefix$text'.trim();
            _notesController.selection = TextSelection.fromPosition(
              TextPosition(offset: _notesController.text.length),
            );
          });
        }
      },
      onEnd: () {
        if (mounted) {
          setState(() {
            _isListening = false;
            _liveSpokenBuffer = '';
          });
        }
      },
      onError: (err) {
        if (mounted) {
          setState(() => _isListening = false);
          // If browser speech recognition is not supported or failed, suggest Whisper
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Speech recognition info: $err. You can also use Whisper AI below.'),
              action: SnackBarAction(
                label: 'Setup AI',
                onPressed: () => WhisperSettingsDialog.show(context),
              ),
            ),
          );
        }
      },
    );
  }

  void _stopLiveListening() {
    _recordTimer?.cancel();
    _speechRecognition.stop();
    setState(() {
      _isListening = false;
      _liveSpokenBuffer = '';
    });
  }

  // ── 2. Whisper Extreme-Accuracy Audio-to-Text ──
  Future<void> _recordAndTranscribeWithWhisper() async {
    final hasKey = await _whisperService.getApiKey();
    if (hasKey == null || hasKey.trim().isEmpty) {
      if (mounted) {
        final setupNow = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surfaceDark,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('Setup Free Groq / OpenAI Key', style: TextStyle(color: Colors.white)),
            content: const Text(
              'To enable ultra-accurate Whisper voice-to-text (99%+ accuracy for Hindi & English construction terms), '
              'please enter a free Groq or OpenAI API key.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Setup Key'),
              ),
            ],
          ),
        );
        if (setupNow == true && mounted) {
          WhisperSettingsDialog.show(context);
        }
      }
      return;
    }

    try {
      if (await _audioRecorder.hasPermission()) {
        String? targetPath;
        if (!kIsWeb) {
          final tempDir = await getTemporaryDirectory();
          targetPath = '${tempDir.path}/whisper_temp_${DateTime.now().millisecondsSinceEpoch}.m4a';
        }

        await _audioRecorder.start(
          RecordConfig(
            encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
          ),
          path: targetPath ?? '',
        );

        setState(() {
          _isListening = true;
          _recordDurationSeconds = 0;
        });

        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) setState(() => _recordDurationSeconds++);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Audio recorder error: $e')),
      );
    }
  }

  Future<void> _stopWhisperRecordingAndTranscribe() async {
    _recordTimer?.cancel();
    setState(() {
      _isListening = false;
      _isTranscribing = true;
    });

    try {
      final path = await _audioRecorder.stop();
      if (path != null) {
        Uint8List? bytes;
        if (kIsWeb) {
          final res = await http.get(Uri.parse(path));
          bytes = res.bodyBytes;
        } else {
          final file = File(path);
          if (await file.exists()) {
            bytes = await file.readAsBytes();
            await file.delete(); // Delete local file immediately to free space
          }
        }

        if (bytes != null && bytes.isNotEmpty) {
          final transcript = await _whisperService.transcribeAudio(
            audioBytes: bytes,
            fileName: kIsWeb ? 'audio.webm' : 'audio.m4a',
            lang: _selectedLanguage,
          );

          if (mounted && transcript.trim().isNotEmpty) {
            final existing = _notesController.text.trim();
            final updated = existing.isEmpty ? transcript : '$existing\n$transcript';
            _notesController.text = updated;
            _notesController.selection = TextSelection.fromPosition(
              TextPosition(offset: _notesController.text.length),
            );

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Transcribed successfully with Whisper AI!')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Whisper error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTranscribing = false);
    }
  }

  // ── Photo Picker ──
  Future<void> _pickPhotos(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        final photo = await _picker.pickImage(source: source, imageQuality: 75);
        if (photo != null) {
          final bytes = await photo.readAsBytes();
          setState(() {
            _selectedPhotos.add(photo);
            _photoBytesList.add(bytes);
          });
        }
      } else {
        final photos = await _picker.pickMultiImage(imageQuality: 75);
        for (final p in photos) {
          final bytes = await p.readAsBytes();
          setState(() {
            _selectedPhotos.add(p);
            _photoBytesList.add(bytes);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo picker error: $e')),
        );
      }
    }
  }

  String _formatTimer(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _languageDescription {
    switch (_selectedLanguage) {
      case 'hindi':
        return 'Outputs शुद्ध हिन्दी (देवनागरी). Spoken Hindi is kept in Hindi without English translation.';
      case 'english':
        return 'Outputs in English. Spoken English is transcribed directly without translation.';
      case 'hinglish':
      default:
        return 'Outputs in Hinglish (Roman Hindi). Spoken words are kept exactly as spoken without English translation.';
    }
  }

  Widget _buildLanguagePill({
    required String id,
    required String flag,
    required String title,
    required String example,
  }) {
    final isSelected = _selectedLanguage == id;
    return GestureDetector(
      onTap: _isListening ? null : () => setState(() => _selectedLanguage = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.18) : AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(flag, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? AppColors.primary : Colors.white70,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              example,
              style: TextStyle(
                color: isSelected ? AppColors.primary.withOpacity(0.85) : Colors.white38,
                fontSize: 10,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Submit Report (Zero audio storage, pure text + photos) ──
  Future<void> _handleSubmit() async {
    final authState = ref.read(authProvider);
    final sitesList = ref.read(activeSitesProvider).valueOrNull ?? [];
    final site = _selectedSite ?? widget.site ?? authState.activeSite ?? (sitesList.isNotEmpty ? sitesList.first : null);

    if (site == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active site selected')),
      );
      return;
    }

    final text = _notesController.text.trim();
    if (text.isEmpty && _photoBytesList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please speak your work update or attach site photos first')),
      );
      return;
    }

    final activeStaff = _selectedStaff ?? ref.read(activeStaffProvider);
    final isAllowed = activeStaff == null ||
        activeStaff.hasModule(StaffModule.report) ||
        site.isHeadOffice;
    if (!isAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Access Denied: Daily Site Reports are turned off for ${activeStaff.name}.'),
          backgroundColor: AppColors.rejected,
        ),
      );
      return;
    }

    const reportRemarks = '[Project Head Review: Pending]';

    final submittedBy = activeStaff != null
        ? '${activeStaff.name} (${activeStaff.role.displayName})'
        : (authState.user?.fullName ?? site.name);

    // Submit via Provider (audioBytes is null because voice is converted to text!)
    final saved = await ref.read(reportSubmissionProvider.notifier).submitDailyReport(
          siteId: site.id,
          siteName: site.name,
          date: _selectedDate,
          submittedBy: submittedBy,
          audioBytes: null, // Zero audio uploaded = zero storage cost!
          photoBytesList: _photoBytesList,
          textNotes: text.isNotEmpty ? text : null,
          remarks: reportRemarks,
        );

    if (saved != null && mounted) {
      _showSuccessDialog(saved);
    }
  }

  void _showSuccessDialog(DailySiteReportModel report) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.approved.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: AppColors.approved, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Report Submitted!',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your daily work report has been submitted and forwarded to the Project Head for review.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.record_voice_over_rounded, color: AppColors.primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          report.notes != null ? 'Voice-to-Text Note Saved' : 'No text provided',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        report.photoUrls.isNotEmpty ? Icons.photo_library : Icons.no_photography,
                        color: report.photoUrls.isNotEmpty ? AppColors.secondary : AppColors.textTertiary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        report.photoUrls.isNotEmpty
                            ? '${report.photoUrls.length} site photos attached'
                            : 'No photos attached',
                        style: TextStyle(
                          color: report.photoUrls.isNotEmpty ? Colors.white : AppColors.textTertiary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final sitesList = ref.watch(activeSitesProvider).valueOrNull ?? [];
    final site = _selectedSite ?? widget.site ?? authState.activeSite ?? (sitesList.isNotEmpty ? sitesList.first : null);
    final submissionState = ref.watch(reportSubmissionProvider);

    // Load staff for the active site
    final staffState = site != null ? ref.watch(siteStaffProvider(site.id)) : null;
    final availableStaff = staffState?.staffList.where((s) {
      if (site != null && site.isHeadOffice) return true; // All staff added to Indore Head Office
      return s.hasModule(StaffModule.report) || s.isSupervisor;
    }).toList() ?? [];

    // Keep selected staff in sync
    if (_selectedStaff != null && !availableStaff.any((s) => s.id == _selectedStaff!.id)) {
      _selectedStaff = null;
    }
    if (_selectedStaff == null && availableStaff.isNotEmpty) {
      final activeStaff = ref.watch(activeStaffProvider);
      if (activeStaff != null && availableStaff.any((s) => s.id == activeStaff.id)) {
        _selectedStaff = activeStaff;
      } else {
        _selectedStaff = availableStaff.first;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Text(context.tr('daily_work_report', defaultText: 'Daily Work Report')),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: LanguageToggleButton(isCompact: true),
          ),
          IconButton(
            icon: const Icon(Icons.settings_voice_rounded),
            tooltip: context.tr('voice_settings', defaultText: 'Voice Settings'),
            onPressed: () => WhisperSettingsDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today_rounded),
            tooltip: context.tr('date', defaultText: 'Select Report Date'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2024),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (picked != null) setState(() => _selectedDate = picked);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Site Banner (with Site Switcher if multiple sites)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          (site?.isHeadOffice ?? false) ? Icons.apartment_rounded : Icons.location_city_rounded,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (sitesList.length > 1)
                              DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: site?.id,
                                  isDense: true,
                                  dropdownColor: AppColors.surfaceDark,
                                  icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary),
                                  style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
                                  items: sitesList.map((s) {
                                    return DropdownMenuItem<String>(
                                      value: s.id,
                                      child: Text(
                                        s.isHeadOffice ? '${s.name} (Head Office)' : s.name,
                                        style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary, fontSize: 15),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (newSiteId) {
                                    if (newSiteId != null) {
                                      setState(() {
                                        _selectedSite = sitesList.firstWhere((s) => s.id == newSiteId);
                                        _selectedStaff = null;
                                      });
                                    }
                                  },
                                ),
                              )
                            else
                              Text(
                                site?.name ?? 'Site',
                                style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
                              ),
                            const SizedBox(height: 2),
                            Text(
                              'Date: ${DateFormat('dd MMMM yyyy').format(_selectedDate)}',
                              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          context.tr('dsr_entry', defaultText: 'DSR Entry'),
                          style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(),

                const SizedBox(height: 16),

                // ── Reporting Staff Selector ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.35),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.badge_rounded, color: AppColors.primary, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                context.tr('reporting_staff', defaultText: 'REPORTING STAFF (SUBMITTED BY)'),
                                style: AppTextStyles.overline.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ],
                          ),
                          if (_selectedStaff != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _selectedStaff!.role.displayName,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.tr('select_reporting_staff', defaultText: 'Select who is entering this Daily Site Report. The approved report will be stamped with this person\'s name.'),
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary, fontSize: 11.5),
                      ),
                      const SizedBox(height: 12),
                      if (staffState?.isLoading ?? false)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                            ),
                          ),
                        )
                      else if (availableStaff.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDark,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 18, color: AppColors.textTertiary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'No staff assigned to ${site?.name ?? "this site"}. Submitting as general staff.',
                                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: availableStaff.map((staff) {
                            final isSelected = _selectedStaff?.id == staff.id;
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedStaff = staff;
                                });
                                if (site != null) {
                                  ref.read(activeStaffProvider.notifier).setActiveStaff(
                                    staff,
                                    siteId: site.id,
                                    module: StaffModule.report,
                                    remember: true,
                                  );
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary.withOpacity(0.2)
                                      : AppColors.surfaceDark,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? AppColors.primary : AppColors.divider,
                                    width: isSelected ? 1.6 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isSelected ? Icons.check_circle_rounded : Icons.person_outline_rounded,
                                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          staff.name,
                                          style: AppTextStyles.bodyMedium.copyWith(
                                            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                        Text(
                                          staff.role.displayName +
                                              (staff.description != null && staff.description!.isNotEmpty
                                                  ? ' • ${staff.description}'
                                                  : ''),
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: isSelected ? AppColors.primary : AppColors.textTertiary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ).animate().fadeIn().slideY(begin: 0.05),

                const SizedBox(height: 20),

                // ── Voice-to-Text Centerpiece ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isListening
                          ? Colors.redAccent.withOpacity(0.6)
                          : AppColors.primary.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Engine Selector Tabs: Whisper AI (Extreme Accuracy) vs Live Dictation
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: _isListening ? null : () => setState(() => _useWhisperEngine = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: _useWhisperEngine ? AppColors.primary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.auto_awesome, size: 14, color: _useWhisperEngine ? Colors.black : Colors.white70),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Whisper AI (Extreme Accuracy)',
                                      style: TextStyle(
                                        color: _useWhisperEngine ? Colors.black : Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: _isListening ? null : () => setState(() => _useWhisperEngine = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: !_useWhisperEngine ? AppColors.primary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.mic, size: 14, color: !_useWhisperEngine ? Colors.black : Colors.white70),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Live Dictation',
                                      style: TextStyle(
                                        color: !_useWhisperEngine ? Colors.black : Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Language Selector Pills (Hindi, Hinglish, English)
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildLanguagePill(
                            id: 'hindi',
                            flag: '🇮🇳',
                            title: 'हिन्दी (Hindi)',
                            example: 'आज 50 बैग सीमेंट लगा',
                          ),
                          _buildLanguagePill(
                            id: 'hinglish',
                            flag: '🇮🇳',
                            title: 'Hinglish',
                            example: 'Aaj 50 bag cement laga',
                          ),
                          _buildLanguagePill(
                            id: 'english',
                            flag: '🇬🇧',
                            title: 'English',
                            example: '50 bags cement used',
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Language note
                      Text(
                        _languageDescription,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 20),

                      Text(
                        _isTranscribing
                            ? '⚡ Groq Whisper converting speech to text...'
                            : (_isListening
                                ? '🔴 Recording... Boliye'
                                : (_notesController.text.isNotEmpty
                                    ? 'Tap to Speak More'
                                    : 'Tap Mic to Speak Today\'s Work')),
                        style: AppTextStyles.h3.copyWith(
                          color: _isListening ? Colors.redAccent : AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isListening
                            ? 'Duration: ${_formatTimer(_recordDurationSeconds)} — Tap again to finish & convert to text'
                            : (_useWhisperEngine
                                ? 'Groq Whisper turbo engine active • Zero cloud audio stored'
                                : 'Live word-by-word streaming dictation'),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: _isListening ? Colors.redAccent : AppColors.textTertiary,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 22),

                      // Large Circular Mic Button
                      GestureDetector(
                        onTap: _isTranscribing ? null : () {
                          if (_useWhisperEngine) {
                            if (_isListening) {
                              _stopWhisperRecordingAndTranscribe();
                            } else {
                              _recordAndTranscribeWithWhisper();
                            }
                          } else {
                            _toggleLiveVoiceToText();
                          }
                        },
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_isListening)
                              Container(
                                width: 130,
                                height: 130,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.redAccent.withOpacity(0.2),
                                ),
                              ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
                                    begin: const Offset(1.0, 1.0),
                                    end: const Offset(1.25, 1.25),
                                    duration: 800.ms,
                                  ),
                            Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: _isListening
                                    ? const LinearGradient(colors: [Colors.redAccent, Colors.red])
                                    : AppColors.primaryGradient,
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isListening ? Colors.red : AppColors.primary).withOpacity(0.4),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: _isTranscribing
                                  ? const Center(
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                                    )
                                  : Icon(
                                      _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                                      color: Colors.white,
                                      size: 42,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Converted Text / Notes Field ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'WORK REPORT (VOICE-TO-TEXT)',
                      style: AppTextStyles.overline.copyWith(color: AppColors.textTertiary),
                    ),
                    if (_notesController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() => _notesController.clear()),
                        child: Text(
                          'Clear Text',
                          style: AppTextStyles.caption.copyWith(color: AppColors.rejected),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                  decoration: InputDecoration(
                    hintText: 'Spoken text will automatically appear here. You can also edit or type manually...',
                    hintStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.cardDark,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Site Photos Section ──
                Text(
                  'SITE PHOTOS (EVIDENCE)',
                  style: AppTextStyles.overline.copyWith(color: AppColors.textTertiary),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickPhotos(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_rounded),
                        label: const Text('Take Camera Photo'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.divider),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickPhotos(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_rounded),
                        label: const Text('Add from Gallery'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.divider),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),

                // Selected Photos Preview Carousel
                if (_selectedPhotos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedPhotos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 90,
                                height: 90,
                                color: AppColors.surfaceDark,
                                child: Image.memory(
                                  _photoBytesList[index],
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedPhotos.removeAt(index);
                                    _photoBytesList.removeAt(index);
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black87,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 36),

                // ── Submit Button ──
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: submissionState.isLoading ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.send_rounded, color: Colors.white),
                        const SizedBox(width: 10),
                        Text(
                          'Submit',
                          style: AppTextStyles.button.copyWith(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),

          // Loading Overlay with dynamic status text
          if (submissionState.isLoading)
            Container(
              color: Colors.black.withOpacity(0.75),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primary.withOpacity(0.5)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppColors.primary),
                      const SizedBox(height: 20),
                      Text(
                        submissionState.loadingStatusText,
                        style: AppTextStyles.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Saving daily work report and site photos',
                        style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
