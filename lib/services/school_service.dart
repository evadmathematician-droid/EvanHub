import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../core/rtdb.dart';
import '../models/school.dart';
import '../models/user_role.dart';

/// Onboarding + school-profile operations. These write to top-level
/// `schools/...` and `users/...`, so they take a [FirebaseDatabase] directly
/// rather than a tenant-scoped ref.
class SchoolService {
  SchoolService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  /// Creates a new isolated tenant for [ownerUid] and makes them its first
  /// School Admin. Runs as ONE atomic multi-path update:
  ///   1. `schools/{schoolId}`  (ownerUid, createdAt, profile, subscription and
  ///      the owner's `members/{ownerUid}` entry, role: schoolAdmin)
  ///   2. `users/{ownerUid}`    (schoolId binding)
  ///
  /// The school is written as a single node so `database.rules.json` can verify
  /// the owner + admin membership together at creation time.
  Future<String> createSchool({
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
        'createdAt': now,
        'profile': {...meta.toMap(), 'updatedAt': now},
        'subscription': const Subscription().toMap(),
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

    return schoolId;
  }

  /// The school's `profile` and `subscription`, combined. Emits once both have
  /// loaded and again whenever either changes.
  Stream<School> streamSchool(String schoolId) {
    final school = _db.ref('schools/$schoolId');
    Map<String, dynamic>? profile;
    Map<String, dynamic>? subscription;
    final subs = <StreamSubscription<DatabaseEvent>>[];
    late final StreamController<School> controller;

    void emit() {
      if (profile == null || subscription == null) return;
      controller.add(School(
        id: schoolId,
        meta: SchoolMeta.fromMap(profile!),
        subscription: Subscription.fromMap(subscription!),
      ));
    }

    controller = StreamController<School>(
      onListen: () {
        subs
          ..add(school.child('profile').onValue.listen((e) {
            profile = asMap(e.snapshot.value);
            emit();
          }, onError: controller.addError))
          ..add(school.child('subscription').onValue.listen((e) {
            subscription = asMap(e.snapshot.value);
            emit();
          }, onError: controller.addError));
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }

  Future<void> updateMeta(String schoolId, SchoolMeta meta) {
    return _db.ref('schools/$schoolId/profile').set({
      ...meta.toMap(),
      'updatedAt': ServerValue.timestamp,
    });
  }
}
