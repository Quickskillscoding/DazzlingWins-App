import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/config.dart';
import '../core/theme.dart';
import 'ui.dart';

/// Picks a photo (camera or gallery), downsized/compressed so it stays well under the server's
/// 8 MB limit. Returns null when cancelled or too large.
/// Pass [source] to open the camera or the gallery directly, without asking.
Future<XFile?> pickPhoto(BuildContext context, {bool allowCamera = true, ImageSource? source}) async {
  final ImageSource from;
  if (source != null) {
    from = source;
  } else if (!allowCamera) {
    from = ImageSource.gallery;
  } else {
    final chosen = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (chosen == null) return null;
    from = chosen;
  }
  try {
    final file = await ImagePicker().pickImage(source: from, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
    if (file == null) return null;
    final size = await File(file.path).length();
    if (size > AppConfig.maxUploadBytes) {
      if (context.mounted) toast(context, 'That image is too large. Please choose a smaller one.', error: true);
      return null;
    }
    return file;
  } catch (_) {
    if (context.mounted) toast(context, 'Could not open the photo. Check the app permissions.', error: true);
    return null;
  }
}

/// Tappable upload box that shows the chosen photo.
class PhotoField extends StatelessWidget {
  const PhotoField({super.key, required this.label, required this.file, required this.onPick, this.required = false});
  final String label;
  final XFile? file;
  final VoidCallback onPick;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(required ? '$label *' : label, style: AppTheme.body(13, weight: FontWeight.w700, color: AppColors.muted)),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: onPick,
        child: Container(
          height: file == null ? 96 : 170,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: file == null ? AppColors.stroke : AppColors.mint.withValues(alpha: 0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: file == null
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add_photo_alternate_outlined, color: AppColors.primaryLight, size: 28),
                  const SizedBox(height: 6),
                  Text('Tap to upload', style: AppTheme.body(13, weight: FontWeight.w700, color: AppColors.primaryLight)),
                ])
              : Image.file(File(file!.path), fit: BoxFit.cover, cacheWidth: 800),
        ),
      ),
    ]);
  }
}
