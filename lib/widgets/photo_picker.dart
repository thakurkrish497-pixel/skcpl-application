import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import 'photo_viewer_dialog.dart';

/// Representation of a picked photo using raw bytes for universal Android Mobile support
class PickedPhoto {
  final Uint8List bytes;
  final String name;
  final String? path;

  const PickedPhoto({
    required this.bytes,
    required this.name,
    this.path,
  });
}

class PhotoPickerWidget extends StatefulWidget {
  final List<PickedPhoto> initialPhotos;
  final List<String> initialPhotoUrls;
  final Function(List<PickedPhoto>) onPhotosChanged;
  final bool isReadOnly;

  const PhotoPickerWidget({
    super.key,
    this.initialPhotos = const [],
    this.initialPhotoUrls = const [],
    required this.onPhotosChanged,
    this.isReadOnly = false,
  });

  @override
  State<PhotoPickerWidget> createState() => _PhotoPickerWidgetState();
}

class _PhotoPickerWidgetState extends State<PhotoPickerWidget> {
  late List<PickedPhoto> _photos;
  final ImagePicker _picker = ImagePicker();
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    _photos = List.from(widget.initialPhotos);
  }

  /// Shows Android bottom sheet to choose Camera or Gallery
  Future<void> _showPickSourceModal() async {
    if (widget.isReadOnly || _isPicking) return;
    HapticFeedback.selectionClick();

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Attach Challan / Receipt Photo',
                style: AppTextStyles.labelLarge.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                ),
                title: const Text('Take Photo with Camera',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Directly photograph site delivery or bill',
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx, ImageSource.camera);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: AppColors.secondary),
                ),
                title: const Text('Choose from Phone Gallery',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Pick existing image saved on your device',
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx, ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );

    if (source != null) {
      await _pickImageFromSource(source);
    }
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    try {
      setState(() => _isPicking = true);
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        final photo = PickedPhoto(
          bytes: bytes,
          name: image.name.isNotEmpty ? image.name : 'attachment_${DateTime.now().millisecondsSinceEpoch}.jpg',
          path: image.path,
        );
        setState(() {
          _photos.add(photo);
        });
        widget.onPhotosChanged(_photos);
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture image: $e'),
            backgroundColor: AppColors.rejected,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _removePhoto(int index) {
    if (widget.isReadOnly) return;
    HapticFeedback.selectionClick();

    setState(() {
      _photos.removeAt(index);
    });
    widget.onPhotosChanged(_photos);
  }

  void _previewLocalImage(PickedPhoto photo) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5.0,
                child: Image.memory(photo.bytes, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 24,
              right: 16,
              child: SafeArea(
                child: IconButton(
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Attachments (Bills / Challans / Photos)',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
            ),
            if (_photos.isNotEmpty || widget.initialPhotoUrls.isNotEmpty)
              Text(
                '${_photos.length + widget.initialPhotoUrls.length} attached',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ...widget.initialPhotoUrls.map((url) => _buildNetworkPhoto(url)),
            ..._photos.asMap().entries.map((entry) => _buildLocalPhoto(entry.value, entry.key)),
            if (!widget.isReadOnly) _buildAddButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildNetworkPhoto(String url) {
    return GestureDetector(
      onTap: () => PhotoViewerDialog.show(context, [url]),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image, color: AppColors.textTertiary),
          ),
        ),
      ),
    );
  }

  Widget _buildLocalPhoto(PickedPhoto photo, int index) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => _previewLocalImage(photo),
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.memory(
              photo.bytes,
              fit: BoxFit.cover,
            ),
          ),
        ),
        if (!widget.isReadOnly)
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: () => _removePhoto(index),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.rejected, width: 1.5),
                ),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close_rounded, color: AppColors.rejected, size: 16),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAddButton() {
    return InkWell(
      onTap: _showPickSourceModal,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider, style: BorderStyle.solid),
        ),
        child: Center(
          child: _isPicking
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                )
              : const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_rounded, color: AppColors.primary, size: 26),
                    SizedBox(height: 4),
                    Text(
                      'Camera / File',
                      style: TextStyle(color: AppColors.textTertiary, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
