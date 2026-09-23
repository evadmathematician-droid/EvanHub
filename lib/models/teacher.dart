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

/// A teacher record — `schools/{schoolId}/teachers/{teacherId}`.
///
/// This is the HR/records entry. It is separate from a `members/{uid}` login;
/// link them by setting [linkedUid] once the teacher has an account.
///
/// The registration fields (NIN, marital status, pincode, qualification,
/// experience, level, stream, photo) mirror the Ninka school app's teacher form.
class Teacher {
  final String id;
  final String firstName;
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

  String get fullName => '$firstName $lastName'.trim();

  factory Teacher.fromMap(String id, Map<String, dynamic> data) {
    String s(String key) => (data[key] ?? '') as String;
    return Teacher(
      id: id,
      firstName: s('firstName'),
      lastName: s('lastName'),
      email: s('email'),
      phone: s('phone'),
      subjects: (data['subjects'] as List?)?.map((e) => '$e').toList() ?? const [],
      employmentType: (data['employmentType'] ?? 'full_time') as String,
      status: (data['status'] ?? 'active') as String,
      linkedUid: data['linkedUid'] as String?,
      createdAt: fromMillis(data['createdAt']),
      nin: s('nin'),
      gender: s('gender'),
      maritalStatus: s('maritalStatus'),
      dob: fromMillis(data['dob']),
      address: s('address'),
      isPincoded: data['isPincoded'] == true,
      pincode: s('pincode'),
      qualification: s('qualification'),
      experience: s('experience'),
      level: s('level'),
      stream: s('stream'),
      photoUrl: s('photoUrl'),
      documents: [
        for (final d in (data['documents'] as List?) ?? const [])
          if (d is Map) TeacherDocument.fromMap(asMap(d)),
      ],
    );
  }

  Map<String, dynamic> toMap() => {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'subjects': subjects,
        'employmentType': employmentType,
        'status': status,
        'linkedUid': linkedUid,
        'createdAt': createdAt == null
            ? ServerValue.timestamp
            : toMillis(createdAt),
        'nin': nin,
        'gender': gender,
        'maritalStatus': maritalStatus,
        'dob': toMillis(dob),
        'address': address,
        'isPincoded': isPincoded,
        'pincode': isPincoded ? pincode : '',
        'qualification': qualification,
        'experience': experience,
        'level': level,
        'stream': stream,
        'photoUrl': photoUrl,
        'documents': documents.map((d) => d.toMap()).toList(),
      };

  Teacher copyWith({
    String? firstName,
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
