import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  final SupabaseClient _client;
  static const String _bucketName = 'transaction_photos';

  StorageService(this._client);

  /// Uploads a photo to Supabase storage and returns the public URL
  Future<String> uploadPhoto(File photo) async {
    final fileName = '${const Uuid().v4()}.jpg';
    final path = 'photos/$fileName';

    await _client.storage.from(_bucketName).upload(path, photo);

    // Get the public URL for the uploaded photo
    return _client.storage.from(_bucketName).getPublicUrl(path);
  }

  /// Deletes a photo from Supabase storage using its URL
  Future<void> deletePhoto(String photoUrl) async {
    try {
      // Extract the path from the full URL
      // The URL looks like: https://[project_id].supabase.co/storage/v1/object/public/transaction_photos/photos/[file_name].jpg
      final uri = Uri.parse(photoUrl);
      final pathSegments = uri.pathSegments;
      
      // Find where the bucket name is in the path
      final bucketIndex = pathSegments.indexOf(_bucketName);
      if (bucketIndex != -1 && bucketIndex < pathSegments.length - 1) {
        // The object path is everything after the bucket name
        final objectPath = pathSegments.sublist(bucketIndex + 1).join('/');
        await _client.storage.from(_bucketName).remove([objectPath]);
      }
    } catch (e) {
      print('Error deleting photo: $e');
    }
  }
}
