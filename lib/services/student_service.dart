import '../core/offline_write.dart';
import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';
import '../models/student.dart';

class StudentService {
  StudentService(this._refs);

  final TenantRefs _refs;

  String get schoolId => _refs.schoolId;

  /// Public halves only, sorted by last name.
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

  /// [student] with its `studentPrivate` half loaded.
  Future<Student> loadPrivate(Student student) async {
    final snapshot = await readOnce(_refs.studentPrivate.child(student.id));
    return student.withPrivate(asMap(snapshot.value));
  }

  /// The student whose admission number (the student ID) is [input], with the
  /// private half loaded, or null when there is none in THIS school. Spaces
  /// around the number and letter case are ignored. Looks the number up in
  /// the school's own `index/admissionNo`, so another school's students can
  /// never be found. Reads the phone's copy, so it works offline.
  Future<Student?> findByAdmissionNo(String input) async {
    final key = indexKey(input);
    if (key.isEmpty) return null;
    final id = (await readOnce(_refs.admissionIndex.child(key))).value;
    if (id is! String || id.isEmpty) return null;
    final public = await readOnce(_refs.students.child(id));
    if (!public.exists) return null;
    return loadPrivate(Student.fromMap(id, asMap(public.value)));
  }

  /// True when another student already holds [admissionNo] (case-insensitive).
  /// Pass [excludeId] when editing so a student doesn't clash with themselves.
  /// The database rules enforce this too; this check gives a friendly message.
  Future<bool> admissionNoTaken(String admissionNo, {String? excludeId}) async {
    final owner =
        await readOnce(_refs.admissionIndex.child(indexKey(admissionNo)));
    return owner.exists && owner.value != excludeId;
  }

  /// Creates or updates [student] as ONE atomic update: public record, private
  /// record and admission-number index entry. [previousAdmissionNo] is the
  /// number the record had before editing; its index entry is released when
  /// the number changes. Returns the student id.
  Future<String> save(Student student, {String? previousAdmissionNo}) async {
    final id = student.id.isEmpty ? _refs.students.push().key! : student.id;
    final newKey = indexKey(student.admissionNo);
    final updates = <String, Object?>{
      'students/$id': student.toPublicMap(),
      'studentPrivate/$id': student.toPrivateMap(),
      'index/admissionNo/$newKey': id,
    };
    if (previousAdmissionNo != null && previousAdmissionNo.isNotEmpty) {
      final oldKey = indexKey(previousAdmissionNo);
      if (oldKey != newKey) updates['index/admissionNo/$oldKey'] = null;
    }
    await commitWrite(_refs.school.update(updates));
    return id;
  }

  /// Removes the public record, private record and index entry together.
  Future<void> delete(Student student) {
    return commitWrite(_refs.school.update({
      'students/${student.id}': null,
      'studentPrivate/${student.id}': null,
      if (student.admissionNo.isNotEmpty)
        'index/admissionNo/${indexKey(student.admissionNo)}': null,
    }));
  }
}
