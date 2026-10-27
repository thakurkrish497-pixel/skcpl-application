import 'speech_service.dart';

class SpeechRecognitionStub implements SpeechRecognitionBase {
  @override
  bool get isSupported => false;

  @override
  bool get isListening => false;

  @override
  void start({
    String lang = 'hi-IN',
    required Function(String text, bool isFinal) onResult,
    required Function() onEnd,
    required Function(String error) onError,
  }) {
    onError('Speech recognition requires Chrome/Edge/Safari on Web or Whisper AI.');
  }

  @override
  void stop() {}
}

SpeechRecognitionBase createSpeechRecognition() => SpeechRecognitionStub();
