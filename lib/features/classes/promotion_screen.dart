import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/promotion_path.dart';
import '../../models/school_class.dart';
import '../../models/user_role.dart';
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
  final _year = TextEditingController(text: DateTime.now().year.toString());
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  Future<void> _run(
      SchoolClass from, PromotionPath path, String? toClassId) async {
    final graduate = path.graduates;
    if (!graduate && toClassId == null) return;
    final auth = context.read<AuthController>();
    final service = PromotionService(auth.tenant!);

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      // JSS 3 to SSS 1 (as in the Ninka app): every pupil needs a BECE record
      // before they can move up, so collect any that are missing first.
      var bece = <String, BeceRecord>{};
      if (path.needsBece(from)) {
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
        toClassId: graduate ? null : toClassId,
        academicYear: _year.text.trim(),
        promotedBy: auth.appUser?.uid ?? '',
        bece: bece,
      );
      setState(() => _message = [
            graduate
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
    final auth = context.read<AuthController>();
    if (auth.role != UserRole.schoolAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Promote a class')),
        body: const EmptyView(
          message: 'Only school admins can promote classes.',
          icon: Icons.lock_outline,
        ),
      );
    }
    final service = ClassService(auth.tenant!);

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

          SchoolClass? from;
          for (final c in classes) {
            if (c.id == _fromClassId) from = c;
          }
          final path = from == null ? null : PromotionPath.of(from, classes);
          final targets = path == null || path.graduates
              ? const <SchoolClass>[]
              : classes.where(path.isTarget).toList();
          // Keep the choice only while it is still a valid target; pick the
          // target automatically when there is just one.
          final toClassId = targets.any((c) => c.id == _toClassId)
              ? _toClassId
              : (targets.length == 1 ? targets.first.id : null);
          final canRun =
              path != null && (path.graduates || toClassId != null);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                initialValue: from?.id,
                decoration: const InputDecoration(labelText: 'From class'),
                items: classes
                    .map((c) =>
                        DropdownMenuItem(value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _fromClassId = v;
                  _toClassId = null;
                  _message = null;
                }),
              ),
              const SizedBox(height: 12),
              if (from != null)
                switch (path) {
                  null => _Note(
                      from.level == null
                          ? '${from.name} has no level set. Edit it under '
                              'Classes before promoting.'
                          : '${from.name} is not a standard class name '
                              '(e.g. Pre 1, Class 3, JSS 1), so its next '
                              'class is unknown. Rename it under Classes to '
                              'promote it.',
                      warning: true,
                    ),
                  PromotionPath(graduates: true) => _Note(
                      '${from.name} is the last class this school runs. Its '
                      'active students will be marked as graduated and show '
                      'under Past.'),
                  final p when targets.isEmpty => _Note(
                      'There is no ${p.next.name} class yet. Add it under '
                      'Classes first.',
                      warning: true,
                    ),
                  final p => DropdownButtonFormField<String>(
                      // Re-key per From class so the field never holds a
                      // value that is missing from its items.
                      key: ValueKey('to-${from.id}'),
                      initialValue: toClassId,
                      decoration: InputDecoration(
                        labelText: 'To class (${p.next.name})',
                      ),
                      items: targets
                          .map((c) => DropdownMenuItem(
                              value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _toClassId = v),
                    ),
                },
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
                onPressed: (_busy || !canRun)
                    ? null
                    : () => _run(from!, path, toClassId),
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(path?.graduates == true
                        ? 'Graduate students'
                        : 'Run promotion'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// An info or warning line under the From class.
class _Note extends StatelessWidget {
  const _Note(this.text, {this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? AppColors.warning : AppColors.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(warning ? Icons.warning_amber_rounded : Icons.info_outline,
            color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
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

