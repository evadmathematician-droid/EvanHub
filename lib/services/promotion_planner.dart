import 'package:firebase_database/firebase_database.dart';

import '../models/promotion_path.dart';
import '../models/school_class.dart';
import '../models/student.dart';
import 'export/export_table.dart';

/// A BECE record collected during the JSS 3 → SSS 1 step.
class BeceRecord {
  final String id;
  final String year;
  const BeceRecord(this.id, this.year);
}

/// What an admin chose on the Promotion screen.
class PromotionRequest {
  const PromotionRequest({
    required this.promoteIds,
    required this.repeatIds,
    required this.targets,
    required this.academicYear,
    required this.promotedBy,
    this.bece = const {},
    this.departments = const {},
  });

  /// Pupils to move up (or graduate from a final class).
  final Set<String> promoteIds;

  /// Pupils who stay in their class this year.
  final Set<String> repeatIds;

  /// From-class id → to-class id, for classes whose pupils move up.
  final Map<String, String> targets;

  final String academicYear;
  final String promotedBy;

  /// JSS 3 → SSS 1: BECE records and departments entered during promotion,
  /// by student id.
  final Map<String, BeceRecord> bece;
  final Map<String, String> departments;
}

enum PromotionOutcome {
  promoted('Promoted'),
  graduated('Graduated'),
  repeated('Repeated'),
  skipped('Skipped');

  const PromotionOutcome(this.label);

  final String label;
}

/// One pupil's line in the promotion report.
class PromotionLine {
  const PromotionLine({
    required this.studentId,
    required this.name,
    required this.admissionNo,
    required this.from,
    required this.to,
    required this.outcome,
    this.note = '',
  });

  final String studentId;
  final String name;
  final String admissionNo;
  final String from;
  final String to;
  final PromotionOutcome outcome;
  final String note;
}

/// The result of a promotion run: every chosen pupil with their outcome.
class PromotionReport {
  PromotionReport(this.lines, {required this.academicYear, DateTime? at})
      : at = at ?? DateTime.now();

  final List<PromotionLine> lines;
  final String academicYear;
  final DateTime at;

  List<PromotionLine> of(PromotionOutcome o) =>
      [for (final l in lines) if (l.outcome == o) l];

  int count(PromotionOutcome o) => of(o).length;

  /// The report as a printable table: promoted, graduated, repeated, then
  /// skipped pupils.
  ExportTable toTable(String schoolName, {List<String> filters = const []}) =>
      ExportTable(
        schoolName: schoolName,
        title: 'Promotion report',
        filters: [
          ...filters,
          if (academicYear.isNotEmpty) 'Academic year $academicYear',
        ],
        generatedAt: at,
        columns: const [
          ExportColumn('Name', flex: 4),
          ExportColumn('Admission no.', flex: 2),
          ExportColumn('From', flex: 2),
          ExportColumn('To', flex: 2),
          ExportColumn('Result', flex: 1.6),
          ExportColumn('Note', flex: 3),
        ],
        rows: [
          for (final o in PromotionOutcome.values)
            for (final l in of(o))
              [l.name, l.admissionNo, l.from, l.to, o.label, l.note],
        ],
      );
}

/// The single multi-path update (relative to `schools/{schoolId}`) and the
/// report it produces.
class PromotionPlan {
  const PromotionPlan(this.updates, this.report);

  final Map<String, Object?> updates;
  final PromotionReport report;
}

