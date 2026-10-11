import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/image_url.dart';
import '../../core/internet_check.dart';
import '../../models/lookup_record.dart';
import '../../services/public_lookup_service.dart';
import '../../services/school_directory.dart';
import '../../theme/app_colors.dart';
import 'lookup_not_approved_dialog.dart';
import 'lookup_result_dialog.dart';

/// "Look Up a Record" — no account or sign-in needed. Choose the school,
/// Student or Teacher, enter the ID (admission number / NIN) and the record
/// opens as a pop-up. Reads only the public nodes (`publicSchools`, and one
/// `publicLookup` record by exact key), so the search needs the internet.
/// The school list comes from [SchoolDirectory], which the login screen
/// starts loading in advance.
class LookupScreen extends StatefulWidget {
  const LookupScreen({super.key});

  @override
  State<LookupScreen> createState() => _LookupScreenState();
}

class _LookupScreenState extends State<LookupScreen> {
  static const _offline =
      'You are offline. Looking up a record needs internet. Connect and try again.';

  final _directory = SchoolDirectory.instance;
  final _id = TextEditingController();
  PublicSchool? _school;
  LookupType _type = LookupType.student;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Uses the list the login screen preloaded; loads it if that never ran.
    _directory.load();
  }

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  Future<void> _pickSchool(List<PublicSchool> schools) async {
    final picked = await showModalBottomSheet<PublicSchool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _SchoolPicker(schools: schools),
    );
    if (picked != null) {
      setState(() {
        _school = picked;
        _message = null;
      });
    }
  }

  Future<void> _search() async {
    final school = _school;
    final id = _id.text.trim();
    if (school == null) {
      setState(() => _message = 'Select your school first.');
      return;
    }
    // Not approved: never read a record; ask people to contact the school.
    if (!school.lookupEnabled) {
      setState(() => _message = null);
      await showLookupNotApproved(context, school);
      return;
    }
    if (id.isEmpty) {
      setState(() => _message = 'Enter your ID.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!await hasInternet()) {
        setState(() => _message = _offline);
        return;
      }
      final record = await PublicLookupService.find(school.id, _type, id);
      if (!mounted) return;
      if (record == null) {
        setState(() => _message = 'No record found for this ID in '
            '${school.name}. Check the ID or contact the school.');
        return;
      }
      await showLookupResult(context,
          record: record, schoolName: school.name);
    } on LookupOfflineException {
      if (mounted) setState(() => _message = _offline);
    } on LookupNotSetUpException {
      if (mounted) setState(() => _message = SchoolListProblem.notSetUp.message);
    } catch (e) {
      debugPrint('Lookup search failed: $e');
      if (mounted) {
        setState(() => _message = 'Could not look up this ID. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = _type == LookupType.student;
    return Scaffold(
      appBar: AppBar(title: const Text('Look Up a Record')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.manage_search,
                      size: 52, color: AppColors.primary),
                  const SizedBox(height: 8),
                  const Text(
                    'Pupils, parents and teachers can check their school '
                    'record here. No account is needed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  ListenableBuilder(
                    listenable: _directory,
                    builder: (context, _) => _schoolField(),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<LookupType>(
                    segments: const [
                      ButtonSegment(
                          value: LookupType.student,
                          icon: Icon(Icons.school_outlined),
                          label: Text('Student')),
                      ButtonSegment(
                          value: LookupType.teacher,
                          icon: Icon(Icons.person_outline),
                          label: Text('Teacher')),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() {
                      _type = s.first;
                      _message = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _id,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _busy ? null : _search(),
                    decoration: InputDecoration(
                      labelText: 'Enter your ID',
                      helperText: student
                          ? 'Your Student ID (admission number)'
                          : 'Your Staff ID (your NIN)',
                      prefixIcon: const Icon(Icons.badge_outlined),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _search,
                    icon: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.search),
                    label: const Text('Search'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The "Select your school" button, a spinner while the first list
  /// loads, or the reason there is no list with a Try Again button.
  Widget _schoolField() {
    final schools = _directory.schools ?? const <PublicSchool>[];
    final problem = _directory.problem;

    if (schools.isEmpty && _directory.loading) {
      return const _SchoolButton(
        label: 'Loading schools…',
        leading: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (schools.isEmpty || problem != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text((problem ?? SchoolListProblem.empty).message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.danger)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _directory.loading
                ? null
                : () => _directory.load(force: true),
            icon: _directory.loading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ],
      );
    }
    // A school picked before a reload is kept only if it is still listed.
    final selected = _school == null
        ? null
        : schools.where((s) => s.id == _school!.id).firstOrNull;
    return _SchoolButton(
      label: selected?.name ?? 'Select your school',
      selected: selected != null,
      leading: selected == null
          ? const Icon(Icons.apartment, color: AppColors.primary)
          : _SchoolLogo(school: selected),
      onTap: () => _pickSchool(schools),
    );
  }
}

/// Full-width button with a drop-down arrow.
class _SchoolButton extends StatelessWidget {
  const _SchoolButton({
    required this.label,
    required this.leading,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final Widget leading;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary)),
          ),
          const Icon(Icons.arrow_drop_down, color: AppColors.primary),
        ],
      ),
    );
  }
}

/// The school's badge in a small circle, or a school icon.
class _SchoolLogo extends StatelessWidget {
  const _SchoolLogo({required this.school});

  final PublicSchool school;

  @override
  Widget build(BuildContext context) {
    const icon = CircleAvatar(
      radius: 16,
      backgroundColor: Color(0x142E3192),
      child: Icon(Icons.apartment, size: 18, color: AppColors.primary),
    );
    if (school.logoUrl.isEmpty) return icon;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: cloudinaryResized(school.logoUrl, width: 96),
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        placeholder: (_, _) => icon,
        errorWidget: (_, _, _) => icon,
      ),
    );
  }
}

/// Every school A–Z with a search box, in a bottom sheet.
class _SchoolPicker extends StatefulWidget {
  const _SchoolPicker({required this.schools});

  final List<PublicSchool> schools;

  @override
  State<_SchoolPicker> createState() => _SchoolPickerState();
}

class _SchoolPickerState extends State<_SchoolPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? widget.schools
        : widget.schools
            .where((s) =>
                s.name.toLowerCase().contains(q) ||
                s.town.toLowerCase().contains(q))
            .toList();
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  hintText:
                      'Search ${widget.schools.length} schools by name or town',
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(
                      child: Text('No school matches this search.',
                          style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : ListView.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final s = shown[i];
                        return ListTile(
                          leading: _SchoolLogo(school: s),
                          title: Text(s.name),
                          subtitle: s.town.isEmpty
                              ? null
                              : Text(s.town,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.of(context).pop(s),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
