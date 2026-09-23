import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_controller.dart';
import 'gate_layout.dart';

/// Shown when the account's school no longer lists it as a member (the admin
/// removed it), instead of a screen full of permission errors.
class NoAccessScreen extends StatelessWidget {
  const NoAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    return GateLayout(
      icon: Icons.lock_outline,
      title: 'You no longer have access to this school',
      message: 'This account (${auth.appUser?.email ?? ''}) is not a member of '
          'the school any more. If you think this is a mistake, ask your '
          'school administrator to add you again.',
      children: [
        ElevatedButton.icon(
          onPressed: auth.signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}
