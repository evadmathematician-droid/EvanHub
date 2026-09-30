import 'package:firebase_database/firebase_database.dart';

import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';
import '../models/promotion_path.dart';
import '../models/school_class.dart';
import '../models/student.dart';

/// A BECE record collected during the JSS 3 → SSS 1 step.
class BeceRecord {
  final String id;
  final String year;
  const BeceRecord(this.id, this.year);
}

/// An active pupil in a class who still has no complete BECE record.
class MissingBece {
  final String studentId;
  final String name;
  final String beceId;
  final String beceYear;
  const MissingBece(this.studentId, this.name, this.beceId, this.beceYear);
}

/// Outcome of a promotion run.
class PromotionResult {
  final int moved;

  /// Pupils left untouched (e.g. an SSS 3 pupil with no WASSCE record).
  final List<String> skipped;
  const PromotionResult(this.moved, this.skipped);
}

class PromotionService {
  PromotionService(this._refs);

  final TenantRefs _refs;

  static bool _blank(Object? v) => (v ?? '').toString().trim().isEmpty;

  static String _name(Map<String, dynamic> data) => [
        data['firstName'],
        data['middleName'],
        data['lastName'],
      ].where((p) => !_blank(p)).join(' ');

  /// Active pupils in [classId] as (id, public record, private record). Exam
  /// records live in `studentPrivate`, the class and status in `students`.
  Future<List<(String, Map<String, dynamic>, Map<String, dynamic>)>>
      _activeIn(String classId) async {
    final results = await Future.wait([
      _refs.students.get(),
      _refs.studentPrivate.get(),
    ]);
    final private = asMap(results[1].value);
    return [
      for (final child in results[0].children)
        if (child.key != null &&
            asMap(child.value)['classId'] == classId &&
            (asMap(child.value)['status'] ?? 'active') == 'active')
          (child.key!, asMap(child.value), asMap(private[child.key])),
    ];
  }

  Future<List<SchoolClass>> _classes() async {
    final snapshot = await _refs.classes.get();
    return [
      for (final c in snapshot.children)
        if (c.key != null && c.value is Map)
          SchoolClass.fromMap(c.key!, asMap(c.value)),
    ];
  }

  /// Active pupils in [classId] whose BECE ID or year is missing. Promoting
  /// JSS 3 → SSS 1 is blocked until each of them has both.
  Future<List<MissingBece>> activeStudentsMissingBece(String classId) async {
    return [
      for (final (id, data, private) in await _activeIn(classId))
        if (_blank(private['beceId']) || _blank(private['beceYear']))
          MissingBece(
            id,
            _name(data),
            (private['beceId'] ?? '').toString(),
            (private['beceYear'] ?? '').toString(),
          ),
    ];
  }

  /// Moves every active student in [fromClassId] one step along its
  /// [PromotionPath] and writes a promotion audit record per student. Runs as
  /// one atomic multi-path update.
  ///
  /// [toClassId] must be a class at the path's next rung, or null when the
  /// path graduates. Anything else (a skipped class, a class from another
  /// level) throws and nothing is written. Graduates keep their classId, so
  /// they still show under their last class with the "Past" filter.
  ///
  /// - JSS 3 → SSS 1: each pupil must already have a BECE ID + year, or one
  ///   supplied in [bece]; otherwise this throws and nothing is written.
  ///   Supplied records are saved with the promotion.
  /// - Graduating SSS 3: a pupil with no WASSCE ID + year is skipped and
  ///   reported, like Ninka's "cannot promote" rule.
  Future<PromotionResult> promoteClass({
    required String fromClassId,
    String? toClassId,
    required String academicYear,
    required String promotedBy,
    Map<String, BeceRecord> bece = const {},
  }) async {
    final classes = await _classes();
    final from = classes.where((c) => c.id == fromClassId).firstOrNull;
    if (from == null) throw StateError('That class no longer exists.');
    final path = PromotionPath.of(from, classes);
    if (path == null) {
      throw StateError('${from.name} is not a standard class, so its next '
          'class is unknown.');
    }
    final to = classes.where((c) => c.id == toClassId).firstOrNull;
    if (path.graduates) {
      if (toClassId != null) {
        throw StateError(
            '${from.name} pupils graduate; they cannot move to another class.');
      }
    } else if (to == null || !path.isTarget(to)) {
      throw StateError(
          '${from.name} pupils can only move to ${path.next.name}.');
    }
    final requireBece = path.needsBece(from);
    final requireWassce = path.needsWassce(from);

    final updates = <String, Object?>{};
    final skipped = <String>[];
    final stillMissingBece = <String>[];
    var count = 0;
    for (final (id, data, private) in await _activeIn(fromClassId)) {
      if (requireBece) {
        final given = bece[id];
        final beceId = given?.id ?? private['beceId'];
        final beceYear = given?.year ?? private['beceYear'];
        if (_blank(beceId) || _blank(beceYear)) {
          stillMissingBece.add(_name(data));
          continue;
        }
        if (given != null) {
          updates['studentPrivate/$id/beceId'] = given.id;
          updates['studentPrivate/$id/beceYear'] = given.year;
        }
      }

      if (requireWassce &&
          (_blank(private['wassceId']) || _blank(private['wassceYear']))) {
        skipped.add('${_name(data)} (WASSCE ID and year missing)');
        continue;
      }

      if (path.graduates) {
        updates['students/$id/status'] = StudentStatus.graduated;
      } else {
        updates['students/$id/classId'] = to!.id;
        // Pre 2 → Class 1 changes level; keep the student's copy in step.
        updates['students/$id/level'] = to.level!.wire;
      }
      updates['promotions/${_refs.promotions.push().key}'] = {
        'studentId': id,
        'fromClassId': fromClassId,
        'toClassId': toClassId,
        'academicYear': academicYear,
        'promotedBy': promotedBy,
        'promotedAt': ServerValue.timestamp,
      };
      count++;
    }

    if (stillMissingBece.isNotEmpty) {
      throw StateError('BECE ID and year are required before promoting: '
          '${stillMissingBece.join(', ')}.');
    }
    if (count == 0) return PromotionResult(0, skipped);
    await _refs.school.update(updates);
    return PromotionResult(count, skipped);
  }
}
