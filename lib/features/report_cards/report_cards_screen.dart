import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/school.dart';
import '../../services/school_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/status_views.dart';
import 'report_card_data.dart';
import 'report_card_profile.dart';

/// More → Report Cards: choose JSS or SS report cards. Until the school has
/// its badge, motto and year founded, the profile form is shown instead
/// (the covers print all three); once saved, the choice appears.
class ReportCardsScreen extends StatefulWidget {
  const ReportCardsScreen({super.key});

  @override
  State<ReportCardsScreen> createState() => _ReportCardsScreenState();
}

class _ReportCardsScreenState extends State<ReportCardsScreen> {
  // Always the signed-in user's own school.
  late final Stream<School> _school =
      SchoolService().streamSchool(context.read<AuthController>().schoolId!);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<School>(
      stream: _school,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Report Cards')),
            body: ErrorView(message: '${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Report Cards')),
            body: const LoadingView(),
          );
        }
        final school = snapshot.data!;
        if (!hasReportCardProfile(school.meta)) {
          return Scaffold(
            appBar: AppBar(title: const Text(reportCardProfileTitle)),
            body: ReportCardProfileForm(
              school: school,
              intro: 'Report card covers print the school badge, motto and '
                  'year founded. Add them once to start making report '
                  'cards. You can change them later from the Report Cards '
                  'screen.',
              // The profile stream updates and the level choice appears.
              onSaved: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Report card details saved.'))),
            ),
          );
        }
        return _levelChooser(context);
      },
    );
  }

  Widget _levelChooser(BuildContext context) {
    final canEdit = context.watch<AuthController>().role.canManageSchool;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Cards'),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Badge, motto and year founded',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push(Routes.reportCardProfile),
            ),
        ],
      ),
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
