import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/internet_check.dart';
import '../../services/public_lookup_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';

/// Admin-only: copies every student and teacher of the school into the
/// public Look Up records and refreshes the school's public listing. New
/// saves publish by themselves; this fills in records saved before Look Up
/// existed and repairs any that were missed.
class PublishLookupSection extends StatefulWidget {
  const PublishLookupSection({super.key});

  @override
  State<PublishLookupSection> createState() => _PublishLookupSectionState();
}

class _PublishLookupSectionState extends State<PublishLookupSection> {
  bool _busy = false;
  int _done = 0;
  int _total = 0;
  String? _message;
  bool _failed = false;

  Future<void> _publish() async {
    final service = PublicLookupService(context.read<AuthController>().tenant!);
    setState(() {
      _busy = true;
      _done = 0;
      _total = 0;
      _message = null;
      _failed = false;
    });
    try {
      if (!await hasInternet()) {
        _finish('Publishing needs an internet connection.', failed: true);
        return;
      }
      final count = await service.publishAll(onProgress: (done, total) {
        if (mounted) {
          setState(() {
            _done = done;
            _total = total;
          });
        }
      });
      _finish('Done. $count record${count == 1 ? '' : 's'} published for '
          'Look Up.');
    } catch (e) {
      _finish('Publishing stopped: $e', failed: true);
    }
  }

  void _finish(String message, {bool failed = false}) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
      _failed = failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Public Look Up', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text(
          'Pupils, parents and teachers can look up their own record from the '
          'sign-in screen with their ID, without an account. Records update '
          'by themselves when you save; use this once to publish everyone '
          'already registered.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        if (_busy) ...[
          LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
          const SizedBox(height: 6),
          Text(_total == 0 ? 'Preparing…' : 'Published $_done of $_total',
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
          onPressed: _busy ? null : _publish,
          icon: const Icon(Icons.publish),
          label: const Text('Publish Lookup Data'),
        ),
      ],
    );
  }
}
