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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: site.isHeadOffice
              ? AppColors.waveCyan.withValues(alpha: 0.3)
              : AppColors.cardBorder,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          if (site.isHeadOffice)
            BoxShadow(
              color: AppColors.waveCyan.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          splashColor: AppColors.primarySurface,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Site icon with gradient
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    gradient: site.isHeadOffice
                        ? AppColors.waveGradient
                        : AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: (site.isHeadOffice ? AppColors.waveCyan : AppColors.primary)
                            .withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                    site.isHeadOffice ? Icons.apartment_rounded : Icons.construction_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                  const SizedBox(height: 16),
                  // Site name
                  Text(
                    site.name,
                    style: AppTextStyles.h4.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (site.address != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      site.address!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textTertiary,
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
                          width: 8,
                          height: 8,
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
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
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
  }
}
