import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/internet_check.dart';
import '../../models/school.dart';
import '../../services/public_lookup_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';

/// Admin-only Public Look Up controls:
///  - the ON/OFF switch (the school's consent). ON publishes every record;
///    OFF removes them all, while the school stays listed so people are
///    asked to contact it;
///  - "Publish Lookup Data", which re-copies every student and teacher
///    (new saves publish by themselves; this repairs anything missed).
class PublishLookupSection extends StatefulWidget {
  const PublishLookupSection({super.key, required this.meta});

  /// The school's profile, live from Settings.
  final SchoolMeta meta;

  @override
  State<PublishLookupSection> createState() => _PublishLookupSectionState();
}

class _PublishLookupSectionState extends State<PublishLookupSection> {
  bool _busy = false;

  /// The switch position while a change is being saved.
  bool? _pending;
  int _done = 0;
  int _total = 0;
  String? _message;
  bool _failed = false;

  PublicLookupService get _service =>
      PublicLookupService(context.read<AuthController>().tenant!);

  void _start({bool? pending}) => setState(() {
        _busy = true;
        _pending = pending;
        _done = 0;
        _total = 0;
        _message = null;
        _failed = false;
      });

  void _progress(int done, int total) {
    if (mounted) {
      setState(() {
        _done = done;
        _total = total;
      });
    }
  }

  void _finish(String message, {bool failed = false}) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pending = null;
      _message = message;
      _failed = failed;
    });
  }

  Future<void> _toggle(bool on) async {
    final auth = context.read<AuthController>();
    final service = _service;
    if (!on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Turn Lookup OFF?'),
          content: const Text(
              'All pupil and teacher records of your school will be removed '
              'from Lookup. Your school stays in the list, and people will be '
              'asked to contact you instead.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Turn OFF')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _start(pending: on);
    try {
      if (!await hasInternet()) {
        _finish('Changing Lookup needs an internet connection.', failed: true);
        return;
      }
      await service.setLookupEnabled(on,
          uid: auth.appUser?.uid ?? '', onProgress: _progress);
      _finish(on
          ? 'Lookup is now ON for your school.'
          : 'Lookup is now OFF. Your school is still listed, but people will '
              'be asked to contact you.');
    } catch (e) {
      _finish('Could not change Lookup: $e', failed: true);
    }
  }

  Future<void> _publish() async {
    final service = _service;
    _start();
    try {
      if (!await hasInternet()) {
        _finish('Publishing needs an internet connection.', failed: true);
        return;
      }
      final count = await service.publishAll(onProgress: _progress);
      _finish('Done. $count record${count == 1 ? '' : 's'} published for '
          'Look Up.');
    } catch (e) {
      _finish('Publishing stopped: $e', failed: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = _pending ?? widget.meta.lookupApproved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Public Look Up', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text(
          'Pupils, parents and teachers can look up their own record from the '
          'sign-in screen with their ID, without an account. Only someone '
          "who knows a pupil's exact ID can see that pupil's record.",
          style: TextStyle(color: AppColors.textSecondary),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: on,
          onChanged: _busy ? null : _toggle,
          title: Text(on ? 'Lookup is ON' : 'Lookup is OFF',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(on
              ? 'Records can be looked up by ID.'
              : 'Your school is listed; people are asked to contact you.'),
        ),
        if (_busy) ...[
          LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
          const SizedBox(height: 6),
          Text(_total == 0 ? 'Working…' : 'Published $_done of $_total',
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
        ],
        if (_message != null) ...[
          Text(_message!,
              style: TextStyle(
                  color: _failed ? AppColors.danger : AppColors.success)),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: _busy || !on ? null : _publish,
          icon: const Icon(Icons.publish),
          label: const Text('Publish Lookup Data'),
        ),
        if (on)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Records update by themselves when you save. Use this once to '
              'publish everyone already registered.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
          ),
      ],
    );
  }
}
