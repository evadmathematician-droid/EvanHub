import 'package:firebase_database/firebase_database.dart';

import '../core/rtdb.dart';
import 'school_level.dart';

/// Lifecycle statuses stored on [Student.status].
class StudentStatus {
  const StudentStatus._();

  static const active = 'active';
  static const graduated = 'graduated';
  static const inactive = 'inactive';
  static const transferred = 'transferred';

  static const all = [active, graduated, inactive, transferred];

  static String label(String status) =>
      status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1);
}

/// A student record — `schools/{schoolId}/students/{studentId}`.
class Student {
  final String id;
  final String firstName;
  final String middleName;
  final String lastName;
  final DateTime? dob;
  final String gender;

  /// Copied from the chosen class at registration so lists can filter by level
  /// without looking classes up. Null for records created before levels existed.
  final SchoolLevel? level;
  final String? classId;

  /// Senior secondary only (Science / Commercial / Arts).
  final String? department;
  final String admissionNo;
  final String admissionYear;
  final String address;
  final String guardianName;
  final String guardianPhone;

  // Leaving-exam records: NPSE (primary), BECE (junior secondary),
  // WASSCE (senior secondary).
  final String npseId;
  final String npseYear;
  final String beceId;
  final String beceYear;
  final String wassceId;
  final String wassceYear;

  final String photoUrl;
  final String status; // see [StudentStatus]
  final DateTime? createdAt;

  const Student({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.middleName = '',
    this.dob,
    this.gender = '',
    this.level,
    this.classId,
    this.department,
    this.admissionNo = '',
    this.admissionYear = '',
    this.address = '',
    this.guardianName = '',
    this.guardianPhone = '',
    this.npseId = '',
    this.npseYear = '',
    this.beceId = '',
    this.beceYear = '',
    this.wassceId = '',
    this.wassceYear = '',
    this.photoUrl = '',
    this.status = StudentStatus.active,
    this.createdAt,
  });

  String get fullName => [firstName, middleName, lastName]
      .where((p) => p.trim().isNotEmpty)
      .join(' ');

  factory Student.fromMap(String id, Map<String, dynamic> data) {
    String s(String key) => (data[key] ?? '') as String;
    return Student(
      id: id,
      firstName: s('firstName'),
      middleName: s('middleName'),
      lastName: s('lastName'),
      dob: fromMillis(data['dob']),
      gender: s('gender'),
      level: SchoolLevel.fromWire(data['level']),
      classId: data['classId'] as String?,
      department: data['department'] as String?,
      admissionNo: s('admissionNo'),
      admissionYear: s('admissionYear'),
      address: s('address'),
      guardianName: s('guardianName'),
      guardianPhone: s('guardianPhone'),
      npseId: s('npseId'),
      npseYear: s('npseYear'),
      beceId: s('beceId'),
      beceYear: s('beceYear'),
      wassceId: s('wassceId'),
      wassceYear: s('wassceYear'),
      photoUrl: s('photoUrl'),
      status: (data['status'] ?? StudentStatus.active) as String,
      createdAt: fromMillis(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'dob': toMillis(dob),
        'gender': gender,
        'level': level?.wire,
        'classId': classId,
        'department': department,
        'admissionNo': admissionNo,
        'admissionYear': admissionYear,
        'address': address,
        'guardianName': guardianName,
        'guardianPhone': guardianPhone,
        'npseId': npseId,
        'npseYear': npseYear,
        'beceId': beceId,
        'beceYear': beceYear,
        'wassceId': wassceId,
        'wassceYear': wassceYear,
        'photoUrl': photoUrl,
        'status': status,
        'createdAt':
            createdAt == null ? ServerValue.timestamp : toMillis(createdAt),
      };
}
