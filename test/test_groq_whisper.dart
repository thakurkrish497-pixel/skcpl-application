import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

Uint8List createWavBytes(int durationSeconds) {
  final sampleRate = 16000;
  final numChannels = 1;
  final bytesPerSample = 2; // 16-bit
  final numSamples = sampleRate * durationSeconds;
  final dataSize = numSamples * numChannels * bytesPerSample;
  final totalSize = 36 + dataSize;

  final b = ByteData(44 + dataSize);
  // 'RIFF'
  b.setUint8(0, 0x52); b.setUint8(1, 0x49); b.setUint8(2, 0x46); b.setUint8(3, 0x46);
  b.setUint32(4, totalSize, Endian.little);
  // 'WAVE'
  b.setUint8(8, 0x57); b.setUint8(9, 0x41); b.setUint8(10, 0x56); b.setUint8(11, 0x45);
  // 'fmt '
  b.setUint8(12, 0x66); b.setUint8(13, 0x6D); b.setUint8(14, 0x74); b.setUint8(15, 0x20);
  b.setUint32(16, 16, Endian.little); // subchunk1size (16 for PCM)
  b.setUint16(20, 1, Endian.little); // audio format (1 = PCM)
  b.setUint16(22, numChannels, Endian.little);
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * numChannels * bytesPerSample, Endian.little); // byte rate
  b.setUint16(32, numChannels * bytesPerSample, Endian.little); // block align
  b.setUint16(34, bytesPerSample * 8, Endian.little); // bits per sample
  // 'data'
  b.setUint8(36, 0x64); b.setUint8(37, 0x61); b.setUint8(38, 0x74); b.setUint8(39, 0x61);
  b.setUint32(40, dataSize, Endian.little);

  return b.buffer.asUint8List();
}

void main() {
  test('Test Groq Whisper transcription API with user key', () async {
    final apiKey = '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';
    final uri = Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions');

    final wav = createWavBytes(2); // 2 second wav
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer $apiKey';
    req.fields['model'] = 'whisper-large-v3-turbo';
    req.fields['language'] = 'hi';
    req.fields['prompt'] = 'Construction site daily report';
    req.files.add(http.MultipartFile.fromBytes('file', wav, filename: 'test.wav'));

    final sResp = await req.send();
    final resp = await http.Response.fromStream(sResp);

    print('Groq Whisper response status: ${resp.statusCode}');
    print('Groq Whisper response body: ${resp.body}');

    expect(resp.statusCode, equals(200));
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    expect(decoded.containsKey('text'), isTrue);
    print('SUCCESS: Groq Whisper transcription API is fully operational!');
  });
}
