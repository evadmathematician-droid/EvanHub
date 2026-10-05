import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/internet_check.dart';
import '../../core/person_name.dart';
import '../../models/school_level.dart';
import '../../models/teacher.dart';
import '../../services/cloudinary_service.dart';
import '../../services/upload_queue.dart';
import '../../services/teacher_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/delete_helpers.dart';
import '../../widgets/photo_avatar.dart';

/// Teacher registration — mirrors the Ninka school app's teacher form (NIN,
/// photo, gender, marital status, DOB, pincode, qualification, experience,
/// subjects, level and stream) and adds document upload.
class TeacherFormScreen extends StatefulWidget {
  const TeacherFormScreen({super.key, this.existing});

  final Teacher? existing;

  @override
  State<TeacherFormScreen> createState() => _TeacherFormScreenState();
}

class _TeacherFormScreenState extends State<TeacherFormScreen> {
  /// 8 upper-case letters/digits, no I or O (same rule as the Ninka app).
  static final _ninPattern = RegExp(r'^[A-HJ-NP-Z0-9]{8}$');

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nin;
  late final TextEditingController _firstName;
  late final TextEditingController _middleName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _pincode;
  late final TextEditingController _qualification;
  late final TextEditingController _experience;
  late final TextEditingController _subjects;
  late final TextEditingController _dobText;

  String _gender = '';
  String _maritalStatus = '';
  DateTime? _dob;
  bool _isPincoded = false;
  String _level = '';
  String _stream = '';
  String _employmentType = 'full_time';
  String _photoUrl = '';

  /// A photo picked with no internet: shown here, queued on Save, and
  /// uploaded when the connection is back.
  Uint8List? _pickedPhoto;
  String _pickedPhotoName = '';

  /// A new photo was uploaded here, so an older one still queued for this
  /// record must not be shown or uploaded.
  bool _photoReplaced = false;
  List<TeacherDocument> _documents = [];

  bool _busy = false;
  bool _photoBusy = false;
  bool _docBusy = false;
  String? _error;

  /// The existing teacher with the private half (NIN, contacts, documents)
  /// loaded; null while loading. Saving and deleting wait for it so private
  /// data is never wiped and the old NIN index entry can be released.
  Teacher? _loaded;

