import 'dart:typed_data';

import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';
import '../models/school_document.dart';
import 'cloudinary_service.dart';

/// School documents: the file bytes live in Cloudinary, the metadata record
/// (title, category, URL, size) lives in the Realtime Database.
class DocumentService {
  DocumentService(this._refs, {CloudinaryService? cloudinary})
      : _cloudinary = cloudinary ?? CloudinaryService();

  final TenantRefs _refs;
  final CloudinaryService _cloudinary;

  Stream<List<SchoolDocument>> watchAll() {
    return watchList(_refs.documents, SchoolDocument.fromMap).map(
      (list) => list
        ..sort((a, b) => (b.uploadedAt ?? DateTime.now())
            .compareTo(a.uploadedAt ?? DateTime.now())),
    );
  }

  /// Uploads [bytes] to Cloudinary under the tenant's folder, then records
  /// metadata in the database. Returns the new document id.
  Future<String> upload({
    required String title,
    required String category,
    required String fileName,
    required Uint8List bytes,
    required String uploadedBy,
  }) async {
    final file = await _cloudinary.upload(
      bytes: bytes,
      fileName: fileName,
      folder: _refs.documentFolder,
    );

    final ref = _refs.documents.push();
    await ref.set(
      SchoolDocument(
        id: '',
        title: title,
        category: category,
        storagePath: file.publicId,
        downloadUrl: file.url,
        sizeBytes: file.bytes,
        uploadedBy: uploadedBy,
      ).toMap(),
    );
    return ref.key!;
  }

  /// Removes the metadata record. Deleting the file itself from Cloudinary needs
  /// a signed (API-secret) request, which must not ship inside the app — remove
  /// orphaned files from the Cloudinary console or a server-side function.
  Future<void> delete(SchoolDocument document) =>
      _refs.documents.child(document.id).remove();
}
