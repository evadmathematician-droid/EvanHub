import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/teacher.dart';
import '../../services/teacher_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/photo_avatar.dart';
import '../../widgets/status_views.dart';

class TeachersListScreen extends StatelessWidget {
  const TeachersListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    final service = TeacherService(auth.tenant!);
    final canEdit = auth.role.canManageSchool;

    return Scaffold(
      appBar: AppBar(title: const Text('Teachers')),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.teacherNew),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
      body: StreamListView<Teacher>(
        stream: service.watchAll(),
        emptyMessage: 'No teachers yet.',
        emptyIcon: Icons.person_outline,
        itemBuilder: (context, t) => Card(
          child: ListTile(
            leading: PhotoAvatar(url: t.photoUrl, title: t.fullName),
            title: Text(t.fullName),
            subtitle: Text([
              if (t.subjects.isNotEmpty) t.subjects.join(', '),
              if (t.level.isNotEmpty) t.level,
              if (t.stream.isNotEmpty) t.stream,
              t.employmentType.replaceAll('_', ' '),
              t.status,
            ].join('  •  ')),
            trailing: canEdit ? const Icon(Icons.chevron_right) : null,
            onTap: canEdit
                ? () => context.push(Routes.teacherEdit(t.id), extra: t)
                : null,
          ),
        ),
      ),
    );
  }
}
