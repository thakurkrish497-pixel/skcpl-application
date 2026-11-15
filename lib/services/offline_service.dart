import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:async';
import 'submission_support.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // ── DROPDOWNS CACHING ──

  static Future<void> cacheDropdowns(DropdownCategory category, String? siteId,
      List<DropdownItemModel> items) async {
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

  // All queue operations share one lock, including legacy manual sync buttons.
  static Future<void> _tail = Future<void>.value();
  static Future<SyncResult>? _syncFlight;
  static final queueRevision = ValueNotifier<int>(0);
  static final _uploading = <String>{};

  static Future<T> _locked<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static Future<void> _write(
      SharedPreferences prefs, String key, List<String> rows) async {
    if (!await prefs.setStringList(key, rows)) {
      throw StateError(
          'Could not save the local queue. Keep this screen open and retry.');
    }
    queueRevision.value++;
  }

  static String? _rowId(String raw) {
    try {
      return (jsonDecode(raw) as Map)['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> _queue(
          String key, Map<String, dynamic> data, String kind) =>
      _locked(() async {
        final prefs = await SharedPreferences.getInstance();
        final id = 'offline_${kind}_${submissionId(data['id'] as String?)}';
        if (_uploading.contains(id)) {
          throw StateError(
              'This entry is syncing. Retry the edit after it finishes.');
        }
        final entry = {...data, 'id': id, 'sync_version': 2};
        final rows = prefs.getStringList(key) ?? [];
        final index = rows.indexWhere((r) => _rowId(r) == id);
        if (index < 0) {
          rows.add(jsonEncode(entry));
        } else {
          if (jsonDecode(rows[index])['site_id'] != data['site_id']) {
            throw StateError(
                'A submission ID cannot be reused for another site.');
          }
          rows[index] = jsonEncode(entry);
        }
        await _write(prefs, key, rows);
        return entry;
      });

  static Future<StockTransactionModel> queueStockTransaction(
          StockTransactionModel tx) async =>
      StockTransactionModel.fromJson(
          await _queue(_keyStockQueue, tx.toJson(), 'stock'));
  static Future<CashTransactionModel> queueCashTransaction(
          CashTransactionModel tx) async =>
      CashTransactionModel.fromJson(
          await _queue(_keyCashQueue, tx.toJson(), 'cash'));

  static Future<List<Map<String, dynamic>>> _read(String key) =>
      _locked(() async {
        final prefs = await SharedPreferences.getInstance();
        final result = <Map<String, dynamic>>[];
        for (final raw in prefs.getStringList(key) ?? <String>[]) {
          // Preserve unreadable entries in storage; sync reports the error per row.
          try {
            result.add(Map<String, dynamic>.from(jsonDecode(raw)));
          } catch (_) {}
        }
        return result;
      });
  static Future<List<StockTransactionModel>>
      getQueuedStockTransactions() async => (await _read(_keyStockQueue))
          .map(StockTransactionModel.fromJson)
          .toList();
  static Future<List<CashTransactionModel>> getQueuedCashTransactions() async =>
      (await _read(_keyCashQueue)).map(CashTransactionModel.fromJson).toList();

  static Future<bool> isQueuedCash(String id) async =>
      (await _read(_keyCashQueue)).any((r) => r['id'] == id);
  static Future<bool> isQueuedStock(String id) async =>
      (await _read(_keyStockQueue)).any((r) => r['id'] == id);

  static Future<void> _update(String key, Map<String, dynamic> updated) =>
      _locked(() async {
        final prefs = await SharedPreferences.getInstance();
        final rows = prefs.getStringList(key) ?? [];
        final index = rows.indexWhere((r) => _rowId(r) == updated['id']);
        if (index < 0) {
          throw StateError(
              'Queued entry was not found; changes were not saved.');
        }
        if (_uploading.contains(updated['id'])) {
          throw StateError(
              'This entry is syncing. Retry the edit after it finishes.');
        }
        final old = Map<String, dynamic>.from(jsonDecode(rows[index]));
        // Preserve legacy reconciliation marker. Do not silently make it retryable.
        rows[index] = jsonEncode({
          ...old,
          ...updated,
          if (old['sync_version'] == 2) 'sync_paused': false,
          if (old['sync_version'] == 2) 'sync_error': null,
        });
        await _write(prefs, key, rows);
      });
  static Future<void> updateQueuedCashTransaction(CashTransactionModel tx) =>
      _update(_keyCashQueue, tx.toJson());
  static Future<void> updateQueuedStockTransaction(StockTransactionModel tx) =>
      _update(_keyStockQueue, tx.toJson());

  static Future<void> pauseCash(String id, Object error) =>
      _pause(_keyCashQueue, id, error);
  static Future<void> pauseStock(String id, Object error) =>
      _pause(_keyStockQueue, id, error);
  static Future<void> _pause(String key, String id, Object error) =>
      _locked(() async {
        final prefs = await SharedPreferences.getInstance();
        final rows = prefs.getStringList(key) ?? [];
        final index = rows.indexWhere((r) => _rowId(r) == id);
        if (index < 0) return;
        final data = Map<String, dynamic>.from(jsonDecode(rows[index]));
        rows[index] = jsonEncode(
            {...data, 'sync_paused': true, 'sync_error': error.toString()});
        await _write(prefs, key, rows);
      });

  static Future<void> _remove(String key, String id) => _locked(() async {
        final prefs = await SharedPreferences.getInstance();
        final rows = prefs.getStringList(key) ?? [];
        await _write(prefs, key, rows.where((r) => _rowId(r) != id).toList());
      });
  static Future<void> removeQueuedCashTransaction(String id) =>
      _remove(_keyCashQueue, id);
  static Future<void> removeQueuedStockTransaction(String id) =>
      _remove(_keyStockQueue, id);

  static Future<void> clearAllQueuedCash() => _locked(() async {
        final prefs = await SharedPreferences.getInstance();
        await _write(prefs, _keyCashQueue, []);
      });
  static Future<void> clearAllQueuedStock() => _locked(() async {
        final prefs = await SharedPreferences.getInstance();
        await _write(prefs, _keyStockQueue, []);
      });
  static Future<int> getPendingSyncCount() => _locked(() async {
        final prefs = await SharedPreferences.getInstance();
        return (prefs.getStringList(_keyStockQueue) ?? []).length +
            (prefs.getStringList(_keyCashQueue) ?? []).length;
      });

  static Future<SyncResult> syncAllQueued(
      {required StockService stockService, required CashService cashService}) {
    return _syncFlight ??= _flush(stockService, cashService)
        .whenComplete(() => _syncFlight = null);
  }

  static Future<SyncResult> _flush(
      StockService stockService, CashService cashService) async {
    var synced = 0;
    final errors = <String>[];
    for (final key in [_keyStockQueue, _keyCashQueue]) {
      final snapshot = await _locked(() async {
        final prefs = await SharedPreferences.getInstance();
        return List<String>.from(prefs.getStringList(key) ?? []);
      });
      for (final raw in snapshot) {
        String? id;
        try {
          final data = Map<String, dynamic>.from(jsonDecode(raw));
          id = data['id'] as String?;
          if (data['sync_paused'] == true) {
            // Report a paused failure without rewrapping and rewriting it every tick.
            errors.add(
                data['sync_error']?.toString() ?? 'Entry needs correction.');
            continue;
          }
          if (data['sync_version'] != 2) {
            throw StateError(
                'Older queued entry needs reconciliation before retry; it has been preserved.');
          }
          final claimed = await _locked(() async {
            final prefs = await SharedPreferences.getInstance();
            if (!(prefs.getStringList(key) ?? []).contains(raw)) return false;
            if (id != null) _uploading.add(id);
            return true;
          });
          if (!claimed) continue;
          // Network I/O must never hold the local storage lock: other sites can still save.
          if (key == _keyStockQueue) {
            await stockService
                .submitTransaction(StockTransactionModel.fromJson(data));
          } else {
            await cashService
                .submitTransaction(CashTransactionModel.fromJson(data));
          }
          await _locked(() async {
            final prefs = await SharedPreferences.getInstance();
            final current = List<String>.from(prefs.getStringList(key) ?? []);
            current.remove(raw);
            await _write(prefs, key, current);
          });
          synced++;
        } catch (e) {
          errors.add(e.toString());
          if (id != null && !isRetryableSubmissionError(e)) {
            await _pause(key, id, e);
          }
        } finally {
          if (id != null) _uploading.remove(id);
        }
      }
    }
    return SyncResult(
        syncedCount: synced,
        remainingCount: await getPendingSyncCount(),
        errors: errors);
  }
}

class SyncResult {
  final int syncedCount;
  final int remainingCount;
  final List<String> errors;
  const SyncResult(
      {required this.syncedCount,
      required this.remainingCount,
      this.errors = const []});
  bool get hasRemaining => remainingCount > 0;
}
