import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/attendance_provider.dart';

/// Display only: staff profiles never persist their own shift timing copy.
class InheritedShiftInfo extends ConsumerWidget {
  final String siteId;
  const InheritedShiftInfo({super.key, required this.siteId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(shiftPolicyForSiteProvider(siteId));
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: policy.when(
          loading: () => const Text('Loading assigned location timings…'),
          error: (_, __) => const Text(
              'Location timings could not be verified. Please retry.'),
          data: (p) => Text(
              'Inherited from assigned site / office: ${p.shiftStartTime} – ${p.shiftEndTime} • Grace ${p.graceMinutes} min. Managed in location settings.'),
        ));
  }
}
