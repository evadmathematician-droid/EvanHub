import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/image_url.dart';
import '../services/upload_queue.dart';

/// A person's photo for a round avatar [radius] logical pixels wide: a small
/// copy from Cloudinary, cached on disk, and decoded at the size it is shown
/// instead of the full-resolution original.
ImageProvider avatarImage(BuildContext context, String url,
    {required double radius}) {
  final px = (radius * 2 * MediaQuery.devicePixelRatioOf(context)).ceil();
  return ResizeImage(
    CachedNetworkImageProvider(cloudinaryResized(url, width: px)),
    width: px,
  );
}

/// The photo a form shows: one just picked offline ([picked]), else one of
/// [recordId]'s still waiting to upload, else the uploaded [url]. Null when
/// there is no photo.
ImageProvider? formPhotoImage(
  BuildContext context, {
  Uint8List? picked,
  String? recordId,
  required String url,
  required double radius,
}) {
  final px = (radius * 2 * MediaQuery.devicePixelRatioOf(context)).ceil();
  if (picked != null) return ResizeImage(MemoryImage(picked), width: px);
  final local = recordId == null || recordId.isEmpty
      ? null
      : UploadQueue.instance?.localPhoto(recordId);
  if (local != null) return ResizeImage(FileImage(File(local)), width: px);
  return url.isEmpty ? null : avatarImage(context, url, radius: radius);
}

/// Round photo for list rows. Tapping it opens the full-size photo; taps on
/// the rest of the row are left to the row itself.
///
/// With [recordId], a photo taken offline for that record shows from the
/// phone until it has uploaded.
class PhotoAvatar extends StatelessWidget {
  const PhotoAvatar({
    super.key,
    required this.url,
    required this.title,
    this.recordId,
    this.radius = 24,
  });

  final String url;

  /// Shown in the full-screen viewer's app bar (usually the person's name).
  final String title;
  final String? recordId;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final queue = UploadQueue.instance;
    if (queue == null || recordId == null) return _avatar(context, null);
    return ValueListenableBuilder(
      valueListenable: queue.listenable(),
      builder: (context, _, _) =>
          _avatar(context, queue.localPhoto(recordId!)),
    );
  }

  Widget _avatar(BuildContext context, String? localPath) {
    final px = (radius * 2 * MediaQuery.devicePixelRatioOf(context)).ceil();
    final ImageProvider? image = localPath != null
        ? ResizeImage(FileImage(File(localPath)), width: px)
        : (url.isEmpty ? null : avatarImage(context, url, radius: radius));
    final avatar = CircleAvatar(
      radius: radius,
      backgroundImage: image,
      child: image == null ? const Icon(Icons.person) : null,
    );
    if (image == null) return avatar;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              PhotoViewer(url: url, title: title, localPath: localPath),
        ),
      ),
      child: avatar,
    );
  }
}

/// Full-screen, pinch-to-zoom view of a photo. [localPath] (a photo still
/// waiting to upload) is shown instead of [url] when given.
class PhotoViewer extends StatelessWidget {
  const PhotoViewer({
    super.key,
    required this.url,
    required this.title,
    this.localPath,
  });

  final String url;
  final String title;
  final String? localPath;

  @override
  Widget build(BuildContext context) {
    final local = localPath;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: local != null
              ? Image.file(
                  File(local),
                  // Same cap as the network copy below.
                  cacheWidth: 2000,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image,
                      color: Colors.white, size: 64),
                )
              : CachedNetworkImage(
                  // Sharp enough to zoom into, without decoding a 12-megapixel
                  // camera original (same size as event photos).
                  imageUrl: cloudinaryResized(url, width: 2000),
                  fit: BoxFit.contain,
                  placeholder: (_, _) =>
                      const CircularProgressIndicator(color: Colors.white),
                  errorWidget: (_, _, _) => const Icon(Icons.broken_image,
                      color: Colors.white, size: 64),
                ),
        ),
      ),
    );
  }
}
