/// Roles a user account can hold within a school.
///
/// [superAdmin] is reserved for a future franchise/network mode where one account
/// manages several schools; it is modelled now but no UI targets it yet.
enum UserRole {
  schoolAdmin,
  teacher,
  parentStudent,
  superAdmin;

  /// Wire value stored in the Realtime Database (`members/{uid}.role`, `users/{uid}.role`).
  String get wire => name;

  String get label => switch (this) {
        UserRole.schoolAdmin => 'School Admin',
        UserRole.teacher => 'Teacher',
        UserRole.parentStudent => 'Parent / Student',
        UserRole.superAdmin => 'Super Admin',
      };

  static UserRole fromWire(Object? value) {
    return UserRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => UserRole.parentStudent,
    );
  }

  bool get canManageSchool =>
      this == UserRole.schoolAdmin || this == UserRole.superAdmin;

  bool get canManageStudents => canManageSchool || this == UserRole.teacher;
}
