import 'package:firebase_database/firebase_database.dart';

import '../core/rtdb.dart';

/// Metadata for an uploaded school file —
/// `schools/{schoolId}/documents/{docId}`. The bytes live in Cloudinary;
/// [storagePath] is the Cloudinary public id, [downloadUrl] the delivery URL.
class SchoolDocument {
  final String id;
  final String title;
  final String category;
  final String storagePath;
  final String downloadUrl;
  final int sizeBytes;
  final String uploadedBy;
  final DateTime? uploadedAt;

  const SchoolDocument({
    required this.id,
    required this.title,
    this.category = 'general',
    this.storagePath = '',
    this.downloadUrl = '',
    this.sizeBytes = 0,
    this.uploadedBy = '',
    this.uploadedAt,
  });

  factory SchoolDocument.fromMap(String id, Map<String, dynamic> data) {
    return SchoolDocument(
      id: id,
      title: (data['title'] ?? '') as String,
      category: (data['category'] ?? 'general') as String,
      storagePath: (data['storagePath'] ?? '') as String,
      downloadUrl: (data['downloadUrl'] ?? '') as String,
      sizeBytes: (data['sizeBytes'] ?? 0) as int,
      uploadedBy: (data['uploadedBy'] ?? '') as String,
      uploadedAt: fromMillis(data['uploadedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'category': category,
        'storagePath': storagePath,
        'downloadUrl': downloadUrl,
        'sizeBytes': sizeBytes,
        'uploadedBy': uploadedBy,
        'uploadedAt': ServerValue.timestamp,
      };
}
