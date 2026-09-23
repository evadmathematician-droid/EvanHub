import 'package:firebase_database/firebase_database.dart';

import '../core/rtdb.dart';
import '../models/school.dart';
import '../models/user_role.dart';

/// Onboarding + school-meta operations. These write to top-level `schools/...`
/// and `users/...`, so they take a [FirebaseDatabase] directly rather than a
/// tenant-scoped ref.
class SchoolService {
  SchoolService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  /// Creates a new isolated tenant for [ownerUid] and makes them its first
  /// School Admin. Runs as ONE atomic multi-path update:
  ///   1. `schools/{schoolId}`  (ownerUid + meta + subscription, with the
  ///      owner's `members/{ownerUid}` entry, role: schoolAdmin, nested inside)
  ///   2. `users/{ownerUid}`    (schoolId binding + role)
  ///
  /// The school is written as a single node so `database.rules.json` can verify
  /// the owner + admin membership together at creation time.
  Future<School> createSchool({
    required String ownerUid,
    required String ownerName,
    required String ownerEmail,
    required SchoolMeta meta,
  }) async {
    final schoolId = _db.ref('schools').push().key!;
    final now = ServerValue.timestamp;

    await _db.ref().update({
      'schools/$schoolId': {
        'ownerUid': ownerUid,
        'meta': meta.toMap(),
        'subscription': const Subscription().toMap(),
        'createdAt': now,
        'members': {
          ownerUid: {
            'role': UserRole.schoolAdmin.wire,
            'displayName': ownerName,
            'email': ownerEmail,
            'addedBy': ownerUid,
            'addedAt': now,
          },
        },
      },
      'users/$ownerUid': {
        'email': ownerEmail,
        'displayName': ownerName,
        'schoolId': schoolId,
        'role': UserRole.schoolAdmin.wire,
        'createdAt': now,
        'updatedAt': now,
      },
    });

    return School(id: schoolId, ownerUid: ownerUid, meta: meta);
  }

  Stream<School> streamSchool(String schoolId) {
    return _db
        .ref('schools/$schoolId')
        .onValue
        .map((e) => School.fromMap(schoolId, asMap(e.snapshot.value)));
  }

  Future<void> updateMeta(String schoolId, SchoolMeta meta) {
    return _db.ref('schools/$schoolId').update({
      'meta': meta.toMap(),
      'updatedAt': ServerValue.timestamp,
    });
  }
}
