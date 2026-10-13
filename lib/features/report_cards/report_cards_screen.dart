import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../theme/app_colors.dart';
import 'report_card_data.dart';

/// More → Report Cards: choose JSS or SS report cards.
class ReportCardsScreen extends StatelessWidget {
  const ReportCardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report Cards')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _LevelCard(
            level: ReportLevel.jss,
            subtitle: 'Junior Secondary School — JSS 1 to JSS 3',
            icon: Icons.menu_book_outlined,
          ),
          SizedBox(height: 16),
          _LevelCard(
            level: ReportLevel.ss,
            subtitle: 'Senior Secondary School — SS 1 to SS 3',
            icon: Icons.school_outlined,
          ),
        ],
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.level,
    required this.subtitle,
    required this.icon,
  });

  final ReportLevel level;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.reportCardLevel(level.name)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: Icon(icon, size: 32, color: AppColors.primary),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(level.title,
                        style: text.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: text.bodyMedium
                            ?.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
