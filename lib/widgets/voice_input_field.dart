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

/// Reusable Voice-to-Text Microphone icon button that connects to any TextEditingController.
/// Supports both:
/// 1. Built-in Browser Live Dictation (100% Free, Zero API Key Required).
/// 2. Groq / OpenAI Whisper AI (for extreme accuracy & Desktop runners).
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
      tooltip: 'Voice to Text (Boliye Hindi / English)',
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

/// Dialog presenting interactive voice dictation
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

  bool _useLiveDictation = true; // Default to free browser dictation when supported
  bool _isRecording = false;
  bool _isTranscribing = false;
  int _durationSeconds = 0;
  Timer? _timer;
  String _selectedLanguage = 'hindi'; // 'hindi' | 'hinglish' | 'english'
  String _liveSpokenBuffer = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _speechRecognition = createSpeechRecognition();
    _audioRecorder = AudioRecorder();

    // If browser speech recognition is not supported (e.g. desktop native), default to Whisper
    _useLiveDictation = _speechRecognition.isSupported;

    // Auto-start recording as soon as the dialog pops up for frictionless voice entry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startVoiceInput();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _speechRecognition.stop();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _startVoiceInput() {
    if (_useLiveDictation && _speechRecognition.isSupported) {
      _startLiveSpeechRecognition();
    } else {
      _startWhisperAudioRecording();
    }
  }

  void _stopVoiceInput() {
    if (_useLiveDictation && _speechRecognition.isSupported) {
      _stopLiveSpeechRecognition();
    } else {
      _stopWhisperAudioRecordingAndTranscribe();
    }
  }

  // ── 1. Free Browser Live Speech Recognition (No API Key Required) ──
  void _startLiveSpeechRecognition() {
    setState(() {
      _errorMessage = null;
      _liveSpokenBuffer = '';
      _isRecording = true;
      _durationSeconds = 0;
    });

    final langTag = _selectedLanguage == 'hindi'
        ? 'hi-IN'
        : (_selectedLanguage == 'english' ? 'en-US' : 'en-IN');

    try {
      _speechRecognition.start(
        lang: langTag,
        onResult: (text, isFinal) {
          if (mounted) {
            setState(() {
              _liveSpokenBuffer = text;
            });
          }
        },
        onEnd: () {
          if (mounted) {
            setState(() {
              _isRecording = false;
            });
          }
        },
        onError: (err) {
          if (mounted) {
            setState(() {
              _isRecording = false;
              _errorMessage = err;
            });
          }
        },
      );

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) setState(() => _durationSeconds++);
      });
    } catch (e) {
      setState(() {
        _isRecording = false;
        _errorMessage = 'Could not start live dictation: $e';
      });
    }
  }

  void _stopLiveSpeechRecognition() {
    _timer?.cancel();
    _speechRecognition.stop();
    setState(() => _isRecording = false);

    if (_liveSpokenBuffer.trim().isNotEmpty) {
      _applyTextToController(_liveSpokenBuffer.trim());
      widget.onComplete?.call();
      Navigator.pop(context);
    } else {
      setState(() {
        _errorMessage = 'No speech detected. Please speak into your microphone.';
      });
    }
  }

  // ── 2. Whisper Cloud AI Audio Recording ──
  Future<void> _startWhisperAudioRecording() async {
    final apiKey = await _whisperService.getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      setState(() {
        _isRecording = false;
        _errorMessage = 'Whisper API key not set. Please configure your free Groq key or use Live Dictation.';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _liveSpokenBuffer = '';
    });

    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        setState(() {
          _errorMessage = 'Microphone permission denied. Please allow microphone access in browser settings.';
        });
        return;
      }

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
        _isRecording = true;
        _durationSeconds = 0;
      });

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) setState(() => _durationSeconds++);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _errorMessage = 'Recording error: $e';
        });
      }
    }
  }

  Future<void> _stopWhisperAudioRecordingAndTranscribe() async {
    _timer?.cancel();
    setState(() {
      _isRecording = false;
      _isTranscribing = true;
      _errorMessage = null;
    });

    try {
      final path = await _audioRecorder.stop();
      if (path == null) {
        throw Exception('No audio captured. Please speak into the microphone.');
      }

      Uint8List? bytes;
      if (kIsWeb) {
        final response = await http.get(Uri.parse(path));
        bytes = response.bodyBytes;
      } else {
        final file = File(path);
        if (await file.exists()) {
          bytes = await file.readAsBytes();
          try {
            await file.delete();
          } catch (_) {}
        }
      }

      if (bytes == null || bytes.isEmpty) {
        throw Exception('Audio file empty. Please try speaking again.');
      }

      final transcript = await _whisperService.transcribeAudio(
        audioBytes: bytes,
        fileName: kIsWeb ? 'audio.webm' : 'audio.m4a',
        lang: _selectedLanguage,
      );

      if (mounted) {
        setState(() {
          _liveSpokenBuffer = transcript.trim();
          _isTranscribing = false;
        });

        if (_liveSpokenBuffer.isNotEmpty) {
          _applyTextToController(_liveSpokenBuffer);
          widget.onComplete?.call();
          Navigator.pop(context);
        } else {
          setState(() {
            _errorMessage = 'No speech detected. Please speak clearly into the microphone.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTranscribing = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
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

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isLight = AppColors.isLight;
    final isWebDictationAvailable = _speechRecognition.isSupported;

    return AlertDialog(
      backgroundColor: isLight ? AppColors.surfaceLight : AppColors.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isLight ? AppColors.cardBorderLight : AppColors.cardBorderDark,
          width: 1,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      content: SizedBox(
        width: 370,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.mic_rounded,
                      color: _isRecording ? Colors.redAccent : AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.fieldLabel != null
                          ? 'Voice: ${widget.fieldLabel}'
                          : 'Voice to Text',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: isLight ? AppColors.textPrimaryLight : AppColors.textPrimaryDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.settings_rounded, size: 18),
                      tooltip: 'Configure Whisper AI Key',
                      color: AppColors.textTertiary,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => WhisperSettingsDialog.show(context),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: AppColors.textTertiary,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        _timer?.cancel();
                        _speechRecognition.stop();
                        _audioRecorder.stop();
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Mode Selector: Live Dictation (Free) vs Whisper AI
            if (isWebDictationAvailable) ...[
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isLight ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _isRecording || _isTranscribing
                            ? null
                            : () {
                                setState(() {
                                  _useLiveDictation = true;
                                  _errorMessage = null;
                                });
                              },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: _useLiveDictation
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Live (No Key)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: _useLiveDictation ? FontWeight.bold : FontWeight.normal,
                                color: _useLiveDictation
                                    ? Colors.white
                                    : (isLight ? AppColors.textSecondaryLight : Colors.white60),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: _isRecording || _isTranscribing
                            ? null
                            : () {
                                setState(() {
                                  _useLiveDictation = false;
                                  _errorMessage = null;
                                });
                              },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: !_useLiveDictation
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Whisper AI',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: !_useLiveDictation ? FontWeight.bold : FontWeight.normal,
                                color: !_useLiveDictation
                                    ? Colors.white
                                    : (isLight ? AppColors.textSecondaryLight : Colors.white60),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Language Selector Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _LanguageChip(
                    label: '🇮🇳 Hindi (हिंदी)',
                    isSelected: _selectedLanguage == 'hindi',
                    onTap: _isRecording || _isTranscribing
                        ? null
                        : () => setState(() => _selectedLanguage = 'hindi'),
                  ),
                  const SizedBox(width: 6),
                  _LanguageChip(
                    label: 'Hinglish',
                    isSelected: _selectedLanguage == 'hinglish',
                    onTap: _isRecording || _isTranscribing
                        ? null
                        : () => setState(() => _selectedLanguage = 'hinglish'),
                  ),
                  const SizedBox(width: 6),
                  _LanguageChip(
                    label: 'English',
                    isSelected: _selectedLanguage == 'english',
                    onTap: _isRecording || _isTranscribing
                        ? null
                        : () => setState(() => _selectedLanguage = 'english'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Main Visual Status & Circular Mic Button
            GestureDetector(
              onTap: _isTranscribing
                  ? null
                  : () {
                      if (_isRecording) {
                        _stopVoiceInput();
                      } else {
                        _startVoiceInput();
                      }
                    },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_isRecording)
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.redAccent.withValues(alpha: 0.18),
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(begin: const Offset(1, 1), end: const Offset(1.25, 1.25)),

                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _isRecording
                          ? const LinearGradient(
                              colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                            )
                          : const LinearGradient(
                              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                            ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isRecording ? Colors.redAccent : AppColors.primary)
                              .withValues(alpha: 0.4),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isTranscribing
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.8,
                              ),
                            )
                          : Icon(
                              _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                              size: 38,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Live Spoken / Recording Label
            Text(
              _isTranscribing
                  ? '⚡ Converting speech to text...'
                  : (_isRecording
                      ? '🔴 Recording... Boliye'
                      : 'Tap Mic to Start Speaking'),
              style: AppTextStyles.h4.copyWith(
                color: _isRecording
                    ? Colors.redAccent
                    : (isLight ? AppColors.textPrimaryLight : AppColors.textPrimaryDark),
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),

            Text(
              _isRecording
                  ? 'Time: ${_formatDuration(_durationSeconds)} • Tap button when done'
                  : (_useLiveDictation
                      ? 'Free browser speech recognition active'
                      : 'Groq/OpenAI cloud speech engine'),
              style: AppTextStyles.bodySmall.copyWith(
                color: _isRecording ? Colors.redAccent : AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),

            // Live Spoken Text Preview Box
            if (_liveSpokenBuffer.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isLight ? const Color(0xFFE0F2FE) : const Color(0xFF0F2347),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isLight ? const Color(0xFFBAE6FD) : AppColors.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  _liveSpokenBuffer,
                  style: TextStyle(
                    fontSize: 13,
                    color: isLight ? AppColors.textPrimaryLight : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.rejected.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.rejected.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: AppColors.rejected, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: AppColors.rejected, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    if (!_useLiveDictation && isWebDictationAvailable) ...[
                      const SizedBox(height: 6),
                      TextButton.icon(
                        icon: const Icon(Icons.swap_horiz_rounded, size: 14),
                        label: const Text('Switch to Free Live Dictation (No Key)', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          setState(() {
                            _useLiveDictation = true;
                            _errorMessage = null;
                          });
                          _startVoiceInput();
                        },
                      ),
                    ],
                    if (!_useLiveDictation) ...[
                      const SizedBox(height: 4),
                      TextButton.icon(
                        icon: const Icon(Icons.key_rounded, size: 14),
                        label: const Text('Enter Free Groq / OpenAI Key', style: TextStyle(fontSize: 11)),
                        onPressed: () => WhisperSettingsDialog.show(context),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _timer?.cancel();
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
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isTranscribing
                        ? null
                        : () {
                            if (_isRecording) {
                              _stopVoiceInput();
                            } else {
                              _startVoiceInput();
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isRecording ? Colors.redAccent : AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      _isRecording ? 'Done (बस)' : 'Speak',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  const _LanguageChip({
    required this.label,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (AppColors.isLight ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : (AppColors.isLight ? AppColors.textPrimaryLight : Colors.white70),
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
