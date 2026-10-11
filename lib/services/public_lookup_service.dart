import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../core/offline_write.dart';
import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';
import '../models/lookup_record.dart';
import '../models/promotion_record.dart';
import '../models/school.dart';
import '../models/school_class.dart';
import '../models/student.dart';
import '../models/teacher.dart';

/// A school in the public list on the Look Up screen.
class PublicSchool {
  const PublicSchool(
      {required this.id, required this.name, this.logoUrl = '', this.town = ''});

  final String id;
  final String name;
  final String logoUrl;
  final String town;
}

/// Thrown by the public reads when the server can't be reached.
class LookupOfflineException implements Exception {
  const LookupOfflineException();
}

/// Keeps the two public nodes in step with the school's own data, and reads
/// them for the Look Up screen (no sign-in needed):
///  - `publicSchools/{schoolId}` — name, logo and town only;
///  - `publicLookup/{schoolId}/{key}` — one pupil's or teacher's own record
///    ([LookupRecord]), readable one at a time by exact key, never as a list.
///
/// Writes go through the database's offline queue like every other save, so
/// a change made offline is published when the phone is back online. They
/// never block or fail the save they follow: a refused publish is logged and
/// the admin's "Publish Lookup Data" button repairs everything.
class PublicLookupService {
  PublicLookupService(this._refs);

  final TenantRefs _refs;

  String get _sid => _refs.schoolId;
  String _path(String key) => 'publicLookup/$_sid/$key';

  // ---------------------------------------------------------------- writes

  /// Runs [updates] at the database root in the background.
  void _publish(Map<String, Object?> updates) {
    if (updates.isEmpty) return;
    unawaited(commitWrite(_refs.root.update(updates)).catchError(
        (Object e) => debugPrint('Public lookup not updated: $e')));
  }

  /// Field-by-field updates for one record, so fields this phone doesn't
  /// send (history on a teacher's phone) are kept.
  Map<String, Object?> _fieldUpdates(String key, Map<String, Object?> fields) =>
      {
        for (final e in LookupRecord.clean(fields).entries)
          '${_path(key)}/${e.key}': e.value,
      };

  /// Publishes [student] (private half loaded) after a save. Pass the
  /// admission number it had before editing as [previousAdmissionNo] so an
  /// old key is removed when the number changed. [withHistory] (admins
  /// only: promotion history is admin-only) also publishes the promotion
  /// history; otherwise the saved history is kept as it is.
  Future<void> publishStudent(Student student,
      {String? previousAdmissionNo, bool withHistory = false}) async {
    try {
      final key = lookupKey(LookupType.student, student.admissionNo);
      if (key.isEmpty) return;
      final updates = _fieldUpdates(
        key,
        LookupRecord.studentFields(
          student,
          className: await _className(student.classId),
          history: withHistory ? await _history(student.id) : null,
        ),
      );
      final oldKey =
          lookupKey(LookupType.student, previousAdmissionNo ?? '');
      if (oldKey.isNotEmpty && oldKey != key) updates[_path(oldKey)] = null;
      _publish(updates);
    } catch (e) {
      debugPrint('Public lookup for a student not prepared: $e');
    }
  }

  void removeStudent(Student student) {
    final key = lookupKey(LookupType.student, student.admissionNo);
    if (key.isNotEmpty) _publish({_path(key): null});
  }

  /// Publishes [teacher] after a save, keyed by NIN. A teacher with no NIN
  /// can't be looked up; an old NIN's record is removed.
  void publishTeacher(Teacher teacher, {String? previousNin}) {
    final key = lookupKey(LookupType.teacher, teacher.nin);
    final updates = key.isEmpty
        ? <String, Object?>{}
        : _fieldUpdates(key, LookupRecord.teacherFields(teacher));
    final oldKey = lookupKey(LookupType.teacher, previousNin ?? '');
    if (oldKey.isNotEmpty && oldKey != key) updates[_path(oldKey)] = null;
    _publish(updates);
  }

  void removeTeacher(Teacher teacher) {
    final key = lookupKey(LookupType.teacher, teacher.nin);
    if (key.isNotEmpty) _publish({_path(key): null});
  }

