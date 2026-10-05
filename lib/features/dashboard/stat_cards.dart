import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../services/stats_service.dart';
import '../../theme/app_colors.dart';

/// The dashboard's count cards: Students, Teachers, Classes, Announcements.
/// Live counts, tap to open the list, a gentle entrance animation, and a
/// responsive grid — 2 columns on phones, 3 on small tablets, 4 on wide
/// screens and web.
class StatCards extends StatelessWidget {
  const StatCards({super.key, required this.stats});

  final SchoolStats stats;

  @override
  Widget build(BuildContext context) {
    final items = [
      _StatItem('Student', 'Students', stats.students, Icons.groups_rounded,
          AppColors.primary, () => context.go(Routes.students)),
      _StatItem('Teacher', 'Teachers', stats.teachers, Icons.person_rounded,
          AppColors.info, () => context.go(Routes.teachers)),
      _StatItem('Class', 'Classes', stats.classes, Icons.class_rounded,
          AppColors.success, () => context.push(Routes.classes)),
      _StatItem('Announcement', 'Announcements', stats.announcements,
          Icons.campaign_rounded, AppColors.accentDark,
          () => context.push(Routes.announcements)),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width < 600 ? 2 : (width < 900 ? 3 : 4);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 84,
        ),
        itemBuilder: (_, i) => _StatCard(item: items[i], index: i),
      );
    });
  }
}

class _StatItem {
  const _StatItem(
      this.singular, this.plural, this.count, this.icon, this.color, this.onTap);

  final String singular;
  final String plural;

  /// Null until the list has loaded.
  final int? count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  String get label => count == 1 ? singular : plural;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.item, required this.index});

  final _StatItem item;

  /// Position in the grid; later cards arrive a little later.
  final int index;

  static const _radius = BorderRadius.all(Radius.circular(16));

  @override
  Widget build(BuildContext context) {
    final color = item.color;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: _radius,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: _radius,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.14),
                color.withValues(alpha: 0.03),
              ],
            ),
          ),
          child: InkWell(
            onTap: item.onTap,
            splashColor: color.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(item.icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.count?.toString() ?? '—',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Fade and rise in once when the dashboard opens; count updates later
    // don't replay it.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + index * 90),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 16), child: child),
      ),
      child: card,
    );
  }
}
