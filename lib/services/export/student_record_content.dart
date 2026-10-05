import 'package:intl/intl.dart';

import '../../models/student.dart';
import 'student_record_pdf.dart';

/// The words of a student record, shared by every format (PDF, Word, image)
/// so they always say the same thing.

final _dateTime = DateFormat('d MMMM yyyy, h:mm a');
final _short = DateFormat('d MMM yyyy');

bool hasText(String? s) => s != null && s.trim().isNotEmpty;

/// "5 October 2026, 2:30 PM".
String exportedAtText(StudentRecordData d) => _dateTime.format(d.exportedAt);

/// The record's sections in the order of the app's details popup, with
/// every empty field — and any section left with nothing in it — left out.
List<(String, List<(String, String)>)> recordSections(StudentRecordData d) {
  final s = d.student;
  final all = <(String, List<(String, String)>)>[
    (
      'PERSONAL INFORMATION',
      [
        ('First name', s.firstName),
        ('Middle name', s.middleName),
        ('Last name', s.lastName),
        (
          'Gender',
          s.gender.isEmpty
              ? ''
              : s.gender[0].toUpperCase() + s.gender.substring(1),
        ),
        ('Date of birth', s.dob == null ? '' : _short.format(s.dob!)),
        ('Home address', s.address),
      ],
    ),
    (
      'GUARDIAN / CONTACT',
      [('Guardian name', s.guardianName), ('Guardian phone', s.guardianPhone)],
    ),
    (
      'ACADEMIC INFORMATION',
      [
        ('Student ID', s.admissionNo),
        ('Level', s.level?.label ?? ''),
        ('Class', d.className),
        ('Department', s.department ?? ''),
        ('Admission year', s.admissionYear),
        (
          'Date registered',
          s.createdAt == null ? '' : _short.format(s.createdAt!),
        ),
        ('Status', StudentStatus.label(s.status)),
        (
          'Last promoted',
          s.lastPromotedAt == null
              ? 'Not yet promoted'
              : _short.format(s.lastPromotedAt!),
        ),
      ],
    ),
    (
      'EXAM RECORDS',
      [
        ('NPSE index no.', s.npseId),
        ('NPSE year', s.npseYear),
        ('BECE index no.', s.beceId),
        ('BECE year', s.beceYear),
        ('WASSCE index no.', s.wassceId),
        ('WASSCE year', s.wassceYear),
      ],
    ),
  ];
  return [
    for (final (title, rows) in all)
      if (rows.any((r) => hasText(r.$2)))
        (
          title,
          [
            for (final r in rows)
              if (hasText(r.$2)) (r.$1, r.$2.trim()),
          ],
        ),
  ];
}

/// The short facts beside the photo: (label, value), empty ones left out.
List<(String, String)> recordSummary(StudentRecordData d) {
  final s = d.student;
  return [
    if (hasText(s.admissionNo)) ('Student ID', s.admissionNo.trim()),
    if (hasText(d.className)) ('Class', d.className),
    ('Status', StudentStatus.label(s.status)),
    if (s.level != null) ('Level', s.level!.label),
  ];
}

/// "Tel: … | Email: …", or empty.
String contactLine(StudentRecordData d) => [
  if (hasText(d.schoolPhone)) 'Tel: ${d.schoolPhone.trim()}',
  if (hasText(d.schoolEmail)) 'Email: ${d.schoolEmail.trim()}',
].join('   |   ');

/// The certification paragraph, exactly as worded by the school.
String certificationText(StudentRecordData d) {
  final s = d.student;
  final school = hasText(d.schoolAddress)
      ? '${d.schoolName.trim()}, ${d.schoolAddress.trim()}'
      : d.schoolName.trim();
  final id = hasText(s.admissionNo) ? s.admissionNo.trim() : s.id;
  return 'This is to certify that ${s.fullName}, Student ID $id, is a '
      'bona fide student of $school. The information contained in this '
      'document is true and correct according to the official records of '
      'the school as at ${exportedAtText(d)}.';
}
