import 'package:firebase_database/firebase_database.dart';

import '../core/rtdb.dart';
import '../models/invite.dart';

/// Why an invite code can't be used.
enum InviteProblem { notFound, expired, used }

/// Result of looking up a code: the invite, and a problem when it can't be
/// used (the invite is still returned for expired / used codes).
class InviteLookup {
  const InviteLookup(this.invite, this.problem);

  final Invite? invite;
  final InviteProblem? problem;

  bool get ok => problem == null;
}

/// Invite codes: looking them up and joining a school with one. Codes live at
/// `invites/{code}` (root) with a copy in `schools/{sid}/inviteList/{code}`;
/// see docs/MULTI_TENANCY.md.
class InviteService {
  InviteService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  /// Reads ONE code (allowed even before signing in).
  Future<InviteLookup> lookup(String code) async {
    final snapshot = await _db.ref('invites/$code').get();
    if (!snapshot.exists) return const InviteLookup(null, InviteProblem.notFound);
    final invite = Invite.fromMap(code, asMap(snapshot.value));
    if (invite.isUsed) return InviteLookup(invite, InviteProblem.used);
    if (invite.isExpired) return InviteLookup(invite, InviteProblem.expired);
    return InviteLookup(invite, null);
  }

  /// The school [uid] is an active member of, or null (no school, or removed
  /// from it). The database only lets a user join when this is null.
  Future<String?> activeSchoolOf(String uid) async {
    final schoolId = (await _db.ref('users/$uid/schoolId').get()).value;
    if (schoolId is! String || schoolId.isEmpty) return null;
    final member = await _db.ref('schools/$schoolId/members/$uid').get();
    return member.exists ? schoolId : null;
  }

  /// Joins [invite]'s school as ONE atomic multi-path update: marks the code
  /// used (invites + inviteList), creates the membership with the invite's
  /// role, points `users/{uid}` at the school, and writes the invite's parent
  /// links / teacher link. The database rules re-check every part.
  Future<void> join({
    required Invite invite,
    required String uid,
    required String displayName,
    required String email,
  }) {
    final sid = invite.schoolId;
    final code = invite.code;
    final now = ServerValue.timestamp;
    final links = {for (final id in invite.linkedStudentIds) id: true};
    return _db.ref().update({
      'invites/$code/usedBy': uid,
      'invites/$code/usedAt': now,
      'schools/$sid/inviteList/$code/usedBy': uid,
      'schools/$sid/members/$uid': {
        'role': invite.role.wire,
        'displayName': displayName,
        'email': email,
        'addedBy': invite.createdBy,
        'addedAt': now,
        'inviteCode': code,
        if (links.isNotEmpty) 'linkedStudentIds': links,
      },
      if (links.isNotEmpty) 'schools/$sid/parentLinks/$uid': links,
      if (invite.linkedTeacherId != null)
        'schools/$sid/teachers/${invite.linkedTeacherId}/linkedUid': uid,
      'users/$uid/schoolId': sid,
      'users/$uid/email': email,
      'users/$uid/displayName': displayName,
      'users/$uid/role': invite.role.wire, // hint only; members/{uid} decides
      'users/$uid/updatedAt': now,
    });
  }
}
