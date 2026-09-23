import 'package:firebase_database/firebase_database.dart';

/// Single source of truth for every Realtime Database path under a school.
///
/// Services never build `schools/...` strings themselves — they take a
/// [TenantRefs] built from the signed-in user's `schoolId`, which structurally
/// prevents a query from reaching another tenant's data.
class TenantRefs {
  TenantRefs(this.schoolId, {FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final String schoolId;
  final FirebaseDatabase _db;

  /// Database root, for atomic multi-path updates.
  DatabaseReference get root => _db.ref();

  DatabaseReference get school => _db.ref('schools/$schoolId');

  DatabaseReference get members => school.child('members');
  DatabaseReference get classes => school.child('classes');
  DatabaseReference get students => school.child('students');
  DatabaseReference get teachers => school.child('teachers');
  DatabaseReference get documents => school.child('documents');
  DatabaseReference get announcements => school.child('announcements');
  DatabaseReference get events => school.child('events');
  DatabaseReference get promotions => school.child('promotions');

  /// Cloudinary folder for a school's document files.
  String get documentFolder => 'schools/$schoolId/documents';

  /// Cloudinary folders for photos and event images.
  String get studentPhotoFolder => 'schools/$schoolId/students';
  String get teacherPhotoFolder => 'schools/$schoolId/teachers';
  String get eventFolder => 'schools/$schoolId/events';
  String get teacherDocumentFolder => 'schools/$schoolId/teachers/documents';

  /// Cloudinary folder for the school's cover photo and badge.
  String get schoolProfileFolder => 'schools/$schoolId/profile';
}
