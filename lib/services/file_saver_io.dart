import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

Future<void> saveAndOpenFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? shareTitle,
}) async {
  // 1. Write to cache directory where Android FileProvider has explicit URI permissions
  final cacheDir = await getTemporaryDirectory();
  final filePath = '${cacheDir.path}/$fileName';
  final file = File(filePath);
  await file.writeAsBytes(bytes, flush: true);

  // 2. Also write to external documents directory so user keeps a permanent copy on Android
  try {
    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final persistentFile = File('${extDir.path}/$fileName');
        await persistentFile.writeAsBytes(bytes, flush: true);
        debugPrint('Saved permanent copy to: ${persistentFile.path}');
      }
    }
  } catch (e) {
    debugPrint('Permanent save copy note: $e');
  }

  // 3. Immediately launch the spreadsheet in the device's default viewer (Excel / Sheets / WPS)
  try {
    final openResult = await OpenFilex.open(filePath);
    debugPrint('OpenFilex result: ${openResult.type} - ${openResult.message}');
  } catch (e) {
    debugPrint('OpenFilex error: $e');
  }

  // 4. Launch the native Android Share sheet (WhatsApp, Gmail, Drive, Bluetooth, etc.)
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath, mimeType: mimeType, name: fileName)],
        subject: shareTitle ?? fileName,
        text: 'SKCPL Site Report: $fileName',
      ),
    );
  } catch (e) {
    debugPrint('SharePlus error: $e');
  }
}
