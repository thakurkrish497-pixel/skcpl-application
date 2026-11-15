import 'package:supabase_flutter/supabase_flutter.dart';

class ReviewQueueEntry {
  final String id, sourceVersion;
  final int revision;
  final Map<String, dynamic> data, review;
  ReviewQueueEntry.fromJson(Map<String, dynamic> json)
      : id = json['entry_id'] as String,
        sourceVersion = json['source_version'] as String,
        revision = (json['review_revision'] as num).toInt(),
        data = Map<String, dynamic>.from(json['data'] as Map),
        review = Map<String, dynamic>.from(json['review_state'] as Map);
}

class ManagementReviewService {
  final SupabaseClient client;
  ManagementReviewService([SupabaseClient? client])
      : client = client ?? Supabase.instance.client;
  Future<List<ReviewQueueEntry>> pending(String module, String site) async {
    final result = <ReviewQueueEntry>[];
    for (var offset = 0;; offset += 200) {
      final page = await client.rpc('skcpl_review_queue', params: {
        'p_module': module,
        'p_site': site
      }).range(offset, offset + 199);
      final rows = List<Map<String, dynamic>>.from(page as List);
      result.addAll(rows.map(ReviewQueueEntry.fromJson));
      if (rows.length < 200) break;
    }
    return result;
  }

  Future<ReviewQueueEntry?> eligibleEntry(String module, String id) async {
    final rows = await client
        .rpc('skcpl_review_queue',
            params: {'p_module': module, 'p_site': 'all'})
        .eq('entry_id', id)
        .limit(1);
    return (rows as List).isEmpty
        ? null
        : ReviewQueueEntry.fromJson(Map<String, dynamic>.from(rows.first));
  }

  Future<Map<String, dynamic>> decide(String module, ReviewQueueEntry entry,
      {required bool approve, String note = '', bool halfDay = false}) async {
    if (!approve && note.trim().isEmpty) {
      throw ArgumentError('A rejection reason is required.');
    }
    final response = await client.rpc('skcpl_review_entry', params: {
      'p_module': module,
      'p_entry': entry.id,
      'p_approve': approve,
      'p_note': note.trim(),
      'p_half_day': halfDay,
      'p_review_revision': entry.revision,
      'p_source_version': entry.sourceVersion
    });
    return Map<String, dynamic>.from(response as Map);
  }
}
