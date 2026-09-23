import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Full-screen message used by the access gates (no access, parent portal,
/// upgrade): an icon, a title, a short explanation and action buttons.
class GateLayout extends StatelessWidget {
  const GateLayout({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.children = const [],
  });

  final IconData icon;
  final String title;
  final String message;

  /// Buttons or extra content under the message.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(icon, size: 56, color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
