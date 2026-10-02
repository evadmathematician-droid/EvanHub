import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/image_url.dart';

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

/// Round photo for list rows. Tapping it opens the full-size photo; taps on
/// the rest of the row are left to the row itself.
class PhotoAvatar extends StatelessWidget {
  const PhotoAvatar({
    super.key,
    required this.url,
    required this.title,
    this.radius = 24,
  });

  final String url;

  /// Shown in the full-screen viewer's app bar (usually the person's name).
  final String title;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: radius,
      backgroundImage:
          url.isEmpty ? null : avatarImage(context, url, radius: radius),
      child: url.isEmpty ? const Icon(Icons.person) : null,
    );
    if (url.isEmpty) return avatar;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PhotoViewer(url: url, title: title),
        ),
      ),
      child: avatar,
    );
  }
}

/// Full-screen, pinch-to-zoom view of a photo.
class PhotoViewer extends StatelessWidget {
  const PhotoViewer({super.key, required this.url, required this.title});

  final String url;
  final String title;

  @override
  Widget build(BuildContext context) {
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
          child: CachedNetworkImage(
            // Sharp enough to zoom into, without decoding a 12-megapixel
            // camera original (same size as event photos).
            imageUrl: cloudinaryResized(url, width: 2000),
            fit: BoxFit.contain,
            placeholder: (_, _) =>
                const CircularProgressIndicator(color: Colors.white),
            errorWidget: (_, _, _) =>
                const Icon(Icons.broken_image, color: Colors.white, size: 64),
          ),
        ),
      ),
    );
  }
}
