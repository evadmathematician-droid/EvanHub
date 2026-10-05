import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_controller.dart';
import '../../widgets/sign_out_dialog.dart';

import 'gate_layout.dart';

/// Parent / student accounts have no screens yet. They land here instead of
/// the staff app, whose data they are not allowed to read.
class ParentPortalScreen extends StatelessWidget {
  const ParentPortalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    return GateLayout(
      icon: Icons.family_restroom,
      title: 'Parent portal coming soon',
      message: 'You are signed in as ${auth.appUser?.email ?? ''}. The parent '
          'and student area of EvanHub is being built. Your school '
          'will let you know when it is ready.',
      children: [
        OutlinedButton.icon(
          onPressed: () => confirmSignOut(context),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}
