import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shows a whole picture at its real proportions: full width, height from the
/// image's own aspect ratio, never cropped (`BoxFit.contain`). Very tall images
/// are capped at [maxHeightFraction] of the screen height and shown whole
/// inside that, on a neutral background.
///
/// Tapping opens [showFullScreenImage] with [fullImage] (defaults to [image]).
class AdaptiveImage extends StatefulWidget {
  const AdaptiveImage({
    super.key,
    required this.image,
    this.fullImage,
    this.maxHeightFraction = 0.7,
    this.borderRadius = 12,
    this.enableFullScreen = true,
  });

  final ImageProvider image;
  final ImageProvider? fullImage;
  final double maxHeightFraction;
  final double borderRadius;
  final bool enableFullScreen;

  @override
  State<AdaptiveImage> createState() => _AdaptiveImageState();
}

class _AdaptiveImageState extends State<AdaptiveImage> {
  /// Aspect ratios already measured, so a card scrolled back into view gets
  /// its final size at once instead of jumping from the placeholder.
  static final _knownRatios = <ImageProvider, double>{};

  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _ratio;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(AdaptiveImage old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image) {
      _ratio = null;
      _failed = false;
      _resolve();
    }
  }

  void _resolve() {
    _ratio ??= _knownRatios[widget.image];
    final stream =
        widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stopListening();
    _listener = ImageStreamListener(
      (info, _) {
        final w = info.image.width;
        final h = info.image.height;
        info.dispose();
        if (w <= 0 || h <= 0) return;
        final ratio = w / h;
        _knownRatios[widget.image] = ratio;
        if (mounted && ratio != _ratio) setState(() => _ratio = ratio);
      },
      onError: (error, _) {
        debugPrint('Image failed to load: $error');
        if (mounted) setState(() => _failed = true);
      },
    );
    _stream = stream..addListener(_listener!);
  }

  void _stopListening() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _listener = null;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight =
        MediaQuery.sizeOf(context).height * widget.maxHeightFraction;
    final ratio = _ratio;

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      // Placeholder / error keep a landscape box until the size is known.
      final height = ratio == null || _failed
          ? math.min(width * 9 / 16, maxHeight)
          : math.min(width / ratio, maxHeight);

      Widget child;
      if (_failed) {
        child = const Center(
          child: Icon(Icons.broken_image_outlined,
              color: AppColors.textMuted, size: 40),
        );
      } else if (ratio == null) {
        child = const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        );
      } else {
        child = Image(
          image: widget.image,
          fit: BoxFit.contain,
          width: width,
          height: height,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const Center(
            child: Icon(Icons.broken_image_outlined,
                color: AppColors.textMuted, size: 40),
          ),
        );
      }

      final box = ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: ColoredBox(
          color: AppColors.background,
          child: SizedBox(width: width, height: height, child: child),
        ),
      );

      if (!widget.enableFullScreen || _failed || ratio == null) return box;
      return GestureDetector(
        onTap: () =>
            showFullScreenImage(context, widget.fullImage ?? widget.image),
        child: box,
      );
    });
  }
}

/// Full-screen viewer: black background, pinch or double-tap to zoom, and a
/// close button.
Future<void> showFullScreenImage(BuildContext context, ImageProvider image) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _FullScreenImage(image: image),
  ));
}

class _FullScreenImage extends StatefulWidget {
  const _FullScreenImage({required this.image});

  final ImageProvider image;

  @override
  State<_FullScreenImage> createState() => _FullScreenImageState();
}

class _FullScreenImageState extends State<_FullScreenImage> {
  final _controller = TransformationController();
  TapDownDetails? _doubleTapAt;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_controller.value != Matrix4.identity()) {
      _controller.value = Matrix4.identity();
      return;
    }
    final p = _doubleTapAt?.localPosition ?? Offset.zero;
    const scale = 2.5;
    _controller.value = Matrix4.identity()
      ..translateByDouble(-p.dx * (scale - 1), -p.dy * (scale - 1), 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTapDown: (d) => _doubleTapAt = d,
              onDoubleTap: _toggleZoom,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image(
                    image: widget.image,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const CircularProgressIndicator(color: Colors.white),
                    errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 56),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton.filled(
                style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white),
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
