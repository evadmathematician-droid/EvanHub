// Promotion system: pick pupils one by one, repeat or promote, SSS streams,
// the 10-month repeater rule and the report.

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evangelistglobal/features/students/student_filters.dart';
import 'package:evangelistglobal/models/promotion_path.dart';
import 'package:evangelistglobal/models/school_class.dart';
import 'package:evangelistglobal/models/school_level.dart';
import 'package:evangelistglobal/models/student.dart';
import 'package:evangelistglobal/services/promotion_planner.dart';

const sec = SchoolLevel.secondary;

SchoolClass cls(String id, String name) =>
    SchoolClass(id: id, name: name, level: sec);

final classes = [
  cls('j1a', 'JSS 1 A'),
  cls('j1b', 'JSS 1 B'),
  cls('j2a', 'JSS 2 A'),
  cls('j2b', 'JSS 2 B'),
  cls('j3', 'JSS 3'),
  cls('s1', 'SSS 1'),
  cls('s2', 'SSS 2'),
  cls('s3', 'SSS 3'),
];

Student pupil(
  String id,
  String classId, {
  String status = StudentStatus.active,
  String? department,
  String beceId = '',
  String beceYear = '',
  String wassceId = '',
  String wassceYear = '',
  DateTime? createdAt,
  DateTime? lastPromotedAt,
}) =>
    Student(
      id: id,
      firstName: id.toUpperCase(),
      lastName: 'Kamara',
      admissionNo: 'ADM-$id',
      level: sec,
      classId: classId,
      status: status,
      department: department,
      beceId: beceId,
      beceYear: beceYear,
      wassceId: wassceId,
      wassceYear: wassceYear,
      createdAt: createdAt,
      lastPromotedAt: lastPromotedAt,
    );

PromotionPlan plan(
  List<Student> students, {
  Set<String> promote = const {},
  Set<String> repeat = const {},
  Map<String, String> targets = const {},
  Map<String, BeceRecord> bece = const {},
  Map<String, String> departments = const {},
}) {
  var n = 0;
  return planPromotion(
    classes: classes,
    students: students,
    request: PromotionRequest(
      promoteIds: promote,
      repeatIds: repeat,
      targets: targets,
      academicYear: '2026',
      promotedBy: 'admin',
      bece: bece,
      departments: departments,
    ),
    newRecordKey: () => 'k${n++}',
  );
}

PromotionOutcome outcomeOf(PromotionPlan p, String id) =>
    p.report.lines.firstWhere((l) => l.studentId == id).outcome;

