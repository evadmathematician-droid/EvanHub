import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../core/tenant/tenant_refs.dart';

/// Per-school counts for the dashboard. A count is null until its list has
/// loaded (from the phone's copy or the server).
class SchoolStats {
  final int? students;
  final int? teachers;
  final int? classes;
  final int? announcements;

  const SchoolStats({
    this.students,
    this.teachers,
    this.classes,
    this.announcements,
  });
}

class StatsService {
  StatsService(this._refs);

  final TenantRefs _refs;

  /// Live counts: emits as soon as any list has loaded and again whenever a
  /// record is added or removed. Listeners answer from the phone's copy, so
  /// this works offline and updates at once after an offline save.
  Stream<SchoolStats> watch() {
    final counts = <String, int>{};
    final subs = <StreamSubscription<DatabaseEvent>>[];
    late final StreamController<SchoolStats> controller;

    void emit() => controller.add(SchoolStats(
          students: counts['students'],
          teachers: counts['teachers'],
          classes: counts['classes'],
          announcements: counts['announcements'],
        ));

    controller = StreamController<SchoolStats>(
      onListen: () {
        for (final (name, ref) in [
          ('students', _refs.students),
          ('teachers', _refs.teachers),
          ('classes', _refs.classes),
          ('announcements', _refs.announcements),
        ]) {
          subs.add(ref.onValue.listen((e) {
            counts[name] = e.snapshot.children.length;
            emit();
          }, onError: controller.addError));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }
}
