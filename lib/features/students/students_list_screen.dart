import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/school_class.dart';
import '../../models/school_level.dart';
import '../../models/student.dart';
import '../../services/class_service.dart';
import '../../services/student_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/photo_avatar.dart';
import '../../widgets/status_views.dart';
import 'student_filters.dart';

/// Students, filtered by class and status with a count on every chip:
///  - a level row (All levels | Pre-primary | Primary | Secondary), shown
///    only when the school runs more than one level;
///  - a class row for the chosen level (All | JSS 1 | JSS 2 | …);
///  - a status row (Active | Past). Tap the selected status again to show
///    both.
/// Each row's counts follow the other rows' choices, so "Class 4 (30)" with
/// Active selected means 30 active pupils in Class 4.
class StudentsListScreen extends StatefulWidget {
  const StudentsListScreen({super.key});

  @override
  State<StudentsListScreen> createState() => _StudentsListScreenState();
}

class _StudentsListScreenState extends State<StudentsListScreen> {
  // Created once so chip taps don't re-subscribe (and flash a spinner).
  late final Stream<List<SchoolClass>> _classes;
  late final Stream<List<Student>> _students;

  /// Null = all levels.
  SchoolLevel? _level;

  /// Null = all classes in the level.
  int? _rung;

  /// Null = active and past.
  StatusFilter? _status = StatusFilter.active;

  @override
  void initState() {
    super.initState();
    final tenant = context.read<AuthController>().tenant!;
    _classes = ClassService(tenant).watchAll();
    _students = StudentService(tenant).watchAll();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.read<AuthController>().role.canManageStudents;

    return Scaffold(
      appBar: AppBar(title: const Text('Students')),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.studentNew),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
      body: StreamBuilder<List<SchoolClass>>(
        stream: _classes,
        builder: (context, classSnap) => StreamBuilder<List<Student>>(
          stream: _students,
          builder: (context, studentSnap) {
            final error = classSnap.error ?? studentSnap.error;
            if (error != null) {
              return ErrorView(message: 'Could not load data.\n$error');
            }
            if (!classSnap.hasData || !studentSnap.hasData) {
              return const LoadingView();
            }
            if (studentSnap.data!.isEmpty) {
              return const EmptyView(
                  message: 'No students yet.', icon: Icons.groups_outlined);
            }
            return _buildFiltered(
                StudentFilters(classSnap.data!, studentSnap.data!), canEdit);
          },
        ),
      ),
    );
  }

  Widget _buildFiltered(StudentFilters f, bool canEdit) {
    // A one-level school has no level row; its class row is that level's.
    // Drop choices that no longer exist (e.g. a deleted class).
    final level = f.levels.length == 1
        ? f.levels.single
        : (f.levels.contains(_level) ? _level : null);
    final rung =
        level != null && f.rungsOf(level).contains(_rung) ? _rung : null;
    final shown = f.where(level: level, rung: rung, status: _status);

    return Column(
      children: [
        if (f.levels.length > 1)
          _ChipRow(children: [
            _chip('All levels', f.count(status: _status), level == null,
                () => _level = null),
            for (final l in f.levels)
              _chip(l.label, f.count(level: l, status: _status), level == l,
                  () {
                _level = l;
                _rung = null;
              }),
          ]),
        if (level != null && f.rungsOf(level).isNotEmpty)
          _ChipRow(children: [
            _chip('All', f.count(level: level, status: _status), rung == null,
                () => _rung = null),
            for (final r in f.rungsOf(level))
              _chip(
                  level.standardClasses[r].name,
                  f.count(level: level, rung: r, status: _status),
                  rung == r,
                  () => _rung = r),
          ]),
        _ChipRow(children: [
          for (final s in StatusFilter.values)
            _chip(
                s.label,
                f.count(level: level, rung: rung, status: s),
                _status == s,
                // Tapping the selected status clears it (shows both).
                () => _status = _status == s ? null : s),
        ]),
        const SizedBox(height: 4),
        Expanded(
          child: shown.isEmpty
              ? const EmptyView(
                  message: 'No students match these filters.',
                  icon: Icons.filter_alt_off_outlined)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                  itemCount: shown.length,
                  itemBuilder: (context, i) =>
                      _studentTile(shown[i], f.classOf(shown[i]), canEdit),
                ),
        ),
      ],
    );
  }

  Widget _chip(String label, int count, bool selected, VoidCallback select) =>
      ChoiceChip(
        label: Text('$label ($count)'),
        selected: selected,
        onSelected: (_) => setState(select),
      );

  Widget _studentTile(Student s, SchoolClass? schoolClass, bool canEdit) =>
      Card(
        child: ListTile(
          leading: PhotoAvatar(url: s.photoUrl, title: s.fullName),
          title: Text(s.fullName),
          subtitle: Text([
            if (schoolClass != null) schoolClass.name,
            if (s.admissionNo.isNotEmpty) 'Adm ${s.admissionNo}',
            if (s.gender.isNotEmpty) s.gender,
            StudentStatus.label(s.status),
          ].join('  •  ')),
          trailing: canEdit ? const Icon(Icons.chevron_right) : null,
          onTap: canEdit
              ? () => context.push(Routes.studentEdit(s.id), extra: s)
              : null,
        ),
      );
}

/// One horizontally scrolling row of chips.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            children[i],
          ],
        ],
      ),
    );
  }
}