  bool get _isEdit => widget.existing != null;
  bool get _privateLoaded => !_isEdit || _loaded != null;
  bool get _teachesSenior => _level == 'SSS' || _level == 'BOTH';

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _nin = TextEditingController(text: t?.nin ?? '');
    _firstName = TextEditingController(text: t?.firstName ?? '');
    _middleName = TextEditingController(text: t?.middleName ?? '');
    _lastName = TextEditingController(text: t?.lastName ?? '');
    _email = TextEditingController(text: t?.email ?? '');
    _phone = TextEditingController(text: t?.phone ?? '');
    _address = TextEditingController(text: t?.address ?? '');
    _pincode = TextEditingController(text: t?.pincode ?? '');
    _qualification = TextEditingController(text: t?.qualification ?? '');
    _experience = TextEditingController(text: t?.experience ?? '');
    _subjects = TextEditingController(text: t?.subjects.join(', ') ?? '');
    _dob = t?.dob;
    _dobText = TextEditingController(text: _formatDate(t?.dob));
    _gender = t?.gender ?? '';
    _maritalStatus = t?.maritalStatus ?? '';
    _isPincoded = t?.isPincoded ?? false;
    _level = t?.level ?? '';
    _stream = t?.stream ?? '';
    _employmentType = t?.employmentType ?? 'full_time';
    _photoUrl = t?.photoUrl ?? '';
    _documents = [...?t?.documents];
    if (t != null) _loadPrivate(t);
  }

  Future<void> _loadPrivate(Teacher t) async {
    try {
      final full = await TeacherService(context.read<AuthController>().tenant!)
          .loadPrivate(t);
      if (!mounted) return;
      setState(() {
        _loaded = full;
        _nin.text = full.nin;
        _email.text = full.email;
        _phone.text = full.phone;
        _address.text = full.address;
        _pincode.text = full.pincode;
        _qualification.text = full.qualification;
        _experience.text = full.experience;
        _dob = full.dob;
        _dobText.text = _formatDate(full.dob);
        _maritalStatus = full.maritalStatus;
        _isPincoded = full.isPincoded;
        _documents = [...full.documents];
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Could not load this teacher\'s private details, so saving is '
            'disabled. Go back and open the teacher again.');
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nin,
      _firstName,
      _middleName,
      _lastName,
      _email,
      _phone,
      _address,
      _pincode,
      _qualification,
      _experience,
      _subjects,
      _dobText,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _formatDate(DateTime? d) =>
      d == null ? '' : DateFormat('d MMM yyyy').format(d);

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 30),
      firstDate: DateTime(now.year - 80),
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
    Uint8List? bytes;
    try {
      bytes = await file.readAsBytes();
      // Offline (phones): keep the photo and queue it on Save.
      if (UploadQueue.instance != null && !await hasInternet()) {
        _keepPickedPhoto(bytes, file.name);
        return;
      }
      final upload = await CloudinaryService().upload(
        bytes: bytes,
        fileName: file.name,
        folder: tenant.teacherPhotoFolder,
      );
      if (mounted) {
        setState(() {
          _photoUrl = upload.url;
          _pickedPhoto = null;
          _photoReplaced = true;
        });
      }
    } catch (e) {
      if (bytes != null && UploadQueue.instance != null && isNetworkError(e)) {
        _keepPickedPhoto(bytes, file.name);
      } else if (mounted) {
        setState(() => _error = 'Photo upload failed: $e');
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  void _keepPickedPhoto(Uint8List bytes, String name) {
    if (!mounted) return;
    setState(() {
      _pickedPhoto = bytes;
      _pickedPhotoName = name;
    });
  }

  /// The photo shown at the top of the form.
  ImageProvider? get _photo => formPhotoImage(
        context,
        picked: _pickedPhoto,
        recordId: _photoReplaced ? null : widget.existing?.id,
        url: _photoUrl,
        radius: 44,
      );

  Future<void> _addDocument() async {
    final tenant = context.read<AuthController>().tenant!;
    final result = await FilePicker.pickFiles();
    if (result.isEmpty) return;
    final file = result.single;
    if (!mounted) return;

    final title = await _askTitle(file.name);
    if (!mounted || title == null || title.isEmpty) return;

    setState(() => _docBusy = true);
    try {
      final bytes = await file.readAsBytes();
      final upload = await CloudinaryService().upload(
        bytes: bytes,
        fileName: file.name,
        folder: tenant.teacherDocumentFolder,
      );
      if (mounted) {
        setState(() => _documents = [
              ..._documents,
              TeacherDocument(
                title: title,
                url: upload.url,
                fileName: file.name,
                sizeBytes: upload.bytes,
              ),
            ]);
      }
    } catch (e) {
      if (mounted) setState(() => _error = uploadFailedMessage(e));
    } finally {
      if (mounted) setState(() => _docBusy = false);
    }
  }

  Future<String?> _askTitle(String suggested) {
    final controller = TextEditingController(text: suggested);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Document title'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
              labelText: 'Title', hintText: 'e.g. B.Ed certificate'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _save() async {
    if (!_privateLoaded) return;
    if (!_formKey.currentState!.validate()) return;
    if (_level.isEmpty) {
      setState(() => _error = 'Choose the level this teacher teaches.');
      return;
    }
    if (_teachesSenior && _stream.isEmpty) {
      setState(() => _error = 'Choose a stream for SSS teachers.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = TeacherService(context.read<AuthController>().tenant!);
    try {
      final nin = _nin.text.trim();
      if (await service.ninTaken(nin, excludeId: widget.existing?.id)) {
        setState(() => _error = 'NIN $nin already exists.');
        return;
      }

      final base =
          _loaded ?? const Teacher(id: '', firstName: '', lastName: '');
      final teacher = base.copyWith(
        nin: nin,
        firstName: titleCaseName(_firstName.text),
        middleName: titleCaseName(_middleName.text),
        lastName: titleCaseName(_lastName.text),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        gender: _gender,
        maritalStatus: _maritalStatus,
        dob: _dob,
        address: _address.text.trim(),
        isPincoded: _isPincoded,
        pincode: _isPincoded ? _pincode.text.trim() : '',
        qualification: _qualification.text.trim(),
        experience: _experience.text.trim(),
        level: _level,
        // Stream only applies to senior secondary teaching.
        stream: _teachesSenior ? _stream : '',
        employmentType: _employmentType,
        photoUrl: _photoUrl,
        documents: _documents,
        subjects: _subjects.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
      );
      final id = await service.save(teacher, previousNin: _loaded?.nin);
      final picked = _pickedPhoto;
      if (picked != null) {
        await UploadQueue.instance?.addPhoto(
          schoolId: service.schoolId,
          collection: 'teachers',
          recordId: id,
          bytes: picked,
          fileName: _pickedPhotoName,
        );
      } else if (_photoReplaced) {
        await UploadQueue.instance?.cancel('teachers', id);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = saveErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    // The loaded copy carries the NIN, whose index entry is removed too.
    final teacher = _loaded;
    if (teacher == null) return;
    final ok = await confirmDelete(
      context,
      title: 'Delete teacher?',
      message: '${teacher.fullName} will be removed.',
    );
    if (!ok || !mounted) return;
    final service = TeacherService(context.read<AuthController>().tenant!);
    final deleted = await runDelete(
      context,
      () => service.delete(teacher),
      done: '${teacher.fullName} deleted.',
    );
    if (deleted && mounted) Navigator.of(context).pop();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  Widget _choice(String label, List<String> options, String value,
      void Function(String) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final o in options)
              ChoiceChip(
                label: Text(o),
                selected: value == o,
                onSelected: (_) => onChanged(o),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit teacher' : 'Teacher registration'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete teacher',
              onPressed: (_busy || !_privateLoaded) ? null : _confirmDelete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
        bottom: _privateLoaded
            ? null
            : const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              ),
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
                      backgroundImage: _photo,
                      child: _photoBusy
                          ? const CircularProgressIndicator()
                          : (_photo == null
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
              controller: _nin,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                TextInputFormatter.withFunction((old, value) => value.copyWith(
                      text: value.text.toUpperCase(),
                    )),
              ],
              decoration: const InputDecoration(
                labelText: 'NIN *',
                helperText: '8 letters/digits (no I or O)',
                counterText: '',
              ),
              validator: (v) => _ninPattern.hasMatch((v ?? '').trim())
                  ? null
                  : 'Invalid NIN format',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _firstName,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              inputFormatters: nameInputFormatters,
              decoration: const InputDecoration(
                  labelText: 'First name *', counterText: ''),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _middleName,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              inputFormatters: nameInputFormatters,
              decoration: const InputDecoration(
                labelText: 'Middle name (optional)',
                helperText: 'Up to two words, e.g. Abu Bakarr',
                counterText: '',
              ),
              validator: middleNameProblem,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastName,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              inputFormatters: nameInputFormatters,
              decoration: const InputDecoration(
                  labelText: 'Last name *', counterText: ''),
              validator: _required,
            ),
            const SizedBox(height: 16),
            _choice('Gender', const ['Male', 'Female'], _gender,
                (v) => setState(() => _gender = v)),
            const SizedBox(height: 16),
            _choice('Marital status', const ['Single', 'Married'],
                _maritalStatus, (v) => setState(() => _maritalStatus = v)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _dobText,
              readOnly: true,
              onTap: _pickDob,
              decoration: const InputDecoration(
                labelText: 'Date of birth',
                suffixIcon: Icon(Icons.calendar_today),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              maxLength: 120,
              decoration:
                  const InputDecoration(labelText: 'Email', counterText: ''),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              maxLength: 40,
              decoration:
                  const InputDecoration(labelText: 'Phone', counterText: ''),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              maxLength: 300,
              decoration:
                  const InputDecoration(labelText: 'Address', counterText: ''),
            ),
            const SizedBox(height: 16),
            _choice('Pincode teacher?', const ['Yes', 'No'],
                _isPincoded ? 'Yes' : 'No', (v) {
              setState(() {
                _isPincoded = v == 'Yes';
                if (!_isPincoded) _pincode.clear();
              });
            }),
            if (_isPincoded) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _pincode,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: '6-digit pincode *', counterText: ''),
                validator: (v) => (v ?? '').trim().length == 6
                    ? null
                    : 'Enter a 6-digit pincode',
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _qualification,
              maxLength: 200,
              decoration: const InputDecoration(
                  labelText: 'Qualification', counterText: ''),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _experience,
              maxLength: 200,
              decoration: const InputDecoration(
                  labelText: 'Teaching experience', counterText: ''),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _subjects,
              decoration: const InputDecoration(
                labelText: 'Subjects taught (comma separated)',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _employmentType,
              decoration: const InputDecoration(labelText: 'Employment type'),
              items: const [
                DropdownMenuItem(value: 'full_time', child: Text('Full time')),
                DropdownMenuItem(value: 'part_time', child: Text('Part time')),
                DropdownMenuItem(value: 'contract', child: Text('Contract')),
              ],
              onChanged: (v) =>
                  setState(() => _employmentType = v ?? 'full_time'),
            ),
            const SizedBox(height: 16),
            _choice('Level *', const ['JSS', 'SSS', 'BOTH'], _level, (v) {
              setState(() {
                _level = v;
                if (v == 'JSS') _stream = '';
              });
            }),
            if (_teachesSenior) ...[
              const SizedBox(height: 16),
              _choice('Stream *', kDepartments, _stream,
                  (v) => setState(() => _stream = v)),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text('Documents',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                TextButton.icon(
                  onPressed: _docBusy ? null : _addDocument,
                  icon: _docBusy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_file),
                  label: Text(_docBusy ? 'Uploading…' : 'Upload'),
                ),
              ],
            ),
            if (_documents.isEmpty)
              const Text('No documents attached (certificates, CV, ID …).',
                  style: TextStyle(color: AppColors.textSecondary)),
            for (var i = 0; i < _documents.length; i++)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(_documents[i].title),
                  subtitle: Text(_size(_documents[i].sizeBytes)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _documents = [
                          for (var j = 0; j < _documents.length; j++)
                            if (j != i) _documents[j],
                        ]),
                  ),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: (_busy || _photoBusy || _docBusy || !_privateLoaded)
                  ? null
                  : _save,
              child: Text(_isEdit ? 'Save changes' : 'Save teacher'),
            ),
          ],
        ),
      ),
    );
  }
}
