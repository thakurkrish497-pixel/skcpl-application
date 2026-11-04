import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../services/speech/speech_service.dart';
import '../services/whisper_service.dart';
import 'whisper_settings_dialog.dart';

/// Reusable Voice-to-Text Microphone icon button for text fields.
/// Matches DSR (Daily Site Report) voice input flow:
/// - Supports Whisper AI (Extreme Accuracy) and Live Dictation
/// - Manual mic tap to record & stop
/// - Hindi, Hinglish, and English modes
class VoiceInputIconButton extends StatelessWidget {
  final TextEditingController controller;
  final String? fieldLabel;
  final VoidCallback? onTranscriptionComplete;
  final bool append;
  final double iconSize;
  final Color? iconColor;

  const VoiceInputIconButton({
    super.key,
    required this.controller,
    this.fieldLabel,
    this.onTranscriptionComplete,
    this.append = true,
    this.iconSize = 22,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.mic_rounded,
        size: iconSize,
        color: iconColor ?? AppColors.primary,
      ),
      tooltip: 'Voice to Text (Hindi / English)',
      onPressed: () {
        VoiceDictationDialog.show(
          context: context,
          controller: controller,
          fieldLabel: fieldLabel,
          append: append,
          onComplete: onTranscriptionComplete,
        );
      },
    );
  }
}

/// Voice Dictation Dialog designed to mirror the DSR voice interface.
class VoiceDictationDialog extends StatefulWidget {
  final TextEditingController controller;
  final String? fieldLabel;
  final bool append;
  final VoidCallback? onComplete;

  const VoiceDictationDialog({
    super.key,
    required this.controller,
    this.fieldLabel,
    this.append = true,
    this.onComplete,
  });

  static Future<void> show({
    required BuildContext context,
    required TextEditingController controller,
    String? fieldLabel,
    bool append = true,
    VoidCallback? onComplete,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => VoiceDictationDialog(
        controller: controller,
        fieldLabel: fieldLabel,
        append: append,
        onComplete: onComplete,
      ),
    );
  }

  @override
  State<VoiceDictationDialog> createState() => _VoiceDictationDialogState();
}

class _VoiceDictationDialogState extends State<VoiceDictationDialog> {
  final _whisperService = WhisperService();
  late final SpeechRecognitionBase _speechRecognition;
  late final AudioRecorder _audioRecorder;

  // Default to 100% Free Live Voice Dictation (Zero keys, Zero setup required)
  bool _useWhisperEngine = false;
  bool _isListening = false;
  bool _isTranscribing = false;
  int _recordDurationSeconds = 0;
  Timer? _recordTimer;
  String _selectedLanguage = 'hindi'; // 'hindi' | 'hinglish' | 'english'
  String _liveSpokenBuffer = '';

