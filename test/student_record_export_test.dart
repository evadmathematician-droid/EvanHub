import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:evangelistglobal/models/school_level.dart';
import 'package:evangelistglobal/models/student.dart';
import 'package:evangelistglobal/services/export/student_record_export.dart';
import 'package:evangelistglobal/services/export/student_record_docx.dart';
import 'package:evangelistglobal/services/export/student_record_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pages in a PDF made by the `pdf` package (one `/Type /Page` object each).
int pageCount(Uint8List pdf) =>
    RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(pdf)).length;

void main() {
  final student = Student(
    id: '-Nabc123',
    firstName: 'Fatmata',
    middleName: 'K.',
    lastName: 'Kamara',
    admissionNo: 'EG/2024/017',
    gender: 'female',
    dob: DateTime(2012, 3, 4),
    level: SchoolLevel.secondary,
    department: 'Science',
    admissionYear: '2024',
    address: '5 Hill Station Road, Freetown',
    guardianName: 'Mohamed Kamara',
    guardianPhone: '+232 76 123456',
    npseId: 'NP-55021',
    npseYear: '2023',
    createdAt: DateTime(2024, 9, 2),
    lastPromotedAt: DateTime(2025, 7, 20),
  );

  StudentRecordData record({
    List<HistoryLine> history = const [],
    String motto = '',
    Uint8List? badge,
  }) =>
      StudentRecordData(
        student: student,
        className: 'JSS 2',
        schoolId: '-OschoolXYZ',
        schoolName: 'Evangelist Model School',
        schoolAddress: '12 Main Road, Freetown',
        schoolPhone: '+232 76 000000',
        schoolEmail: 'office@ems.edu.sl',
        motto: motto,
        headName: 'Mrs. A. Sesay',
        exportedAt: DateTime(2026, 10, 5, 14, 30),
        history: history,
        badge: badge,
      );

  HistoryLine line(int i) => HistoryLine(
      year: '${2015 + i}/${2016 + i}',
      from: 'Class $i',
      to: 'Class ${i + 1}',
      outcome: 'Promoted',
      date: '20 Jul ${2016 + i}');

  test('file name is <ID>_<Name>_Record with no spaces or symbols', () {
    expect(StudentRecordExport.fileName(student, RecordFormat.pdf),
        'EG_2024_017_Fatmata_K_Kamara_Record.pdf');
    expect(StudentRecordExport.fileName(student, RecordFormat.png),
        'EG_2024_017_Fatmata_K_Kamara_Record.png');
  });

  test('file name falls back to the record id when there is no ID', () {
    final noId = Student(id: 'rec1', firstName: 'A', lastName: 'B');
    expect(StudentRecordExport.fileName(noId, RecordFormat.pdf),
        'rec1_A_B_Record.pdf');
  });

  test('reference is <schoolCode>-<studentId>-<yyyyMMddHHmm>', () {
    expect(record().reference, 'EMS-EG2024017-202610051430');
  });

  test('a full record with a short history fits on ONE A4 page', () async {
    final bytes = await buildStudentRecordPdfSafely(
        record(history: [line(1), line(2), line(3)], motto: 'Knowledge is Light'));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(pageCount(bytes), 1);
  });

  test('a very long promotion history continues on a second page', () async {
    final bytes = await buildStudentRecordPdfSafely(
        record(history: [for (var i = 0; i < 40; i++) line(i)]));
    expect(pageCount(bytes), greaterThan(1));
  });

  test('a corrupt image does not stop the export', () async {
    final bytes = await buildStudentRecordPdfSafely(
        record(badge: Uint8List.fromList([1, 2, 3, 4])));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  group('Word record', () {
    String part(Archive zip, String name) =>
        utf8.decode(zip.findFile(name)!.content as List<int>);

    // Smallest valid PNG: 1×1 pixel.
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

    test('has the document, footer and the same wording as the PDF', () {
      final zip = ZipDecoder().decodeBytes(buildStudentRecordDocx(
          record(history: [line(1)], motto: 'Knowledge is Light')));
      final doc = part(zip, 'word/document.xml');
      expect(doc, contains('EVANGELIST MODEL SCHOOL'));
      expect(doc, contains('STUDENT INFORMATION RECORD'));
      expect(doc, contains('Knowledge is Light'));
      expect(doc, contains('This is to certify that Fatmata K. Kamara'));
      expect(doc, contains('Head Teacher / Principal'));
      expect(doc, contains('Mrs. A. Sesay'));
      expect(doc, contains('PROMOTION HISTORY'));
      // No stamp uploaded: the dashed box instead.
      expect(doc, contains('Official Stamp'));
      expect(part(zip, 'word/footer1.xml'),
          contains('Ref: EMS-EG2024017-202610051430'));
    });

    test('empty fields are left out', () {
      final doc = part(
          ZipDecoder().decodeBytes(buildStudentRecordDocx(record())),
          'word/document.xml');
      expect(doc, isNot(contains('WASSCE')));
      expect(doc, isNot(contains('PROMOTION HISTORY')));
    });

    test('badge, photo and stamp are embedded as pictures', () {
      final zip = ZipDecoder().decodeBytes(buildStudentRecordDocx(
          StudentRecordData(
        student: student,
        className: 'JSS 2',
        schoolName: 'Evangelist Model School',
        exportedAt: DateTime(2026, 10, 5),
        history: const [],
        badge: png,
        photo: png,
        stamp: png,
      )));
      expect(zip.files.where((f) => f.name.startsWith('word/media/')).length, 3);
      expect(part(zip, 'word/_rels/document.xml.rels'), contains('media/image3.png'));
      expect(part(zip, 'word/document.xml'), isNot(contains('Official Stamp')));
    });

    test('a corrupt image is simply left out', () {
      final zip = ZipDecoder().decodeBytes(buildStudentRecordDocx(
          record(badge: Uint8List.fromList([1, 2, 3, 4]))));
      expect(zip.files.where((f) => f.name.startsWith('word/media/')), isEmpty);
    });
  });
}
