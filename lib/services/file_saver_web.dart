import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<void> saveAndOpenFile(
    {required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? shareTitle}) async {
  final blob =
      web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Future<void>.delayed(
      const Duration(seconds: 10), () => web.URL.revokeObjectURL(url));
}
