import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';
import '../models/school_event.dart';
import 'cloudinary_service.dart';

/// School events: the image lives in Cloudinary, the post itself in the
/// Realtime Database.
class EventService {
  EventService(this._refs, {CloudinaryService? cloudinary})
      : _cloudinary = cloudinary ?? CloudinaryService();

  final TenantRefs _refs;
  final CloudinaryService _cloudinary;

  static const _uploadTimeout = Duration(seconds: 90);
  static const _dbTimeout = Duration(seconds: 20);

  /// Newest first.
  Stream<List<SchoolEvent>> watchAll() {
    return watchList(_refs.events, SchoolEvent.fromMap).map(
      (list) => list
        ..sort((a, b) => (b.createdAt ?? DateTime.now())
            .compareTo(a.createdAt ?? DateTime.now())),
    );
  }

  /// A new event id. Push keys are generated on the phone (no network needed)
  /// and sort by time, so offline posts get their final id straight away.
  String newId() => _refs.events.push().key!;

  /// Compresses and uploads [imageBytes] (when given), then saves the event
  /// under [id] (a new id when null). Safe to retry with the same [id]: the
  /// Cloudinary asset is named after it, and an event that an earlier attempt
  /// already saved is left as it is.
  Future<String> add({
    required String title,
    required String text,
    required String authorUid,
    Uint8List? imageBytes,
    String? imageName,
    String? id,
  }) async {
    final eventId = id ?? newId();
    final ref = _refs.events.child(eventId);

    // The rules only accept `createdAt == now` on create, so re-writing an
    // event that already exists would be rejected — and means an earlier
    // attempt succeeded anyway.
    final existing = await ref.get().timeout(_dbTimeout);
    if (existing.exists) return eventId;

    var imageUrl = '';
    if (imageBytes != null) {
      final upload = await _cloudinary
          .upload(
            bytes: await compressForUpload(imageBytes),
            fileName: 'event_$eventId.jpg',
            folder: _refs.eventFolder,
            publicId: eventId,
          )
          .timeout(_uploadTimeout);
      imageUrl = upload.url;
    }
    await ref
        .set(SchoolEvent(
          id: eventId,
          title: title,
          text: text,
          imageUrl: imageUrl,
          authorUid: authorUid,
        ).toMap())
        .timeout(_dbTimeout);
    return eventId;
  }

  Future<void> delete(String id) => _refs.events.child(id).remove();
}

/// Shrinks a photo to at most 1600px on its longer side, JPEG quality 80 —
/// keeps the whole picture (no cropping). Falls back to the original bytes
/// where compression isn't available (web, Windows, Linux) or doesn't help.
Future<Uint8List> compressForUpload(Uint8List bytes) async {
  if (kIsWeb) return bytes;
  try {
    final out = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 1600,
      minHeight: 1600,
      quality: 80,
    );
    return out.isNotEmpty && out.length < bytes.length ? out : bytes;
  } catch (e) {
    debugPrint('Image compression unavailable, uploading original: $e');
    return bytes;
  }
}
