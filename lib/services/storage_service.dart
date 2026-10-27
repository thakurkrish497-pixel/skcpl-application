import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/supabase_constants.dart';

class StorageService {
  static const String _bucketName = 'transaction_photos';

  // Dedicated client with service role key to ensure workers without auth session can upload photos
  late final SupabaseClient _storageClient;

  StorageService([SupabaseClient? client]) {
    _storageClient = SupabaseClient(
      SupabaseConstants.supabaseUrl,
      SupabaseConstants.supabaseServiceRoleKey,
    );
  }

  /// Uploads photo bytes directly (cross-platform: Web, iOS, Android, macOS)
  Future<String> uploadPhotoBytes(Uint8List bytes, {String? fileName}) async {
    final cleanName = fileName != null && fileName.isNotEmpty
        ? fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        : 'photo.jpg';
    final uniqueName = '${const Uuid().v4()}_$cleanName';
    final path = 'photos/$uniqueName';

    await _storageClient.storage.from(_bucketName).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    return _storageClient.storage.from(_bucketName).getPublicUrl(path);
  }

  /// Uploads a photo object (Uint8List, XFile, or File) and returns the public URL
  Future<String> uploadPhoto(dynamic photo) async {
    if (photo is Uint8List) {
      return uploadPhotoBytes(photo);
    }

    try {
      // Handles XFile or File having readAsBytes()
      final bytes = await photo.readAsBytes() as Uint8List;
      final name = (photo.name != null) ? photo.name.toString() : 'photo.jpg';
      return await uploadPhotoBytes(bytes, fileName: name);
    } catch (_) {
      // Fallback
      final fileName = '${const Uuid().v4()}.jpg';
      final path = 'photos/$fileName';
      await _storageClient.storage.from(_bucketName).upload(
            path,
            photo,
            fileOptions: const FileOptions(upsert: true),
          );
      return _storageClient.storage.from(_bucketName).getPublicUrl(path);
    }
  }

  /// Deletes a photo from Supabase storage using its URL
  Future<void> deletePhoto(String photoUrl) async {
    try {
      final uri = Uri.parse(photoUrl);
      final pathSegments = uri.pathSegments;

      final bucketIndex = pathSegments.indexOf(_bucketName);
      if (bucketIndex != -1 && bucketIndex < pathSegments.length - 1) {
        final objectPath = pathSegments.sublist(bucketIndex + 1).join('/');
        await _storageClient.storage.from(_bucketName).remove([objectPath]);
      }
    } catch (e) {
      // Silently handle deletion error
    }
  }
}
