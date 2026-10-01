import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';
import '../models/school_class.dart';
import '../models/student.dart';
import 'promotion_planner.dart';

export 'promotion_planner.dart'
    show BeceRecord, PromotionLine, PromotionOutcome, PromotionReport,
        PromotionRequest;

/// What a pupil still needs before moving from JSS 3 to SSS 1.
class SssEntryNeed {
  const SssEntryNeed(this.student, {required this.bece, required this.department});

  final Student student;
  final bool bece;
  final bool department;
}

class PromotionService {
  PromotionService(this._refs);

  final TenantRefs _refs;

  Future<List<SchoolClass>> _classes() async {
    final snapshot = await _refs.classes.get();
    return [
      for (final c in snapshot.children)
        if (c.key != null && c.value is Map)
          SchoolClass.fromMap(c.key!, asMap(c.value)),
    ];
  }

  /// Every student with the private half (exam records) filled in.
  Future<List<Student>> _studentsWithPrivate() async {
    final results = await Future.wait([
      _refs.students.get(),
      _refs.studentPrivate.get(),
    ]);
    final private = asMap(results[1].value);
    return [
      for (final child in results[0].children)
        if (child.key != null && child.value is Map)
          Student.fromParts(
              child.key!, asMap(child.value), asMap(private[child.key])),
    ];
  }

  /// Of [ids], the pupils still missing a BECE record or a department, which
  /// JSS 3 → SSS 1 needs.
  Future<List<SssEntryNeed>> sssEntryNeeds(Iterable<String> ids) async {
    final wanted = ids.toSet();
    final needs = <SssEntryNeed>[];
    for (final s in await _studentsWithPrivate()) {
      if (!wanted.contains(s.id)) continue;
      final bece = s.beceId.trim().isEmpty || s.beceYear.trim().isEmpty;
      final department = (s.department ?? '').isEmpty;
      if (bece || department) {
        needs.add(SssEntryNeed(s, bece: bece, department: department));
      }
    }
    return needs;
  }

  /// Runs [request] as ONE atomic multi-path update and returns the report.
  /// See [planPromotion] for the rules each pupil is checked against.
  Future<PromotionReport> run(PromotionRequest request) async {
    final data = await Future.wait([_classes(), _studentsWithPrivate()]);
    final plan = planPromotion(
      classes: data[0] as List<SchoolClass>,
      students: data[1] as List<Student>,
      request: request,
      newRecordKey: () => _refs.promotions.push().key!,
    );
    if (plan.updates.isNotEmpty) await _refs.school.update(plan.updates);
    return plan.report;
  }
}
