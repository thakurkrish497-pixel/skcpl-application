import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../providers/theme_provider.dart';

/// Interactive, clearly visible button to toggle between Dark Mode and Light Mode (White & Blue).
class ThemeToggleButton extends ConsumerWidget {
  final bool isCompact;

  const ThemeToggleButton({
    super.key,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isLight = themeMode == ThemeMode.light;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isLight
              ? AppColors.primary.withValues(alpha: 0.6)
              : AppColors.waveCyan.withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isLight ? AppColors.primary : AppColors.waveCyan).withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            ref.read(themeProvider.notifier).toggleTheme();
          },
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 10 : 14,
              vertical: isCompact ? 6 : 8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mode Icon
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isLight
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : AppColors.waveCyan.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isLight ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    size: isCompact ? 14 : 16,
                    color: isLight ? AppColors.primary : AppColors.waveCyan,
                  ),
                ),
                const SizedBox(width: 7),

                // Mode label
                Text(
                  isLight ? 'Light' : 'Dark',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dual segmented button switch: [ 🌙 Dark | ☀️ Light ]
class ThemeSegmentedSwitch extends ConsumerWidget {
  const ThemeSegmentedSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isLight = themeMode == ThemeMode.light;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.cardDarkAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dark option
          _ThemeSegment(
            title: 'Dark',
            icon: Icons.dark_mode_rounded,
            isSelected: !isLight,
            activeColor: AppColors.waveCyan,
            onTap: () {
              ref.read(themeProvider.notifier).setTheme(ThemeMode.dark);
            },
          ),
          const SizedBox(width: 4),
          // Light option
          _ThemeSegment(
            title: 'Light',
            icon: Icons.light_mode_rounded,
            isSelected: isLight,
            activeColor: AppColors.primary,
            onTap: () {
              ref.read(themeProvider.notifier).setTheme(ThemeMode.light);
            },
          ),
        ],
      ),
    );
  }
}

class _ThemeSegment extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;

  const _ThemeSegment({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: AppTextStyles.bodySmall.copyWith(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
