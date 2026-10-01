import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/login_timer.dart';
import '../../models/school.dart';
import '../../services/school_service.dart';
import '../../services/stats_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/status_views.dart';
import 'school_events_panel.dart';
import 'school_hero.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<SchoolStats> _statsFuture;

  /// The school profile, followed here for the life of the screen. It must
  /// NOT be a StreamBuilder inside the ListView: the list disposes the banner
  /// when it scrolls off-screen, and the rebuilt StreamBuilder would listen to
  /// the same single-subscription stream again ("Stream has already been
  /// listened to"), replacing the banner with an error box.
  StreamSubscription<School>? _schoolSub;
  School? _school;

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
    _schoolSub = SchoolService()
        .streamSchool(context.read<AuthController>().schoolId!)
        .listen(
          (school) {
            if (mounted) setState(() => _school = school);
          },
          onError: (Object e) => debugPrint('School profile failed: $e'),
        );
  }

  @override
  void dispose() {
    _schoolSub?.cancel();
    super.dispose();
  }

  Future<SchoolStats> _loadStats() {
    final refs = context.read<AuthController>().tenant!;
    return StatsService(refs)
        .load()
        .whenComplete(() => LoginTimer.finish('dashboard numbers loaded'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _statsFuture = _loadStats());
          await _statsFuture;
        },
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Profile banner runs edge to edge; the rest is padded below.
            SchoolHero(school: _school),
            Padding(
              padding: const EdgeInsets.all(16),
              child: _content(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<SchoolStats>(
          future: _statsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorView(
                message: 'Could not load stats.\n${snapshot.error}',
                onRetry: () => setState(() => _statsFuture = _loadStats()),
              );
            }
            final stats = snapshot.data;
            return GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                _StatTile('Students', stats?.students, Icons.groups_outlined),
                _StatTile('Teachers', stats?.teachers, Icons.person_outline),
                _StatTile('Classes', stats?.classes, Icons.class_outlined),
                _StatTile('Announcements', stats?.announcements,
                    Icons.campaign_outlined),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        const SchoolEventsPanel(),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.label, this.value, this.icon);

  final String label;
  final int? value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: AppColors.primary),
            Text(
              value?.toString() ?? '—',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800),
            ),
            Text(label,
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
