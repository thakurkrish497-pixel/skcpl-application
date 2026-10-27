import 'dart:typed_data';

Future<void> saveAndOpenFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? shareTitle,
}) async {
  throw UnsupportedError('Platform not supported for file saving');
}
