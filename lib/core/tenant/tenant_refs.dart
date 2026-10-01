import 'package:firebase_database/firebase_database.dart';

/// Single source of truth for every Realtime Database path under a school.
///
/// Services never build `schools/...` strings themselves — they take a
/// [TenantRefs] built from the signed-in user's `schoolId`, which structurally
/// prevents a query from reaching another tenant's data.
///
/// Branches are split by who may read them (see `database.rules.json`):
/// public records (`students`, `teachers`) and their private halves
/// (`studentPrivate`, `teacherPrivate`) share the same record id.
class TenantRefs {
  TenantRefs(this.schoolId, {FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final String schoolId;
  final FirebaseDatabase _db;

  /// Database root, for atomic multi-path updates.
  DatabaseReference get root => _db.ref();

  DatabaseReference get school => _db.ref('schools/$schoolId');

  DatabaseReference get profile => school.child('profile');
  DatabaseReference get subscription => school.child('subscription');
  DatabaseReference get members => school.child('members');
  DatabaseReference get classes => school.child('classes');
  DatabaseReference get students => school.child('students');
  DatabaseReference get studentPrivate => school.child('studentPrivate');
  DatabaseReference get teachers => school.child('teachers');
  DatabaseReference get teacherPrivate => school.child('teacherPrivate');
  DatabaseReference get documents => school.child('documents');
  DatabaseReference get announcements => school.child('announcements');
  DatabaseReference get events => school.child('events');
  DatabaseReference get promotions => school.child('promotions');
  DatabaseReference get settings => school.child('settings');

  /// Salted hash of the password that guards deleting school history.
  DatabaseReference get deletePassword => settings.child('deletePassword');

  /// `index/admissionNo/{indexKey}` → studentId.
  DatabaseReference get admissionIndex => school.child('index/admissionNo');

  /// `index/nin/{nin}` → teacherId.
  DatabaseReference get ninIndex => school.child('index/nin');

  /// Pre-Phase-1 layout: the school profile lived at `meta`. Read only by the
  /// one-time migration.
  DatabaseReference get legacyMeta => school.child('meta');

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
