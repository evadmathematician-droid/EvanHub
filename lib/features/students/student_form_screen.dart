import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/school_class.dart';
import '../../models/school_level.dart';
import '../../models/student.dart';
import '../../services/class_service.dart';
import '../../services/cloudinary_service.dart';
import '../../services/student_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';

/// Exams recorded on a student. Which ones show depends on the class and
/// status (see `_exams`): NPSE, BECE (SSS only) and WASSCE (graduated SSS).
enum _Exam {
  npse('NPSE'),
  bece('BECE'),
  wassce('WASSCE');

  const _Exam(this.label);
  final String label;
}

class StudentFormScreen extends StatefulWidget {
  const StudentFormScreen({super.key, this.existing});

  final Student? existing;

  @override
  State<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends State<StudentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _admissionNo;
  late final TextEditingController _firstName;
  late final TextEditingController _middleName;
  late final TextEditingController _lastName;
  late final TextEditingController _dobText;
  late final TextEditingController _admissionYear;
  late final TextEditingController _address;
  late final TextEditingController _guardianName;
  late final TextEditingController _guardianPhone;
  late final Map<_Exam, TextEditingController> _examId;
  late final Map<_Exam, TextEditingController> _examYear;

  String _gender = '';
  DateTime? _dob;
  SchoolLevel? _level;
  SecondaryStage? _stage;
  String? _classId;
  String? _department;
  String _status = StudentStatus.active;
  String _photoUrl = '';

  List<SchoolClass> _classes = const [];
  StreamSubscription<List<SchoolClass>>? _classSub;

  bool _busy = false;
  bool _photoBusy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  SchoolClass? get _selectedClass {
    for (final c in _classes) {
      if (c.id == _classId) return c;
    }
    return null;
  }

  /// Exam records that apply to the selected class and status, mirroring the
  /// Ninka school app:
  ///  - NPSE: active secondary pupils (the exam they entered on); for primary
  ///    it is the leaving exam, so only once graduated.
  ///  - BECE: senior secondary (SSS) pupils only — JSS never has one.
  ///  - WASSCE: graduated SSS pupils only.
  List<_Exam> get _exams {
    final c = _selectedClass;
    if (c == null) return const [];
    final graduated = _status == StudentStatus.graduated;
    final active = _status == StudentStatus.active;
    switch (c.level) {
      case SchoolLevel.primary:
        return graduated ? const [_Exam.npse] : const [];
      case SchoolLevel.secondary:
        final senior = c.stage == SecondaryStage.senior;
        return [
          if (active) _Exam.npse,
          if (senior) _Exam.bece,
          if (senior && graduated) _Exam.wassce,
        ];
      default:
        return const [];
    }
  }

  bool _keepExam(_Exam e) {
    final c = _selectedClass;
    if (c == null) return false;
    final senior = c.level == SchoolLevel.secondary &&
        c.stage == SecondaryStage.senior;
    return switch (e) {
      _Exam.npse => c.level != SchoolLevel.prePrimary,
      _Exam.bece || _Exam.wassce => senior,
    };
  }

  bool get _needsDepartment =>
      _selectedClass?.level == SchoolLevel.secondary &&
      _selectedClass?.stage == SecondaryStage.senior;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _admissionNo = TextEditingController(text: s?.admissionNo ?? '');
    _firstName = TextEditingController(text: s?.firstName ?? '');
    _middleName = TextEditingController(text: s?.middleName ?? '');
    _lastName = TextEditingController(text: s?.lastName ?? '');
    _dob = s?.dob;
    _dobText = TextEditingController(text: _formatDate(s?.dob));
    _admissionYear = TextEditingController(
        text: s?.admissionYear ?? DateTime.now().year.toString());
    _address = TextEditingController(text: s?.address ?? '');
    _guardianName = TextEditingController(text: s?.guardianName ?? '');
    _guardianPhone = TextEditingController(text: s?.guardianPhone ?? '');
    _examId = {
      _Exam.npse: TextEditingController(text: s?.npseId ?? ''),
      _Exam.bece: TextEditingController(text: s?.beceId ?? ''),
      _Exam.wassce: TextEditingController(text: s?.wassceId ?? ''),
    };
    _examYear = {
      _Exam.npse: TextEditingController(text: s?.npseYear ?? ''),
      _Exam.bece: TextEditingController(text: s?.beceYear ?? ''),
      _Exam.wassce: TextEditingController(text: s?.wassceYear ?? ''),
    };
    _gender = s?.gender ?? '';
    _level = s?.level;
    _classId = s?.classId;
    _department = s?.department;
    _status = s?.status ?? StudentStatus.active;
    _photoUrl = s?.photoUrl ?? '';

