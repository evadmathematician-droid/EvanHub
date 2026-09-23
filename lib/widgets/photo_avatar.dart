import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
      backgroundImage: url.isEmpty ? null : CachedNetworkImageProvider(url),
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
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (_, __) =>
                const CircularProgressIndicator(color: Colors.white),
            errorWidget: (_, __, ___) =>
                const Icon(Icons.broken_image, color: Colors.white, size: 64),
          ),
        ),
      ),
    );
  }
}
