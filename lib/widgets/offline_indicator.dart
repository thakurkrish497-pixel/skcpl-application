import 'package:flutter/material.dart';
import 'universal_sync_button.dart';

/// Compatibility entry point for older forms. Counts and retry results come from
/// the same reactive sync state used everywhere else in the application.
class OfflineSyncButton extends StatelessWidget {
  const OfflineSyncButton({super.key});

  @override
  Widget build(BuildContext context) => const UniversalSyncButton();
}