    final tenant = context.read<AuthController>().tenant!;
    _classSub = ClassService(tenant).watchAll().listen((list) {
      if (mounted) setState(() => _classes = list);
    });
  }

  @override
  void dispose() {
    _classSub?.cancel();
    for (final c in [
      _admissionNo,
      _firstName,
      _middleName,
      _lastName,
      _dobText,
      _admissionYear,
      _address,
      _guardianName,
      _guardianPhone,
      ..._examId.values,
      ..._examYear.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Creates the standard class ladder for [level] when the school has no
  /// classes at that level yet, so the Class dropdown is never empty.
  Future<void> _ensureStandardClasses(SchoolLevel? level) async {
    if (level == null || _classes.any((c) => c.level == level)) return;
    try {
      await ClassService(context.read<AuthController>().tenant!)
          .addStandardClasses(level,
              academicYear: DateTime.now().year.toString());
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not create classes: $e');
    }
  }

  String _formatDate(DateTime? d) =>
      d == null ? '' : DateFormat('d MMM yyyy').format(d);

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 8),
      firstDate: DateTime(now.year - 40),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _dob = picked;
      _dobText.text = _formatDate(picked);
    });
  }

  Future<void> _pickPhoto() async {
    final tenant = context.read<AuthController>().tenant!;
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result.isEmpty) return;
    final file = result.single;
    if (!mounted) return;

    setState(() => _photoBusy = true);
    try {
      final bytes = await file.readAsBytes();
      final upload = await CloudinaryService().upload(
        bytes: bytes,
        fileName: file.name,
        folder: tenant.studentPhotoFolder,
      );
      if (mounted) setState(() => _photoUrl = upload.url);
    } catch (e) {
      if (mounted) setState(() => _error = 'Photo upload failed: $e');
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final schoolClass = _selectedClass;
    final level = _level;
    if (schoolClass == null || level == null) {
      setState(() => _error = 'Choose a level and a class.');
      return;
    }

    // A leaving pupil in the final class needs their exam record on file.
    final exam = _exams.isEmpty ? null : _exams.last;
    if (exam != null &&
        _status == StudentStatus.graduated &&
        level.isFinalClassName(schoolClass.name) &&
        (_examId[exam]!.text.trim().isEmpty ||
            _examYear[exam]!.text.trim().isEmpty)) {
      setState(() => _error =
          '${exam.label} ID and year are required before marking a '
          '${schoolClass.name} student as graduated.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final service = StudentService(context.read<AuthController>().tenant!);
    try {
      final taken = await service.admissionNoTaken(
        _admissionNo.text,
        excludeId: widget.existing?.id,
      );
      if (taken) {
        setState(() => _error =
            'Admission number ${_admissionNo.text.trim()} is already in use.');
        return;
      }

      String id(_Exam e) => _examId[e]!.text.trim();
      String year(_Exam e) => _examYear[e]!.text.trim();
      final student = Student(
        id: widget.existing?.id ?? '',
        admissionNo: _admissionNo.text.trim(),
        firstName: _firstName.text.trim(),
        middleName: _middleName.text.trim(),
        lastName: _lastName.text.trim(),
        gender: _gender,
        dob: _dob,
        level: level,
        classId: schoolClass.id,
        department: _needsDepartment ? _department : null,
        admissionYear: _admissionYear.text.trim(),
        address: _address.text.trim(),
        guardianName: _guardianName.text.trim(),
        guardianPhone: _guardianPhone.text.trim(),
        // Only exams that can apply to the class are kept; others are cleared.
        npseId: _keepExam(_Exam.npse) ? id(_Exam.npse) : '',
        npseYear: _keepExam(_Exam.npse) ? year(_Exam.npse) : '',
        beceId: _keepExam(_Exam.bece) ? id(_Exam.bece) : '',
        beceYear: _keepExam(_Exam.bece) ? year(_Exam.bece) : '',
        wassceId: _keepExam(_Exam.wassce) ? id(_Exam.wassce) : '',
        wassceYear: _keepExam(_Exam.wassce) ? year(_Exam.wassce) : '',
        photoUrl: _photoUrl,
        status: _status,
        createdAt: widget.existing?.createdAt,
      );
      if (_isEdit) {
        await service.update(student);
      } else {
        await service.add(student);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete student?'),
        content: Text('${widget.existing!.fullName} will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final service = StudentService(context.read<AuthController>().tenant!);
    await service.delete(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final isSecondary = _level == SchoolLevel.secondary;
    final stage = _stage ?? (isSecondary ? _selectedClass?.stage : null);
    final levelClasses = _classes
        .where((c) =>
            c.level == _level && (!isSecondary || stage == null || c.stage == stage))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit student' : 'Register student'),
        actions: [
          if (_isEdit)
            IconButton(
              onPressed: _busy ? null : _confirmDelete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: GestureDetector(
                onTap: _photoBusy ? null : _pickPhoto,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundImage:
                          _photoUrl.isEmpty ? null : NetworkImage(_photoUrl),
                      child: _photoBusy
                          ? const CircularProgressIndicator()
                          : (_photoUrl.isEmpty
                              ? const Icon(Icons.person, size: 40)
                              : null),
                    ),
                    const CircleAvatar(
                      radius: 14,
                      child: Icon(Icons.camera_alt, size: 16),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _admissionNo,
              decoration: const InputDecoration(labelText: 'Admission no. *'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _firstName,
              decoration: const InputDecoration(labelText: 'First name *'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _middleName,
              decoration:
                  const InputDecoration(labelText: 'Middle name (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastName,
              decoration: const InputDecoration(labelText: 'Last name *'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _gender.isEmpty ? null : _gender,
              decoration: const InputDecoration(labelText: 'Gender'),
              items: const [
                DropdownMenuItem(value: 'Female', child: Text('Female')),
                DropdownMenuItem(value: 'Male', child: Text('Male')),
              ],
              onChanged: (v) => setState(() => _gender = v ?? ''),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dobText,
              readOnly: true,
              onTap: _pickDob,
              decoration: const InputDecoration(
                labelText: 'Date of birth',
                suffixIcon: Icon(Icons.calendar_today),
              ),
            ),
            const SizedBox(height: 20),
            Text('School placement',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<SchoolLevel>(
              initialValue: _level,
              decoration: const InputDecoration(labelText: 'Level *'),
              items: [
                for (final l in SchoolLevel.values)
                  DropdownMenuItem(value: l, child: Text(l.label)),
              ],
              onChanged: (v) => setState(() {
                _level = v;
                _stage = null;
                _classId = null;
                _department = null;
                _ensureStandardClasses(v);
              }),
              validator: (v) => v == null ? 'Choose a level' : null,
            ),
            if (isSecondary) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<SecondaryStage>(
                key: ValueKey('stage-${stage?.wire}'),
                initialValue: stage,
                decoration: const InputDecoration(labelText: 'Section (JSS / SSS) *'),
                items: const [
                  DropdownMenuItem(
                      value: SecondaryStage.junior,
                      child: Text('JSS (Junior secondary)')),
                  DropdownMenuItem(
                      value: SecondaryStage.senior,
                      child: Text('SSS (Senior secondary)')),
                ],
                onChanged: (v) => setState(() {
                  _stage = v;
                  _classId = null;
                  _department = null;
                }),
                validator: (v) => v == null ? 'Choose JSS or SSS' : null,
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // Re-key so the field resets when the level/stage (and item list) changes.
              key: ValueKey('class-${_level?.wire}-${stage?.wire}'),
              initialValue: levelClasses.any((c) => c.id == _classId)
                  ? _classId
                  : null,
              decoration: InputDecoration(
                labelText: 'Class *',
                helperText: _level != null && levelClasses.isEmpty
                    ? 'No ${_level!.label} classes yet — add them under '
                        'More → Classes.'
                    : null,
              ),
              items: [
                for (final c in levelClasses)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() {
                _classId = v;
                _department = null;
              }),
              validator: (v) => v == null ? 'Choose a class' : null,
            ),
            if (_needsDepartment) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _department,
                decoration: const InputDecoration(labelText: 'Department *'),
                items: [
                  for (final d in kDepartments)
                    DropdownMenuItem(value: d, child: Text(d)),
                ],
                onChanged: (v) => setState(() => _department = v),
                validator: (v) => v == null ? 'Choose a department' : null,
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _admissionYear,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Admission year'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                for (final s in StudentStatus.all)
                  DropdownMenuItem(
                      value: s, child: Text(StudentStatus.label(s))),
              ],
              onChanged: (v) =>
                  setState(() => _status = v ?? StudentStatus.active),
            ),
            for (final exam in _exams) ...[
              const SizedBox(height: 20),
              Text('${exam.label} record',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              TextFormField(
                controller: _examId[exam],
                decoration: InputDecoration(labelText: '${exam.label} ID'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _examYear[exam],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: '${exam.label} year'),
              ),
            ],
            const SizedBox(height: 20),
            Text('Guardian', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _guardianName,
              decoration: const InputDecoration(labelText: 'Guardian name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _guardianPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Guardian phone'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: (_busy || _photoBusy) ? null : _save,
              child: Text(_isEdit ? 'Save changes' : 'Register student'),
            ),
          ],
        ),
      ),
    );
  }
}
