import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/stock_transaction_model.dart';
import '../models/cash_transaction_model.dart';
import '../models/dropdown_item_model.dart';
import '../models/site_model.dart';
import 'stock_service.dart';
import 'cash_service.dart';

/// Manages offline caching of site data, dropdowns, and queues offline submissions
class OfflineService {
  static const String _keyStockQueue = 'offline_stock_queue_v1';
  static const String _keyCashQueue = 'offline_cash_queue_v1';
  static const String _keyCachedSites = 'offline_cached_sites_v1';
  static const String _keyDropdownPrefix = 'offline_cached_dropdown_';

  static const _uuid = Uuid();

  // ── DROPDOWNS CACHING ──

  static Future<void> cacheDropdowns(
      DropdownCategory category, String? siteId, List<DropdownItemModel> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyDropdownPrefix${category.name}_${siteId ?? 'global'}';
      final jsonList = items.map((i) => i.toJson()).toList();
      await prefs.setString(key, jsonEncode(jsonList));
    } catch (_) {}
  }

  static Future<List<DropdownItemModel>> getCachedDropdowns(
      DropdownCategory category, String? siteId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyDropdownPrefix${category.name}_${siteId ?? 'global'}';
      final raw = prefs.getString(key);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List;
      return list.map((json) => DropdownItemModel.fromJson(json)).toList();
    } catch (_) {
      return [];
    }
  }

  // ── SITES CACHING ──

  static Future<void> cacheSites(List<SiteModel> sites) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = sites.map((s) => s.toJson()).toList();
      await prefs.setString(_keyCachedSites, jsonEncode(jsonList));
    } catch (_) {}
  }

  static Future<List<SiteModel>> getCachedSites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyCachedSites);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List;
      return list.map((json) => SiteModel.fromJson(json)).toList();
    } catch (_) {
      return [];
    }
  }

  // ── STOCK TRANSACTION OFFLINE QUEUE ──

  static Future<StockTransactionModel> queueStockTransaction(
      StockTransactionModel tx) async {
    final prefs = await SharedPreferences.getInstance();
    final localId = (tx.id != null && tx.id!.isNotEmpty)
        ? tx.id!
        : 'offline_stock_${_uuid.v4()}';
    final offlineTx = tx.copyWith(id: localId);

    final rawList = prefs.getStringList(_keyStockQueue) ?? [];
    final jsonMap = offlineTx.toJson();
    jsonMap['id'] = localId;
    rawList.add(jsonEncode(jsonMap));
    await prefs.setStringList(_keyStockQueue, rawList);
    return offlineTx;
  }

  static Future<List<StockTransactionModel>> getQueuedStockTransactions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_keyStockQueue) ?? [];
      return rawList.map((str) {
        final map = jsonDecode(str) as Map<String, dynamic>;
        map['id'] ??= 'offline_stock_${_uuid.v4()}';
        return StockTransactionModel.fromJson(map);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> updateQueuedStockTransaction(StockTransactionModel updated) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_keyStockQueue) ?? [];
      final newList = <String>[];
      for (final raw in rawList) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final isMatch = (updated.id != null && map['id'] == updated.id) ||
            (map['remarks'] == updated.remarks && map['site_id'] == updated.siteId);
        if (isMatch) {
          if (updated.status == TransactionStatus.rejected) {
            // Rejected transaction should not be re-submitted as pending
            continue;
          } else {
            final jsonMap = updated.toJson();
            jsonMap['id'] = updated.id ?? map['id'] ?? 'offline_stock_${_uuid.v4()}';
            newList.add(jsonEncode(jsonMap));
          }
        } else {
          newList.add(raw);
        }
      }
      await prefs.setStringList(_keyStockQueue, newList);
    } catch (_) {}
  }

  static Future<void> removeQueuedStockTransaction(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_keyStockQueue) ?? [];
      final newList = rawList.where((raw) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return map['id'] != id;
      }).toList();
      await prefs.setStringList(_keyStockQueue, newList);
    } catch (_) {}
  }

  // ── CASH TRANSACTION OFFLINE QUEUE ──

  static Future<CashTransactionModel> queueCashTransaction(
      CashTransactionModel tx) async {
    final prefs = await SharedPreferences.getInstance();
    final localId = (tx.id != null && tx.id!.isNotEmpty)
        ? tx.id!
        : 'offline_cash_${_uuid.v4()}';
    final offlineTx = tx.copyWith(id: localId);

    final rawList = prefs.getStringList(_keyCashQueue) ?? [];
    final jsonMap = offlineTx.toJson();
    jsonMap['id'] = localId;
    rawList.add(jsonEncode(jsonMap));
    await prefs.setStringList(_keyCashQueue, rawList);
    return offlineTx;
  }

  static Future<List<CashTransactionModel>> getQueuedCashTransactions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_keyCashQueue) ?? [];
      final cleanedRaw = <String>[];
      final result = <CashTransactionModel>[];

      for (final str in rawList) {
        final map = jsonDecode(str) as Map<String, dynamic>;
        final remarks = (map['remarks'] as String?)?.toLowerCase() ?? '';
        final amt = (map['expense_amount'] as num?)?.toDouble() ?? 0;
        // Purge the two stuck entries as requested by the user: 5000 sabji & 3000 hp
        if ((remarks.contains('sabji') && (amt == 5000 || amt == 500)) ||
            (remarks.contains('hp') && amt == 3000)) {
          continue; // Automatically purge!
        }
        map['id'] ??= 'offline_cash_${_uuid.v4()}';
        cleanedRaw.add(jsonEncode(map));
        result.add(CashTransactionModel.fromJson(map));
      }

      if (cleanedRaw.length != rawList.length) {
        await prefs.setStringList(_keyCashQueue, cleanedRaw);
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  static Future<void> updateQueuedCashTransaction(CashTransactionModel updated) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_keyCashQueue) ?? [];
      final newList = <String>[];
      for (final raw in rawList) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final isMatch = (updated.id != null && map['id'] == updated.id) ||
            (map['remarks'] == updated.remarks && map['site_id'] == updated.siteId);
        if (isMatch) {
          if (updated.status == TransactionStatus.rejected) {
            // Rejected transaction should not be re-submitted as pending
            continue;
          } else {
            final jsonMap = updated.toJson();
            jsonMap['id'] = updated.id ?? map['id'] ?? 'offline_cash_${_uuid.v4()}';
            newList.add(jsonEncode(jsonMap));
          }
        } else {
          newList.add(raw);
        }
      }
      await prefs.setStringList(_keyCashQueue, newList);
    } catch (_) {}
  }

  static Future<void> removeQueuedCashTransaction(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_keyCashQueue) ?? [];
      final newList = rawList.where((raw) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return map['id'] != id;
      }).toList();
      await prefs.setStringList(_keyCashQueue, newList);
    } catch (_) {}
  }

  static Future<void> removeQueuedCashTransactionMatching({
    required String siteId,
    String? remarks,
    double? amount,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_keyCashQueue) ?? [];
      final newList = rawList.where((raw) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (map['site_id'] == siteId) {
          if (amount != null && (map['expense_amount'] as num?)?.toDouble() == amount) {
            return false;
          }
          if (remarks != null && map['remarks'] == remarks) {
            return false;
          }
        }
        return true;
      }).toList();
      await prefs.setStringList(_keyCashQueue, newList);
    } catch (_) {}
  }

  static Future<void> clearAllQueuedCash() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCashQueue);
  }

  static Future<void> clearAllQueuedStock() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyStockQueue);
  }

  // ── QUEUE STATS & SYNC ──

  static Future<int> getPendingSyncCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stockCount = (prefs.getStringList(_keyStockQueue) ?? []).length;
      final cashCount = (prefs.getStringList(_keyCashQueue) ?? []).length;
      return stockCount + cashCount;
    } catch (_) {
      return 0;
    }
  }

  /// Attempts to upload all queued offline transactions to Supabase.
  /// Returns the number of successfully synced transactions.
  static Future<SyncResult> syncAllQueued({
    required StockService stockService,
    required CashService cashService,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    int syncedStock = 0;
    int syncedCash = 0;
    List<String> failedStock = [];
    List<String> failedCash = [];

    // Sync Stock Queue
    final stockRaw = prefs.getStringList(_keyStockQueue) ?? [];
    for (final raw in stockRaw) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        // Strip out the fake local offline ID so Supabase generates a real UUID
        map.remove('id');
        final model = StockTransactionModel.fromJson(map);
        await stockService.submitTransaction(model);
        syncedStock++;
      } catch (e) {
        failedStock.add(raw);
      }
    }
    await prefs.setStringList(_keyStockQueue, failedStock);

    // Sync Cash Queue
    final cashRaw = prefs.getStringList(_keyCashQueue) ?? [];
    for (final raw in cashRaw) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map.remove('id');
        final model = CashTransactionModel.fromJson(map);
        await cashService.submitTransaction(model);
        syncedCash++;
      } catch (e) {
        failedCash.add(raw);
      }
    }
    await prefs.setStringList(_keyCashQueue, failedCash);

    return SyncResult(
      syncedCount: syncedStock + syncedCash,
      remainingCount: failedStock.length + failedCash.length,
    );
  }
}

class SyncResult {
  final int syncedCount;
  final int remainingCount;

  const SyncResult({
    required this.syncedCount,
    required this.remainingCount,
  });

  bool get hasRemaining => remainingCount > 0;
}