  /// A student's or teacher's new photo, after a queued upload finished.
  Future<void> publishPhoto(String collection, String recordId) async {
    try {
      if (collection == 'students') {
        final snap = await readOnce(_refs.students.child(recordId));
        if (!snap.exists) return;
        final s = Student.fromMap(recordId, asMap(snap.value));
        final key = lookupKey(LookupType.student, s.admissionNo);
        if (key.isNotEmpty) _publish(_fieldUpdates(key, {'photoUrl': s.photoUrl}));
      } else if (collection == 'teachers') {
        // Only admins edit teachers, so this runs on an admin phone.
        final full = await _teacherWithPrivate(recordId);
        if (full == null) return;
        final key = lookupKey(LookupType.teacher, full.nin);
        if (key.isNotEmpty) {
          _publish(_fieldUpdates(key, {'photoUrl': full.photoUrl}));
        }
      }
    } catch (e) {
      debugPrint('Public lookup photo not updated: $e');
    }
  }

  /// Re-publishes the pupils in [studentIds] with their promotion history
  /// (after a promotion run, which only admins can do).
  Future<void> republishStudents(Iterable<String> studentIds) async {
    for (final id in studentIds.toSet()) {
      try {
        final results = await Future.wait([
          readOnce(_refs.students.child(id)),
          readOnce(_refs.studentPrivate.child(id)),
        ]);
        if (!results[0].exists) continue;
        await publishStudent(Student.fromParts(
            id, asMap(results[0].value), asMap(results[1].value)),
            withHistory: true);
      } catch (e) {
        debugPrint('Public lookup for $id not refreshed: $e');
      }
    }
  }

  /// `publicSchools/{schoolId}` from the school's profile.
  void publishSchool(SchoolMeta meta) =>
      _publish({'publicSchools/$_sid': _schoolMap(meta)});

  static Map<String, Object?> _schoolMap(SchoolMeta meta) => {
        'name': meta.name.trim(),
        'logoUrl': meta.logoUrl ?? '',
        'town': meta.address.trim(),
        'updatedAt': ServerValue.timestamp,
      };

  /// Admin "Publish Lookup Data": copies every student and teacher of the
  /// school into `publicLookup` (whole records, so stale fields go) and
  /// refreshes `publicSchools`. Needs internet; waits for the server.
  /// [onProgress] gets (done, total). Returns how many records were written.
  Future<int> publishAll({void Function(int done, int total)? onProgress}) async {
    final results = await Future.wait([
      _refs.profile.get(),
      _refs.classes.get(),
      _refs.students.get(),
      _refs.studentPrivate.get(),
      _refs.teachers.get(),
      _refs.teacherPrivate.get(),
      _refs.promotions.get(),
    ]);
    final meta = SchoolMeta.fromMap(asMap(results[0].value));
    final classNames = _classNames(results[1]);
    final studentPrivate = asMap(results[3].value);
    final teacherPrivate = asMap(results[5].value);
    final historyById = _historyByStudent(results[6], classNames);

    final records = <String, Map<String, Object?>>{};
    for (final c in results[2].children) {
      if (c.key == null || c.value is! Map) continue;
      final s = Student.fromParts(
          c.key!, asMap(c.value), asMap(studentPrivate[c.key]));
      final key = lookupKey(LookupType.student, s.admissionNo);
      if (key.isEmpty) continue;
      records[key] = LookupRecord.clean(LookupRecord.studentFields(
        s,
        className: classNames[s.classId] ?? '',
        history: historyById[s.id] ?? const [],
      ));
    }
    for (final c in results[4].children) {
      if (c.key == null || c.value is! Map) continue;
      final t = Teacher.fromParts(
          c.key!, asMap(c.value), asMap(teacherPrivate[c.key]));
      final key = lookupKey(LookupType.teacher, t.nin);
      if (key.isEmpty) continue;
      records[key] = LookupRecord.clean(LookupRecord.teacherFields(t));
    }

    final total = records.length;
    onProgress?.call(0, total);
    await _refs.root.update({'publicSchools/$_sid': _schoolMap(meta)});
    var done = 0;
    final entries = records.entries.toList();
    const batch = 25;
    for (var i = 0; i < entries.length; i += batch) {
      final chunk = entries.skip(i).take(batch);
      await _refs.root.update({
        for (final e in chunk) _path(e.key): e.value,
      });
      done += chunk.length;
      onProgress?.call(done, total);
    }
    return done;
  }