  @override
  void initState() {
    super.initState();
    _speechRecognition = createSpeechRecognition();
    _audioRecorder = AudioRecorder();
    // Do NOT auto-record on open — matches DSR where the user taps when ready.
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _speechRecognition.stop();
    _audioRecorder.dispose();
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
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordDurationSeconds++);
    });

    // Baseline prefix to append if there was existing text (matches DSR live typing)
    final initialPrefix = widget.append && widget.controller.text.trim().isNotEmpty
        ? '${widget.controller.text.trim()} '
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
            // Live stream words into the controller immediately (just like DSR!)
            widget.controller.text = '$initialPrefix$text'.trim();
            widget.controller.selection = TextSelection.fromPosition(
              TextPosition(offset: widget.controller.text.length),
            );
          });
        }
      },
      onEnd: () {
        if (mounted) {
          setState(() => _isListening = false);
        }
      },
      onError: (err) {
        if (mounted) {
          setState(() => _isListening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Speech notice: $err. You can switch to Whisper AI.'),
              backgroundColor: AppColors.rejected,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      },
    );
  }

  void _stopLiveListening() {
    _recordTimer?.cancel();
    _speechRecognition.stop();
    setState(() => _isListening = false);

    if (_liveSpokenBuffer.trim().isNotEmpty) {
      _applyTextToController(_liveSpokenBuffer.trim());
      widget.onComplete?.call();
      Navigator.pop(context);
    }
  }

  // ── 2. Whisper AI ──
  Future<void> _recordAndTranscribeWithWhisper() async {
    final hasKey = await _whisperService.getApiKey();
    if (hasKey == null || hasKey.trim().isEmpty) {
      // If no key configured, fallback directly to Live Dictation (Zero popups!)
      setState(() => _useWhisperEngine = false);
      _startLiveListening();
      return;
    }

    try {
      if (await _audioRecorder.hasPermission()) {
        String? targetPath;
        if (!kIsWeb) {
          final tempDir = await getTemporaryDirectory();
          targetPath = '${tempDir.path}/whisper_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        }

        await _audioRecorder.start(
          const RecordConfig(
            encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
          ),
          path: targetPath ?? '',
        );

        setState(() {
          _isListening = true;
          _recordDurationSeconds = 0;
          _liveSpokenBuffer = '';
        });

        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _recordDurationSeconds++);
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(kIsWeb
                  ? 'Microphone permission denied. Please allow microphone in browser.'
                  : 'Microphone permission denied. Please allow microphone access in device Settings.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio recorder error: $e')),
        );
      }
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
            await file.delete();
          }
        }

        if (bytes != null && bytes.isNotEmpty) {
          final transcript = await _whisperService.transcribeAudio(
            audioBytes: bytes,
            fileName: kIsWeb ? 'audio.webm' : 'audio.m4a',
            lang: _selectedLanguage,
          );

          if (mounted && transcript.trim().isNotEmpty) {
            _applyTextToController(transcript.trim());
            widget.onComplete?.call();
            Navigator.pop(context);
            return;
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: AppColors.rejected,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Settings',
              textColor: Colors.white,
              onPressed: () => WhisperSettingsDialog.show(context),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTranscribing = false);
    }
  }

  void _applyTextToController(String text) {
    if (widget.append && widget.controller.text.trim().isNotEmpty) {
      final existing = widget.controller.text.trim();
      widget.controller.text = '$existing $text';
    } else {
      widget.controller.text = text;
    }
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: widget.controller.text.length),
    );
  }

  String _formatTimer(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildLanguagePill({
    required String id,
    required String flag,
    required String title,
    required String example,
  }) {
    final isSelected = _selectedLanguage == id;
    final isLight = AppColors.isLight;

    return InkWell(
      onTap: _isListening || _isTranscribing ? null : () => setState(() => _selectedLanguage = id),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: isLight ? 0.2 : 0.18)
              : (isLight ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(flag, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected
                        ? (isLight ? AppColors.primaryDark : Colors.white)
                        : (isLight ? AppColors.textSecondaryLight : Colors.white70),
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                Text(
                  example,
                  style: TextStyle(
                    color: isLight ? AppColors.textTertiary : Colors.white38,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = AppColors.isLight;

    return AlertDialog(
      backgroundColor: isLight ? AppColors.surfaceLight : AppColors.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: isLight ? AppColors.cardBorderLight : AppColors.cardBorderDark,
          width: 1,
        ),
      ),
      contentPadding: const EdgeInsets.all(22),
      content: SizedBox(
        width: 390,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Header: Field Name & Settings
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.mic_rounded, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.fieldLabel != null
                              ? 'Voice: ${widget.fieldLabel}'
                              : 'Voice-to-Text',
                          style: AppTextStyles.labelLarge.copyWith(
                            color: isLight ? AppColors.textPrimaryLight : AppColors.textPrimaryDark,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Same high-accuracy speech engine as DSR',
                          style: TextStyle(
                            color: isLight ? AppColors.textSecondaryLight : AppColors.textTertiaryDark,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.settings_rounded, size: 20),
                      tooltip: 'Voice Settings (Groq / OpenAI Key)',
                      color: isLight ? AppColors.textTertiary : Colors.white54,
                      onPressed: () => WhisperSettingsDialog.show(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 22),
                      color: isLight ? AppColors.textTertiary : Colors.white54,
                      onPressed: () {
                        _recordTimer?.cancel();
                        _speechRecognition.stop();
                        _audioRecorder.stop();
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Engine Selector Tabs (Exact same as DSR)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isLight ? Colors.black.withValues(alpha: 0.05) : AppColors.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isLight ? AppColors.cardBorderLight : AppColors.divider,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _isListening || _isTranscribing
                          ? null
                          : () => setState(() => _useWhisperEngine = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _useWhisperEngine ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 13,
                              color: _useWhisperEngine ? Colors.white : (isLight ? AppColors.textSecondaryLight : Colors.white70),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Whisper AI (Extreme)',
                              style: TextStyle(
                                color: _useWhisperEngine ? Colors.white : (isLight ? AppColors.textSecondaryLight : Colors.white70),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: _isListening || _isTranscribing
                          ? null
                          : () => setState(() => _useWhisperEngine = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: !_useWhisperEngine ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.mic,
                              size: 13,
                              color: !_useWhisperEngine ? Colors.white : (isLight ? AppColors.textSecondaryLight : Colors.white70),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Live Dictation',
                              style: TextStyle(
                                color: !_useWhisperEngine ? Colors.white : (isLight ? AppColors.textSecondaryLight : Colors.white70),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
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
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildLanguagePill(
                  id: 'hindi',
                  flag: '🇮🇳',
                  title: 'हिन्दी (Hindi)',
                  example: '50 बैग सीमेंट लगा',
                ),
                _buildLanguagePill(
                  id: 'hinglish',
                  flag: '🇮🇳',
                  title: 'Hinglish',
                  example: '50 bag cement laga',
                ),
                _buildLanguagePill(
                  id: 'english',
                  flag: '🇬🇧',
                  title: 'English',
                  example: '50 bags cement used',
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Dynamic Status Text
            Text(
              _isTranscribing
                  ? '⚡ Groq Whisper converting speech to text...'
                  : (_isListening
                      ? '🔴 Recording... Boliye'
                      : 'Tap Mic to Start Speaking'),
              style: AppTextStyles.h4.copyWith(
                color: _isListening
                    ? Colors.redAccent
                    : (isLight ? AppColors.textPrimaryLight : AppColors.textPrimaryDark),
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),

            Text(
              _isListening
                  ? 'Duration: ${_formatTimer(_recordDurationSeconds)} — Tap button again when done'
                  : (_useWhisperEngine
                      ? 'Groq Whisper turbo engine • Sub-second transcription'
                      : 'Live word-by-word streaming dictation'),
              style: AppTextStyles.bodySmall.copyWith(
                color: _isListening ? Colors.redAccent : AppColors.textTertiary,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),

            // DSR Large Circular Mic Button
            GestureDetector(
              onTap: _isTranscribing
                  ? null
                  : () {
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
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.redAccent.withValues(alpha: 0.2),
                      ),
                    ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
                          begin: const Offset(1.0, 1.0),
                          end: const Offset(1.22, 1.22),
                          duration: 800.ms,
                        ),
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _isListening
                          ? const LinearGradient(colors: [Colors.redAccent, Colors.red])
                          : AppColors.primaryGradient,
                      boxShadow: [
                        BoxShadow(
                          color: (_isListening ? Colors.red : AppColors.primary).withValues(alpha: 0.4),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: _isTranscribing
                        ? const Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                            ),
                          )
                        : Icon(
                            _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                            color: Colors.white,
                            size: 38,
                          ),
                  ),
                ],
              ),
            ),

            // Live Spoken Buffer Preview (if streaming live dictation)
            if (_liveSpokenBuffer.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isLight ? const Color(0xFFE0F2FE) : const Color(0xFF0F2347),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isLight ? const Color(0xFFBAE6FD) : AppColors.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  _liveSpokenBuffer,
                  style: TextStyle(
                    fontSize: 12,
                    color: isLight ? const Color(0xFF0369A1) : Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            const SizedBox(height: 18),

            // Bottom Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _recordTimer?.cancel();
                      _speechRecognition.stop();
                      _audioRecorder.stop();
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(
                        color: isLight ? AppColors.cardBorderLight : AppColors.cardBorderDark,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: isLight ? AppColors.textSecondaryLight : AppColors.textSecondaryDark,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                if (_liveSpokenBuffer.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _applyTextToController(_liveSpokenBuffer.trim());
                        widget.onComplete?.call();
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Apply Text',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
