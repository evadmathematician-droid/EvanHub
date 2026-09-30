import 'package:firebase_database/firebase_database.dart';

import '../core/rtdb.dart';

/// A file attached to a teacher record (certificate, CV, ID …). The bytes live
/// in Cloudinary; only the link is stored on the teacher.
class TeacherDocument {
  final String title;
  final String url;
  final String fileName;
  final int sizeBytes;

  const TeacherDocument({
    required this.title,
    required this.url,
    this.fileName = '',
    this.sizeBytes = 0,
  });

  factory TeacherDocument.fromMap(Map<String, dynamic> m) => TeacherDocument(
        title: (m['title'] ?? '') as String,
        url: (m['url'] ?? '') as String,
        fileName: (m['fileName'] ?? '') as String,
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'url': url,
        'fileName': fileName,
        'sizeBytes': sizeBytes,
      };
}

/// A teacher. Stored in two halves with the same id (see
/// `database.rules.json`):
///  - `schools/{schoolId}/teachers/{id}` — public fields ([toPublicMap]),
///    readable by admins and teachers;
///  - `schools/{schoolId}/teacherPrivate/{id}` — NIN, contact details,
///    documents … ([toPrivateMap]), admins only.
/// Lists load only the public half; [withPrivate] fills in the rest.
///
/// This is the HR/records entry. It is separate from a `members/{uid}` login;
/// link them by setting [linkedUid] once the teacher has an account.
///
/// The registration fields (NIN, marital status, pincode, qualification,
/// experience, level, stream, photo) mirror the Ninka school app's teacher form.
class Teacher {
  final String id;
  final String firstName;

  /// Optional, up to two words (e.g. "Abu Bakarr").
  final String middleName;
  final String lastName;
  final String email;
  final String phone;
  final List<String> subjects;
  final String employmentType; // full_time | part_time | contract
  final String status; // active | inactive
  final String? linkedUid;
  final DateTime? createdAt;

  /// National ID number: 8 upper-case letters/digits, unique within a school.
  final String nin;
  final String gender; // Male | Female
  final String maritalStatus; // Single | Married
  final DateTime? dob;
  final String address;
  final bool isPincoded;
  final String pincode; // 6 digits, only when [isPincoded]
  final String qualification;
  final String experience;

  /// JSS | SSS | BOTH — which part of the secondary school they teach.
  final String level;

  /// Arts | Science | Commercial — only for SSS / BOTH.
  final String stream;
  final String photoUrl;
  final List<TeacherDocument> documents;

  const Teacher({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.middleName = '',
    this.email = '',
    this.phone = '',
    this.subjects = const [],
    this.employmentType = 'full_time',
    this.status = 'active',
    this.linkedUid,
    this.createdAt,
    this.nin = '',
    this.gender = '',
    this.maritalStatus = '',
    this.dob,
    this.address = '',
    this.isPincoded = false,
    this.pincode = '',
    this.qualification = '',
    this.experience = '',
    this.level = '',
    this.stream = '',
    this.photoUrl = '',
    this.documents = const [],
  });

  String get fullName => [firstName, middleName, lastName]
      .where((p) => p.trim().isNotEmpty)
      .join(' ');

  /// Builds a teacher from its public and private halves. Passing the same
  /// map twice reads a pre-Phase-1 record that held every field in one place.
  factory Teacher.fromParts(
    String id,
    Map<String, dynamic> public,
    Map<String, dynamic> private,
  ) {
    String s(String key) => (public[key] ?? '') as String;
    String p(String key) => (private[key] ?? '') as String;
    return Teacher(
      id: id,
      firstName: s('firstName'),
      middleName: s('middleName'),
      lastName: s('lastName'),
      gender: s('gender'),
      subjects:
          (public['subjects'] as List?)?.map((e) => '$e').toList() ?? const [],
      level: s('level'),
      stream: s('stream'),
      employmentType: (public['employmentType'] ?? 'full_time') as String,
      status: (public['status'] ?? 'active') as String,
      photoUrl: s('photoUrl'),
      linkedUid: public['linkedUid'] as String?,
      createdAt: fromMillis(public['createdAt']),
      nin: p('nin'),
      isPincoded: private['isPincoded'] == true,
      pincode: p('pincode'),
      maritalStatus: p('maritalStatus'),
      dob: fromMillis(private['dob']),
      email: p('email'),
      phone: p('phone'),
      address: p('address'),
      qualification: p('qualification'),
      experience: p('experience'),
      documents: [
        for (final d in (private['documents'] as List?) ?? const [])
          if (d is Map) TeacherDocument.fromMap(asMap(d)),
      ],
    );
  }

  /// Public half only (what list screens load).
  factory Teacher.fromMap(String id, Map<String, dynamic> data) =>
      Teacher.fromParts(id, data, const {});

  /// This teacher with the private half from `teacherPrivate/{id}` filled in.
  Teacher withPrivate(Map<String, dynamic> private) =>
      Teacher.fromParts(id, toPublicMap(), private);

  /// `teachers/{id}` — readable by admins and teachers.
  Map<String, dynamic> toPublicMap() => {
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'gender': gender,
        'subjects': subjects,
        'level': level,
        'stream': stream,
        'employmentType': employmentType,
        'status': status,
        'photoUrl': photoUrl,
        'linkedUid': linkedUid,
        'createdAt': createdAt == null
            ? ServerValue.timestamp
            : toMillis(createdAt),
      };

  /// `teacherPrivate/{id}` — admins only.
  Map<String, dynamic> toPrivateMap() => {
        'nin': nin,
        'isPincoded': isPincoded,
        'pincode': isPincoded ? pincode : '',
        'maritalStatus': maritalStatus,
        'dob': toMillis(dob),
        'email': email,
        'phone': phone,
        'address': address,
        'qualification': qualification,
        'experience': experience,
        'documents': documents.map((d) => d.toMap()).toList(),
      };

  Teacher copyWith({
    String? firstName,
    String? middleName,
    String? lastName,
    String? email,
    String? phone,
    List<String>? subjects,
    String? employmentType,
    String? status,
    String? linkedUid,
    String? nin,
    String? gender,
    String? maritalStatus,
    DateTime? dob,
    String? address,
    bool? isPincoded,
    String? pincode,
    String? qualification,
    String? experience,
    String? level,
    String? stream,
    String? photoUrl,
    List<TeacherDocument>? documents,
  }) =>
      Teacher(
        id: id,
        firstName: firstName ?? this.firstName,
        middleName: middleName ?? this.middleName,
        lastName: lastName ?? this.lastName,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        subjects: subjects ?? this.subjects,
        employmentType: employmentType ?? this.employmentType,
        status: status ?? this.status,
        linkedUid: linkedUid ?? this.linkedUid,
        createdAt: createdAt,
        nin: nin ?? this.nin,
        gender: gender ?? this.gender,
        maritalStatus: maritalStatus ?? this.maritalStatus,
        dob: dob ?? this.dob,
        address: address ?? this.address,
        isPincoded: isPincoded ?? this.isPincoded,
        pincode: pincode ?? this.pincode,
        qualification: qualification ?? this.qualification,
        experience: experience ?? this.experience,
        level: level ?? this.level,
        stream: stream ?? this.stream,
        photoUrl: photoUrl ?? this.photoUrl,
        documents: documents ?? this.documents,
      );
}
