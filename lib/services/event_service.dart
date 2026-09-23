import 'dart:typed_data';

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

  /// Newest first.
  Stream<List<SchoolEvent>> watchAll() {
    return watchList(_refs.events, SchoolEvent.fromMap).map(
      (list) => list
        ..sort((a, b) => (b.createdAt ?? DateTime.now())
            .compareTo(a.createdAt ?? DateTime.now())),
    );
  }

  /// Uploads [imageBytes] (when given) then saves the event.
  Future<String> add({
    required String title,
    required String text,
    required String authorUid,
    Uint8List? imageBytes,
    String? imageName,
  }) async {
    var imageUrl = '';
    if (imageBytes != null) {
      final upload = await _cloudinary.upload(
        bytes: imageBytes,
        fileName: imageName ?? 'event.jpg',
        folder: _refs.eventFolder,
      );
      imageUrl = upload.url;
    }
    final ref = _refs.events.push();
    await ref.set(SchoolEvent(
      id: '',
      title: title,
      text: text,
      imageUrl: imageUrl,
      authorUid: authorUid,
    ).toMap());
    return ref.key!;
  }

  Future<void> delete(String id) => _refs.events.child(id).remove();
}
