import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skcpl_app/widgets/offline_indicator.dart';
import 'package:skcpl_app/services/offline_service.dart';
import 'sync_safety_test.dart' show cash;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:skcpl_app/widgets/photo_picker.dart';

class FixturePhoto extends XFile {
  FixturePhoto()
      : super.fromData(base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aF1sAAAAASUVORK5CYII='));
  @override
  String get name => 'fixture.png';
}

class FixturePicker extends ImagePicker {
  final ImageSource expected;
  bool called = false;
  FixturePicker(this.expected);
  @override
  Future<XFile?> pickImage(
      {required ImageSource source,
      double? maxWidth,
      double? maxHeight,
      int? imageQuality,
      CameraDevice preferredCameraDevice = CameraDevice.rear,
      bool requestFullMetadata = true}) async {
    expect(source, expected);
    called = true;
    return FixturePhoto();
  }
}

void main() {
  for (final source in [ImageSource.camera, ImageSource.gallery]) {
    testWidgets('Receipt attachment from ${source.name} preserves photo bytes',
        (tester) async {
      final picker = FixturePicker(source);
      List<PickedPhoto> selected = [];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PhotoPickerWidget(
                  picker: picker,
                  onPhotosChanged: (photos) => selected = photos))));
      await tester.tap(find.text('Camera / File'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(source == ImageSource.camera
          ? 'Take Photo with Camera'
          : 'Choose from Phone Gallery'));
      await tester.pumpAndSettle();
      expect(picker.called, true);
      expect(selected.single.bytes, isNotEmpty);
      expect(selected.single.name, 'fixture.png');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
    testWidgets(
        'Native $platform receipt picker uses files instead of unsupported camera',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final picker = FixturePicker(ImageSource.gallery);
      List<PickedPhoto> selected = [];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PhotoPickerWidget(
                  picker: picker,
                  onPhotosChanged: (photos) => selected = photos))));
      await tester.tap(find.text('Camera / File'));
      await tester.pumpAndSettle();
      expect(find.text('Take Photo with Camera'), findsNothing);
      await tester.tap(find.text('Choose Image File'));
      await tester.pumpAndSettle();
      expect(picker.called, isTrue);
      expect(selected.single.name, 'fixture.png');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
  testWidgets('Locked attachments never expose camera or gallery actions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body:
                PhotoPickerWidget(isReadOnly: true, onPhotosChanged: (_) {}))));
    expect(find.text('Camera / File'), findsNothing);
  });
  testWidgets(
      'Legacy stock-form sync indicator updates immediately when an entry is queued',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: OfflineSyncButton()))));
    await tester.pump(const Duration(milliseconds: 1));
    await OfflineService.queueCashTransaction(cash());
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Sync (1)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