  // ------------------------------------------------------- school helpers

  Future<String> _className(String? classId) async {
    if (classId == null || classId.isEmpty) return '';
    final snap = await readOnce(_refs.classes.child(classId).child('name'));
    return (snap.value ?? '').toString();
  }

  Future<List<LookupPromotion>> _history(String studentId) async {
    final results =
        await Future.wait([readOnce(_refs.promotions), readOnce(_refs.classes)]);
    return _historyByStudent(results[0], _classNames(results[1]))[studentId] ??
        const [];
  }

  Future<Teacher?> _teacherWithPrivate(String id) async {
    final results = await Future.wait([
      readOnce(_refs.teachers.child(id)),
      readOnce(_refs.teacherPrivate.child(id)),
    ]);
    if (!results[0].exists) return null;
    return Teacher.fromParts(
        id, asMap(results[0].value), asMap(results[1].value));
  }

  static Map<String, String> _classNames(DataSnapshot classes) => {
        for (final c in classes.children)
          if (c.key != null && c.value is Map)
            c.key!: SchoolClass.fromMap(c.key!, asMap(c.value)).name,
      };

  static Map<String, List<LookupPromotion>> _historyByStudent(
      DataSnapshot promotions, Map<String, String> classNames) {
    final records = [
      for (final r in promotions.children)
        if (r.key != null && r.value is Map)
          PromotionRecord.fromMap(r.key!, asMap(r.value)),
    ]..sort((a, b) => (a.promotedAt ?? DateTime(0))
        .compareTo(b.promotedAt ?? DateTime(0)));
    String name(String? id) => classNames[id] ?? '';
    final out = <String, List<LookupPromotion>>{};
    for (final r in records) {
      (out[r.studentId] ??= []).add(LookupPromotion.fromRecord(r, name));
    }
    return out;
  }

  // ------------------------------------------- public reads (no sign-in)

  static const _readTimeout = Duration(seconds: 15);

  /// Reads [path] from the server. Throws [LookupOfflineException] when it
  /// can't be reached.
  static Future<DataSnapshot> _serverRead(String path) async {
    try {
      return await FirebaseDatabase.instance
          .ref(path)
          .get()
          .timeout(_readTimeout);
    } on TimeoutException {
      throw const LookupOfflineException();
    } on FirebaseException catch (e) {
      if (e.code.contains('disconnected') ||
          e.code.contains('network') ||
          e.code.contains('unavailable')) {
        throw const LookupOfflineException();
      }
      rethrow;
    }
  }

  /// Every school in `publicSchools`, A → Z.
  static Future<List<PublicSchool>> loadSchools() async {
    final snap = await _serverRead('publicSchools');
    return [
      for (final c in snap.children)
        if (c.key != null && c.value is Map)
          () {
            final m = asMap(c.value);
            return PublicSchool(
              id: c.key!,
              name: (m['name'] ?? '').toString(),
              logoUrl: (m['logoUrl'] ?? '').toString(),
              town: (m['town'] ?? '').toString(),
            );
          }(),
    ].where((s) => s.name.trim().isNotEmpty).toList()
      ..sort((a, b) => compareText(a.name, b.name));
  }

  /// The record for [id] in [schoolId], or null when there is none.
  static Future<LookupRecord?> find(
      String schoolId, LookupType type, String id) async {
    final key = lookupKey(type, id);
    if (key.isEmpty || schoolId.isEmpty) return null;
    final snap = await _serverRead('publicLookup/$schoolId/$key');
    if (!snap.exists || snap.value is! Map) return null;
    final record = LookupRecord.fromMap(asMap(snap.value));
    return record.type == type ? record : null;
  }
}
