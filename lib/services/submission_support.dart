import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Only transport failures belong in the automatic retry queue.
bool isRetryableSubmissionError(Object error) {
  if (error is TimeoutException || error is ClientException) return true;
  if (error is StorageException) {
    final code = int.tryParse(error.statusCode ?? '');
    return code == 408 || code == 429 || (code != null && code >= 500);
  }
  if (error is PostgrestException) {
    return ['408', '429', '500', '502', '503', '504'].contains(error.code);
  }
  final name = error.runtimeType.toString();
  return name == 'SocketException' ||
      name == 'ClientException' ||
      name == 'HandshakeException';
}

String submissionId(String? id) {
  final candidate = id?.replaceFirst(RegExp(r'^offline_(cash|stock)_'), '');
  if (candidate != null &&
      RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
          .hasMatch(candidate)) {
    return candidate;
  }
  return const Uuid().v4();
}

/// Local-only attachment payload. Never send bytes to a database table.
class PendingPhoto {
  final Uint8List bytes;
  final String name;
  const PendingPhoto({required this.bytes, required this.name});
  Map<String, dynamic> toJson() => {'name': name, 'bytes': base64Encode(bytes)};
  factory PendingPhoto.fromJson(Map<String, dynamic> json) => PendingPhoto(
        name: json['name'] as String,
        bytes: base64Decode(json['bytes'] as String),
      );
}

/// Only an unavailable legacy schema may route writes to the compatibility table.
bool isSchemaUnavailable(Object error) =>
    error is PostgrestException &&
    const ['42P01', '42703', 'PGRST204', 'PGRST205'].contains(error.code);
