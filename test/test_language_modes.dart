import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skcpl_app/services/whisper_service.dart';

void main() {
  for (final mode in ['english', 'hindi', 'hinglish', 'auto']) {
    test('Whisper language mode: $mode', () async {
      final service = WhisperService(MockClient((request) async {
        if (mode == 'english' || mode == 'hindi') {
          expect(request.body, contains('name="language"'));
        }
        if (mode == 'auto' || mode == 'hinglish') {
          expect(request.body, isNot(contains('name="language"')));
        }
        return http.Response('{"text":"fixture transcription"}', 200);
      }));
      await service.saveApiKey('fixture-key');
      expect(
          await service.transcribeAudio(
              audioBytes: Uint8List.fromList([1]),
              fileName: 'fixture.m4a',
              lang: mode),
          'fixture transcription');
    });
  }
}
