import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/announcement.dart';
import '../../models/school_class.dart';
import '../../services/announcement_service.dart';
import '../../services/class_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/status_views.dart';

class AnnouncementsListScreen extends StatelessWidget {
  const AnnouncementsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    final service = AnnouncementService(auth.tenant!);
    final classService = ClassService(auth.tenant!);
    final canPost = auth.role.canManageStudents;

    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      floatingActionButton: canPost
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.announcementNew),
              icon: const Icon(Icons.add),
              label: const Text('Post'),
            )
          : null,
      body: StreamBuilder<List<SchoolClass>>(
        stream: classService.watchAll(),
        builder: (context, classSnap) {
          final classNames = {
            for (final c in classSnap.data ?? const <SchoolClass>[]) c.id: c.name
          };
          return StreamListView<Announcement>(
            stream: service.watchAll(),
            emptyMessage: 'No announcements yet.',
            emptyIcon: Icons.campaign_outlined,
            itemBuilder: (context, a) {
              final audience = a.isSchoolWide
                  ? 'School-wide'
                  : 'Class: ${classNames[a.audience] ?? a.audience}';
              final when = a.createdAt == null
                  ? ''
                  : DateFormat.yMMMd().add_jm().format(a.createdAt!);
              return Card(
                child: ListTile(
                  title: Text(a.title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(a.body),
                      const SizedBox(height: 6),
                      Text('$audience  •  $when',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: canPost
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => service.delete(a.id),
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
