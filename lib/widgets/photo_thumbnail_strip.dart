import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import 'photo_viewer_dialog.dart';

/// Horizontal photo thumbnail strip for Transaction cards (History, Review, Details)
/// Tapping any thumbnail opens the full-screen zoomable PhotoViewerDialog
class PhotoThumbnailStrip extends StatelessWidget {
  final List<String> photoUrls;
  final String? title;
  final double size;

  const PhotoThumbnailStrip({
    super.key,
    required this.photoUrls,
    this.title,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    if (photoUrls.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.receipt_long_rounded,
                size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              title ??
                  'Attached Bills (${photoUrls.length}) • Tap to zoom',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: size,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photoUrls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final url = photoUrls[index];
              return InkWell(
                onTap: () => PhotoViewerDialog.show(
                  context,
                  photoUrls,
                  initialIndex: index,
                ),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      width: 1,
                    ),
                    color: AppColors.surfaceDark,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        url,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image_rounded,
                              size: 20, color: AppColors.textTertiary),
                        ),
                      ),
                      // Small magnifying glass overlay in corner
                      Positioned(
                        bottom: 3,
                        right: 3,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.zoom_in_rounded,
                              size: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
