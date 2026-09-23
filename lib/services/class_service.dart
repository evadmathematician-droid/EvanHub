import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';
import '../models/school_class.dart';
import '../models/school_level.dart';

class ClassService {
  ClassService(this._refs);

  final TenantRefs _refs;

  Stream<List<SchoolClass>> watchAll() {
    return watchList(_refs.classes, SchoolClass.fromMap).map(
      (list) => list..sort((a, b) => compareText(a.name, b.name)),
    );
  }

  Future<String> add(SchoolClass schoolClass) async {
    final ref = _refs.classes.push();
    await ref.set(schoolClass.toMap());
    return ref.key!;
  }

  /// Creates the standard class ladder for [level] in one atomic write, skipping
  /// any class whose name already exists at that level. Returns how many were
  /// added.
  Future<int> addStandardClasses(
    SchoolLevel level, {
    required String academicYear,
  }) async {
    final existing = await _refs.classes.get();
    final taken = <String>{
      for (final c in existing.children)
        if (asMap(c.value)['level'] == level.wire)
          (asMap(c.value)['name'] ?? '').toString().toLowerCase(),
    };

    final updates = <String, Object?>{};
    for (final std in level.standardClasses) {
      if (taken.contains(std.name.toLowerCase())) continue;
      updates[_refs.classes.push().key!] = SchoolClass(
        id: '',
        name: std.name,
        level: level,
        stage: std.stage,
        academicYear: academicYear,
      ).toMap();
    }
    if (updates.isEmpty) return 0;
    await _refs.classes.update(updates);
    return updates.length;
  }

  Future<void> update(SchoolClass schoolClass) {
    return _refs.classes.child(schoolClass.id).update(schoolClass.toMap());
  }

  Future<void> delete(String id) => _refs.classes.child(id).remove();
}
