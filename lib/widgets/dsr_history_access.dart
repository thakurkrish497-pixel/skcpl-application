import 'package:flutter/material.dart';
import '../screens/site_reports/dsr_history_screen.dart';

/// History remains available when an approval checkpoint is disabled.
class DsrHistoryAccess extends StatelessWidget {
  final Widget child;
  final String siteId;
  const DsrHistoryAccess({super.key, required this.child, this.siteId = 'all'});
  @override
  Widget build(BuildContext context) => Column(children: [
        Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
                icon: const Icon(Icons.history),
                label: const Text('DSR History'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DsrHistoryScreen(
                        initialSiteId: siteId == 'all' ? null : siteId))))),
        Expanded(child: child),
      ]);
}
