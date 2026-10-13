import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../models/school_class.dart';
import '../../models/student.dart';
import '../../services/class_service.dart';
import '../../services/file_actions.dart';
import '../../services/student_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/status_views.dart';
import 'report_card_data.dart';
import 'report_card_pdf.dart';

/// Pick a JSS or SS form (built from the school's own classes and pupils),
/// optionally an SS department, check the principal's name, and export one
/// cover page per pupil as a single PDF. Reads the phone's copy of the
/// data, so it works offline.
class ReportCardClassScreen extends StatefulWidget {
  const ReportCardClassScreen({super.key, required this.level});

  final ReportLevel level;

  @override
  State<ReportCardClassScreen> createState() => _ReportCardClassScreenState();
}

class _ReportCardClassScreenState extends State<ReportCardClassScreen> {
  late final Stream<List<SchoolClass>> _classes;
  late final Stream<List<Student>> _students;
  late final Future<ReportCardSchool> _school;
  final _principal = TextEditingController();

  /// True once the user edits the principal's name, so the profile value
  /// arriving later never overwrites their text.
  bool _principalEdited = false;

  DepartmentFilter _department = DepartmentFilter.all;
  ReportForm? _selected;
  bool _busy = false;

  ReportLevel get _level => widget.level;

  @override
  void initState() {
    super.initState();
    // Always the signed-in user's own school.
    final refs = context.read<AuthController>().tenant!;
    _classes = ClassService(refs).watchAll();
    _students = StudentService(refs).watchAll();
    _school = loadReportCardSchool(refs);
    _school.then((s) {
      if (mounted && !_principalEdited && _principal.text.isEmpty) {
        _principal.text = s.principal;
      }
    });
  }

  @override
  void dispose() {
    _principal.dispose();
    super.dispose();
  }

  String _groupName(ReportForm form) =>
      _level == ReportLevel.ss && _department != DepartmentFilter.all
          ? '${form.label} (${_department.label})'
          : form.label;

  String _fileName(ReportForm form) {
    final base = _groupName(form)
        .replaceAll(RegExp(r'[^A-Za-z0-9-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return '${base}_Report_Cards.pdf';
  }

  Future<void> _export(
      ReportForm form, List<Student> pupils, {required bool share}) async {
    final messenger = ScaffoldMessenger.of(context);
    if (pupils.isEmpty) {
      messenger.showSnackBar(SnackBar(
          content: Text('No pupils found in ${_groupName(form)}.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final school = await _school;
      final bytes = await buildReportCardsPdf(
        pupils: [for (final s in pupils) ReportCardPupil.fromStudent(s, form)],
        school: school,
        level: _level,
        principal: _principal.text.trim(),
      );
      final name = _fileName(form);
      if (share) {
        await FileActions.share(name, bytes, mimeType: 'application/pdf');
      } else {
        await Printing.layoutPdf(
          name: name,
          format: PdfPageFormat.a4.landscape,
          onLayout: (_) async => bytes,
        );
      }
    } catch (e) {
      debugPrint('Report card export failed: $e');
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not make the report cards. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_level.title)),
      body: StreamBuilder<List<SchoolClass>>(
        stream: _classes,
        builder: (context, classSnap) => StreamBuilder<List<Student>>(
          stream: _students,
          builder: (context, studentSnap) {
            if (classSnap.hasError || studentSnap.hasError) {
              return const ErrorView(
                  message: 'Could not load the classes. Please try again.');
            }
            if (!classSnap.hasData || !studentSnap.hasData) {
              return const LoadingView(message: 'Loading classes…');
            }
            return _body(classSnap.data!, studentSnap.data!);
          },
        ),
      ),
    );
  }

  Widget _body(List<SchoolClass> classes, List<Student> students) {
    // Every form that has pupils, so the list stays put while the
    // department filter changes the counts.
    final forms = groupPupils(
            classes: classes, students: students, level: _level)
        .keys
        .toList();
    final groups = groupPupils(
      classes: classes,
      students: students,
      level: _level,
      department: _department,
    );
    if (forms.isEmpty) {
      return EmptyView(
        icon: Icons.class_outlined,
        message: 'No ${_level.code} pupils found.\nAdd pupils to '
            '${_level.code} classes (e.g. ${_level.code} 1) first.',
      );
    }
    final selected = forms.contains(_selected) ? _selected : null;
    final pupils = selected == null ? const <Student>[] : groups[selected] ?? [];
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_level == ReportLevel.ss) ...[
                Text('Department', style: text.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final d in DepartmentFilter.values)
                      ChoiceChip(
                        label: Text(d.label),
                        selected: _department == d,
                        onSelected: (_) => setState(() => _department = d),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              Text('Class', style: text.titleSmall),
              const SizedBox(height: 8),
              for (final form in forms)
                _FormTile(
                  form: form,
                  count: groups[form]?.length ?? 0,
                  selected: form == selected,
                  onTap: () => setState(() => _selected = form),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _principal,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => _principalEdited = true,
                decoration: const InputDecoration(
                  labelText: "Principal's name",
                  helperText: 'Printed on these report cards only. '
                      'The school profile is not changed.',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: selected == null || _busy
                        ? null
                        : () => _export(selected, pupils, share: false),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.print_outlined),
                    label: Text(selected == null
                        ? 'Choose a class'
                        : 'Export / Print'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Share PDF',
                  onPressed: selected == null || _busy
                      ? null
                      : () => _export(selected, pupils, share: true),
                  icon: const Icon(Icons.share_outlined),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FormTile extends StatelessWidget {
  const _FormTile({
    required this.form,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final ReportForm form;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.divider,
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? AppColors.primary : AppColors.textMuted,
        ),
        title: Text(form.label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        trailing: Text(
          '$count ${count == 1 ? 'pupil' : 'pupils'}',
          style: TextStyle(
            color: count == 0 ? AppColors.danger : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
