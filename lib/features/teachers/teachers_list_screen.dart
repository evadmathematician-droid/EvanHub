import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/teacher.dart';
import '../../services/teacher_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/photo_avatar.dart';
import '../../widgets/status_views.dart';
import 'teacher_filters.dart';

/// Teachers, with the Bubuya app's Total / Active / Past bar on top (tap one
/// to filter), a search box (name, NIN, ID), Active / Past chips, a Rank
/// filter and a Sort menu. Every filter combines, and all of it runs on the
/// teachers saved on this phone, so it works offline.
class TeachersListScreen extends StatefulWidget {
  const TeachersListScreen({super.key});

  @override
  State<TeachersListScreen> createState() => _TeachersListScreenState();
}

class _TeachersListScreenState extends State<TeachersListScreen> {
  // Created once so filter taps don't re-subscribe (and flash a spinner).
  late final Stream<List<Teacher>> _teachers;
  final _search = TextEditingController();

  /// Null = all.
  TeacherStatusFilter? _status;

  /// A value from [TeacherFilters.rankOptions]; null = all ranks.
  String? _rank;
  TeacherSort _sort = TeacherSort.nameAz;

  bool get _filtering =>
      _search.text.trim().isNotEmpty || _status != null || _rank != null;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController>();
    final service = TeacherService(auth.tenant!);
    // NINs are in the admin-only private half; others search by name / ID.
    _teachers = auth.role.canManageSchool
        ? service.watchAllWithNin()
        : service.watchAll();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clearFilters() => setState(() {
        _search.clear();
        _status = null;
        _rank = null;
      });

  @override
  Widget build(BuildContext context) {
    final canEdit = context.read<AuthController>().role.canManageSchool;

    return Scaffold(
      appBar: AppBar(title: const Text('Teachers')),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.teacherNew),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
      body: StreamBuilder<List<Teacher>>(
        stream: _teachers,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorView(message: 'Could not load data.\n${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingView();
          return _buildFiltered(TeacherFilters(snapshot.data!), canEdit);
        },
      ),
    );
  }

  Widget _buildFiltered(TeacherFilters f, bool canEdit) {
    // A rank that no longer exists in the data (e.g. last one edited away)
    // stops filtering.
    final options = f.rankOptions;
    if (_rank != null && !options.contains(_rank)) _rank = null;
    final shown = f.apply(
        search: _search.text, status: _status, rank: _rank, sort: _sort);

    return Column(
      children: [
        Material(
          color: AppColors.surface,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TotalsBar(
                  total: f.total,
                  active: f.activeCount,
                  past: f.pastCount,
                  selected: _status,
                  onSelect: (s) => setState(() => _status = s),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _searchBox()),
                    const SizedBox(width: 8),
                    _sortButton(),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _chip('All', _status == null, () => _status = null),
                      for (final s in TeacherStatusFilter.values)
                        _chip(s.label, _status == s, () => _status = s),
                      _rankButton(options),
                    ],
                  ),
                ),
                SizedBox(
                  height: 36,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Showing ${shown.length} of ${f.total}',
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.textSecondary),
                        ),
                      ),
                      if (_filtering)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.filter_alt_off_outlined,
                              size: 18),
                          label: const Text('Clear filters'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: f.total == 0
              ? const EmptyView(
                  message: 'No teachers yet.', icon: Icons.person_outline)
              : shown.isEmpty
                  ? const EmptyView(
                      message: 'No teachers match these filters',
                      icon: Icons.filter_alt_off_outlined)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                      itemCount: shown.length,
                      itemBuilder: (context, i) =>
                          _teacherTile(shown[i], canEdit),
                    ),
        ),
      ],
    );
  }

  Widget _searchBox() => TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search name, NIN or ID',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(_search.clear),
                ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        ),
      );

  /// "Sort ▾" — the chosen order is ticked.
  Widget _sortButton() => MenuAnchor(
        alignmentOffset: const Offset(0, 4),
        menuChildren: [
          for (final s in TeacherSort.values)
            MenuItemButton(
              leadingIcon: Icon(s.icon, size: 20),
              trailingIcon: s == _sort
                  ? const Icon(Icons.check, size: 18, color: AppColors.primary)
                  : null,
              onPressed: () => setState(() => _sort = s),
              child: Text(s.label),
            ),
        ],
        builder: (context, menu, _) => FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          icon: const Icon(Icons.sort, size: 18),
          label: const Text('Sort'),
        ),
      );

  /// "Rank ▾" / "Principal ▾" after the status chips.
  Widget _rankButton(List<String> options) {
    final active = _rank != null;
    final color = active ? Colors.white : AppColors.primary;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final r in [null, ...options])
          MenuItemButton(
            trailingIcon: r == _rank
                ? const Icon(Icons.check, size: 18, color: AppColors.primary)
                : null,
            onPressed: () => setState(() => _rank = r),
            child: Text(r ?? 'All Ranks'),
          ),
      ],
      builder: (context, menu, _) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.military_tech_outlined, size: 16, color: color),
              const SizedBox(width: 4),
              Text(_rank ?? 'Rank',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: color)),
              Icon(Icons.arrow_drop_down, size: 20, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback select) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          labelStyle: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
          selectedColor: AppColors.primary,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          selected: selected,
          onSelected: (_) => setState(select),
        ),
      );

  Widget _teacherTile(Teacher t, bool canEdit) => Card(
        child: ListTile(
          leading:
              PhotoAvatar(url: t.photoUrl, title: t.fullName, recordId: t.id),
          title: Text(t.fullName,
              style: t.isActive
                  ? null
                  : const TextStyle(color: AppColors.textSecondary)),
          subtitle: Text([
            t.rankLabel,
            t.statusLabel,
            if (t.nin.isNotEmpty) 'NIN ${t.nin}',
            if (t.subjects.isNotEmpty) t.subjects.join(', '),
            if (t.level.isNotEmpty) t.level,
            if (t.stream.isNotEmpty) t.stream,
          ].join('  •  ')),
          trailing: canEdit ? const Icon(Icons.chevron_right) : null,
          onTap: canEdit
              ? () => context.push(Routes.teacherEdit(t.id), extra: t)
              : null,
        ),
      );
}

/// Total | Active | Past in one card. Tapping a figure filters the list by
/// it (Total = all); the chosen one is highlighted.
class _TotalsBar extends StatelessWidget {
  const _TotalsBar({
    required this.total,
    required this.active,
    required this.past,
    required this.selected,
    required this.onSelect,
  });

  final int total;
  final int active;
  final int past;
  final TeacherStatusFilter? selected;
  final ValueChanged<TeacherStatusFilter?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            _figure('Total', total, AppColors.primary, selected == null,
                () => onSelect(null)),
            const VerticalDivider(width: 1),
            _figure('Active', active, AppColors.success,
                selected == TeacherStatusFilter.active,
                () => onSelect(TeacherStatusFilter.active)),
            const VerticalDivider(width: 1),
            _figure('Past', past, AppColors.textSecondary,
                selected == TeacherStatusFilter.past,
                () => onSelect(TeacherStatusFilter.past)),
          ],
        ),
      ),
    );
  }

  Widget _figure(String label, int count, Color color, bool isSelected,
          VoidCallback onTap) =>
      Expanded(
        child: Material(
          color: isSelected ? color.withValues(alpha: 0.12) : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    child: Text('$count',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: color)),
                  ),
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: color)),
                ],
              ),
            ),
          ),
        ),
      );
}
