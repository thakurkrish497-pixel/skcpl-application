import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

Future<String> transcribe({
  required List<int> audioBytes,
  String? language,
  String? prompt,
}) async {
  final apiKey = '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';
  final uri = Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions');

  final req = http.MultipartRequest('POST', uri);
  req.headers['Authorization'] = 'Bearer $apiKey';
  req.fields['model'] = 'whisper-large-v3-turbo';
  req.fields['response_format'] = 'json';
  if (language != null) {
    req.fields['language'] = language;
  }
  if (prompt != null) {
    req.fields['prompt'] = prompt;
  }
  req.files.add(http.MultipartFile.fromBytes('file', audioBytes, filename: 'test.m4a'));

  final sResp = await req.send();
  final resp = await http.Response.fromStream(sResp);
  final body = jsonDecode(resp.body);
  return body['text'] as String;
}

void main() {
  test('Groq Whisper Language Modes on English Audio', () async {
    final enBytes = await File('/Users/saketkumar/.gemini/antigravity-ide/brain/a43d21d5-fcc3-45a8-94bf-5a99cab6f508/scratch/english_test.m4a').readAsBytes();

    final resHinglish = await transcribe(
      audioBytes: enBytes,
      prompt: 'Aaj site par 50 bag cement laga hai, footing complete hua. Shuttering, sariya, labour.',
    );
    print('English Audio transcribed in Hinglish mode: $resHinglish');

    final resEnglish = await transcribe(
      audioBytes: enBytes,
      language: 'en',
      prompt: 'Today site work report: cement bags, concrete, footing, shuttering, labour.',
    );
    print('English Audio transcribed in English mode: $resEnglish');
  });
}
