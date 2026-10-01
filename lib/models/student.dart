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

/// A student. Stored in two halves with the same id (see
/// `database.rules.json`):
///  - `schools/{schoolId}/students/{id}` — public fields ([toPublicMap]);
///  - `schools/{schoolId}/studentPrivate/{id}` — personal details and exam
///    records ([toPrivateMap]).
/// Lists load only the public half, so private fields hold their defaults
/// until [withPrivate] fills them in.
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

  /// When the student last moved up a class (or graduated). Null until
  /// their first promotion.
  final DateTime? lastPromotedAt;

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
    this.lastPromotedAt,
  });

  String get fullName => [firstName, middleName, lastName]
      .where((p) => p.trim().isNotEmpty)
      .join(' ');

  /// How long a pupil may go without promotion before they count as a
  /// repeater. A school year promotes once, so 10 months without a move means
  /// the last promotion passed them by.
  static const repeaterMonths = 10;

  /// When the repeater clock started: the last promotion, or registration
  /// for a pupil never promoted.
  DateTime? get inClassSince => lastPromotedAt ?? createdAt;

  /// An active pupil with no promotion for [repeaterMonths] months. Shown in
  /// red as "Repeater"; nothing about it is stored.
  bool isRepeater([DateTime? now]) {
    final since = inClassSince;
    if (status != StudentStatus.active || since == null) return false;
    final n = now ?? DateTime.now();
    final cutoff = DateTime(n.year, n.month - repeaterMonths, n.day);
    return !since.isAfter(cutoff);
  }

  /// Builds a student from its public and private halves. Passing the same
  /// map twice reads a pre-Phase-1 record that held every field in one place.
  factory Student.fromParts(
    String id,
    Map<String, dynamic> public,
    Map<String, dynamic> private,
  ) {
    String s(String key) => (public[key] ?? '') as String;
    String p(String key) => (private[key] ?? '') as String;
    return Student(
      id: id,
      firstName: s('firstName'),
      middleName: s('middleName'),
      lastName: s('lastName'),
      gender: s('gender'),
      level: SchoolLevel.fromWire(public['level']),
      classId: public['classId'] as String?,
      department: public['department'] as String?,
      admissionNo: s('admissionNo'),
      admissionYear: s('admissionYear'),
      photoUrl: s('photoUrl'),
      status: (public['status'] ?? StudentStatus.active) as String,
      createdAt: fromMillis(public['createdAt']),
      lastPromotedAt: fromMillis(public['lastPromotedAt']),
      dob: fromMillis(private['dob']),
      address: p('address'),
      guardianName: p('guardianName'),
      guardianPhone: p('guardianPhone'),
      npseId: p('npseId'),
      npseYear: p('npseYear'),
      beceId: p('beceId'),
      beceYear: p('beceYear'),
      wassceId: p('wassceId'),
      wassceYear: p('wassceYear'),
    );
  }

  /// Public half only (what list screens load).
  factory Student.fromMap(String id, Map<String, dynamic> data) =>
      Student.fromParts(id, data, const {});

  /// This student with the private half from `studentPrivate/{id}` filled in.
  Student withPrivate(Map<String, dynamic> private) =>
      Student.fromParts(id, toPublicMap(), private);

  /// `students/{id}` — readable by admins and teachers.
  Map<String, dynamic> toPublicMap() => {
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'gender': gender,
        'level': level?.wire,
        'classId': classId,
        'department': department,
        'admissionNo': admissionNo,
        'admissionYear': admissionYear,
        'status': status,
        'photoUrl': photoUrl,
        'createdAt':
            createdAt == null ? ServerValue.timestamp : toMillis(createdAt),
        // Kept as is when the record is edited; promotion sets it.
        'lastPromotedAt': toMillis(lastPromotedAt),
      };

  /// `studentPrivate/{id}` — personal details and exam records.
  Map<String, dynamic> toPrivateMap() => {
        'dob': toMillis(dob),
        'address': address,
        'guardianName': guardianName,
        'guardianPhone': guardianPhone,
        'npseId': npseId,
        'npseYear': npseYear,
        'beceId': beceId,
        'beceYear': beceYear,
        'wassceId': wassceId,
        'wassceYear': wassceYear,
      };
}
