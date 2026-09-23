import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/school_class.dart';
import '../../models/school_level.dart';
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

/// What promoting a class means, based on the standard class ladder.
enum _Outcome { promote, graduate, notInLadder }

class _Plan {
  const _Plan(this.outcome, {this.level, this.rung = -1});

  final _Outcome outcome;

  /// Target level and ladder position; set only for [_Outcome.promote].
  final SchoolLevel? level;
  final int rung;

  StandardClass get next => level!.standardClasses[rung];

  /// True for classes at the target rung (including sections like "JSS 2 B").
  bool isTarget(SchoolClass c) =>
      c.level == level && level!.rungOf(c.name) == rung;

  /// Pupils in [from] go to the next class in its level's ladder. Pre-primary
  /// has no leaving exam, so Pre 2 moves up to Primary Class 1; the final
  /// Primary and Secondary classes (Class 6, SSS 3) graduate.
  static _Plan of(SchoolClass from) {
    final level = from.level;
    final rung = level?.rungOf(from.name) ?? -1;
    if (level == null || rung < 0) return const _Plan(_Outcome.notInLadder);
    if (rung < level.standardClasses.length - 1) {
      return _Plan(_Outcome.promote, level: level, rung: rung + 1);
    }
    if (level == SchoolLevel.prePrimary) {
      return const _Plan(_Outcome.promote,
          level: SchoolLevel.primary, rung: 0);
    }
    return const _Plan(_Outcome.graduate);
  }
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

  Future<void> _run(SchoolClass from, _Plan plan, String? toClassId) async {
    final graduate = plan.outcome == _Outcome.graduate;
    if (!graduate && toClassId == null) return;
    final auth = context.read<AuthController>();
    final service = PromotionService(auth.tenant!);

    // JSS 3 to SSS 1 (as in the Ninka app): every pupil needs a BECE record
    // before they can move up, so collect any that are missing first.
    final requireBece = !graduate &&
        from.level == SchoolLevel.secondary &&
        plan.next.stage == SecondaryStage.senior &&
        from.level!.standardClasses[plan.rung - 1].stage ==
            SecondaryStage.junior;
    // Graduating SSS 3 needs each pupil's WASSCE record.
    final requireWassce = graduate && from.level == SchoolLevel.secondary;

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
        toClassId: graduate ? null : toClassId,
        academicYear: _year.text.trim(),
        promotedBy: auth.appUser?.uid ?? '',
        requireBece: requireBece,
        requireWassce: requireWassce,
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
          final plan = from == null ? null : _Plan.of(from);
          final targets = plan?.outcome == _Outcome.promote
              ? classes.where(plan!.isTarget).toList()
              : const <SchoolClass>[];
          // Keep the choice only while it is still a valid target; pick the
          // target automatically when there is just one.
          final toClassId = targets.any((c) => c.id == _toClassId)
              ? _toClassId
              : (targets.length == 1 ? targets.first.id : null);
          final canRun = from != null &&
              (plan!.outcome == _Outcome.graduate || toClassId != null);

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
                switch (plan!.outcome) {
                  _Outcome.notInLadder => _Note(
                      from.level == null
                          ? '${from.name} has no level set. Edit it under '
                              'Classes before promoting.'
                          : '${from.name} is not a standard class name '
                              '(e.g. JSS 1, Class 3), so its next class is '
                              'unknown. Rename it under Classes to promote it.',
                      warning: true,
                    ),
                  _Outcome.graduate => _Note(
                      '${from.name} is the final class. Its active students '
                      'will be marked as graduated.'),
                  _Outcome.promote when targets.isEmpty => _Note(
                      'There is no ${plan.next.name} class yet. Add it under '
                      'Classes first.',
                      warning: true,
                    ),
                  _Outcome.promote => DropdownButtonFormField<String>(
                      // Re-key per From class so the field never holds a
                      // value that is missing from its items.
                      key: ValueKey('to-${from.id}'),
                      initialValue: toClassId,
                      decoration: InputDecoration(
                        labelText: 'To class (${plan.next.name})',
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
                    : () => _run(from!, plan, toClassId),
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(plan?.outcome == _Outcome.graduate
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

