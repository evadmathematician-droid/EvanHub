import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/user_role.dart';
import '../../state/auth_controller.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    final items = <_MoreItem>[
      _MoreItem('Classes', Icons.class_outlined, Routes.classes),
      // The database rules let only school admins write promotions.
      if (auth.role == UserRole.schoolAdmin)
        _MoreItem('Promotion', Icons.trending_up, Routes.promote),
      _MoreItem('Documents', Icons.folder_outlined, Routes.documents),
      _MoreItem('Announcements', Icons.campaign_outlined, Routes.announcements),
      _MoreItem('Settings', Icons.settings_outlined, Routes.settings),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '${auth.appUser?.displayName ?? auth.appUser?.email ?? ''}'
              '  •  ${auth.role.label}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final item in items)
            ListTile(
              leading: Icon(item.icon),
              title: Text(item.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(item.route),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => context.read<AuthController>().signOut(),
          ),
        ],
      ),
    );
  }
}

class _MoreItem {
  final String label;
  final IconData icon;
  final String route;
  const _MoreItem(this.label, this.icon, this.route);
}
