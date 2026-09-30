import '../core/rtdb.dart';
import 'user_role.dart';

/// An invite code — `invites/{code}` at the database root (readable by anyone
/// who knows the code). A school admin creates it; the person who joins with
/// it fills in [usedBy] / [usedAt].
class Invite {
  final String code;
  final String schoolId;
  final String schoolName;

  /// [UserRole.teacher] or [UserRole.parentStudent].
  final UserRole role;

  /// Teacher invites: the teacher record to link to the new login.
  final String? linkedTeacherId;

  /// Parent invites: the students the parent may see.
  final Set<String> linkedStudentIds;

  final String createdBy;
  final DateTime? createdAt;
  final DateTime expiresAt;
  final String? usedBy;
  final DateTime? usedAt;

  const Invite({
    required this.code,
    required this.schoolId,
    required this.schoolName,
    required this.role,
    required this.createdBy,
    required this.expiresAt,
    this.linkedTeacherId,
    this.linkedStudentIds = const {},
    this.createdAt,
    this.usedBy,
    this.usedAt,
  });

  bool get isUsed => usedBy != null && usedBy!.isNotEmpty;

  /// Judged by this device's clock; the database rules use server time.
  bool get isExpired => !DateTime.now().isBefore(expiresAt);

  bool get isPending => !isUsed && !isExpired;

  factory Invite.fromMap(String code, Map<String, dynamic> data) {
    return Invite(
      code: code,
      schoolId: (data['schoolId'] ?? '') as String,
      schoolName: (data['schoolName'] ?? '') as String,
      role: UserRole.fromWire(data['role']),
      linkedTeacherId: data['linkedTeacherId'] as String?,
      linkedStudentIds: asMap(data['linkedStudentIds']).keys.toSet(),
      createdBy: (data['createdBy'] ?? '') as String,
      createdAt: fromMillis(data['createdAt']),
      expiresAt: fromMillis(data['expiresAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      usedBy: data['usedBy'] as String?,
      usedAt: fromMillis(data['usedAt']),
    );
  }
}
