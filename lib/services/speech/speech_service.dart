import 'speech_service_stub.dart'
    if (dart.library.html) 'speech_service_web.dart' as impl;

abstract class SpeechRecognitionBase {
  bool get isSupported;
  bool get isListening;

  void start({
    String lang = 'hi-IN',
    required Function(String text, bool isFinal) onResult,
    required Function() onEnd,
    required Function(String error) onError,
  });

  void stop();
}

/// Factory returning platform implementation of live speech recognition
SpeechRecognitionBase createSpeechRecognition() => impl.createSpeechRecognition();
