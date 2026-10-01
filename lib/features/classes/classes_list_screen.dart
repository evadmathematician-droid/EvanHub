import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/school_class.dart';
import '../../models/school_level.dart';
import '../../models/user_role.dart';
import '../../services/class_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/status_views.dart';

class ClassesListScreen extends StatefulWidget {
  const ClassesListScreen({super.key});

  @override
  State<ClassesListScreen> createState() => _ClassesListScreenState();
}

class _ClassesListScreenState extends State<ClassesListScreen> {
  /// Null means "All levels".
  SchoolLevel? _filter;

  Future<void> _addStandard(ClassService service) async {
    final level = await showDialog<SchoolLevel>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add standard classes for…'),
        children: [
          for (final l in SchoolLevel.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, l),
              child: Text(
                '${l.label}  (${l.standardClasses.map((c) => c.name).join(', ')})',
              ),
            ),
        ],
      ),
    );
    if (level == null || !mounted) return;
    try {
      final added = await service.addStandardClasses(
        level,
        academicYear: DateTime.now().year.toString(),
      );
      _snack(added == 0
          ? 'Those ${level.label} classes already exist.'
          : 'Added $added ${level.label} classes.');
    } catch (e) {
      _snack('Could not add classes: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    final service = ClassService(auth.tenant!);
    final canEdit = auth.role.canManageStudents;
    // The database rules let only school admins write promotions.
    final canPromote = auth.role == UserRole.schoolAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Classes'),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Add standard classes',
              onPressed: () => _addStandard(service),
              icon: const Icon(Icons.playlist_add),
            ),
          if (canPromote)
            IconButton(
              tooltip: 'Promotion',
              onPressed: () => context.push(Routes.promote),
              icon: const Icon(Icons.trending_up),
            ),
        ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.classNew),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                for (final l in SchoolLevel.values) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(l.label),
                    selected: _filter == l,
                    onSelected: (_) => setState(() => _filter = l),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: StreamListView<SchoolClass>(
              stream: service.watchAll().map(
                    (list) => _filter == null
                        ? list
                        : list.where((c) => c.level == _filter).toList(),
                  ),
              emptyMessage: canEdit
                  ? 'No classes yet. Tap the list-add icon above to create the '
                      'standard classes for a level.'
                  : 'No classes yet.',
              emptyIcon: Icons.class_outlined,
              itemBuilder: (context, c) => Card(
                child: ListTile(
                  title: Text(c.name),
                  subtitle: Text([
                    if (c.level != null) c.level!.label,
                    if (c.stage != null) c.stage!.label,
                    if (c.academicYear.isNotEmpty) c.academicYear,
                  ].join('  •  ')),
                  trailing: canEdit ? const Icon(Icons.chevron_right) : null,
                  onTap: canEdit
                      ? () => context.push(Routes.classEdit(c.id), extra: c)
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
