import 'dart:typed_data';
import 'file_saver_stub.dart'
    if (dart.library.html) 'file_saver_web.dart'
    if (dart.library.io) 'file_saver_io.dart';

class FileSaverHelper {
  static const String excelMimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  static Future<void> saveAndOpen({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? shareTitle,
  }) async {
    await saveAndOpenFile(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      shareTitle: shareTitle,
    );
  }
}
