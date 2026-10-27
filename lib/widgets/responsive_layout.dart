import 'package:flutter/material.dart';

/// Screen breakpoint constants for universal responsiveness
class ResponsiveBreakpoints {
  ResponsiveBreakpoints._();

  static const double mobile = 600.0;
  static const double tablet = 960.0;
  static const double desktop = 1280.0;
}

/// Helper methods to detect device form-factor
class Responsive {
  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < ResponsiveBreakpoints.mobile;

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= ResponsiveBreakpoints.mobile && width < ResponsiveBreakpoints.desktop;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= ResponsiveBreakpoints.desktop;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= ResponsiveBreakpoints.mobile;
}

/// Wraps page content in a centered, max-width constrained container
/// so that screens look balanced on tablets, desktop monitors, and ultrawide displays.
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = 1200.0,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// A responsive grid that automatically adjusts column count based on available width:
/// - Mobile (< 650px): 1 column
/// - Tablet / Medium (650px - 1100px): 2 columns
/// - Large Desktop (> 1100px): 3 columns (or user specified)
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final int? mobileColumns;
  final int? tabletColumns;
  final int? desktopColumns;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.spacing = 14.0,
    this.runSpacing = 14.0,
    this.mobileColumns,
    this.tabletColumns,
    this.desktopColumns,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int columns;

        if (width < 680) {
          columns = mobileColumns ?? 1;
        } else if (width < 1080) {
          columns = tabletColumns ?? 2;
        } else {
          columns = desktopColumns ?? (tabletColumns ?? 2);
        }

        if (columns <= 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) SizedBox(height: runSpacing),
              ],
            ],
          );
        }

        final itemWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map((c) => SizedBox(width: itemWidth, child: c))
              .toList(),
        );
      },
    );
  }
}
