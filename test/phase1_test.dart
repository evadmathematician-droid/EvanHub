// Phase 1: index keys, the public/private record split and the migration
// checks. These must agree with database.rules.json.

import 'package:flutter_test/flutter_test.dart';

import 'package:evangelistglobal/core/rtdb.dart';
import 'package:evangelistglobal/models/school.dart';
import 'package:evangelistglobal/models/school_level.dart';
import 'package:evangelistglobal/models/student.dart';
import 'package:evangelistglobal/models/teacher.dart';
import 'package:evangelistglobal/services/migration_service.dart';

void main() {
  group('indexKey', () {
    test('lower-cases and encodes characters keys cannot hold', () {
      expect(indexKey('EG/2024/001'), 'eg%2f2024%2f001');
      expect(indexKey('A.B#C\$D[E]F'), 'a%2eb%23c%24d%5be%5df');
      expect(indexKey('50%'), '50%25');
    });

    test('is case-insensitive and trims', () {
      expect(indexKey(' ABC1 '), indexKey('abc1'));
    });
  });

  group('Student split', () {
    final full = Student.fromParts('s1', {
      'firstName': 'Ama',
      'lastName': 'Kamara',
      'admissionNo': 'A1',
      'status': 'active',
      'level': 'secondary',
      'classId': 'c1',
      'createdAt': 1000,
      // Private fields in the public map must be ignored.
      'guardianPhone': 'should not leak',
    }, {
      'guardianPhone': '0770',
      'beceId': '12345678',
      'beceYear': '2024',
      'dob': 5000,
    });

    test('public map holds no private fields', () {
      final public = full.toPublicMap();
      for (final key in ['dob', 'address', 'guardianName', 'guardianPhone',
          'npseId', 'beceId', 'wassceId']) {
        expect(public.containsKey(key), isFalse, reason: key);
      }
      expect(public['level'], 'secondary');
      expect(public['createdAt'], 1000);
    });

    test('private map holds the personal and exam fields', () {
      final private = full.toPrivateMap();
      expect(private['guardianPhone'], '0770');
      expect(private['beceId'], '12345678');
      expect(private['dob'], 5000);
      expect(private.containsKey('firstName'), isFalse);
    });

    test('withPrivate merges a loaded private half', () {
      final listItem = Student.fromMap('s1', full.toPublicMap());
      expect(listItem.guardianPhone, '');
      final loaded = listItem.withPrivate(full.toPrivateMap());
      expect(loaded.guardianPhone, '0770');
      expect(loaded.createdAt, full.createdAt);
    });
  });

  group('Teacher split', () {
    const t = Teacher(
      id: 't1',
      firstName: 'Musa',
      lastName: 'Sesay',
      nin: 'AB12CD34',
      phone: '0777',
      subjects: ['Maths'],
    );

    test('NIN and contacts stay private', () {
      expect(t.toPublicMap().containsKey('nin'), isFalse);
      expect(t.toPublicMap().containsKey('phone'), isFalse);
      expect(t.toPrivateMap()['nin'], 'AB12CD34');
      expect(t.toPublicMap()['subjects'], ['Maths']);
    });
  });

  group('Migration checks', () {
    test('a valid student has no problems', () {
      const s = Student(
          id: 's', firstName: 'A', lastName: 'B', admissionNo: 'X1');
      expect(studentProblems(s), isEmpty);
    });

    test('flags values the rules would reject', () {
      final s = Student(
        id: 's',
        firstName: 'A' * 61,
        lastName: '',
        admissionNo: ' X1',
        gender: 'male',
        admissionYear: '24',
      );
      final problems = studentProblems(s);
      expect(problems, hasLength(5));
    });

    test('teacher NIN must match the rules pattern', () {
      const bad = Teacher(
          id: 't', firstName: 'A', lastName: 'B', nin: 'IO123456');
      expect(teacherProblems(bad).single, contains('NIN'));
      const empty = Teacher(id: 't', firstName: 'A', lastName: 'B');
      expect(teacherProblems(empty), isEmpty);
    });

    test('profile needs a name', () {
      expect(profileProblems(const SchoolMeta(name: '')), isNotEmpty);
    });
  });

  group('SchoolLevel.rungOf', () {
    test('matches sections and ignores case/spaces', () {
      expect(SchoolLevel.secondary.rungOf('JSS 1 A'), 0);
      expect(SchoolLevel.secondary.rungOf('jss3'), 2);
      expect(SchoolLevel.primary.rungOf('Class 10'), -1);
    });
  });
}
