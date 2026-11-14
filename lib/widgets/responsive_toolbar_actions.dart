import 'package:flutter/material.dart';

/// Keep all desktop actions reachable in a single labelled mobile overflow menu.
class ResponsiveToolbarActions extends StatelessWidget {
  final List<Widget> actions;
  const ResponsiveToolbarActions({super.key, required this.actions});
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 650) {
      return Row(mainAxisSize: MainAxisSize.min, children: actions);
    }
    return PopupMenuButton<int>(
        tooltip: 'Dashboard actions',
        itemBuilder: (context) => [
              for (var i = 0; i < actions.length; i++)
                if (actions[i] is IconButton)
                  PopupMenuItem<int>(
                      value: i,
                      onTap: (actions[i] as IconButton).onPressed,
                      child: Text((actions[i] as IconButton).tooltip ??
                          'Dashboard action'))
                else if (actions[i] is! SizedBox)
                  PopupMenuItem<int>(enabled: false, child: actions[i]),
            ]);
  }
}
