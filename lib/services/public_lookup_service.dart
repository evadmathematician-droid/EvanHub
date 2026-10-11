import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../core/internet_check.dart';
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
  const PublicSchool({
    required this.id,
    required this.name,
    this.logoUrl = '',
    this.town = '',
    this.lookupEnabled = true,
    this.adminName = '',
    this.adminPhone = '',
    this.adminWhatsApp = '',
  });

  final String id;
  final String name;
  final String logoUrl;
  final String town;

  /// False when the school has not approved Look Up: no record is read and
  /// people are asked to contact the school instead.
  final bool lookupEnabled;
  final String adminName;

  /// International form (+232…), or '' when none was given.
  final String adminPhone;
  final String adminWhatsApp;

  /// The number for WhatsApp: its own, else the admin phone.
  String get whatsAppNumber => adminWhatsApp.isNotEmpty ? adminWhatsApp : adminPhone;

  factory PublicSchool.fromMap(String id, Map<String, dynamic> m) =>
      PublicSchool(
        id: id,
        name: (m['name'] ?? '').toString(),
        logoUrl: (m['logoUrl'] ?? '').toString(),
        // "location" since index version 1; "town" on older entries.
        town: (m['location'] ?? m['town'] ?? '').toString(),
        // Missing = approved (schools listed before the choice existed).
        lookupEnabled: m['lookupEnabled'] != false,
        adminName: (m['adminName'] ?? '').toString(),
        adminPhone: (m['adminPhone'] ?? '').toString(),
        adminWhatsApp: (m['adminWhatsApp'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'logoUrl': logoUrl,
        'town': town,
        'lookupEnabled': lookupEnabled,
        'adminName': adminName,
        'adminPhone': adminPhone,
        'adminWhatsApp': adminWhatsApp,
      };
}

/// Thrown by the public reads when the server can't be reached.
class LookupOfflineException implements Exception {
  const LookupOfflineException();
}

/// Thrown by the public reads when the database rules refuse them (the
/// public-read rules are not deployed).
class LookupNotSetUpException implements Exception {
  const LookupNotSetUpException();
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

  /// Whether the school approves Look Up (from the profile on this phone;
  /// a school that never decided counts as approved). Record writes skip
  /// silently when it doesn't — the rules refuse them too.
  Future<bool> _lookupOn() async {
    try {
      final v = (await readOnce(_refs.profile.child('lookupEnabled'))).value;
      return v != false;
    } catch (e) {
      debugPrint('Look Up approval unknown, not publishing: $e');
      return false;
    }
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
      if (key.isEmpty || !await _lookupOn()) return;
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
  Future<void> publishTeacher(Teacher teacher, {String? previousNin}) async {
    if (!await _lookupOn()) return;
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
      if (!await _lookupOn()) return;
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

  /// Version of the public index (`publicSchools` + `publicLookup`) this app
  /// writes. A school whose `profile/publicIndexVersion` is lower gets its
  /// whole index rebuilt ([publishAll]) the next time an admin signs in.
  /// Raise it when the shape of the public records changes.
  static const publicIndexVersion = 1;

  /// `publicSchools/{schoolId}` from the school's profile.
  void publishSchool(SchoolMeta meta) {
    if (meta.name.trim().isEmpty) return;
    _publish({'publicSchools/$_sid': _schoolMap(meta)});
  }

  /// Refreshes `publicSchools/{schoolId}` from the profile saved on this
  /// phone. Called whenever an admin reaches the app, so every school that
  /// is in use gets listed — including those registered before Look Up.
  /// Then, once per school (tracked by `profile/publicIndexVersion`), it
  /// rebuilds every pupil's and teacher's public record, so records saved
  /// before Look Up existed can be found too.
  Future<void> refreshSchoolListing() async {
    final Map<String, dynamic> profile;
    try {
      profile = asMap((await readOnce(_refs.profile)).value);
      final meta = SchoolMeta.fromMap(profile);
      if (meta.name.trim().isEmpty) return;
      // Schools registered before Look Up had no choice to make: they count
      // as approved, and this records it.
      if (profile['lookupEnabled'] == null) {
        _publish({'schools/$_sid/profile/lookupEnabled': true});
      }
      publishSchool(meta);
    } catch (e) {
      debugPrint('School listing for Look Up not refreshed: $e');
      return;
    }
    await _upgradeIndex(profile['publicIndexVersion']);
  }

  /// The one-time backfill: runs [publishAll] (which records the version)
  /// when the school's index is older than [publicIndexVersion]. Online
  /// only (it reads the whole school from the server); offline or on a
  /// failure it tries again at the next sign-in. Safe to repeat.
  Future<void> _upgradeIndex(Object? savedVersion) async {
    final saved = savedVersion is num ? savedVersion.toInt() : 0;
    if (saved >= publicIndexVersion) return;
    try {
      if (!await hasInternet()) return;
      final count = await publishAll();
      debugPrint('Public lookup index v$publicIndexVersion built for $_sid: '
          '$count record(s).');
    } catch (e) {
      debugPrint('Public lookup index not built, will retry: $e');
    }
  }

  static Map<String, Object?> _schoolMap(SchoolMeta meta) => {
        'name': meta.name.trim(),
        'logoUrl': meta.logoUrl ?? '',
        'location': meta.address.trim(),
        // Same as location, for app versions that read "town".
        'town': meta.address.trim(),
        'active': true,
        'lookupEnabled': meta.lookupApproved,
        'adminName': meta.adminName.trim(),
        // International form (+232…) for Call / WhatsApp; null removes it.
        'adminPhone': meta.adminPhoneIntl.isEmpty ? null : meta.adminPhoneIntl,
        'adminWhatsApp':
            meta.adminWhatsAppIntl.isEmpty ? null : meta.adminWhatsAppIntl,
        'updatedAt': ServerValue.timestamp,
      };

  /// Settings switch: turns Look Up ON or OFF for the school (needs
  /// internet; waits for the server).
  ///  - ON records the decision, updates the school's listing and publishes
  ///    every record ([publishAll]); returns how many.
  ///  - OFF records the decision, keeps the school listed with
  ///    lookupEnabled false and removes ALL its records; returns 0.
  Future<int> setLookupEnabled(bool on,
      {required String uid,
      void Function(int done, int total)? onProgress}) async {
    await _refs.profile.update({
      'lookupEnabled': on,
      'lookupConsentAt': ServerValue.timestamp,
      'lookupConsentBy': uid,
    });
    if (on) return publishAll(onProgress: onProgress);
    final meta = SchoolMeta.fromMap(asMap((await _refs.profile.get()).value));
    await _refs.root.update({
      if (meta.name.trim().isNotEmpty) 'publicSchools/$_sid': _schoolMap(meta),
      'publicLookup/$_sid': null,
    });
    return 0;
  }

  /// Admin "Publish Lookup Data": copies every student and teacher of the
  /// school into `publicLookup` (whole records, so stale fields go) and
  /// refreshes `publicSchools`. Needs internet; waits for the server.
  /// [onProgress] gets (done, total). Returns how many records were written.
  /// Records [publicIndexVersion] on the profile when done.
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
    if (!meta.lookupApproved) {
      // Not approved: keep the school listed, publish no records.
      if (meta.name.trim().isNotEmpty) {
        await _refs.root.update({'publicSchools/$_sid': _schoolMap(meta)});
      }
      await _markIndexBuilt();
      onProgress?.call(0, 0);
      return 0;
    }
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
      // No ID or no name: can't be looked up (the rules need both).
      if (key.isEmpty || s.fullName.trim().isEmpty) continue;
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
      // No ID or no name: can't be looked up (the rules need both).
      if (key.isEmpty || t.fullName.trim().isEmpty) continue;
      records[key] = LookupRecord.clean(LookupRecord.teacherFields(t));
    }

    final total = records.length;
    onProgress?.call(0, total);
    if (meta.name.trim().isNotEmpty) {
      await _refs.root.update({'publicSchools/$_sid': _schoolMap(meta)});
    }
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
    await _markIndexBuilt();
    return done;
  }

  /// Records on the profile that the index is built at [publicIndexVersion],
  /// so the one-time rebuild at sign-in ([refreshSchoolListing]) is skipped.
  Future<void> _markIndexBuilt() =>
      _refs.profile.child('publicIndexVersion').set(publicIndexVersion);

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

  /// Reads [path] from the server (a one-time `get()`, never the phone's
  /// copy, which is empty on a fresh install). Throws
  /// [LookupOfflineException] when the server can't be reached and
  /// [LookupNotSetUpException] when the rules refuse the read.
  static Future<DataSnapshot> _serverRead(String path) async {
    try {
      return await FirebaseDatabase.instance
          .ref(path)
          .get()
          .timeout(_readTimeout);
    } on TimeoutException {
      throw const LookupOfflineException();
    } on FirebaseException catch (e) {
      final text = '${e.code} ${e.message}'.toLowerCase();
      if (text.contains('permission')) {
        debugPrint('Lookup read of "$path" refused by the rules: $e');
        throw const LookupNotSetUpException();
      }
      if (text.contains('disconnected') ||
          text.contains('network') ||
          text.contains('unavailable') ||
          text.contains('offline')) {
        throw const LookupOfflineException();
      }
      debugPrint('Lookup read of "$path" failed: $e');
      rethrow;
    }
  }

  /// Every school in `publicSchools`, A → Z.
  static Future<List<PublicSchool>> loadSchools() async {
    final snap = await _serverRead('publicSchools');
    return [
      for (final c in snap.children)
        if (c.key != null && c.value is Map && asMap(c.value)['active'] != false)
          PublicSchool.fromMap(c.key!, asMap(c.value)),
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
