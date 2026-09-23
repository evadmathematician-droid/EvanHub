import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/student.dart';
import '../../services/student_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/photo_avatar.dart';
import '../../widgets/status_views.dart';

class StudentsListScreen extends StatelessWidget {
  const StudentsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    final service = StudentService(auth.tenant!);
    final canEdit = auth.role.canManageStudents;

    return Scaffold(
      appBar: AppBar(title: const Text('Students')),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.studentNew),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
      body: StreamListView<Student>(
        stream: service.watchAll(),
        emptyMessage: 'No students yet.',
        emptyIcon: Icons.groups_outlined,
        itemBuilder: (context, s) => Card(
          child: ListTile(
            leading: PhotoAvatar(url: s.photoUrl, title: s.fullName),
            title: Text(s.fullName),
            subtitle: Text([
              if (s.admissionNo.isNotEmpty) 'Adm ${s.admissionNo}',
              if (s.gender.isNotEmpty) s.gender,
              s.status,
            ].join('  •  ')),
            trailing: canEdit ? const Icon(Icons.chevron_right) : null,
            onTap: canEdit
                ? () => context.push(Routes.studentEdit(s.id), extra: s)
                : null,
          ),
        ),
      ),
    );
  }
}
