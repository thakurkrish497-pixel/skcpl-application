import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skcpl_app/services/whisper_service.dart';

void main() {
  test('Whisper returns a transcription and never embeds a real API key',
      () async {
    final service = WhisperService(MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer fixture-key');
      expect(request.body, contains('whisper-large-v3-turbo'));
      return http.Response(jsonEncode({'text': 'Footing completed'}), 200);
    }));
    await service.saveApiKey('fixture-key');
    expect(
        await service.transcribeAudio(
            audioBytes: Uint8List.fromList([1, 2]), fileName: 'fixture.wav'),
        'Footing completed');
  });
  test('Whisper reports invalid credentials without accepting an empty result',
      () async {
    final service =
        WhisperService(MockClient((_) async => http.Response('{}', 401)));
    await service.saveApiKey('fixture-key');
    await expectLater(
        service.transcribeAudio(
            audioBytes: Uint8List.fromList([1]), fileName: 'fixture.wav'),
        throwsException);
  });
}
