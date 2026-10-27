import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../providers/locale_provider.dart';

/// Clearly visible, interactive language switcher button.
/// Allows instant switching between English and Hindi with persistent default storage.
class LanguageToggleButton extends ConsumerWidget {
  final bool isCompact;

  const LanguageToggleButton({
    super.key,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);
    final isHindi = currentLocale.languageCode == 'hi';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isHindi ? AppColors.pending.withValues(alpha: 0.6) : AppColors.divider,
          width: 1.2,
        ),
        boxShadow: [
          if (isHindi)
            BoxShadow(
              color: AppColors.pending.withValues(alpha: 0.25),
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
            ref.read(localeProvider.notifier).toggleLocale();
          },
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 10 : 14,
              vertical: isCompact ? 6 : 8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Flag / Language icon
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isHindi
                        ? AppColors.pending.withValues(alpha: 0.2)
                        : AppColors.primary.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    isHindi ? '🇮🇳' : '🌐',
                    style: TextStyle(fontSize: isCompact ? 13 : 16),
                  ),
                ),
                const SizedBox(width: 8),

                // Language text
                Text(
                  isHindi ? 'हिन्दी' : 'English',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isHindi ? AppColors.pending : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),

                const SizedBox(width: 6),
                Icon(
                  Icons.swap_horiz_rounded,
                  size: 16,
                  color: isHindi ? AppColors.pending : AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dual segmented button switch: [ EN | हिन्दी ]
class LanguageSegmentedSwitch extends ConsumerWidget {
  const LanguageSegmentedSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);
    final isHindi = currentLocale.languageCode == 'hi';

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // English option
          _LanguageSegment(
            title: 'English',
            isSelected: !isHindi,
            onTap: () {
              ref.read(localeProvider.notifier).setLocale(const Locale('en'));
            },
          ),
          const SizedBox(width: 4),
          // Hindi option
          _LanguageSegment(
            title: 'हिन्दी',
            isSelected: isHindi,
            onTap: () {
              ref.read(localeProvider.notifier).setLocale(const Locale('hi'));
            },
          ),
        ],
      ),
    );
  }
}

class _LanguageSegment extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageSegment({
    required this.title,
    required this.isSelected,
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
          color: isSelected
              ? (title == 'हिन्दी' ? AppColors.pending : AppColors.primary)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (title == 'हिन्दी' ? AppColors.pending : AppColors.primary)
                        .withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          title,
          style: AppTextStyles.bodySmall.copyWith(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
