import 'package:firebase_database/firebase_database.dart';

import '../core/rtdb.dart';

/// A school event / news post — `schools/{schoolId}/events/{id}`.
/// Mirrors the Ninka app's "school update": a heading, a text and one image.
class SchoolEvent {
  final String id;
  final String title;
  final String text;
  final String imageUrl;
  final String authorUid;
  final DateTime? createdAt;

  const SchoolEvent({
    required this.id,
    required this.title,
    this.text = '',
    this.imageUrl = '',
    this.authorUid = '',
    this.createdAt,
  });

  factory SchoolEvent.fromMap(String id, Map<String, dynamic> data) {
    String s(String key) => (data[key] ?? '') as String;
    return SchoolEvent(
      id: id,
      title: s('title'),
      text: s('text'),
      imageUrl: s('imageUrl'),
      authorUid: s('authorUid'),
      createdAt: fromMillis(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'text': text,
        'imageUrl': imageUrl,
        'authorUid': authorUid,
        'createdAt': ServerValue.timestamp,
      };
}
