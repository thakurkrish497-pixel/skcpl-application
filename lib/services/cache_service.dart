import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CacheStats {
  final int imageCount;
  final int imageBytes;
  final int diskCacheBytes;
  final int offlinePendingCount;
  final int totalPrefKeys;

  const CacheStats({
    required this.imageCount,
    required this.imageBytes,
    required this.diskCacheBytes,
    required this.offlinePendingCount,
    required this.totalPrefKeys,
  });

  String get formattedTotalSize {
    final totalBytes = imageBytes + diskCacheBytes;
    if (totalBytes <= 0) return '0 KB';
    final kb = totalBytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  String get formattedDiskSize {
    if (diskCacheBytes <= 0) return '0 KB';
    final kb = diskCacheBytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Service to manage Android app storage, image cache, and temporary files
class CacheService {
  CacheService._();

  /// Gets current memory & Android disk storage stats
  static Future<CacheStats> getStats() async {
    final imageCache = PaintingBinding.instance.imageCache;
    final imgCount = imageCache.currentSize;
    final imgBytes = imageCache.currentSizeBytes;

    int diskBytes = 0;
    if (!kIsWeb) {
      try {
        final tempDir = await getTemporaryDirectory();
        if (tempDir.existsSync()) {
          await for (final file in tempDir.list(recursive: true, followLinks: false)) {
            if (file is File) {
              diskBytes += await file.length();
            }
          }
        }
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    final stockQueue = prefs.getStringList('offline_stock_queue_v1') ?? prefs.getStringList('offline_queue_stock') ?? [];
    final cashQueue = prefs.getStringList('offline_cash_queue_v1') ?? prefs.getStringList('offline_queue_cash') ?? [];
    final allKeys = prefs.getKeys().length;

    return CacheStats(
      imageCount: imgCount,
      imageBytes: imgBytes,
      diskCacheBytes: diskBytes,
      offlinePendingCount: stockQueue.length + cashQueue.length,
      totalPrefKeys: allKeys,
    );
  }

  /// Clears queued offline transactions
  static Future<void> clearOfflineQueues() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('offline_stock_queue_v1');
    await prefs.remove('offline_cash_queue_v1');
    await prefs.remove('offline_queue_stock');
    await prefs.remove('offline_queue_cash');
  }

  /// Clears Flutter memory image cache completely
  static void clearImageCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  /// Clears Android temp cache directory on phone storage
  static Future<void> clearDiskCache() async {
    if (kIsWeb) return;
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        await for (final entity in tempDir.list(recursive: false)) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Clears cached dropdowns and image memory to reduce app size
  /// Preserves user session and offline transaction queues
  static Future<void> clearDropdownCache() async {
    clearImageCache();
    await clearDiskCache();
    final prefs = await SharedPreferences.getInstance();
    final keysToRemove = prefs.getKeys().where((k) => k.startsWith('cached_dropdown_')).toList();
    for (var key in keysToRemove) {
      await prefs.remove(key);
    }
  }

  /// Clears temporary app cache (memory, disk temp files, and cached dropdown data)
  /// Safely preserves all offline transaction queues, language preferences, theme settings, credentials, and audit logs.
  static Future<void> clearAllTemporaryData() async {
    clearImageCache();
    await clearDiskCache();
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList();

    const protectedExactKeys = {
      'app_language_code',
      'theme_mode',
      'app_theme',
      'skcpl_role_permissions_config',
      'whisper_api_key',
      'whisper_endpoint',
      'whisper_mode',
      'offline_stock_queue_v1',
      'offline_cash_queue_v1',
      'offline_queue_stock',
      'offline_queue_cash',
    };

    for (var k in keys) {
      if (protectedExactKeys.contains(k)) continue;
      if (k.startsWith('offline_')) continue;
      if (k.startsWith('audit_')) continue;
      if (k.startsWith('auth_')) continue;
      if (k.startsWith('site_announcement')) continue;
      if (k.startsWith('cached_site_staff')) continue;

      // Only delete temporary cached items
      if (k.startsWith('cached_') || k.startsWith('temp_') || k.startsWith('preview_')) {
        await prefs.remove(k);
      }
    }
  }
}
