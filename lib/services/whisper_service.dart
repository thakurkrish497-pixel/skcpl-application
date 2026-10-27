import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Ultra-accurate Voice-to-Text service utilizing Whisper (Groq / OpenAI).
/// Groq Whisper (whisper-large-v3-turbo) transcribes Indian Hindi/English audio
/// in ~300ms with 99%+ accuracy and zero audio storage required.
class WhisperService {
  static const String _keyGroqApiKey = 'whisper_groq_api_key';
  static const String _keyOpenAiApiKey = 'whisper_openai_api_key';
  static const String _keySelectedProvider = 'whisper_selected_provider'; // 'groq' | 'openai'
  static const String defaultGroqApiKey = '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';


  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = await getProvider();
    if (provider == 'openai') {
      return prefs.getString(_keyOpenAiApiKey);
    }
    final saved = prefs.getString(_keyGroqApiKey);
    if (saved != null && saved.trim().isNotEmpty) {
      return saved;
    }
    return defaultGroqApiKey;
  }

  Future<void> saveApiKey(String key, {String? provider}) async {
    final prefs = await SharedPreferences.getInstance();
    final prov = provider ?? await getProvider();
    if (prov == 'openai') {
      await prefs.setString(_keyOpenAiApiKey, key.trim());
    } else {
      await prefs.setString(_keyGroqApiKey, key.trim());
    }
  }

  Future<String> getProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySelectedProvider) ?? 'groq';
  }

  Future<void> setProvider(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelectedProvider, provider);
  }

  /// Transcribes in-memory audio bytes to text with extreme accuracy.
  /// Preserves the user's spoken language: Hindi, Hinglish, or English without unwanted translation.
  Future<String> transcribeAudio({
    required Uint8List audioBytes,
    required String fileName,
    String lang = 'hindi', // 'hindi' | 'hinglish' | 'english' | 'auto'
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw Exception(
        'Whisper API Key is not configured. Please tap the Settings (gear) icon to enter your free Groq or OpenAI key.',
      );
    }

    final provider = await getProvider();
    final isGroq = provider == 'groq';

    final endpoint = isGroq
        ? Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions')
        : Uri.parse('https://api.openai.com/v1/audio/transcriptions');

    final request = http.MultipartRequest('POST', endpoint);
    request.headers['Authorization'] = 'Bearer ${apiKey.trim()}';

    // Model selection
    request.fields['model'] = isGroq ? 'whisper-large-v3-turbo' : 'whisper-1';
    request.fields['response_format'] = 'json';

    // Language & prompt configuration to PRESERVE spoken language (never force-translate to English)
    final mode = lang.toLowerCase();
    if (mode == 'hindi' || mode == 'hi') {
      // Pure Devanagari Hindi
      request.fields['language'] = 'hi';
      request.fields['prompt'] =
          'आज साइट पर काम हुआ। 50 बैग सीमेंट लगा, फुटिंग कास्टिंग पूरी हुई, '
          'कल शटरिंग करेंगे, सरिया, लेबर, खुदाई, डंपर, ट्रैक्टर, साइट रिपोर्ट।';
    } else if (mode == 'english' || mode == 'en') {
      // English
      request.fields['language'] = 'en';
      request.fields['prompt'] =
          'Today site work report: cement bags, concrete, footing, shuttering, '
          'curing, excavation, reinforcement, labour, supervisor.';
    } else {
      // Hinglish (Roman Hindi) or Auto-detect:
      // DO NOT set language='en'! Setting language='en' forces Whisper to translate Hindi into English.
      // Leaving language omitted and using a Hinglish prompt transcribes verbatim in Hinglish.
      request.fields['prompt'] =
          'Aaj site par kaam hua. 50 bag cement laga, footing casting complete hui, '
          'kal shuttering karenge, sariya, labour, excavation, dumper, tractor, site report.';
    }

    // Determine clean filename for mime type detection
    String resolvedName = fileName;
    if (!resolvedName.contains('.')) {
      resolvedName += '.m4a';
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        audioBytes,
        filename: resolvedName,
      ),
    );

    final streamedResponse = await request.send().timeout(const Duration(seconds: 25));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final text = decoded['text'] as String?;
      if (text != null && text.trim().isNotEmpty) {
        return text.trim();
      }
      return '';
    } else {
      try {
        final errJson = jsonDecode(response.body);
        final errMsg = errJson['error']?['message'] ?? response.body;
        throw Exception('Transcription error (${response.statusCode}): $errMsg');
      } catch (_) {
        throw Exception('Transcription failed (${response.statusCode}): ${response.body}');
      }
    }
  }

  /// Verifies connection and API key validity
  Future<bool> verifyKey(String key, String provider) async {
    try {
      final isGroq = provider == 'groq';
      final endpoint = isGroq
          ? Uri.parse('https://api.groq.com/openai/v1/models')
          : Uri.parse('https://api.openai.com/v1/models');

      final resp = await http.get(
        endpoint,
        headers: {'Authorization': 'Bearer ${key.trim()}'},
      ).timeout(const Duration(seconds: 10));

      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
