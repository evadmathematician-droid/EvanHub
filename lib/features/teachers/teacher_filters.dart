import 'package:flutter/material.dart';

import '../../core/rtdb.dart';
import '../../models/teacher.dart';

/// Active | Past on the Teachers screen. Null (in the screen) = all.
enum TeacherStatusFilter {
  active('Active'),
  past('Past');

  const TeacherStatusFilter(this.label);
  final String label;

  bool matches(Teacher t) => (this == active) == t.isActive;
}

/// Sort orders for the Teachers screen. Name A → Z is the default.
enum TeacherSort {
  nameAz('Name A → Z', Icons.sort_by_alpha),
  nameZa('Name Z → A', Icons.sort_by_alpha),
  rank('Rank (Principal first)', Icons.military_tech_outlined),
  nin('NIN', Icons.badge_outlined),
  newest('Newest registered first', Icons.schedule);

  const TeacherSort(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The Teachers screen's search, filters and sort over the teachers on this
/// phone (so it all works offline). Pure: no widgets, no database.
class TeacherFilters {
  TeacherFilters(this.teachers);

  final List<Teacher> teachers;

  int get total => teachers.length;
  int get activeCount => teachers.where((t) => t.isActive).length;
  int get pastCount => total - activeCount;

  /// Rank filter choices: the standard ranks, then any other rank found in
  /// the data, then "Unassigned" when some teacher has no rank.
  List<String> get rankOptions {
    final found = {for (final t in teachers) t.rank.trim()};
    final std = TeacherRank.options.map((r) => r.toLowerCase()).toSet();
    final extra = found
        .where((r) => r.isNotEmpty && !std.contains(r.toLowerCase()))
        .toList()
      ..sort(compareText);
    return [
      ...TeacherRank.options,
      ...extra,
      if (found.contains('')) TeacherRank.unassigned,
    ];
  }

  /// Search on full name, NIN and record id; case-insensitive.
  static bool matchesSearch(Teacher t, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return t.fullName.toLowerCase().contains(q) ||
        t.nin.toLowerCase().contains(q) ||
        t.id.toLowerCase().contains(q);
  }

  /// [rank] is a value from [rankOptions]; null = all ranks.
  static bool matchesRank(Teacher t, String? rank) =>
      rank == null || t.rankLabel.toLowerCase() == rank.toLowerCase();

  /// Search AND status AND rank, then sorted.
  List<Teacher> apply({
    String search = '',
    TeacherStatusFilter? status,
    String? rank,
    TeacherSort sort = TeacherSort.nameAz,
  }) {
    final shown = teachers
        .where((t) =>
            matchesSearch(t, search) &&
            (status == null || status.matches(t)) &&
            matchesRank(t, rank))
        .toList();
    return sorted(shown, sort);
  }

  static List<Teacher> sorted(List<Teacher> list, TeacherSort sort) {
    int byName(Teacher a, Teacher b) {
      final c = compareText(a.fullName, b.fullName);
      return c != 0 ? c : a.id.compareTo(b.id);
    }

    final out = [...list];
    switch (sort) {
      case TeacherSort.nameAz:
        out.sort(byName);
      case TeacherSort.nameZa:
        out.sort((a, b) => byName(b, a));
      case TeacherSort.rank:
        out.sort((a, b) {
          final c =
              TeacherRank.order(a.rank).compareTo(TeacherRank.order(b.rank));
          return c != 0 ? c : byName(a, b);
        });
      case TeacherSort.nin:
        // Teachers without a NIN go to the bottom, A → Z by name.
        out.sort((a, b) {
          final an = a.nin.trim(), bn = b.nin.trim();
          if (an.isEmpty != bn.isEmpty) return an.isEmpty ? 1 : -1;
          final c = an.compareTo(bn);
          return c != 0 ? c : byName(a, b);
        });
      case TeacherSort.newest:
        // Records without a date (very old ones) go last.
        out.sort((a, b) {
          final ad = a.createdAt, bd = b.createdAt;
          if (ad == null || bd == null) {
            if (ad == bd) return byName(a, b);
            return ad == null ? 1 : -1;
          }
          final c = bd.compareTo(ad);
          return c != 0 ? c : byName(a, b);
        });
    }
    return out;
  }
}
