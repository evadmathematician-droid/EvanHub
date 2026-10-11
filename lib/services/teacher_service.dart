import 'dart:async';

import '../core/offline_write.dart';
import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';
import '../models/teacher.dart';
import 'public_lookup_service.dart';

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

  /// Like [watchAll], with each teacher's NIN filled in from
  /// `teacherPrivate` so the list can search and sort by it. Admins only
  /// (the private half is admin-only); both lists are kept synced on the
  /// phone, so this works offline. Emits once both have loaded.
  Stream<List<Teacher>> watchAllWithNin() {
    List<Teacher>? teachers;
    Map<String, dynamic>? private;
    final subs = <StreamSubscription<Object?>>[];
    late final StreamController<List<Teacher>> controller;

    void emit() {
      final t = teachers, p = private;
      if (t == null || p == null) return;
      controller.add([
        for (final teacher in t)
          teacher.copyWith(nin: (asMap(p[teacher.id])['nin'] ?? '') as String),
      ]);
    }

    controller = StreamController<List<Teacher>>(
      onListen: () {
        subs
          ..add(watchAll().listen((list) {
            teachers = list;
            emit();
          }, onError: controller.addError))
          ..add(_refs.teacherPrivate.onValue.listen((e) {
            private = asMap(e.snapshot.value);
            emit();
          }, onError: (Object e) {
            // No NINs (e.g. rules refused): still show the list.
            private = const {};
            emit();
          }));
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
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
    // The public Look Up copy (keyed by NIN) follows, queued offline.
    unawaited(PublicLookupService(_refs)
        .publishTeacher(teacher, previousNin: previousNin));
    return id;
  }

  /// Removes the public record, private record and NIN index entry together,
  /// and the public Look Up copy. [teacher] must have its private half
  /// loaded (for the NIN).
  Future<void> delete(Teacher teacher) async {
    await commitWrite(_refs.school.update({
      'teachers/${teacher.id}': null,
      'teacherPrivate/${teacher.id}': null,
      if (teacher.nin.isNotEmpty) 'index/nin/${teacher.nin}': null,
    }));
    PublicLookupService(_refs).removeTeacher(teacher);
  }
}
