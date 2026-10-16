import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';

class PhotoPickerWidget extends StatefulWidget {
  final List<File> initialPhotos;
  final List<String> initialPhotoUrls;
  final Function(List<File>) onPhotosChanged;
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
  late List<File> _photos;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _photos = List.from(widget.initialPhotos);
  }

  Future<void> _pickImage() async {
    if (widget.isReadOnly) return;
    
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      setState(() {
        _photos.add(File(image.path));
      });
      widget.onPhotosChanged(_photos);
    }
  }

  void _removePhoto(int index) {
    if (widget.isReadOnly) return;
    
    setState(() {
      _photos.removeAt(index);
    });
    widget.onPhotosChanged(_photos);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Attachments (Photos)',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
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
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
        image: DecorationImage(
          image: NetworkImage(url),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildLocalPhoto(File file, int index) {
    return Stack(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
            image: DecorationImage(
              image: FileImage(file),
              fit: BoxFit.cover,
            ),
          ),
        ),
        if (!widget.isReadOnly)
          Positioned(
            top: -4,
            right: -4,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surfaceDark,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cancel, color: AppColors.rejected, size: 20),
              ),
              onPressed: () => _removePhoto(index),
            ),
          ),
      ],
    );
  }

  Widget _buildAddButton() {
    return InkWell(
      onTap: _pickImage,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider, style: BorderStyle.solid),
        ),
        child: const Center(
          child: Icon(Icons.add_a_photo, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
