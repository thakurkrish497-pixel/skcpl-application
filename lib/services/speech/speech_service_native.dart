import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'speech_service.dart';

class SpeechRecognitionNative implements SpeechRecognitionBase {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;

  @override
  bool get isSupported => true;

  @override
  bool get isListening => _isListening;

  @override
  void start({
    String lang = 'hi-IN',
    required Function(String text, bool isFinal) onResult,
    required Function() onEnd,
    required Function(String error) onError,
  }) async {
    try {
      if (!_isInitialized) {
        _isInitialized = await _speech.initialize(
          onError: (val) {
            _isListening = false;
            onError(val.errorMsg);
          },
          onStatus: (val) {
            if (val == 'done' || val == 'notListening') {
              _isListening = false;
              onEnd();
            }
          },
        );
      }

      if (!_isInitialized) {
        onError('Speech recognition not available or microphone permission denied.');
        return;
      }

      // Format locale for Android/iOS: e.g. 'hi-IN' -> 'hi_IN'
      final localeId = lang.replaceAll('-', '_');

      _isListening = true;
      await _speech.listen(
        onResult: (result) {
          onResult(result.recognizedWords, result.finalResult);
        },
        localeId: localeId,
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 4),
        cancelOnError: false,
        partialResults: true,
      );
    } catch (e) {
      _isListening = false;
      onError('Speech recognition error: $e');
    }
  }

  @override
  void stop() async {
    _isListening = false;
    try {
      await _speech.stop();
    } catch (_) {}
  }
}

SpeechRecognitionBase createSpeechRecognition() => SpeechRecognitionNative();

