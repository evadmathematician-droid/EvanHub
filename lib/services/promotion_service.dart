import 'package:firebase_database/firebase_database.dart';

import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';

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

  /// Moves every active student in [fromClassId] to [toClassId] (or graduates
  /// them when [toClassId] is null) and writes a promotion audit record per
  /// student. Runs as one atomic multi-path update.
  ///
  /// - [requireBece]: the JSS 3 → SSS 1 step. Each pupil must already have a
  ///   BECE ID + year, or one supplied in [bece]; otherwise this throws and
  ///   nothing is written. Supplied records are saved with the promotion.
  /// - [requireWassce]: graduating SSS 3. A pupil with no WASSCE ID + year is
  ///   skipped and reported, like Ninka's "cannot promote" rule.
  Future<PromotionResult> promoteClass({
    required String fromClassId,
    String? toClassId,
    required String academicYear,
    required String promotedBy,
    bool requireBece = false,
    bool requireWassce = false,
    Map<String, BeceRecord> bece = const {},
  }) async {
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

      updates['students/$id/classId'] = toClassId;
      if (toClassId == null) updates['students/$id/status'] = 'graduated';
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
