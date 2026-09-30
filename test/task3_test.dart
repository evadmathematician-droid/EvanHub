// Task 3: class ladders, promotion paths and the Students screen filters.

import 'package:flutter_test/flutter_test.dart';

import 'package:evangelistglobal/features/students/student_filters.dart';
import 'package:evangelistglobal/models/promotion_path.dart';
import 'package:evangelistglobal/models/school_class.dart';
import 'package:evangelistglobal/models/school_level.dart';
import 'package:evangelistglobal/models/student.dart';

SchoolClass cls(String id, String name, SchoolLevel level) =>
    SchoolClass(id: id, name: name, level: level);

/// The standard classes of [level] with ids like `secondary-0`.
List<SchoolClass> ladder(SchoolLevel level) => [
      for (final (i, std) in level.standardClasses.indexed)
        cls('${level.wire}-$i', std.name, level),
    ];

/// Where [name]'s pupils go in a school running [levels]: the next class's
/// name, 'Past', or null when unknown.
String? nextOf(String name, List<SchoolLevel> levels) {
  final classes = [for (final l in levels) ...ladder(l)];
  final from = classes.firstWhere((c) => c.name == name);
  final path = PromotionPath.of(from, classes);
  if (path == null) return null;
  return path.graduates ? 'Past' : path.next.name;
}

void main() {
  const pre = SchoolLevel.prePrimary;
  const pri = SchoolLevel.primary;
  const sec = SchoolLevel.secondary;

  group('class ladders', () {
    test('match the school system', () {
      List<String> names(SchoolLevel l) =>
          l.standardClasses.map((c) => c.name).toList();
      expect(names(pre), ['Pre 1', 'Pre 2']);
      expect(names(pri), [for (var i = 1; i <= 6; i++) 'Class $i']);
      expect(names(sec),
          ['JSS 1', 'JSS 2', 'JSS 3', 'SSS 1', 'SSS 2', 'SSS 3']);
    });
  });

  group('PromotionPath', () {
    test('nursery: Pre 1 → Pre 2 → Class 1 when the school has primary', () {
      expect(nextOf('Pre 1', [pre, pri]), 'Pre 2');
      expect(nextOf('Pre 2', [pre, pri]), 'Class 1');
    });

    test('nursery-only school: Pre 2 → Past', () {
      expect(nextOf('Pre 2', [pre]), 'Past');
    });

    test('primary: one class at a time, Class 6 → Past', () {
      for (var i = 1; i < 6; i++) {
        expect(nextOf('Class $i', [pri]), 'Class ${i + 1}');
      }
      expect(nextOf('Class 6', [pri]), 'Past');
      // Never into secondary, even when the school runs it.
      expect(nextOf('Class 6', [pri, sec]), 'Past');
    });

    test('secondary: JSS 3 → SSS 1 → … → SSS 3 → Past', () {
      expect(nextOf('JSS 1', [sec]), 'JSS 2');
      expect(nextOf('JSS 2', [sec]), 'JSS 3');
      expect(nextOf('JSS 3', [sec]), 'SSS 1');
      expect(nextOf('SSS 1', [sec]), 'SSS 2');
      expect(nextOf('SSS 2', [sec]), 'SSS 3');
      expect(nextOf('SSS 3', [sec]), 'Past');
    });

    test('JSS-only school: JSS 3 → Past', () {
      final jss = ladder(sec).take(3).toList();
      final path = PromotionPath.of(jss[2], jss)!;
      expect(path.graduates, isTrue);
      // Graduating JSS 3 needs no WASSCE (that is for SSS 3 only).
      expect(path.needsWassce(jss[2]), isFalse);
    });

    test('BECE is needed for JSS 3 → SSS 1 only; WASSCE for SSS 3 only', () {
      final classes = ladder(sec);
      for (final c in classes) {
        final path = PromotionPath.of(c, classes)!;
        expect(path.needsBece(c), c.name == 'JSS 3', reason: c.name);
        expect(path.needsWassce(c), c.name == 'SSS 3', reason: c.name);
      }
    });

    test('targets only the next rung of the right level', () {
      final classes = [
        ...ladder(pri),
        ...ladder(sec),
        cls('jss2b', 'JSS 2 B', sec),
      ];
      final jss1 = classes.firstWhere((c) => c.name == 'JSS 1');
      final path = PromotionPath.of(jss1, classes)!;
      expect(classes.where(path.isTarget).map((c) => c.name),
          ['JSS 2', 'JSS 2 B']);
      // A primary class that happens to be the right rung is not a target.
      expect(path.isTarget(cls('x', 'Class 2', pri)), isFalse);
      expect(path.isTarget(cls('y', 'JSS 3', sec)), isFalse);
    });

    test('unknown when the class has no level or a non-standard name', () {
      final odd = cls('n', 'Nursery 1', pre);
      expect(PromotionPath.of(odd, [odd]), isNull);
      const noLevel = SchoolClass(id: 'z', name: 'Class 1');
      expect(PromotionPath.of(noLevel, const [noLevel]), isNull);
    });
  });

  group('StudentFilters', () {
    Student st(String id, String? classId, String status,
            {SchoolLevel? level}) =>
        Student(
          id: id,
          firstName: id,
          lastName: 'X',
          classId: classId,
          status: status,
          level: level,
        );

    final classes = [
      ...ladder(pri),
      cls('c4b', 'Class 4 B', pri),
      ...ladder(sec).take(3), // JSS only
    ];
    final f = StudentFilters(classes, [
      st('a', 'primary-3', StudentStatus.active), // Class 4
      st('b', 'c4b', StudentStatus.active), // Class 4 B
      st('c', 'primary-3', StudentStatus.transferred), // Class 4, past
      st('d', 'primary-5', StudentStatus.graduated), // Class 6, past
      st('e', 'secondary-0', StudentStatus.active), // JSS 1
      // Graduated before classes were kept on graduation: no class.
      st('f', null, StudentStatus.graduated, level: pri),
    ]);

    test('lists only levels and classes the school runs', () {
      expect(f.levels, [pri, sec]);
      expect(f.rungsOf(pri), [0, 1, 2, 3, 4, 5]);
      expect(f.rungsOf(sec), [0, 1, 2]);
      expect(f.rungsOf(pre), isEmpty);
    });

    test('class and status filters combine', () {
      List<String> ids(Iterable<Student> s) => s.map((x) => x.id).toList();
      expect(ids(f.where(level: pri, rung: 3, status: StatusFilter.active)),
          ['a', 'b']);
      expect(ids(f.where(level: pri, rung: 3, status: StatusFilter.past)),
          ['c']);
      expect(ids(f.where(level: pri, rung: 3)), ['a', 'b', 'c']);
      expect(ids(f.where(level: pri, status: StatusFilter.past)),
          ['c', 'd', 'f']);
    });

    test('counts', () {
      expect(f.count(status: StatusFilter.active), 3);
      expect(f.count(status: StatusFilter.past), 3);
      expect(f.count(level: sec, rung: 0, status: StatusFilter.active), 1);
      expect(f.count(level: sec, rung: 1), 0);
    });
  });
}
