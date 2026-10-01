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

  int count({
    SchoolLevel? level,
    int? rung,
    StatusFilter? status,
    String? department,
  }) =>
      where(level: level, rung: rung, status: status, department: department)
          .length;
}
