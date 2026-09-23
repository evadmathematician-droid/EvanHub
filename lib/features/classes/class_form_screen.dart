import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/school_class.dart';
import '../../models/school_level.dart';
import '../../services/class_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';

class ClassFormScreen extends StatefulWidget {
  const ClassFormScreen({super.key, this.existing});

  final SchoolClass? existing;

  @override
  State<ClassFormScreen> createState() => _ClassFormScreenState();
}

class _ClassFormScreenState extends State<ClassFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  SchoolLevel? _level;
  SecondaryStage? _stage;
  late final TextEditingController _year;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _level = c?.level;
    _stage = c?.stage;
    _year = TextEditingController(
        text: c?.academicYear ?? DateTime.now().year.toString());
  }

  @override
  void dispose() {
    for (final c in [_name, _year]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = ClassService(context.read<AuthController>().tenant!);
    final schoolClass = SchoolClass(
      id: widget.existing?.id ?? '',
      name: _name.text.trim(),
      level: _level,
      stage: _level == SchoolLevel.secondary ? _stage : null,
      academicYear: _year.text.trim(),
      classTeacherId: widget.existing?.classTeacherId,
      createdAt: widget.existing?.createdAt,
    );
    try {
      if (_isEdit) {
        await service.update(schoolClass);
      } else {
        await service.add(schoolClass);
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
        title: const Text('Delete class?'),
        content: Text(
            '${widget.existing!.name} will be removed. Students keep their '
            'records but become unassigned.'),
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
    final service = ClassService(context.read<AuthController>().tenant!);
    await service.delete(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit class' : 'Add class'),
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
            TextFormField(
              controller: _name,
              decoration:
                  const InputDecoration(labelText: 'Class name * (e.g. Class 1 A)'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SchoolLevel>(
              initialValue: _level,
              decoration: const InputDecoration(labelText: 'Level *'),
              items: [
                for (final l in SchoolLevel.values)
                  DropdownMenuItem(value: l, child: Text(l.label)),
              ],
              onChanged: (v) => setState(() {
                _level = v;
                if (v != SchoolLevel.secondary) _stage = null;
              }),
              validator: (v) => v == null ? 'Choose a level' : null,
            ),
            if (_level == SchoolLevel.secondary) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<SecondaryStage>(
                initialValue: _stage,
                decoration: const InputDecoration(labelText: 'Stage *'),
                items: [
                  for (final s in SecondaryStage.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => _stage = v),
                validator: (v) => v == null ? 'Choose a stage' : null,
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _year,
              decoration: const InputDecoration(labelText: 'Academic year'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _busy ? null : _save,
              child: Text(_isEdit ? 'Save changes' : 'Add class'),
            ),
          ],
        ),
      ),
    );
  }
}
