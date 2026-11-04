import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import 'skcpl_brand_logo.dart';

/// Modal dialog providing 1-click download links for native Android, Windows, and Mac apps
class DownloadAppsDialog extends StatelessWidget {
  const DownloadAppsDialog({super.key});

  static const String androidApkUrl =
      'https://github.com/thakurkrish497-pixel/skcpl-application/releases/download/v1.0.0/SKCPL-Android.apk';
  static const String windowsZipUrl =
      'https://github.com/thakurkrish497-pixel/skcpl-application/releases/download/v1.0.0/SKCPL-Windows-x64.zip';
  static const String macOsZipUrl =
      'https://github.com/thakurkrish497-pixel/skcpl-application/releases/download/v1.0.0/SKCPL-macOS.zip';
  static const String releasesPageUrl =
      'https://github.com/thakurkrish497-pixel/skcpl-application/releases/tag/v1.0.0';

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const DownloadAppsDialog(),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const SkcplBrandLogo(variant: LogoVariant.compact, customSize: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Download SKCPL Apps',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Native apps for Phones & Laptops',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_done_rounded, color: AppColors.approved, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'All your data (sites, expenses, attendance, stock) is synced securely in the cloud. Updating or switching devices never loses your data!',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── 1. Android Phones ──
              _buildDownloadTile(
                icon: Icons.android_rounded,
                iconColor: const Color(0xFF3DDC84),
                title: 'Android Phone (APK)',
                subtitle: 'Direct installer for Samsung, OnePlus, Vivo, Xiaomi, etc.',
                buttonLabel: 'Download APK',
                onPressed: () => _launchUrl(androidApkUrl),
              ),
              const SizedBox(height: 10),

              // ── 2. Windows Laptops ──
              _buildDownloadTile(
                icon: Icons.laptop_windows_rounded,
                iconColor: const Color(0xFF00ADEF),
                title: 'Windows Laptop (64-bit)',
                subtitle: 'Standalone executable (.exe) in ZIP — no installer needed',
                buttonLabel: 'Download ZIP',
                onPressed: () => _launchUrl(windowsZipUrl),
              ),
              const SizedBox(height: 10),

              // ── 3. Mac Laptops ──
              _buildDownloadTile(
                icon: Icons.laptop_mac_rounded,
                iconColor: Colors.white,
                title: 'Mac Laptop (macOS)',
                subtitle: 'Native macOS .app bundle for Apple Silicon & Intel Macs',
                buttonLabel: 'Download App',
                onPressed: () => _launchUrl(macOsZipUrl),
              ),
              const SizedBox(height: 10),

              // ── 4. iPhones (iOS) ──
              _buildDownloadTile(
                icon: Icons.apple_rounded,
                iconColor: AppColors.goldAccent,
                title: 'Apple iPhone (iOS)',
                subtitle: 'Install via Xcode USB or company TestFlight deployment',
                buttonLabel: 'View Guide',
                onPressed: () => _launchUrl(releasesPageUrl),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.open_in_new_rounded, size: 14),
          label: const Text('GitHub Releases Page'),
          onPressed: () => _launchUrl(releasesPageUrl),
        ),
      ],
    );
  }

  Widget _buildDownloadTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: iconColor.withValues(alpha: 0.15),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surfaceDark,
              foregroundColor: AppColors.waveCyan,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AppColors.divider),
              ),
            ),
            onPressed: onPressed,
            child: Text(buttonLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

