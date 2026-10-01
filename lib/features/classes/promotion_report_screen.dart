import 'package:flutter/material.dart';

import '../../services/promotion_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/export_button.dart';

/// The outcome of a promotion run: totals, then who was promoted,
/// graduated, repeated or skipped (with the reason). Print gives the same
/// report as PDF, Word or Excel with the school name as the heading.
class PromotionReportScreen extends StatelessWidget {
  const PromotionReportScreen({
    super.key,
    required this.report,
    required this.schoolName,
    this.filters = const [],
  });

  final PromotionReport report;
  final Future<String> schoolName;

  /// What was promoted, e.g. ["SSS 1", "Science"].
  final List<String> filters;

  static const _colors = {
    PromotionOutcome.promoted: AppColors.success,
    PromotionOutcome.graduated: AppColors.info,
    PromotionOutcome.repeated: AppColors.warning,
    PromotionOutcome.skipped: AppColors.danger,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promotion report'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ExportButton(
              buildTable: () async =>
                  report.toTable(await schoolName, filters: filters),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (filters.isNotEmpty || report.academicYear.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                [
                  ...filters,
                  if (report.academicYear.isNotEmpty)
                    'Academic year ${report.academicYear}',
                ].join('  •  '),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          Row(
            children: [
              for (final o in PromotionOutcome.values) ...[
                if (o != PromotionOutcome.promoted) const SizedBox(width: 8),
                Expanded(child: _total(o)),
              ],
            ],
          ),
          for (final o in PromotionOutcome.values)
            if (report.count(o) > 0) ...[
              const SizedBox(height: 20),
              Text('${o.label} (${report.count(o)})',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: _colors[o])),
              const SizedBox(height: 6),
              Card(
                child: Column(
                  children: [
                    for (final l in report.of(o))
                      ListTile(
                        dense: true,
                        title: Text(l.name),
                        subtitle: Text([
                          if (l.admissionNo.isNotEmpty) 'Adm ${l.admissionNo}',
                          if (l.from.isNotEmpty || l.to.isNotEmpty)
                            [l.from, l.to]
                                .where((p) => p.isNotEmpty)
                                .join(' → '),
                          if (l.note.isNotEmpty) l.note,
                        ].join('  •  ')),
                      ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _total(PromotionOutcome o) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _colors[o]!.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text('${report.count(o)}',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _colors[o])),
            Text(o.label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      );
}
