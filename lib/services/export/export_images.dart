import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../core/image_url.dart';

/// Images for the student record PDF (badge, stamp, student photo), kept in
/// the app's image cache on the phone so an export works offline once each
/// image has been fetched online.
///
/// Cloudinary is asked for JPG (photos) and PNG (badge / stamp, which may be
/// transparent) rather than its automatic format, which can be WebP — a
/// format PDFs handle poorly.
class ExportImages {
  ExportImages._();

  static const _wait = Duration(seconds: 12);

  static String? _url(String? url, {required int width, required String format}) {
    if (url == null || url.trim().isEmpty) return null;
    return cloudinaryResized(url, width: width)
        .replaceFirst(',f_auto/', ',f_$format/');
  }

  static String? badgeUrl(String? url) => _url(url, width: 300, format: 'png');
  static String? stampUrl(String? url) => _url(url, width: 400, format: 'png');
  static String? photoUrl(String? url) => _url(url, width: 500, format: 'jpg');

  /// The image's bytes from the phone's cache, else downloaded (and then
  /// cached). Null when there is no image or it can't be had offline.
  static Future<Uint8List?> load(String? exportUrl) async {
    if (exportUrl == null) return null;
    try {
      final file =
          await DefaultCacheManager().getSingleFile(exportUrl).timeout(_wait);
      return await file.readAsBytes();
    } catch (e) {
      debugPrint('Export image unavailable ($exportUrl): $e');
      return null;
    }
  }

  /// Fetches images into the cache in the background while online, so a
  /// later export works with no internet.
  static void prefetch(Iterable<String?> exportUrls) {
    for (final url in exportUrls) {
      if (url != null) unawaited(load(url));
    }
  }
}
