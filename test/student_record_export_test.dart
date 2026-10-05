import 'dart:typed_data';

import 'package:evangelistglobal/models/student.dart';
import 'package:evangelistglobal/services/export/student_record_export.dart';
import 'package:evangelistglobal/services/export/student_record_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final student = Student(
    id: '-Nabc123',
    firstName: 'Fatmata',
    middleName: 'K.',
    lastName: 'Kamara',
    admissionNo: 'EG/2024/017',
    gender: 'female',
    dob: DateTime(2012, 3, 4),
    guardianName: 'Mohamed Kamara',
    createdAt: DateTime(2024, 9, 2),
  );

  test('file name is <ID>_<Name>_<date> with unsafe characters replaced', () {
    final at = DateTime(2026, 10, 4, 14, 30);
    expect(StudentRecordExport.fileName(student, at, RecordFormat.pdf),
        'EG_2024_017_Fatmata_K_Kamara_2026-10-04.pdf');
    expect(StudentRecordExport.fileName(student, at, RecordFormat.png),
        'EG_2024_017_Fatmata_K_Kamara_2026-10-04.png');
  });

  test('file name falls back to the record id when there is no ID', () {
    final noId = Student(id: 'rec1', firstName: 'A', lastName: 'B');
    expect(StudentRecordExport.fileName(noId, DateTime(2026, 1, 2), RecordFormat.pdf),
        'rec1_A_B_2026-01-02.pdf');
  });

  test('PDF builds with no images, history and non-Latin text', () async {
    final bytes = await buildStudentRecordPdfSafely(StudentRecordData(
      student: student,
      className: 'JSS 2',
      schoolName: 'Evangelist Model School',
      schoolAddress: '12 Main Road, Freetown',
      schoolPhone: '+232 76 000000',
      headName: 'Mrs. A. Sesay ✓',
      exportedAt: DateTime(2026, 10, 4, 14, 30),
      history: const [
        HistoryLine(
            year: '2024/2025',
            from: 'JSS 1',
            to: 'JSS 2',
            outcome: 'Promoted',
            date: '20 Jul 2025'),
      ],
    ));
    // A real PDF: starts with the %PDF header and has some size.
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(2000));
  });

  test('a corrupt image does not stop the export', () async {
    final bytes = await buildStudentRecordPdfSafely(StudentRecordData(
      student: student,
      className: 'JSS 2',
      schoolName: 'Evangelist Model School',
      exportedAt: DateTime(2026, 10, 4),
      history: const [],
      badge: Uint8List.fromList([1, 2, 3, 4]),
    ));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
