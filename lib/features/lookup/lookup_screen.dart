import 'package:flutter/material.dart';

import '../../core/internet_check.dart';
import '../../models/lookup_record.dart';
import '../../services/public_lookup_service.dart';
import '../../theme/app_colors.dart';
import 'lookup_result_dialog.dart';

/// "Look Up a Record" — no account or sign-in needed. Choose the school,
/// Student or Teacher, enter the ID (admission number / NIN) and the record
/// opens as a pop-up. Reads only the public nodes (`publicSchools`, and one
/// `publicLookup` record by exact key), so it needs the internet.
class LookupScreen extends StatefulWidget {
  const LookupScreen({super.key});

  @override
  State<LookupScreen> createState() => _LookupScreenState();
}

class _LookupScreenState extends State<LookupScreen> {
  static const _offline = 'Lookup needs an internet connection.';

  final _id = TextEditingController();
  List<PublicSchool>? _schools;
  bool _loadingSchools = true;
  String? _schoolsError;
  PublicSchool? _school;
  LookupType _type = LookupType.student;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadSchools();
  }

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  Future<void> _loadSchools() async {
    setState(() {
      _loadingSchools = true;
      _schoolsError = null;
    });
    String? error;
    List<PublicSchool>? schools;
    if (!await hasInternet()) {
      error = _offline;
    } else {
      try {
        schools = await PublicLookupService.loadSchools();
        if (schools.isEmpty) error = 'No schools are listed yet.';
      } on LookupOfflineException {
        error = _offline;
      } catch (e) {
        error = 'Could not load the list of schools. Try again.';
      }
    }
    if (!mounted) return;
    setState(() {
      _schools = schools;
      _schoolsError = error;
      _loadingSchools = false;
    });
  }

  Future<void> _pickSchool() async {
    final schools = _schools;
    if (schools == null || schools.isEmpty) return;
    final picked = await showDialog<PublicSchool>(
      context: context,
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
            '${school.name}. Check the ID and try again.');
        return;
      }
      await showLookupResult(context,
          record: record, schoolName: school.name);
    } on LookupOfflineException {
      if (mounted) setState(() => _message = _offline);
    } catch (e) {
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
                  _schoolField(),
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

  Widget _schoolField() {
    if (_loadingSchools) {
      return const InputDecorator(
        decoration: InputDecoration(
            labelText: 'Select School', prefixIcon: Icon(Icons.apartment)),
        child: Row(
          children: [
            SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Loading schools…'),
          ],
        ),
      );
    }
    if (_schoolsError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_schoolsError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.danger)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loadSchools,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      );
    }
    return InkWell(
      onTap: _pickSchool,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Select School',
          prefixIcon: Icon(Icons.apartment),
          suffixIcon: Icon(Icons.arrow_drop_down),
        ),
        isEmpty: _school == null,
        child: Text(_school?.name ?? '',
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// The school list with a search box.
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
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search for your school',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Flexible(
              child: shown.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No school matches this search.',
                          style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final s = shown[i];
                        return ListTile(
                          leading: const Icon(Icons.apartment,
                              color: AppColors.primary),
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
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
