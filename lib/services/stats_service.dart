import '../core/tenant/tenant_refs.dart';

/// Per-school counts for the dashboard.
class SchoolStats {
  final int students;
  final int teachers;
  final int classes;
  final int announcements;

  const SchoolStats({
    this.students = 0,
    this.teachers = 0,
    this.classes = 0,
    this.announcements = 0,
  });
}

class StatsService {
  StatsService(this._refs);

  final TenantRefs _refs;

  Future<SchoolStats> load() async {
    final results = await Future.wait([
      _refs.students.get(),
      _refs.teachers.get(),
      _refs.classes.get(),
      _refs.announcements.get(),
    ]);
    return SchoolStats(
      students: results[0].children.length,
      teachers: results[1].children.length,
      classes: results[2].children.length,
      announcements: results[3].children.length,
    );
  }
}
