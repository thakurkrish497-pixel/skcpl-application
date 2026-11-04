import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final srcFile = File('assets/images/skcpl_logo_transparent.png');
  final srcBytes = srcFile.readAsBytesSync();
  final logo = img.decodePng(srcBytes);

  if (logo == null) {
    print('Failed to decode logo');
    return;
  }

  print('Loaded logo: ${logo.width}x${logo.height}');

  // 1. Generate master app_icon.png (1024x1024) with brand dark navy #0B1528 background
  // Safe zone for iOS squircle and Android legacy icons: logo ~750x750 (center 73%)
  final appIcon = img.Image(width: 1024, height: 1024);
  // Fill background with #0B1528
  img.fill(appIcon, color: img.ColorRgba8(11, 21, 40, 255));

  // Add subtle brand gradient/glow in center
  final centerLogo = img.copyResize(logo, width: 750, height: 750, interpolation: img.Interpolation.cubic);
  final offsetX = (1024 - centerLogo.width) ~/ 2;
  final offsetY = (1024 - centerLogo.height) ~/ 2;

  img.compositeImage(appIcon, centerLogo, dstX: offsetX, dstY: offsetY);
  File('assets/images/app_icon.png').writeAsBytesSync(img.encodePng(appIcon));
  print('Saved assets/images/app_icon.png');

  // 2. Generate adaptive icon foreground (1024x1024) with transparent background
  // Android Adaptive icon safe zone is 66% (675x675)
  final fgIcon = img.Image(width: 1024, height: 1024, numChannels: 4);
  img.fill(fgIcon, color: img.ColorRgba8(0, 0, 0, 0)); // transparent

  final adaptiveLogo = img.copyResize(logo, width: 660, height: 660, interpolation: img.Interpolation.cubic);
  final fgOffsetX = (1024 - adaptiveLogo.width) ~/ 2;
  final fgOffsetY = (1024 - adaptiveLogo.height) ~/ 2;

  img.compositeImage(fgIcon, adaptiveLogo, dstX: fgOffsetX, dstY: fgOffsetY);
  File('assets/images/app_icon_foreground.png').writeAsBytesSync(img.encodePng(fgIcon));
  print('Saved assets/images/app_icon_foreground.png');

  print('Done!');
}

