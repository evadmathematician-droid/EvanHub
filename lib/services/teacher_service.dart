import '../core/offline_write.dart';
import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';
import '../models/teacher.dart';

class TeacherService {
  TeacherService(this._refs);

  final TenantRefs _refs;

  String get schoolId => _refs.schoolId;

  /// Public halves only, sorted by last name.
  Stream<List<Teacher>> watchAll() {
    return watchList(_refs.teachers, Teacher.fromMap).map(
      (list) => list..sort((a, b) => compareText(a.lastName, b.lastName)),
    );
  }

  /// [teacher] with its `teacherPrivate` half loaded (admins only).
  Future<Teacher> loadPrivate(Teacher teacher) async {
    final snapshot = await readOnce(_refs.teacherPrivate.child(teacher.id));
    return teacher.withPrivate(asMap(snapshot.value));
  }

  /// True when another teacher in this school already has [nin]. The
  /// database rules enforce this too; this check gives a friendly message.
  Future<bool> ninTaken(String nin, {String? excludeId}) async {
    if (nin.isEmpty) return false;
    final owner = await readOnce(_refs.ninIndex.child(nin));
    return owner.exists && owner.value != excludeId;
  }

  /// Creates or updates [teacher] as ONE atomic update: public record, private
  /// record and NIN index entry. [previousNin] is the NIN before editing; its
  /// index entry is released when the NIN changes. Returns the teacher id.
  Future<String> save(Teacher teacher, {String? previousNin}) async {
    final id = teacher.id.isEmpty ? _refs.teachers.push().key! : teacher.id;
    final updates = <String, Object?>{
      'teachers/$id': teacher.toPublicMap(),
      'teacherPrivate/$id': teacher.toPrivateMap(),
      if (teacher.nin.isNotEmpty) 'index/nin/${teacher.nin}': id,
    };
    if (previousNin != null &&
        previousNin.isNotEmpty &&
        previousNin != teacher.nin) {
      updates['index/nin/$previousNin'] = null;
    }
    await commitWrite(_refs.school.update(updates));
    return id;
  }

  /// Removes the public record, private record and NIN index entry together.
  /// [teacher] must have its private half loaded (for the NIN).
  Future<void> delete(Teacher teacher) {
    return commitWrite(_refs.school.update({
      'teachers/${teacher.id}': null,
      'teacherPrivate/${teacher.id}': null,
      if (teacher.nin.isNotEmpty) 'index/nin/${teacher.nin}': null,
    }));
  }
}
