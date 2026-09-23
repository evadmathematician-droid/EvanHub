import 'package:firebase_database/firebase_database.dart';

import '../core/rtdb.dart';

/// A school announcement — `schools/{schoolId}/announcements/{id}`.
///
/// [audience] is either the sentinel `'school'` (visible to everyone) or a
/// specific `classId`.
class Announcement {
  static const audienceSchool = 'school';

  final String id;
  final String title;
  final String body;
  final String audience;
  final String authorUid;
  final DateTime? createdAt;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.audience = audienceSchool,
    this.authorUid = '',
    this.createdAt,
  });

  bool get isSchoolWide => audience == audienceSchool;

  factory Announcement.fromMap(String id, Map<String, dynamic> data) {
    return Announcement(
      id: id,
      title: (data['title'] ?? '') as String,
      body: (data['body'] ?? '') as String,
      audience: (data['audience'] ?? audienceSchool) as String,
      authorUid: (data['authorUid'] ?? '') as String,
      createdAt: fromMillis(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'body': body,
        'audience': audience,
        'authorUid': authorUid,
        'createdAt': ServerValue.timestamp,
      };
}
