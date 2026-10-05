import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/image_url.dart';
import '../../core/internet_check.dart';
import '../../models/school.dart';
import '../../services/cloudinary_service.dart';
import '../../services/school_service.dart';
import '../../services/upload_queue.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';

/// Settings → School images (admins only): the school badge and the school
/// stamp printed on student record PDFs.
///
/// The stamp works offline: picked with no internet, it is kept on the phone,
/// shown here and on exported records, and uploaded when the connection is
/// back. The badge needs the internet, like the cover photo.
class SchoolImagesSection extends StatefulWidget {
  const SchoolImagesSection({super.key, required this.school});

  final School school;

  @override
  State<SchoolImagesSection> createState() => _SchoolImagesSectionState();
}

class _SchoolImagesSectionState extends State<SchoolImagesSection> {
  final _service = SchoolService();
  bool _badgeBusy = false;
  bool _stampBusy = false;
  String? _message;

  String get _schoolId => widget.school.id;

  void _say(String message) {
    if (mounted) setState(() => _message = message);
  }

  /// Camera or gallery. Null when the user backs out.
  Future<ImageSource?> _askSource() => showModalBottomSheet<ImageSource>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );

  Future<void> _changeBadge() async {
    final folder = context.read<AuthController>().tenant!.schoolProfileFolder;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() {
      _badgeBusy = true;
      _message = null;
    });
    try {
      final upload = await CloudinaryService().upload(
        bytes: await picked.readAsBytes(),
        fileName: picked.name,
        folder: folder,
      );
      await _service.setProfileImage(_schoolId, 'logoUrl', upload.url);
      _say('Badge updated.');
    } catch (e) {
      _say(uploadFailedMessage(e));
    } finally {
      if (mounted) setState(() => _badgeBusy = false);
    }
  }

  Future<void> _changeStamp() async {
    final folder = context.read<AuthController>().tenant!.schoolProfileFolder;
    final source = await _askSource();
    if (source == null || !mounted) return;
    // No resizing: re-encoding could lose a PNG's transparent background.
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _stampBusy = true;
      _message = null;
    });
    final queue = UploadQueue.instance;

    Future<void> keepForLater() async {
      await queue!.addPhoto(
        schoolId: _schoolId,
        collection: 'profile',
        recordId: '',
        field: 'stampUrl',
        bytes: bytes,
        fileName: picked.name,
      );
      _say('Stamp saved on this phone. It will upload when you are online.');
    }

    try {
      if (queue != null && !await hasInternet()) {
        await keepForLater();
        return;
      }
      final upload = await CloudinaryService().upload(
        bytes: bytes,
        fileName: picked.name,
        folder: folder,
      );
      await _service.setProfileImage(_schoolId, 'stampUrl', upload.url);
      await queue?.cancel('profile', '', field: 'stampUrl');
      _say('Stamp updated.');
    } catch (e) {
      if (queue != null && isNetworkError(e)) {
        await keepForLater();
      } else {
        _say(uploadFailedMessage(e));
      }
    } finally {
      if (mounted) setState(() => _stampBusy = false);
    }
  }

  Future<void> _removeStamp() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove the school stamp?'),
        content: const Text('Exported student records will show an empty '
            '"School Stamp" box until a new stamp is uploaded.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _stampBusy = true);
    try {
      await UploadQueue.instance?.cancel('profile', '', field: 'stampUrl');
      await _service.setProfileImage(_schoolId, 'stampUrl', null);
      _say('Stamp removed.');
    } catch (e) {
      _say('Could not remove the stamp. Try again.');
    } finally {
      if (mounted) setState(() => _stampBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.school.meta;
    final queue = UploadQueue.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('School images', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _ImageTile(
          title: 'School badge',
          subtitle: 'Shown on the dashboard and on exported student records. '
              'Needs internet to change.',
          preview: _preview(meta.logoUrl, null, round: true),
          busy: _badgeBusy,
          onChange: _changeBadge,
        ),
        const SizedBox(height: 12),
        // Rebuilds when a stamp waiting on the phone uploads.
        queue == null
            ? _stampTile(meta, null)
            : ValueListenableBuilder(
                valueListenable: queue.listenable(),
                builder: (context, _, _) => _stampTile(
                    meta, queue.localSchoolImage(_schoolId, 'profile', 'stampUrl')),
              ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(_message!, style: const TextStyle(color: AppColors.primary)),
        ],
      ],
    );
  }

  Widget _stampTile(SchoolMeta meta, String? localPath) {
    final hasStamp =
        localPath != null || (meta.stampUrl?.trim().isNotEmpty ?? false);
    return _ImageTile(
      title: 'School stamp',
      subtitle: localPath != null
          ? 'Waiting to upload — it will go up when you are online.'
          : 'Printed on exported student records.',
      tip: 'Tip: use a PNG with a transparent background, so the stamp '
          'prints cleanly over the page.',
      preview: _preview(meta.stampUrl, localPath, round: false),
      busy: _stampBusy,
      onChange: _changeStamp,
      onRemove: hasStamp ? _removeStamp : null,
    );
  }

  Widget _preview(String? url, String? localPath, {required bool round}) {
    final Widget image;
    if (localPath != null) {
      image = Image.file(File(localPath), fit: BoxFit.contain, cacheWidth: 300);
    } else if (url != null && url.trim().isNotEmpty) {
      image = CachedNetworkImage(
        imageUrl: cloudinaryResized(url, width: 300),
        fit: BoxFit.contain,
        errorWidget: (_, _, _) => const Icon(Icons.broken_image_outlined),
      );
    } else {
      image = Center(
        child: Text(round ? 'No badge' : 'No stamp',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textMuted)),
      );
    }
    return Container(
      width: 72,
      height: 72,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        shape: round ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: round ? null : BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.title,
    required this.subtitle,
    required this.preview,
    required this.busy,
    required this.onChange,
    this.onRemove,
    this.tip,
  });

  final String title;
  final String subtitle;
  final String? tip;
  final Widget preview;
  final bool busy;
  final VoidCallback onChange;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            preview,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12.5)),
                  if (tip != null) ...[
                    const SizedBox(height: 4),
                    Text(tip!,
                        style: const TextStyle(
                            color: AppColors.info, fontSize: 12)),
                  ],
                  const SizedBox(height: 6),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: onChange,
                          icon: const Icon(Icons.upload_outlined, size: 18),
                          label: const Text('Change'),
                        ),
                        if (onRemove != null)
                          TextButton.icon(
                            onPressed: onRemove,
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.danger),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Remove'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
