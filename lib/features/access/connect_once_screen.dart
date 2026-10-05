import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_controller.dart';
import '../../widgets/sign_out_dialog.dart';

import 'gate_layout.dart';

/// Shown instead of an endless splash when the account is signed in on this
/// phone but nothing has been saved here yet (first launch after install or
/// update) and there is no internet. The app opens by itself as soon as the
/// connection returns; Retry just checks again.
class ConnectOnceScreen extends StatelessWidget {
  const ConnectOnceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    return GateLayout(
      icon: Icons.wifi_off,
      title: 'Connect to the internet once',
      message: 'This phone needs the internet one time to finish setting up '
          '${auth.firebaseUser?.email ?? 'your account'}. After that you '
          'can use the app offline.',
      children: [
        ElevatedButton.icon(
          onPressed: auth.retryConnection,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => confirmSignOut(context),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}
