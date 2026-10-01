import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/promotion_path.dart';
import '../../models/school_class.dart';
import '../../models/school_level.dart';
import '../../models/student.dart';
import '../../models/user_role.dart';
import '../../services/class_service.dart';
import '../../services/promotion_service.dart';
import '../../services/school_service.dart';
import '../../services/student_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/repeater_badge.dart';
import '../../widgets/status_views.dart';
import '../students/student_filters.dart';
import 'promotion_report_screen.dart';

/// Promotes pupils one by one or all at once:
///  1. pick a class (JSS 1 = every JSS 1 section), optionally one section;
///  2. for SSS 1–3, pick a stream (Science, Commercial, Arts);
///  3. tick the pupils who move up. Unticked pupils repeat the class.
/// Pupils not promoted for 10 months show in red as "Repeater". After the
/// run a report lists who was promoted, graduated, repeated or skipped.
class PromotionScreen extends StatefulWidget {
  const PromotionScreen({super.key});

  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen> {
  late final Stream<List<SchoolClass>> _classes;
  late final Stream<List<Student>> _students;
  late final Future<String> _schoolName;
  final _year = TextEditingController(text: DateTime.now().year.toString());

  SchoolLevel? _level;
  int? _rung;

  /// One section only (e.g. JSS 1 A); null = every section.
  String? _classId;

  /// SSS stream; '' = pupils with no department. Must be chosen for SSS.
  String? _stream;

  final Set<String> _selected = {};

  /// From-class id → to-class id chosen by the admin.
  final Map<String, String> _targetChoice = {};

  bool _busy = false;

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
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  void _pickGroup(SchoolLevel level, int rung) => setState(() {
        _level = level;
        _rung = rung;
        _classId = null;
        _stream = null;
        _selected.clear();
      });

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    if (auth.role != UserRole.schoolAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Promotion')),
        body: const EmptyView(
          message: 'Only school admins can promote pupils.',
          icon: Icons.lock_outline,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Promotion')),
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
            if (classSnap.data!.isEmpty) {
              return const EmptyView(message: 'Create classes first.');
            }
            return _body(classSnap.data!,
                StudentFilters(classSnap.data!, studentSnap.data!));
          },
        ),
      ),
    );
  }

  Widget _body(List<SchoolClass> classes, StudentFilters f) {
    const active = StatusFilter.active;
    final level = _level;
    final rung = _rung;
    final grouped = level != null && rung != null;
    final senior = StudentFilters.isSenior(level, rung);

    // Sections of the chosen class (JSS 1 A, JSS 1 B …).
    final sections = grouped
        ? (classes
            .where((c) => c.level == level && level.rungOf(c.name) == rung)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name)))
        : const <SchoolClass>[];
    final classId =
        sections.any((c) => c.id == _classId) ? _classId : null;
    bool inScope(Student s) => classId == null || s.classId == classId;

    final inGroup = grouped
        ? f.where(level: level, rung: rung, status: active).where(inScope)
        : const <Student>[];
    final pupils = senior && _stream == null
        ? const <Student>[]
        : [
            for (final s in inGroup)
              if (_stream == null || (s.department ?? '') == _stream) s,
          ];
    final ids = {for (final s in pupils) s.id};
    _selected.retainAll(ids);

    final scopeSections =
        classId == null ? sections : sections.where((c) => c.id == classId);

    return Column(
      children: [
        Material(
          color: AppColors.surface,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Class'),
                _chipRow([
                  for (final l in f.levels)
                    for (final r in f.rungsOf(l))
                      _chip(
                        l.standardClasses[r].name,
                        f.count(level: l, rung: r, status: active),
                        l == level && r == rung,
                        () => _pickGroup(l, r),
                      ),
                ]),
                if (sections.length > 1) ...[
                  const SizedBox(height: 8),
                  _label('Section'),
                  _chipRow([
                    _chip(
                        'All ${level!.standardClasses[rung!].name}',
                        f.count(level: level, rung: rung, status: active),
                        classId == null,
                        () => setState(() => _classId = null)),
                    for (final c in sections)
                      _chip(
                          c.name,
                          f
                              .where(level: level, rung: rung, status: active)
                              .where((s) => s.classId == c.id)
                              .length,
                          classId == c.id,
                          () => setState(() => _classId = c.id)),
                  ]),
                ],
                if (senior) ...[
                  const SizedBox(height: 8),
                  _label('Stream'),
                  _chipRow([
                    for (final d in [...kDepartments, ''])
                      if (d.isNotEmpty ||
                          inGroup.any((s) => (s.department ?? '').isEmpty))
                        _chip(
                          d.isEmpty ? 'No department' : d,
                          inGroup
                              .where((s) => (s.department ?? '') == d)
                              .length,
                          _stream == d,
                          () => setState(() => _stream = d),
                        ),
                  ]),
                ],
                if (grouped) ...[
                  const SizedBox(height: 8),
                  for (final c in scopeSections)
                    _destination(c, classes),
                ],
              ],
            ),
          ),
        ),
        Expanded(child: _pupilList(pupils, f, grouped, senior)),
        if (pupils.isNotEmpty) _bottomBar(pupils, classes),
      ],
    );
  }

  /// "JSS 1 A → JSS 2 A", with a picker when there is more than one choice.
  Widget _destination(SchoolClass from, List<SchoolClass> classes) {
    final path = PromotionPath.of(from, classes);
    final Widget to;
    if (path == null) {
      to = const Text('not a standard class name – rename it under Classes',
          style: TextStyle(color: AppColors.danger));
    } else if (path.graduates) {
      to = const Text('Past (graduates)',
          style: TextStyle(fontWeight: FontWeight.w600));
    } else {
      final targets = classes.where(path.isTarget).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      final chosen = _targetFor(from, path, classes);
      to = targets.isEmpty
          ? Text('no ${path.next.name} class yet – add it under Classes',
              style: const TextStyle(color: AppColors.danger))
          : targets.length == 1
              ? Text(targets.single.name,
                  style: const TextStyle(fontWeight: FontWeight.w600))
              : DropdownButton<String>(
                  value: chosen?.id,
                  hint: Text('Choose ${path.next.name}'),
                  isDense: true,
                  underline: const SizedBox(),
                  items: [
                    for (final t in targets)
                      DropdownMenuItem(value: t.id, child: Text(t.name)),
                  ],
                  onChanged: (v) =>
                      setState(() => _targetChoice[from.id] = v!),
                );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Text('${from.name}  →  ',
              style: const TextStyle(color: AppColors.textSecondary)),
          Flexible(child: to),
        ],
      ),
    );
  }

  SchoolClass? _targetFor(
      SchoolClass from, PromotionPath path, List<SchoolClass> classes) {
    final chosen = classes
        .where((c) => c.id == _targetChoice[from.id] && path.isTarget(c))
        .firstOrNull;
    return chosen ?? path.defaultTarget(from, classes);
  }

  Widget _pupilList(
      List<Student> pupils, StudentFilters f, bool grouped, bool senior) {
    if (!grouped) {
      return const EmptyView(
          message: 'Choose a class above to see its pupils.',
          icon: Icons.touch_app_outlined);
    }
    if (senior && _stream == null) {
      return const EmptyView(
          message: 'Choose a stream: Science, Commercial or Arts.',
          icon: Icons.alt_route);
    }
    if (pupils.isEmpty) {
      return const EmptyView(
          message: 'No active pupils here.', icon: Icons.groups_outlined);
    }
    final all = _selected.length == pupils.length;
    final date = DateFormat('d MMM yyyy');
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        CheckboxListTile(
          value: all ? true : (_selected.isEmpty ? false : null),
          tristate: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text('Select all (${pupils.length})',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Ticked pupils move up. The rest repeat.'),
          onChanged: (_) => setState(() => all
              ? _selected.clear()
              : _selected.addAll(pupils.map((s) => s.id))),
        ),
        const Divider(height: 1),
        for (final s in pupils)
          _pupilTile(s, f.classOf(s), date),
      ],
    );
  }

  Widget _pupilTile(Student s, SchoolClass? c, DateFormat date) {
    final repeater = s.isRepeater();
    final since = s.inClassSince;
    return CheckboxListTile(
      value: _selected.contains(s.id),
      controlAffinity: ListTileControlAffinity.leading,
      tileColor: repeater ? AppColors.danger.withValues(alpha: 0.06) : null,
      title: Row(
        children: [
          Flexible(
            child: Text(
              s.fullName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: repeater ? AppColors.danger : null,
              ),
            ),
          ),
          if (repeater) ...[
            const SizedBox(width: 6),
            const RepeaterBadge(),
          ],
        ],
      ),
      subtitle: Text([
        if (c != null) c.name,
        if (s.department != null && s.department!.isNotEmpty) s.department!,
        if (s.admissionNo.isNotEmpty) 'Adm ${s.admissionNo}',
        if (since != null)
          '${s.lastPromotedAt == null ? 'Registered' : 'Promoted'} '
              '${date.format(since)}',
      ].join('  •  ')),
      onChanged: (v) => setState(
          () => v == true ? _selected.add(s.id) : _selected.remove(s.id)),
    );
  }

  Widget _bottomBar(List<Student> pupils, List<SchoolClass> classes) {
    final promote = _selected.length;
    final repeat = pupils.length - promote;
    return Material(
      elevation: 8,
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Promote $promote  •  Repeat $repeat',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: _year,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Academic year',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _review(pupils, classes),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.trending_up),
                label: const Text('Review'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _review(List<Student> pupils, List<SchoolClass> classes) async {
    final byId = {for (final c in classes) c.id: c};
    final promoteIds = {..._selected};
    final repeatIds = {
      for (final s in pupils)
        if (!promoteIds.contains(s.id)) s.id,
    };

    // Every class that pupils move up from needs a destination.
    final targets = <String, String>{};
    final toSss = <String>[];
    var graduate = 0;
    for (final s in pupils.where((s) => promoteIds.contains(s.id))) {
      final from = byId[s.classId];
      final path = from == null ? null : PromotionPath.of(from, classes);
      if (from == null || path == null) continue;
      if (path.graduates) {
        graduate++;
        continue;
      }
      final to = _targetFor(from, path, classes);
      if (to == null) {
        _snack('Choose where ${from.name} pupils move to.');
        return;
      }
      targets[from.id] = to.id;
      if (path.needsBece(from)) toSss.add(s.id);
    }

    final moving = promoteIds.length - graduate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm promotion'),
        content: Text([
          if (moving > 0)
            'Promote $moving pupil(s) to: '
                '${{for (final id in targets.values) byId[id]!.name}.join(', ')}.',
          if (graduate > 0) 'Graduate $graduate pupil(s). They move to Past.',
          if (repeatIds.isNotEmpty)
            '${repeatIds.length} pupil(s) repeat their class.',
          'Academic year: ${_year.text.trim()}',
        ].join('\n\n')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Promote')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final auth = context.read<AuthController>();
    final service = PromotionService(auth.tenant!);
    setState(() => _busy = true);
    try {
      // JSS 3 → SSS 1: collect missing BECE records and departments first.
      var bece = <String, BeceRecord>{};
      var departments = <String, String>{};
      if (toSss.isNotEmpty) {
        final needs = await service.sssEntryNeeds(toSss);
        if (needs.isNotEmpty) {
          if (!mounted) return;
          final entered = await showDialog<_SssEntry>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _SssEntryDialog(needs: needs),
          );
          if (entered == null) {
            _snack('Promotion cancelled.');
            return;
          }
          bece = entered.bece;
          departments = entered.departments;
        }
      }

      final report = await service.run(PromotionRequest(
        promoteIds: promoteIds,
        repeatIds: repeatIds,
        targets: targets,
        academicYear: _year.text.trim(),
        promotedBy: auth.appUser?.uid ?? '',
        bece: bece,
        departments: departments,
      ));
      if (!mounted) return;
      final group = [
        if (_level != null && _rung != null)
          _level!.standardClasses[_rung!].name,
        if (_stream != null) _stream!.isEmpty ? 'No department' : _stream!,
      ];
      setState(() => _selected.clear());
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PromotionReportScreen(
          report: report,
          schoolName: _schoolName,
          filters: group,
        ),
      ));
    } catch (e) {
      _snack('Promotion failed: ${e is StateError ? e.message : e}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
      );

  Widget _chipRow(List<Widget> chips) => SizedBox(
        height: 32,
        child: ListView(scrollDirection: Axis.horizontal, children: chips),
      );

  Widget _chip(String label, int count, bool selected, VoidCallback onTap) =>
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
          onSelected: (_) => onTap(),
        ),
      );
}

