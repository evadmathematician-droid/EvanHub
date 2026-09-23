import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';
import '../models/teacher.dart';

class TeacherService {
  TeacherService(this._refs);

  final TenantRefs _refs;

  Stream<List<Teacher>> watchAll() {
    return watchList(_refs.teachers, Teacher.fromMap).map(
      (list) => list..sort((a, b) => compareText(a.lastName, b.lastName)),
    );
  }

  /// True when another teacher in this school already has [nin].
  Future<bool> ninTaken(String nin, {String? excludeId}) async {
    final snapshot = await _refs.teachers.get();
    for (final child in snapshot.children) {
      if (child.key == excludeId) continue;
      if (asMap(child.value)['nin'] == nin) return true;
    }
    return false;
  }

  Future<String> add(Teacher teacher) async {
    final ref = _refs.teachers.push();
    await ref.set(teacher.toMap());
    return ref.key!;
  }

  Future<void> update(Teacher teacher) {
    return _refs.teachers.child(teacher.id).update(teacher.toMap());
  }

  Future<void> delete(String id) => _refs.teachers.child(id).remove();
}
