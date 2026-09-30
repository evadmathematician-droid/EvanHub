import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/school_class.dart';
import '../../models/school_level.dart';
import '../../models/student.dart';
import '../../services/class_service.dart';
import '../../services/export/export_table.dart';
import '../../services/school_service.dart';
import '../../services/student_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/export_button.dart';
import '../../widgets/photo_avatar.dart';
import '../../widgets/status_views.dart';
import 'student_filters.dart';

/// Students, filtered by class and status with a count on every choice.
/// The filter panel at the top has two rows:
///  1. Active | Past (tap the selected one again to show both) and the
///     Print button (PDF, Word or Excel of exactly what is listed);
///  2. the class chips (All | JSS 1 | JSS 2 | …), led by a level picker when
///     the school runs more than one level.
/// Each row's counts follow the other row's choice, so "Class 4 (30)" with
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

  /// Loaded up front so printing doesn't wait on the network.
  late final Future<String> _schoolName;

  /// Null = all levels.
  SchoolLevel? _level;

  /// Null = all classes in the level.
  int? _rung;

  /// Null = active and past.
  StatusFilter? _status = StatusFilter.active;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController>();
    _classes = ClassService(auth.tenant!).watchAll();
    _students = StudentService(auth.tenant!).watchAll();
    _schoolName = SchoolService()
        .schoolName(auth.schoolId!)
        .catchError((Object _) => '');
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
    // A one-level school has no level picker; its classes are that level's.
    // Drop choices that no longer exist (e.g. a deleted class).
    final multiLevel = f.levels.length > 1;
    final level = multiLevel
        ? (f.levels.contains(_level) ? _level : null)
        : f.levels.firstOrNull;
    final rung =
        level != null && f.rungsOf(level).contains(_rung) ? _rung : null;
    final shown = f.where(level: level, rung: rung, status: _status);

    Future<ExportTable> buildTable() async => ExportTable(
          schoolName: await _schoolName,
          title: 'Students',
          filters: [
            if (multiLevel) level?.label ?? 'All levels',
            if (level != null && rung != null)
              level.standardClasses[rung].name
            else
              'All classes',
            _status?.label ?? 'Active and past',
          ],
          columns: const [
            ExportColumn('Name', flex: 4),
            ExportColumn('Admission no.', flex: 2),
            ExportColumn('Class', flex: 2),
            ExportColumn('Gender', flex: 1.5),
            ExportColumn('Status', flex: 1.5),
          ],
          rows: [
            for (final s in shown)
              [
                s.fullName,
                s.admissionNo,
                f.classOf(s)?.name ?? '',
                s.gender,
                StudentStatus.label(s.status),
              ],
          ],
        );

    return Column(
      children: [
        Material(
          color: AppColors.surface,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _statusSwitch(f, level, rung)),
                    const SizedBox(width: 8),
                    ExportButton(buildTable: buildTable),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      if (multiLevel) _levelPicker(f, level),
                      if (level != null && f.rungsOf(level).isNotEmpty) ...[
                        _chip('All', f.count(level: level, status: _status),
                            rung == null, () => _rung = null),
                        for (final r in f.rungsOf(level))
                          _chip(
                              level.standardClasses[r].name,
                              f.count(level: level, rung: r, status: _status),
                              rung == r,
                              () => _rung = r),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const EmptyView(
                  message: 'No students match these filters.',
                  icon: Icons.filter_alt_off_outlined)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  itemCount: shown.length,
                  itemBuilder: (context, i) =>
                      _studentTile(shown[i], f.classOf(shown[i]), canEdit),
                ),
        ),
      ],
    );
  }

  /// Active | Past as one compact switch. Tapping the selected side again
  /// clears it and shows both.
  Widget _statusSwitch(StudentFilters f, SchoolLevel? level, int? rung) =>
      SegmentedButton<StatusFilter>(
        segments: [
          for (final s in StatusFilter.values)
            ButtonSegment(
              value: s,
              label: Text(
                '${s.label} (${f.count(level: level, rung: rung, status: s)})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        selected: {?_status},
        emptySelectionAllowed: true,
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          selectedBackgroundColor: AppColors.primary,
          selectedForegroundColor: Colors.white,
        ),
        onSelectionChanged: (s) =>
            setState(() => _status = s.isEmpty ? null : s.first),
      );

  /// "All levels ▾" / "Primary ▾" at the front of the class row.
  Widget _levelPicker(StudentFilters f, SchoolLevel? level) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: PopupMenuButton<SchoolLevel?>(
          tooltip: 'Choose a level',
          onSelected: (l) => setState(() {
            _level = l;
            _rung = null;
          }),
          itemBuilder: (_) => [
            PopupMenuItem(
                value: null,
                child: Text('All levels (${f.count(status: _status)})')),
            for (final l in f.levels)
              PopupMenuItem(
                  value: l,
                  child: Text(
                      '${l.label} (${f.count(level: l, status: _status)})')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(level?.label ?? 'All levels',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                const Icon(Icons.arrow_drop_down,
                    size: 20, color: AppColors.primary),
              ],
            ),
          ),
        ),
      );

  Widget _chip(String label, int count, bool selected, VoidCallback select) =>
      Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text('$label ($count)'),
          labelStyle: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
          selectedColor: AppColors.primary,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          selected: selected,
          onSelected: (_) => setState(select),
        ),
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
