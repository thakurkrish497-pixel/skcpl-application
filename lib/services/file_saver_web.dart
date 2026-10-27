// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> saveAndOpenFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? shareTitle,
}) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  // Delay revoking the object URL so the browser has time to initialize download
  Future.delayed(const Duration(seconds: 10), () {
    html.Url.revokeObjectUrl(url);
  });
}
