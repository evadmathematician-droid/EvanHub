import 'package:firebase_database/firebase_database.dart';


import 'user_role.dart';

/// The `users/{uid}` document — a per-account tenant binding read at launch so the
/// app knows which school (if any) the signed-in user belongs to.
class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final String? schoolId;
  final UserRole role;

  const AppUser({
    required this.uid,
    required this.email,
    this.displayName = '',
    this.schoolId,
    this.role = UserRole.parentStudent,
  });

  bool get hasSchool => schoolId != null && schoolId!.isNotEmpty;

  factory AppUser.fromMap(String uid, Map<String, dynamic> data) {
    return AppUser(
      uid: uid,
      email: (data['email'] ?? '') as String,
      displayName: (data['displayName'] ?? '') as String,
      schoolId: data['schoolId'] as String?,
      role: UserRole.fromWire(data['role']),
    );
  }

  Map<String, dynamic> toMap() => {
        'email': email,
        'displayName': displayName,
        'schoolId': schoolId,
        'role': role.wire,
        'updatedAt': ServerValue.timestamp,
      };
}
