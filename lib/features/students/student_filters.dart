import 'package:flutter/material.dart';

import '../../core/rtdb.dart';
import '../../models/school_class.dart';
import '../../models/school_level.dart';
import '../../models/student.dart';

/// The status chips on the Students screen. "Past" is every student who has
/// left: graduated, inactive or transferred.
enum StatusFilter {
  active('Active'),
  past('Past');

  const StatusFilter(this.label);

  final String label;

  bool matches(Student s) =>
      (s.status == StudentStatus.active) == (this == StatusFilter.active);
}

/// The Sort menu on the Students screen.
enum StudentSort {
  name('Name', Icons.sort_by_alpha),
  id('ID (admission no.)', Icons.badge_outlined),
  className('Class', Icons.class_outlined),
  registered('Date of registration', Icons.event_outlined);

  const StudentSort(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Places each student on a class ladder (level + rung) through their class,
/// so the Students screen can filter and count by class and status.
///
/// A student whose class is missing or has a non-standard name has rung -1:
/// they show under "All" only.
class StudentFilters {
  StudentFilters(List<SchoolClass> classes, this.students)
      : _classes = {for (final c in classes) c.id: c},
        levels = [
          for (final l in SchoolLevel.values)
            if (classes.any((c) => c.level == l)) l,
        ],
        _rungs = {
          for (final l in SchoolLevel.values)
            l: {
              for (final c in classes)
                if (c.level == l && l.rungOf(c.name) >= 0) l.rungOf(c.name),
            }.toList()
              ..sort(),
        };

  final Map<String, SchoolClass> _classes;
  final List<Student> students;

  /// Levels the school runs (it has at least one class there), in ladder
  /// order. The Students screen shows a level row only when there are two
  /// or more.
  final List<SchoolLevel> levels;

  final Map<SchoolLevel, List<int>> _rungs;

  /// Ladder positions of [level] that the school has a class for, e.g. a
  /// JSS-only school gets [0, 1, 2] (JSS 1–3) for secondary.
  List<int> rungsOf(SchoolLevel level) => _rungs[level]!;

  SchoolClass? classOf(Student s) => _classes[s.classId];

  /// The class's level, or the level copied onto the student when the class
  /// is gone.
  SchoolLevel? levelOf(Student s) => classOf(s)?.level ?? s.level;

  int rungOf(Student s) {
    final c = classOf(s);
    final level = c?.level;
    return c == null || level == null ? -1 : level.rungOf(c.name);
  }

  /// True for SSS 1–3, where pupils belong to a department.
  static bool isSenior(SchoolLevel? level, int? rung) =>
      level == SchoolLevel.secondary &&
      rung != null &&
      level!.standardClasses[rung].stage == SecondaryStage.senior;

  /// [level] null = every level, [rung] null = every class in the level,
  /// [status] null = active and past, [department] null = every department
  /// ('' = pupils with no department recorded).
  bool matches(
    Student s, {
    SchoolLevel? level,
    int? rung,
    StatusFilter? status,
    String? department,
  }) =>
      (level == null || levelOf(s) == level) &&
      (rung == null || rungOf(s) == rung) &&
      (status == null || status.matches(s)) &&
      (department == null || (s.department ?? '') == department);

  List<Student> where({
    SchoolLevel? level,
    int? rung,
    StatusFilter? status,
    String? department,
  }) =>
      [
        for (final s in students)
          if (matches(s,
              level: level, rung: rung, status: status, department: department))
            s,
      ];

  /// [list] in [sort] order (a new list). Ties, and students missing the
  /// sorted value, fall back to name order; missing values go last.
  ///  - name: last name, then first and middle name (A–Z);
  ///  - id: admission number, numbers compared by value (2 before 10);
  ///  - className: class ladder order (Pre 1 … SSS 3), then class name;
  ///  - registered: newest registration first.
  List<Student> sorted(List<Student> list, StudentSort sort) {
    int byName(Student a, Student b) {
      for (final (x, y) in [
        (a.lastName, b.lastName),
        (a.firstName, b.firstName),
        (a.middleName, b.middleName),
      ]) {
        final c = compareText(x, y);
        if (c != 0) return c;
      }
      return 0;
    }

    int byClass(Student a, Student b) {
      final la = levelOf(a), lb = levelOf(b);
      if (la != lb) {
        if (la == null) return 1;
        if (lb == null) return -1;
        return la.index.compareTo(lb.index);
      }
      final ra = rungOf(a), rb = rungOf(b);
      if (ra != rb) {
        if (ra < 0) return 1;
        if (rb < 0) return -1;
        return ra.compareTo(rb);
      }
      return compareText(classOf(a)?.name ?? '', classOf(b)?.name ?? '');
    }

    int byId(Student a, Student b) {
      final x = a.admissionNo.trim(), y = b.admissionNo.trim();
      if (x.isEmpty != y.isEmpty) return x.isEmpty ? 1 : -1;
      return compareNatural(x, y);
    }

    int byRegistered(Student a, Student b) {
      final x = a.createdAt, y = b.createdAt;
      if (x == null || y == null) {
        return x == y ? 0 : (x == null ? 1 : -1);
      }
      return y.compareTo(x);
    }

    final primary = switch (sort) {
      StudentSort.name => byName,
      StudentSort.id => byId,
      StudentSort.className => byClass,
      StudentSort.registered => byRegistered,
    };
    return [...list]..sort((a, b) {
        final c = primary(a, b);
        return c != 0 ? c : byName(a, b);
      });
  }

  int count({
    SchoolLevel? level,
    int? rung,
    StatusFilter? status,
    String? department,
  }) =>
      where(level: level, rung: rung, status: status, department: department)
          .length;
}

/// Text order where runs of digits compare by value, case-insensitive:
/// "EG/2" < "EG/10", "a9" < "A10".
int compareNatural(String a, String b) {
  final digits = RegExp(r'\d+|\D+');
  final pa = digits.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final pb = digits.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = pa[i], y = pb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = nx != null && ny != null ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}
