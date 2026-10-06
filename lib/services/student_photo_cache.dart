import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Pupils' passport photos kept on the phone for exports, so a PDF / Word /
/// image record or the pupils register shows the photo even with data off.
///
/// Each photo is a small Cloudinary thumbnail (300 px wide JPEG) saved in the
/// app's own storage as `{studentId}_{fingerprint of the photo URL}.jpg`, so
/// a changed photo gets a new file and the old one is deleted. Phones only:
/// on the web every load is a plain download. Cleared on sign-out.
class StudentPhotoCache {
  StudentPhotoCache._();

  static final instance = StudentPhotoCache._();

  static const _downloadWait = Duration(seconds: 10);

  /// The 300 px JPEG thumbnail of a Cloudinary photo (little data, plenty
  /// for a passport-size frame). Other URLs are used as they are.
  static String thumbnailUrl(String url) {
    const marker = '/upload/';
    final at = url.indexOf(marker);
    if (at == -1) return url;
    final split = at + marker.length;
    final rest = url.substring(split).split('/');
    // Drop any transformation already in the URL (e.g. "c_fill,w_200").
    final transform = RegExp(r'^[a-z]{1,3}_[^/,]+(,[a-z]{1,3}_[^/,]+)*$');
    var i = 0;
    while (i < rest.length - 1 && transform.hasMatch(rest[i])) {
      i++;
    }
    return '${url.substring(0, split)}w_300,c_limit,q_auto,f_jpg/'
        '${rest.sublist(i).join('/')}';
  }

  Directory? _dir;
  final _inFlight = <String, Future<Uint8List?>>{};

  Future<Directory> _folder() async {
    final existing = _dir;
    if (existing != null) return existing;
    final docs = await getApplicationDocumentsDirectory();
    final dir =
        Directory('${docs.path}${Platform.pathSeparator}student_photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  static String _prefix(String studentId) =>
      '${studentId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}_';

  static String _fileName(String studentId, String url) =>
      '${_prefix(studentId)}'
      '${sha1.convert(utf8.encode(url)).toString().substring(0, 16)}.jpg';

  /// The saved copy of [studentId]'s photo at [url], or null (not saved yet,
  /// on the web, or no photo).
  Future<Uint8List?> local(String studentId, String url) async {
    if (kIsWeb || url.trim().isEmpty) return null;
    try {
      final file = File(
          '${(await _folder()).path}${Platform.pathSeparator}${_fileName(studentId, url)}');
      return await file.exists() ? await file.readAsBytes() : null;
    } catch (e) {
      debugPrint('Photo cache read failed: $e');
      return null;
    }
  }

  /// The saved copy, else — when [download] is true — the thumbnail fetched
  /// now and kept for next time. Null when there is no photo or it can't be
  /// had (offline and never saved): callers show a placeholder.
  Future<Uint8List?> load(String studentId, String url,
      {bool download = true}) async {
    if (url.trim().isEmpty) return null;
    final saved = await local(studentId, url);
    if (saved != null || !download) return saved;
    final key = '$studentId|$url';
    return _inFlight[key] ??=
        _download(studentId, url).whenComplete(() => _inFlight.remove(key));
  }

  /// Makes sure a copy is saved (a photo just shown online). Never throws.
  Future<void> keep(String studentId, String url) async {
    if (kIsWeb) return;
    await load(studentId, url);
  }

  Future<Uint8List?> _download(String studentId, String url) async {
    try {
      final response =
          await http.get(Uri.parse(thumbnailUrl(url))).timeout(_downloadWait);
      final bytes = response.bodyBytes;
      if (response.statusCode != 200 || !_isImage(bytes)) return null;
      if (!kIsWeb) await _save(studentId, url, bytes);
      return bytes;
    } catch (e) {
      debugPrint('Photo download failed ($studentId): $e');
      return null;
    }
  }

  Future<void> _save(String studentId, String url, Uint8List bytes) async {
    final dir = await _folder();
    final name = _fileName(studentId, url);
    final temp = File('${dir.path}${Platform.pathSeparator}$name.part');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename('${dir.path}${Platform.pathSeparator}$name');
    // An older photo of the same pupil is no longer needed.
    final prefix = _prefix(studentId);
    await for (final f in dir.list()) {
      final base = f.uri.pathSegments.last;
      if (f is File && base.startsWith(prefix) && base != name) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  /// Quietly saves every photo not saved yet, one at a time. Stops at the
  /// first network failure (the connection dropped). Returns how many were
  /// downloaded.
  Future<int> prefetch(Iterable<(String, String)> photos) async {
    if (kIsWeb) return 0;
    var done = 0;
    for (final (id, url) in photos) {
      if (url.trim().isEmpty || await local(id, url) != null) continue;
      if (await _download(id, url) == null) break;
      done++;
    }
    return done;
  }

  /// Deletes every saved photo (sign-out).
  Future<void> clearAll() async {
    if (kIsWeb) return;
    try {
      final dir = await _folder();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('Could not clear saved photos: $e');
    }
    _dir = null;
  }

  /// JPEG or PNG, so an error page saved as a "photo" is never used.
  static bool _isImage(Uint8List b) =>
      b.length > 8 &&
      ((b[0] == 0xFF && b[1] == 0xD8) ||
          (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47));
}
