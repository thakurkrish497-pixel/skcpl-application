import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/cash_transaction_model.dart';
import '../models/stock_transaction_model.dart';
import '../models/site_staff_model.dart';
import 'storage_service.dart';
import 'submission_support.dart';
import 'entry_date_policy.dart';

class HandledRejectedSubmission implements Exception {
  final String module, id;
  const HandledRejectedSubmission._(this.module, this.id);
  @override
  String toString() =>
      'This rejected entry was already handled on the server. Its device copy is preserved for review.';
}

/// Dedicated correction drafts. Never clears or rewrites the operational offline queues.
class RejectedEntryService {
  final SupabaseClient client;
  RejectedEntryService(this.client);
  static Future<void> _tail = Future.value();
  static Future<T> _locked<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  String _key(String module, String id) =>
      'rejected_correction_v1_${module}_$id';
  Future<Map<String, dynamic>?> draft(String module, String id) async {
    final raw =
        (await SharedPreferences.getInstance()).getString(_key(module, id));
    return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw));
  }

  Future<void> _save(
      String module, String id, Map<String, dynamic> data) async {
    if (!await (await SharedPreferences.getInstance())
        .setString(_key(module, id), jsonEncode(data))) {
      throw StateError(
          'Could not preserve your correction. Keep the form open and retry.');
    }
  }

  Future<void> _clear(String module, String id) async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key(module, id));
    } catch (_) {
      /* An acknowledged cloud record must not become a failed submission. */
    }
  }

  Future<Map<String, dynamic>> _action(
      String module, String source, String action, DateTime? expected,
      {String? newId,
      Map<String, dynamic>? payload,
      SiteStaffModel? staff}) async {
    try {
      final result = Map<String, dynamic>.from(
          await client.rpc('skcpl_rejected_entry_action', params: {
        'p_module': module,
        'p_source': source,
        'p_action': action,
        'p_new_id': newId,
        'p_payload': payload,
        'p_staff_id': staff?.id,
        'p_staff_pin': staff?.pin,
        'p_expected_updated': expected?.toUtc().toIso8601String()
      }).timeout(const Duration(seconds: 30)));
      if (result['action'] != action ||
          result['source_id'] != source ||
          (action == 'resubmit' &&
              (result['replacement_id'] != newId ||
                  (result['entry'] as Map?)?['id'] != newId))) {
        throw StateError(
            'The server did not confirm this entry. Refresh history; the correction draft remains preserved.');
      }
      return result;
    } on PostgrestException catch (error) {
      if (isSchemaUnavailable(error) || error.code == 'PGRST202') {
        throw StateError(
            'Rejected-entry actions are not activated on the server yet. The original entry and saved correction are preserved.');
      }
      rethrow;
    }
  }

  /// Called only after an upload denial or hidden-ID collision, never on ordinary new writes.
  Future<void> checkHandledSubmission(
      String module, String rawId, Map<String, dynamic> payload) async {
    final id = submissionId(rawId);
    Map<String, dynamic>? receipt;
    try {
      receipt = await client
          .from('skcpl_rejected_events')
          .select('source_id,action,replacement_id')
          .eq('module', module)
          .eq('source_id', id)
          .maybeSingle()
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // No positive receipt: keep the existing queue error and retry behaviour.
      return;
    }
    if (receipt == null ||
        receipt['source_id'] != id ||
        !['dismiss', 'resubmit'].contains(receipt['action'])) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        'handled_rejected_copy_v1_${module}_$id',
        jsonEncode({
          'receipt': receipt,
          'payload': payload,
          'preserved_at': DateTime.now().toUtc().toIso8601String()
        }))) {
      throw StateError(
          'Keep this entry queued: its recovery copy could not be saved.');
    }
    throw HandledRejectedSubmission._(module, id);
  }

  Future<void> dismiss(String module, String id, DateTime? updated,
      {SiteStaffModel? staff}) async {
    await _action(module, id, 'dismiss', updated, staff: staff);
    await _clear(module, id);
  }

  Future<Map<String, dynamic>> _resubmit(String module, String id,
          DateTime? updated, Map<String, dynamic> input,
          {SiteStaffModel? staff}) =>
      _locked(() async {
        EntryDatePolicy.requireDateValue(input['date']);
        final previous = await draft(module, id);
        final same = previous != null &&
            jsonEncode(previous['input']) == jsonEncode(input);
        final data = <String, dynamic>{
          'new_id': previous?['new_id'] ?? const Uuid().v4(),
          'input': input,
          'urls': same
              ? previous['urls']
              : List<String>.from(input['photo_urls'] ?? []),
          if (same && previous.containsKey('server_payload'))
            'server_payload': previous['server_payload'],
        };
        // Save before reads/uploads; credentials are never persisted in this draft.
        await _save(module, id, data);
        final handled = await client
            .from('skcpl_rejected_events')
            .select('action,replacement_id')
            .eq('module', module)
            .eq('source_id', id)
            .maybeSingle()
            .timeout(const Duration(seconds: 15));
        if (handled != null) {
          if (handled['action'] != 'resubmit' ||
              handled['replacement_id'] != data['new_id'] ||
              previous?['server_payload'] == null) {
            throw StateError(
                'This rejected entry was already handled. Refresh history; your correction remains saved locally.');
          }
          final result = await _action(module, id, 'resubmit', updated,
              newId: data['new_id'],
              payload: Map<String, dynamic>.from(previous!['server_payload']),
              staff: staff);
          if (!same) {
            throw StateError(
                'The previous resubmission is already saved. These newer changes remain in the correction draft; refresh history before editing the new entry.');
          }
          await _clear(module, id);
          return Map<String, dynamic>.from(result['entry']);
        }
        final photos = (input['local_pending_photos'] as List? ?? [])
            .map((p) => PendingPhoto.fromJson(Map<String, dynamic>.from(p)))
            .toList();
        final urls = List<String>.from(data['urls']);
        final base = (input['photo_urls'] as List? ?? []).length;
        for (var i = 0; i < photos.length; i++) {
          if (urls.length > base + i) continue;
          urls.add(await StorageService(client)
              .uploadPhotoBytes(photos[i].bytes,
                  fileName: photos[i].name,
                  submissionPath: 'photos/$module/${data['new_id']}/$i.jpg')
              .timeout(const Duration(seconds: 45)));
          data['urls'] = List<String>.from(urls);
          await _save(module, id, data);
        }
        final payload = Map<String, dynamic>.from(input)
          ..remove('local_pending_photos')
          ..['photo_urls'] = urls;
        data['server_payload'] = payload;
        await _save(module, id, data);
        final result = await _action(module, id, 'resubmit', updated,
            newId: data['new_id'], payload: payload, staff: staff);
        await _clear(module, id);
        return Map<String, dynamic>.from(result['entry']);
      });
  Future<CashTransactionModel> resubmitCash(
          CashTransactionModel source, CashTransactionModel correction,
          {SiteStaffModel? staff}) async =>
      CashTransactionModel.fromJson(await _resubmit(
          'cash', source.id!, source.updatedAt, correction.toJson(),
          staff: staff));
  Future<StockTransactionModel> resubmitStock(
          StockTransactionModel source, StockTransactionModel correction,
          {SiteStaffModel? staff}) async =>
      StockTransactionModel.fromJson(await _resubmit(
          'stock', source.id!, source.updatedAt, correction.toJson(),
          staff: staff));
}
