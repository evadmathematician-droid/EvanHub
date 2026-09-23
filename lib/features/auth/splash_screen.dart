import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Shown only while [AuthController] resolves the initial Firebase auth state.
/// The router redirects away as soon as the status is known.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school, color: Colors.white, size: 64),
            SizedBox(height: 16),
            Text(
              'Evangelist Global',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}