/// Works out a promotion run without touching the database, so the rules can
/// be tested. [students] must include their private halves (exam records).
///
/// - Promoted pupils move exactly one class along their [PromotionPath], to
///   the class in [PromotionRequest.targets]; final classes graduate.
/// - Repeaters stay where they are; a history record notes the repeat.
/// - Every promoted or graduated pupil gets `lastPromotedAt`, which resets
///   the 10-month repeater clock.
/// - JSS 3 → SSS 1 needs a BECE ID + year and a department for each pupil
///   (on file or entered now); if any is missing this throws and nothing is
///   written.
/// - Graduating SSS 3 needs a WASSCE record; pupils without one are skipped
///   and reported.
/// - Anyone who can't be moved safely (left the school, class missing or
///   non-standard, wrong target) is skipped with the reason.
PromotionPlan planPromotion({
  required List<SchoolClass> classes,
  required List<Student> students,
  required PromotionRequest request,
  required String Function() newRecordKey,
}) {
  final classById = {for (final c in classes) c.id: c};
  final studentById = {for (final s in students) s.id: s};
  final updates = <String, Object?>{};
  final lines = <PromotionLine>[];
  final missingSssEntry = <String>[];

  void audit(String id, String fromClassId, String? toClassId) {
    updates['promotions/${newRecordKey()}'] = {
      'studentId': id,
      'fromClassId': fromClassId,
      'toClassId': toClassId,
      'academicYear': request.academicYear,
      'promotedBy': request.promotedBy,
      'promotedAt': ServerValue.timestamp,
    };
  }

  final ids = [...request.promoteIds, ...request.repeatIds];
  for (final id in ids) {
    final promote = request.promoteIds.contains(id);
    final s = studentById[id];
    final from = classById[s?.classId];
    PromotionLine line(PromotionOutcome o, String to, [String note = '']) =>
        PromotionLine(
          studentId: id,
          name: s?.fullName ?? id,
          admissionNo: s?.admissionNo ?? '',
          from: from?.name ?? '',
          to: to,
          outcome: o,
          note: note,
        );

    if (s == null || s.status != StudentStatus.active) {
      lines.add(line(PromotionOutcome.skipped, '', 'Not an active pupil'));
      continue;
    }
    if (from == null) {
      lines.add(line(PromotionOutcome.skipped, '', 'Has no class'));
      continue;
    }
    final path = PromotionPath.of(from, classes);
    if (path == null) {
      lines.add(line(PromotionOutcome.skipped, '',
          '${from.name} is not a standard class name'));
      continue;
    }

    if (!promote) {
      audit(id, from.id, from.id);
      lines.add(line(PromotionOutcome.repeated, from.name));
      continue;
    }

    if (path.graduates) {
      if (path.needsWassce(from) &&
          (s.wassceId.trim().isEmpty || s.wassceYear.trim().isEmpty)) {
        lines.add(line(
            PromotionOutcome.skipped, '', 'WASSCE ID and year missing'));
        continue;
      }
      updates['students/$id/status'] = StudentStatus.graduated;
      updates['students/$id/lastPromotedAt'] = ServerValue.timestamp;
      audit(id, from.id, null);
      lines.add(line(PromotionOutcome.graduated, 'Past'));
      continue;
    }

    final to = classById[request.targets[from.id]];
    if (to == null || !path.isTarget(to)) {
      lines.add(line(PromotionOutcome.skipped, '',
          'Choose the ${path.next.name} class to move to'));
      continue;
    }

    if (path.needsBece(from)) {
      final bece = request.bece[id];
      final hasBece = bece != null
          ? bece.id.trim().isNotEmpty && bece.year.trim().isNotEmpty
          : s.beceId.trim().isNotEmpty && s.beceYear.trim().isNotEmpty;
      final department = request.departments[id] ?? s.department ?? '';
      if (!hasBece || department.isEmpty) {
        missingSssEntry.add(s.fullName);
        continue;
      }
      if (bece != null) {
        updates['studentPrivate/$id/beceId'] = bece.id.trim();
        updates['studentPrivate/$id/beceYear'] = bece.year.trim();
      }
      updates['students/$id/department'] = department;
    }

    updates['students/$id/classId'] = to.id;
    // Pre 2 → Class 1 changes level; keep the student's copy in step.
    updates['students/$id/level'] = to.level!.wire;
    updates['students/$id/lastPromotedAt'] = ServerValue.timestamp;
    audit(id, from.id, to.id);
    lines.add(line(PromotionOutcome.promoted, to.name));
  }

  if (missingSssEntry.isNotEmpty) {
    throw StateError('BECE ID, BECE year and department are required before '
        'moving to SSS 1: ${missingSssEntry.join(', ')}.');
  }
  return PromotionPlan(
    updates,
    PromotionReport(lines, academicYear: request.academicYear),
  );
}
