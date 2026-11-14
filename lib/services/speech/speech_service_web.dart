import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'speech_service.dart';

@JS('SpeechRecognition')
external JSFunction? get _speechConstructor;
@JS('webkitSpeechRecognition')
external JSFunction? get _webkitConstructor;

class SpeechRecognitionWeb implements SpeechRecognitionBase {
  web.SpeechRecognition? _recognition;
  bool _isListening = false;
  @override
  bool get isSupported =>
      _speechConstructor != null || _webkitConstructor != null;
  @override
  bool get isListening => _isListening;
  @override
  void start(
      {String lang = 'hi-IN',
      required Function(String, bool) onResult,
      required Function() onEnd,
      required Function(String) onError}) {
    stop();
    final constructor = _speechConstructor ?? _webkitConstructor;
    if (constructor == null) {
      onError('Live speech recognition is unavailable in this browser.');
      return;
    }
    try {
      final recognition =
          constructor.callAsConstructor<web.SpeechRecognition>();
      _recognition = recognition;
      recognition.continuous = true;
      recognition.interimResults = true;
      recognition.lang = lang;
      recognition.onresult = ((web.Event event) {
        if (_recognition != recognition) return;
        final results = (event as web.SpeechRecognitionEvent).results;
        final text = <String>[];
        var isFinal = false;
        for (var i = 0; i < results.length; i++) {
          final result = results.item(i);
          if (result.length > 0) text.add(result.item(0).transcript);
          isFinal = isFinal || result.isFinal;
        }
        if (text.isNotEmpty) onResult(text.join(' ').trim(), isFinal);
      }).toJS;
      recognition.onerror = ((web.Event event) {
        if (_recognition != recognition) return;
        _isListening = false;
        onError((event as web.SpeechRecognitionErrorEvent).error);
      }).toJS;
      recognition.onend = ((web.Event event) {
        if (_recognition != recognition) return;
        _isListening = false;
        onEnd();
      }).toJS;
      recognition.start();
      _isListening = true;
    } catch (e) {
      _isListening = false;
      onError('$e');
    }
  }

  @override
  void stop() {
    final recognition = _recognition;
    _recognition = null;
    _isListening = false;
    if (recognition != null) {
      recognition.onresult = null;
      recognition.onerror = null;
      recognition.onend = null;
      try {
        recognition.abort();
      } catch (_) {}
    }
  }
}

SpeechRecognitionBase createSpeechRecognition() => SpeechRecognitionWeb();