void main() {
  group('repeater rule (10 months without promotion)', () {
    final now = DateTime(2026, 9, 30);

    test('never promoted: counts from registration', () {
      expect(pupil('a', 'j1a', createdAt: DateTime(2025, 11, 30))
          .isRepeater(now), isTrue);
      expect(pupil('a', 'j1a', createdAt: DateTime(2025, 12, 1))
          .isRepeater(now), isFalse);
    });

    test('a promotion restarts the clock', () {
      expect(
          pupil('a', 'j2a',
                  createdAt: DateTime(2020), lastPromotedAt: DateTime(2026, 7))
              .isRepeater(now),
          isFalse);
    });

    test('only active pupils', () {
      expect(
          pupil('a', 'j1a',
                  status: StudentStatus.graduated, createdAt: DateTime(2020))
              .isRepeater(now),
          isFalse);
    });
  });

  group('sections', () {
    test('JSS 1 A goes to JSS 2 A by default', () {
      final from = classes.first;
      final path = PromotionPath.of(from, classes)!;
      expect(PromotionPath.sectionOf(from), 'a');
      expect(path.defaultTarget(from, classes)!.id, 'j2a');
    });

    test('the only next class is the default', () {
      final j2b = classes.firstWhere((c) => c.id == 'j2b');
      expect(PromotionPath.of(j2b, classes)!.defaultTarget(j2b, classes)!.id,
          'j3');
    });
  });

  group('planPromotion', () {
    test('ticked pupils move up, the rest repeat', () {
      final p = plan(
        [pupil('a', 'j1a'), pupil('b', 'j1a'), pupil('c', 'j1b')],
        promote: {'a', 'c'},
        repeat: {'b'},
        targets: {'j1a': 'j2a', 'j1b': 'j2b'},
      );
      expect(outcomeOf(p, 'a'), PromotionOutcome.promoted);
      expect(outcomeOf(p, 'b'), PromotionOutcome.repeated);
      expect(p.updates['students/a/classId'], 'j2a');
      expect(p.updates['students/c/classId'], 'j2b');
      expect(p.updates['students/a/lastPromotedAt'], ServerValue.timestamp);
      // The repeater is not moved; only a history record is written.
      expect(p.updates.keys.where((k) => k.startsWith('students/b/')), isEmpty);
      expect(p.updates.values.whereType<Map>().where(
              (r) => r['studentId'] == 'b' && r['toClassId'] == 'j1a'),
          hasLength(1));
    });

    test('a class is never skipped', () {
      final p = plan([pupil('a', 'j1a')],
          promote: {'a'}, targets: {'j1a': 'j3'});
      expect(outcomeOf(p, 'a'), PromotionOutcome.skipped);
      expect(p.updates.keys.where((k) => k.startsWith('students/')), isEmpty);
    });

    test('JSS 3 → SSS 1 needs BECE and a department', () {
      expect(
          () => plan([pupil('a', 'j3')], promote: {'a'}, targets: {'j3': 's1'}),
          throwsStateError);
      final p = plan(
        [pupil('a', 'j3'), pupil('b', 'j3', beceId: '12345678', beceYear: '2026', department: 'Arts')],
        promote: {'a', 'b'},
        targets: {'j3': 's1'},
        bece: {'a': const BeceRecord('87654321', '2026')},
        departments: {'a': 'Science'},
      );
      expect(p.updates['students/a/department'], 'Science');
      expect(p.updates['studentPrivate/a/beceId'], '87654321');
      expect(p.updates['students/b/department'], 'Arts');
      expect(outcomeOf(p, 'b'), PromotionOutcome.promoted);
    });

    test('SSS 3 graduates only with WASSCE; others are skipped', () {
      final p = plan([
        pupil('a', 's3', wassceId: 'W1', wassceYear: '2026'),
        pupil('b', 's3'),
      ], promote: {'a', 'b'});
      expect(outcomeOf(p, 'a'), PromotionOutcome.graduated);
      expect(p.updates['students/a/status'], StudentStatus.graduated);
      expect(outcomeOf(p, 'b'), PromotionOutcome.skipped);
    });

    test('pupils who left are skipped', () {
      final p = plan([pupil('a', 'j1a', status: StudentStatus.transferred)],
          promote: {'a'}, targets: {'j1a': 'j2a'});
      expect(outcomeOf(p, 'a'), PromotionOutcome.skipped);
    });

    test('report table lists promoted, graduated, repeated, skipped', () {
      final p = plan([
        pupil('r', 'j1a'),
        pupil('p', 'j1a'),
        pupil('g', 's3', wassceId: 'W', wassceYear: '2026'),
        pupil('s', 's3'),
      ], promote: {'s', 'g', 'p'}, repeat: {'r'}, targets: {'j1a': 'j2a'});
      final t = p.report.toTable('Evangelist Academy', filters: ['JSS 1']);
      expect(t.title, 'Promotion report');
      expect(t.filters, ['JSS 1', 'Academic year 2026']);
      expect([for (final r in t.rows) r[4]],
          ['Promoted', 'Graduated', 'Repeated', 'Skipped']);
    });
  });

  test('Students filters: SSS stream', () {
    final f = StudentFilters(classes, [
      pupil('a', 's1', department: 'Science'),
      pupil('b', 's1', department: 'Arts'),
      pupil('c', 's1'),
    ]);
    expect(StudentFilters.isSenior(sec, 3), isTrue);
    expect(StudentFilters.isSenior(sec, 2), isFalse);
    expect(f.where(level: sec, rung: 3, department: 'Science').single.id, 'a');
    expect(f.count(level: sec, rung: 3, department: ''), 1);
    expect(f.count(level: sec, rung: 3), 3);
  });
}
