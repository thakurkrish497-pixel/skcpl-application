// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'speech_service.dart';

class SpeechRecognitionWeb implements SpeechRecognitionBase {
  html.SpeechRecognition? _recognition;
  bool _isListening = false;

  @override
  bool get isSupported => html.SpeechRecognition.supported;

  @override
  bool get isListening => _isListening;

  @override
  void start({
    String lang = 'hi-IN',
    required Function(String text, bool isFinal) onResult,
    required Function() onEnd,
    required Function(String error) onError,
  }) {
    if (!isSupported) {
      onError('Live speech recognition is not supported in this browser.');
      return;
    }

    stop();

    try {
      final recognition = html.SpeechRecognition();
      _recognition = recognition;
      recognition.continuous = true;
      recognition.interimResults = true;
      recognition.lang = lang;

      recognition.onResult.listen((event) {
        final results = event.results;
        if (results != null) {
          String combined = '';
          bool anyFinal = false;
          for (var i = 0; i < results.length; i++) {
            final res = results[i];
            final alt = res.item(0);
            if (alt.transcript != null) {
              combined += '${alt.transcript!} ';
              // ignore: unnecessary_null_comparison
              if (res.isFinal == true) anyFinal = true;
            }
          }
          onResult(combined.trim(), anyFinal);
        }
      });

      recognition.onError.listen((event) {
        _isListening = false;
        onError(event.toString());
      });

      recognition.onEnd.listen((_) {
        _isListening = false;
        onEnd();
      });

      recognition.start();
      _isListening = true;
    } catch (e) {
      _isListening = false;
      onError(e.toString());
    }
  }

  @override
  void stop() {
    if (_recognition != null) {
      try {
        _recognition!.stop();
      } catch (_) {}
      _recognition = null;
    }
    _isListening = false;
  }
}

SpeechRecognitionBase createSpeechRecognition() => SpeechRecognitionWeb();
