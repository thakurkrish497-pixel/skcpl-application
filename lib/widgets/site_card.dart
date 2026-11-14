import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../models/site_model.dart';

/// Card widget for site selection in the site list
class SiteCard extends StatelessWidget {
  final SiteModel site;
  final VoidCallback onTap;
  final bool showStatus;

  const SiteCard({
    super.key,
    required this.site,
    required this.onTap,
    this.showStatus = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact =
            constraints.maxHeight < 210 || constraints.maxWidth < 220;
        final pad = isCompact ? 13.0 : 16.0;
        final iconPad = isCompact ? 8.0 : 10.0;
        final iconSize = isCompact ? 18.0 : 22.0;
        final spacing = isCompact ? 8.0 : 12.0;

        return Container(
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: site.isHeadOffice
                  ? AppColors.waveCyan.withValues(alpha: 0.3)
                  : AppColors.cardBorder,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
              if (site.isHeadOffice)
                BoxShadow(
                  color: AppColors.waveCyan.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              splashColor: AppColors.primarySurface,
              child: Padding(
                padding: EdgeInsets.all(pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Site icon with gradient
                    Container(
                      padding: EdgeInsets.all(iconPad),
                      decoration: BoxDecoration(
                        gradient: site.isHeadOffice
                            ? AppColors.waveGradient
                            : AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: [
                          BoxShadow(
                            color: (site.isHeadOffice
                                    ? AppColors.waveCyan
                                    : AppColors.primary)
                                .withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        site.isHeadOffice
                            ? Icons.apartment_rounded
                            : Icons.construction_rounded,
                        color: Colors.white,
                        size: iconSize,
                      ),
                    ),
                    SizedBox(height: spacing),
                    // Site name
                    Text(
                      site.name,
                      style: AppTextStyles.h4.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: isCompact ? 14 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (site.address != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        site.address!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: isCompact ? 11 : 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const Spacer(),
                    // Status indicator
                    if (showStatus)
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: site.isActive
                                  ? AppColors.approved
                                  : AppColors.textTertiary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            site.isActive ? 'Active' : 'Inactive',
                            style: AppTextStyles.caption.copyWith(
                              color: site.isActive
                                  ? AppColors.approved
                                  : AppColors.textTertiary,
                              fontSize: isCompact ? 11 : 12,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: isCompact ? 12 : 14,
                            color: AppColors.textTertiary,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
