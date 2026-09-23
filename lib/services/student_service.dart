import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';
import '../models/student.dart';

class StudentService {
  StudentService(this._refs);

  final TenantRefs _refs;

  Stream<List<Student>> watchAll() {
    return watchList(_refs.students, Student.fromMap).map(
      (list) => list..sort((a, b) => compareText(a.lastName, b.lastName)),
    );
  }

  Stream<List<Student>> watchByClass(String classId) {
    return watchAll().map(
      (list) => list.where((s) => s.classId == classId).toList(),
    );
  }

  /// True when another student already uses [admissionNo] (case-insensitive).
  /// Pass [excludeId] when editing so a student doesn't clash with themselves.
  Future<bool> admissionNoTaken(String admissionNo, {String? excludeId}) async {
    final wanted = admissionNo.trim().toLowerCase();
    final snapshot = await _refs.students.get();
    for (final child in snapshot.children) {
      if (child.key == excludeId) continue;
      final existing =
          (asMap(child.value)['admissionNo'] ?? '').toString().toLowerCase();
      if (existing == wanted) return true;
    }
    return false;
  }

  Future<String> add(Student student) async {
    final ref = _refs.students.push();
    await ref.set(student.toMap());
    return ref.key!;
  }

  Future<void> update(Student student) {
    return _refs.students.child(student.id).update(student.toMap());
  }

  Future<void> delete(String id) => _refs.students.child(id).remove();
}
