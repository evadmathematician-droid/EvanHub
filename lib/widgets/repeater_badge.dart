import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The red "Repeater" label for pupils not promoted in 10 months (see
/// `Student.isRepeater`).
class RepeaterBadge extends StatelessWidget {
  const RepeaterBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('Repeater',
            style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );
}
