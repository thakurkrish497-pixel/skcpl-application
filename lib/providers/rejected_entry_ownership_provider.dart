import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import '../services/submission_support.dart';

/// Stable ownership from prior verified resubmissions survives profile-name edits.
final rejectedResubmissionOwnersProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final client = ref.read(supabaseClientProvider);
  final result = <String, String>{};
  for (var offset = 0;; offset += 200) {
    try {
      final rows = await client
          .from('skcpl_rejected_events')
          .select('module,replacement_id,actor_staff_id')
          .order('module')
          .order('source_id')
          .range(offset, offset + 199);
      for (final row in rows) {
        if (row['replacement_id'] != null && row['actor_staff_id'] != null) {
          result['${row['module']}:${row['replacement_id']}'] =
              row['actor_staff_id'] as String;
        }
      }
      if (rows.length < 200) break;
    } catch (error) {
      if (!isSchemaUnavailable(error)) rethrow;
      break;
    }
  }
  return result;
});
