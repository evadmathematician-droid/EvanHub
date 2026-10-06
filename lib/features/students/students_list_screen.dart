import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../core/internet_check.dart';
import '../../core/offline_write.dart';
import '../../core/rtdb.dart';
import '../../models/school.dart';
import '../../models/school_class.dart';
import '../../models/school_level.dart';
import '../../models/student.dart';
import '../../services/class_service.dart';
import '../../services/export/export_images.dart';
import '../../services/export/export_table.dart';
import '../../services/export/photo_placeholder.dart';
import '../../services/file_actions.dart';
import '../../services/school_service.dart';
import '../../services/student_photo_cache.dart';
import '../../services/student_service.dart';
import '../../services/upload_queue.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/export_button.dart';
import '../../widgets/photo_avatar.dart';
import '../../widgets/repeater_badge.dart';
import '../../widgets/status_views.dart';
import 'student_filters.dart';

/// Students, filtered by class and status with a count on every choice.
/// The filter panel at the top has:
///  1. Active | Past (tap the selected one again to show both), the Sort
///     button (name, ID, class or date of registration) and the Print
///     button (PDF, Word or Excel of exactly what is listed, in that order);
///  2. the class chips (All | JSS 1 | JSS 2 | …), led by a level picker when
///     the school runs more than one level;
///  3. for SSS 1–3, the stream chips (Science | Commercial | Arts).
/// Pupils not promoted for 10 months show in red as "Repeater".
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

  /// SSS department; null = every stream, '' = no department recorded.
  String? _stream;

  /// Null = active and past.
  StatusFilter? _status = StatusFilter.active;

  StudentSort _sort = StudentSort.name;

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
    final senior = StudentFilters.isSenior(level, rung);
    final stream = senior ? _stream : null;
    final shown = f.sorted(
        f.where(level: level, rung: rung, status: _status, department: stream),
        _sort);
    int streamCount(String? d) =>
        f.count(level: level, rung: rung, status: _status, department: d);

    // The full pupils register: every field of exactly the pupils shown
    // (current filters and sort), the same columns in PDF, Excel and Word.
    Future<ExportTable> buildTable() async {
      // Runs on tap (not during build), always for the user's own school.
      final refs = context.read<AuthController>().tenant!;
      final className = level != null && rung != null
          ? level.standardClasses[rung].name
          : null;
      // Private halves (date of birth, guardian, address, exams) from the
      // phone's copy, so this works offline too.
      final Map<String, dynamic> private;
      final SchoolMeta meta;
      try {
        private = asMap((await readOnce(refs.studentPrivate)).value);
        meta = SchoolMeta.fromMap(asMap((await readOnce(refs.profile)).value));
      } on TimeoutException {
        throw const FileActionException('The pupils\' details are not saved '
            'on this phone yet. Connect to the internet once and try again.');
      }
      final logo = await ExportImages.load(ExportImages.badgeUrl(meta.logoUrl));
      final photos = await _registerPhotos(shown);
      final date = DateFormat('dd/MM/yyyy');
      String d(DateTime? v) => v == null ? '-' : date.format(v);
      String t(String? v) => (v ?? '').trim().isEmpty ? '-' : v!.trim();

      return ExportTable(
        schoolName: meta.name.isNotEmpty ? meta.name : await _schoolName,
        title: 'Pupils Register',
        heading: 'Pupils Register - ${className ?? level?.label ?? 'All classes'}',
        schoolAddress: meta.address,
        logo: logo,
        rowPhotos: photos,
        layout: ExportLayout.register,
        filters: [
          if (multiLevel) level?.label ?? 'All levels',
          className ?? 'All classes',
          if (stream != null) stream.isEmpty ? 'No department' : stream,
          _status?.label ?? 'Active and past',
        ],
        columns: _registerColumns,
        rows: [
          for (final s in shown.map((s) =>
              s.withPrivate(asMap(private[s.id]))))
            [
              t(s.admissionNo),
              t(s.fullName),
              t(s.gender.isEmpty
                  ? ''
                  : s.gender[0].toUpperCase() + s.gender.substring(1)),
              d(s.dob),
              t(f.levelOf(s)?.label),
              t(f.classOf(s)?.name),
              t(s.department),
              t(s.admissionYear),
              d(s.createdAt),
              t(StudentStatus.label(s.status)),
              _promotionStatus(s),
              d(s.lastPromotedAt),
              t(s.guardianName),
              t(s.guardianPhone),
              t(s.address),
              t(s.npseId),
              t(s.npseYear),
              t(s.beceId),
              t(s.beceYear),
              t(s.wassceId),
              t(s.wassceYear),
            ],
        ],
      );
    }

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
                    Expanded(child: _statusSwitch(f, level, rung, stream)),
                    const SizedBox(width: 8),
                    _sortButton(),
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
                            rung == null, () {
                          _rung = null;
                          _stream = null;
                        }),
                        for (final r in f.rungsOf(level))
                          _chip(
                              level.standardClasses[r].name,
                              f.count(level: level, rung: r, status: _status),
                              rung == r, () {
                            _rung = r;
                            _stream = null;
                          }),
                      ],
                    ],
                  ),
                ),
                if (senior) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 32,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _chip('All streams', streamCount(null), stream == null,
                            () => _stream = null),
                        for (final d in kDepartments)
                          _chip(d, streamCount(d), stream == d,
                              () => _stream = d),
                        if (streamCount('') > 0)
                          _chip('No department', streamCount(''),
                              stream == '', () => _stream = ''),
                      ],
                    ),
                  ),
                ],
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
  Widget _statusSwitch(StudentFilters f, SchoolLevel? level, int? rung,
          String? stream) =>
      SegmentedButton<StatusFilter>(
        segments: [
          for (final s in StatusFilter.values)
            ButtonSegment(
              value: s,
              label: Text(
                '${s.label} (${f.count(level: level, rung: rung, status: s, department: stream)})',
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

  /// "Sort ▾": Name | ID | Class | Date of registration. The chosen one is
  /// ticked; the list and the printed file both follow it.
  Widget _sortButton() => MenuAnchor(
        alignmentOffset: const Offset(0, 4),
        menuChildren: [
          for (final s in StudentSort.values)
            MenuItemButton(
              leadingIcon: Icon(s.icon, size: 20),
              trailingIcon: s == _sort
                  ? const Icon(Icons.check, size: 18, color: AppColors.primary)
                  : null,
              onPressed: () => setState(() => _sort = s),
              child: Text(s.label),
            ),
        ],
        builder: (context, menu, _) => FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          icon: const Icon(Icons.sort, size: 18),
          label: const Text('Sort'),
        ),
      );

  /// "All levels ▾" / "Primary ▾" at the front of the class row.
  Widget _levelPicker(StudentFilters f, SchoolLevel? level) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: PopupMenuButton<SchoolLevel?>(
          tooltip: 'Choose a level',
          onSelected: (l) => setState(() {
            _level = l;
            _rung = null;
            _stream = null;
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
          leading: PhotoAvatar(
              url: s.photoUrl, title: s.fullName, recordId: s.id),
          title: s.isRepeater()
              ? Row(
                  children: [
                    Flexible(
                      child: Text(s.fullName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.danger)),
                    ),
                    const SizedBox(width: 6),
                    const RepeaterBadge(),
                  ],
                )
              : Text(s.fullName),
          subtitle: Text([
            if (schoolClass != null) schoolClass.name,
            if ((s.department ?? '').isNotEmpty) s.department!,
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

/// The pupils register columns, in order — the same in PDF, Excel and Word.
/// Narrow columns for short values, wider ones for names and addresses.
const _registerColumns = [
  // Widths fit the longest word or date at 7 pt on A4 landscape, so nothing
  // is broken mid-word ("No." is 0.7 ≈ 16 pt; 1.0 ≈ 23 pt).
  ExportColumn('Student ID', flex: 2.0),
  ExportColumn('Full name', flex: 1.8),
  ExportColumn('Gender', flex: 1.22),
  ExportColumn('Date of birth', flex: 1.75, isDate: true),
  ExportColumn('Level', flex: 1.79),
  ExportColumn('Class', flex: 1.4),
  ExportColumn('Department', flex: 1.9),
  ExportColumn('Admission year', flex: 1.75),
  ExportColumn('Admission date', flex: 1.75, isDate: true),
  ExportColumn('Status', flex: 1.85),
  ExportColumn('Promotion status', flex: 1.62),
  ExportColumn('Last promoted', flex: 1.75, isDate: true),
  ExportColumn('Guardian name', flex: 1.75),
  ExportColumn('Guardian phone', flex: 1.75),
  ExportColumn('Home address', flex: 1.7),
  ExportColumn('NPSE index no.', flex: 1.75),
  ExportColumn('NPSE year', flex: 0.96),
  ExportColumn('BECE index no.', flex: 1.75),
  ExportColumn('BECE year', flex: 1.05),
  ExportColumn('WASSCE index no.', flex: 1.75),
  ExportColumn('WASSCE year', flex: 1.44),
];

/// Where the pupil stands with promotion, in one word or two: Graduated,
/// Repeater (no promotion for 10 months, as in the list), Promoted, or Not
/// yet promoted.
String _promotionStatus(Student s) {
  if (s.status == StudentStatus.graduated) return 'Graduated';
  if (s.isRepeater()) return 'Repeater';
  return s.lastPromotedAt != null ? 'Promoted' : 'Not yet promoted';
}

/// One passport photo per pupil, in [shown] order, for the register's photo
/// column: a photo still waiting to upload, else the copy saved on the phone,
/// else a download when online, else the "No Photo" placeholder. Loads a few
/// at a time; a photo that can't be had never stops the export.
Future<List<Uint8List?>> _registerPhotos(List<Student> shown) async {
  final placeholder = await photoPlaceholderPng();
  final online = await hasInternet();
  final cache = StudentPhotoCache.instance;
  final queue = UploadQueue.instance;

  Future<Uint8List?> one(Student s) async {
    try {
      final waiting = queue?.localPhoto(s.id);
      if (waiting != null) return await File(waiting).readAsBytes();
      return await cache.load(s.id, s.photoUrl, download: online) ??
          placeholder;
    } catch (_) {
      return placeholder;
    }
  }

  final photos = List<Uint8List?>.filled(shown.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < shown.length) {
      final i = next++;
      photos[i] = await one(shown[i]);
    }
  }

  await Future.wait([for (var w = 0; w < 6; w++) worker()]);
  return photos;
}