/// BECE records and departments entered for JSS 3 → SSS 1.
class _SssEntry {
  const _SssEntry(this.bece, this.departments);

  final Map<String, BeceRecord> bece;
  final Map<String, String> departments;
}

/// Collects what each JSS 3 pupil still needs before SSS 1: a BECE ID and
/// year, and a department (Science, Commercial or Arts).
class _SssEntryDialog extends StatefulWidget {
  const _SssEntryDialog({required this.needs});

  final List<SssEntryNeed> needs;

  @override
  State<_SssEntryDialog> createState() => _SssEntryDialogState();
}

class _SssEntryDialogState extends State<_SssEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _ids;
  late final Map<String, TextEditingController> _years;
  final Map<String, String> _departments = {};

  @override
  void initState() {
    super.initState();
    _ids = {
      for (final n in widget.needs)
        if (n.bece) n.student.id: TextEditingController(text: n.student.beceId),
    };
    _years = {
      for (final n in widget.needs)
        if (n.bece)
          n.student.id: TextEditingController(text: n.student.beceYear),
    };
  }

  @override
  void dispose() {
    for (final c in [..._ids.values, ..._years.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _SssEntry(
        {
          for (final id in _ids.keys)
            id: BeceRecord(_ids[id]!.text.trim(), _years[id]!.text.trim()),
        },
        {..._departments},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Before SSS 1'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                'JSS 3 pupils need a BECE ID and year, and a department, '
                'before moving to SSS 1. ${widget.needs.length} pupil(s) '
                'to fill in.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              for (final n in widget.needs) ...[
                const SizedBox(height: 16),
                Text(n.student.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (n.bece) ...[
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _ids[n.student.id],
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                        labelText: 'BECE ID (8 digits)', counterText: ''),
                    validator: (v) => (v ?? '').trim().length == 8
                        ? null
                        : 'Enter the 8-digit BECE ID',
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _years[n.student.id],
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                        labelText: 'BECE year (4 digits)', counterText: ''),
                    validator: (v) => (v ?? '').trim().length == 4
                        ? null
                        : 'Enter the 4-digit year',
                  ),
                ],
                if (n.department) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _departments[n.student.id],
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: [
                      for (final d in kDepartments)
                        DropdownMenuItem(value: d, child: Text(d)),
                    ],
                    onChanged: (v) => _departments[n.student.id] = v!,
                    validator: (v) => v == null ? 'Choose a department' : null,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save & promote')),
      ],
    );
  }
}
