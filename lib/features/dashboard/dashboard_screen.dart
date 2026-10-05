import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/login_timer.dart';
import '../../models/school.dart';
import '../../services/export/export_images.dart';
import '../../services/school_service.dart';
import '../../services/stats_service.dart';
import '../../state/auth_controller.dart';
import 'school_events_panel.dart';
import 'school_hero.dart';
import 'stat_cards.dart';
import 'student_search_bar.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// Live counts for the cards, followed for the life of the screen.
  StreamSubscription<SchoolStats>? _statsSub;
  SchoolStats _stats = const SchoolStats();

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
    _watchStats();
    _schoolSub = SchoolService()
        .streamSchool(context.read<AuthController>().schoolId!)
        .listen(
          (school) {
            // Keeps the badge and stamp on the phone for offline record
            // exports.
            ExportImages.prefetch([
              ExportImages.badgeUrl(school.meta.logoUrl),
              ExportImages.stampUrl(school.meta.stampUrl),
            ]);
            if (mounted) setState(() => _school = school);
          },
          onError: (Object e) => debugPrint('School profile failed: $e'),
        );
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    _schoolSub?.cancel();
    super.dispose();
  }

  void _watchStats() {
    _statsSub?.cancel();
    final refs = context.read<AuthController>().tenant!;
    var first = true;
    _statsSub = StatsService(refs).watch().listen(
      (stats) {
        if (first) {
          first = false;
          LoginTimer.finish('dashboard numbers loaded');
        }
        if (mounted) setState(() => _stats = stats);
      },
      onError: (Object e) => debugPrint('Dashboard counts failed: $e'),
    );
  }

  /// Pull to refresh: the counts are live already; this just re-listens.
  Future<void> _refresh() async {
    _watchStats();
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Profile banner runs edge to edge; the rest is padded below.
            SchoolHero(school: _school),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Full width, between the banner and the cards.
                  const StudentSearchBar(),
                  const SizedBox(height: 16),
                  StatCards(stats: _stats),
                  const SizedBox(height: 24),
                  const SchoolEventsPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
