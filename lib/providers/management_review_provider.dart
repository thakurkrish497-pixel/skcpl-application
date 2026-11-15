import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/management_review_service.dart';
import 'auth_provider.dart';
export '../services/management_review_service.dart';

final managementReviewServiceProvider = Provider<ManagementReviewService>(
    (ref) => ManagementReviewService(ref.read(supabaseClientProvider)));
final managementReviewQueueProvider = FutureProvider.autoDispose
    .family<List<ReviewQueueEntry>, ({String module, String site})>(
        (ref, args) => ref
            .watch(managementReviewServiceProvider)
            .pending(args.module, args.site));
