import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';

/// Full-screen high-definition interactive photo viewer for Accounts, Admin, and Site users
class PhotoViewerDialog extends StatefulWidget {
  final List<String> photoUrls;
  final int initialIndex;

  const PhotoViewerDialog({
    super.key,
    required this.photoUrls,
    this.initialIndex = 0,
  });

  /// Convenient helper to open the photo viewer anywhere in the app
  static Future<void> show(
    BuildContext context,
    List<String> photoUrls, {
    int initialIndex = 0,
  }) {
    if (photoUrls.isEmpty) return Future.value();
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      barrierDismissible: true,
      builder: (ctx) => PhotoViewerDialog(
        photoUrls: photoUrls,
        initialIndex: initialIndex,
      ),
    );
  }

  @override
  State<PhotoViewerDialog> createState() => _PhotoViewerDialogState();
}

class _PhotoViewerDialogState extends State<PhotoViewerDialog> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.photoUrls.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open URL: $url'),
            backgroundColor: AppColors.rejected,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUrl = widget.photoUrls[_currentIndex];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Photo Carousel with Interactive Viewer ──
          PageView.builder(
            controller: _pageController,
            itemCount: widget.photoUrls.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              final url = widget.photoUrls[index];
              return Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 6.0,
                  clipBehavior: Clip.none,
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      final total = progress.expectedTotalBytes;
                      final loaded = progress.cumulativeBytesLoaded;
                      final percent = total != null ? (loaded / total) : null;
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              value: percent,
                              color: AppColors.primary,
                              strokeWidth: 3,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              percent != null
                                  ? 'Loading photo ${(percent * 100).toInt()}%...'
                                  : 'Loading photo...',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          margin: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.cardDark,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.broken_image_rounded,
                                  color: AppColors.rejected, size: 54),
                              const SizedBox(height: 14),
                              Text('Failed to load image',
                                  style: AppTextStyles.labelLarge
                                      .copyWith(color: AppColors.textPrimary)),
                              const SizedBox(height: 6),
                              Text(
                                'Check your internet connection or open in browser.',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: AppColors.textTertiary),
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: () => _openExternalUrl(url),
                                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                                label: const Text('Open Link'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),

          // ── Top Navigation Bar ──
          Positioned(
            top: 24,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Row(
                children: [
                  // Android back button
                  IconButton(
                    tooltip: 'Back',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.65),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),

                  // Photo counter pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.photo_library_rounded,
                            color: AppColors.primary, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          '${_currentIndex + 1} / ${widget.photoUrls.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),

                  // Open External / Download button
                  IconButton(
                    tooltip: 'Open in Browser / Full View',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.65),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 20),
                    onPressed: () => _openExternalUrl(currentUrl),
                  ),
                ],
              ),
            ),
          ),

          // ── Previous / Next arrows for Desktop/Web ──
          if (widget.photoUrls.length > 1) ...[
            if (_currentIndex > 0)
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                    ),
                    icon: const Icon(Icons.chevron_left_rounded,
                        color: Colors.white, size: 36),
                    onPressed: () {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                ),
              ),
            if (_currentIndex < widget.photoUrls.length - 1)
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                    ),
                    icon: const Icon(Icons.chevron_right_rounded,
                        color: Colors.white, size: 36),
                    onPressed: () {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
