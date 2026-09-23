import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/school_class.dart';
import '../../models/school_level.dart';
import '../../services/class_service.dart';
import '../../services/promotion_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/status_views.dart';

/// Moves every active student from one class into another (or graduates them)
/// and writes a promotion audit record per student.
class PromotionScreen extends StatefulWidget {
  const PromotionScreen({super.key});

  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen> {
  String? _fromClassId;
  String? _toClassId;
  bool _graduate = false;
  final _year = TextEditingController(text: DateTime.now().year.toString());
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  Future<void> _run(List<SchoolClass> classes) async {
    if (_fromClassId == null) return;
    if (!_graduate && _toClassId == null) return;
    final from = classes.firstWhere((c) => c.id == _fromClassId);
    final auth = context.read<AuthController>();
    final service = PromotionService(auth.tenant!);

    // JSS 3 to SSS 1 (as in the Ninka app): every pupil needs a BECE record
    // before they can move up, so collect any that are missing first.
    final requireBece = !_graduate && isFinalJuniorClassName(from.name);
    // Graduating SSS 3 needs each pupil's WASSCE record.
    final requireWassce = _graduate &&
        from.level == SchoolLevel.secondary &&
        SchoolLevel.secondary.isFinalClassName(from.name);

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      var bece = <String, BeceRecord>{};
      if (requireBece) {
        final missing = await service.activeStudentsMissingBece(from.id);
        if (missing.isNotEmpty) {
          if (!mounted) return;
          final collected = await showDialog<Map<String, BeceRecord>>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _BeceDialog(pupils: missing),
          );
          if (collected == null) {
            setState(() => _message = 'Promotion cancelled.');
            return;
          }
          bece = collected;
        }
      }

      final result = await service.promoteClass(
        fromClassId: from.id,
        toClassId: _graduate ? null : _toClassId,
        academicYear: _year.text.trim(),
        promotedBy: auth.appUser?.uid ?? '',
        requireBece: requireBece,
        requireWassce: requireWassce,
        bece: bece,
      );
      setState(() => _message = [
            _graduate
                ? '${result.moved} student(s) marked as graduated.'
                : 'Promoted ${result.moved} student(s).',
            if (result.skipped.isNotEmpty)
              'Skipped: ${result.skipped.join('; ')}. '
                  'Add their records in the student form, then run again.',
          ].join(' '));
    } catch (e) {
      setState(() => _message = 'Promotion failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ClassService(context.read<AuthController>().tenant!);

    return Scaffold(
      appBar: AppBar(title: const Text('Promote a class')),
      body: StreamBuilder<List<SchoolClass>>(
        stream: service.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorView(message: '${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingView();
          final classes = snapshot.data!;
          if (classes.isEmpty) {
            return const EmptyView(message: 'Create classes first.');
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _fromClassId,
                decoration: const InputDecoration(labelText: 'From class'),
                items: classes
                    .map((c) =>
                        DropdownMenuItem(value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: (v) => setState(() => _fromClassId = v),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Graduate (leave school)'),
                value: _graduate,
                onChanged: (v) => setState(() => _graduate = v),
              ),
              if (!_graduate) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _toClassId,
                  decoration: const InputDecoration(labelText: 'To class'),
                  items: classes
                      .where((c) => c.id != _fromClassId)
                      .map((c) =>
                          DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _toClassId = v),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _year,
                decoration: const InputDecoration(labelText: 'Academic year'),
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(_message!,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _busy ? null : () => _run(classes),
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Run promotion'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Collects a BECE ID + year for each JSS 3 pupil that has none, before the
/// class can be promoted to SSS 1. Pops a map of studentId to record, or null
/// if cancelled.
class _BeceDialog extends StatefulWidget {
  const _BeceDialog({required this.pupils});

  final List<MissingBece> pupils;

  @override
  State<_BeceDialog> createState() => _BeceDialogState();
}

class _BeceDialogState extends State<_BeceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _ids;
  late final Map<String, TextEditingController> _years;

  @override
  void initState() {
    super.initState();
    _ids = {
      for (final p in widget.pupils)
        p.studentId: TextEditingController(text: p.beceId),
    };
    _years = {
      for (final p in widget.pupils)
        p.studentId: TextEditingController(text: p.beceYear),
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
    Navigator.pop(context, {
      for (final p in widget.pupils)
        p.studentId: BeceRecord(
          _ids[p.studentId]!.text.trim(),
          _years[p.studentId]!.text.trim(),
        ),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('BECE record required'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                'JSS 3 pupils need a BECE ID and year before moving to SSS 1. '
                '${widget.pupils.length} pupil(s) still to fill in.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              for (final p in widget.pupils) ...[
                const SizedBox(height: 16),
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _ids[p.studentId],
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
                  controller: _years[p.studentId],
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
            onPressed: _submit, child: const Text('Save & promote')),
      ],
    );
  }
}

