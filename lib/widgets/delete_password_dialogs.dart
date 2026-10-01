import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/tenant/tenant_refs.dart';
import '../services/delete_guard_store.dart';
import '../services/delete_password_service.dart';
import '../theme/app_colors.dart';
import 'delete_helpers.dart';

/// The software developer, who alone can reset a school's delete password.
const developerPhone = '088-236-249';

const _minLength = 4;

/// Guards deleting a school history post with the school's delete password.
///
/// The first time (no password yet) the user creates one; every time after,
/// they must enter it. Five wrong passwords lock delete on this phone for five
/// minutes. Ends with an "Are you sure?" confirmation. Returns true only when
/// the post may be deleted.
Future<bool> confirmHistoryDelete(
  BuildContext context, {
  required TenantRefs refs,
  required String uid,
}) async {
  final guard = DeleteGuardStore.instance;
  final service = DeletePasswordService(refs);
  final schoolId = refs.schoolId;
  final messenger = ScaffoldMessenger.of(context);
  void say(String message) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  final locked = guard.lockRemaining(schoolId);
  if (locked != null) {
    say('Too many wrong passwords. Delete is locked on this phone for '
        '${_minutesSeconds(locked)}.');
    return false;
  }

  // Ask the database first; fall back to this phone's copy when offline.
  DeletePasswordHash? stored;
  var reachedDatabase = false;
  try {
    stored = await service.load();
    reachedDatabase = true;
    await guard.cacheHash(schoolId, stored);
  } catch (e) {
    debugPrint('Could not load delete password: $e');
    stored = guard.cachedHash(schoolId);
  }
  if (!context.mounted) return false;

  if (stored == null) {
    if (!reachedDatabase) {
      say('Could not check the delete password. Connect to the internet '
          'and try again.');
      return false;
    }
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CreateDeletePasswordDialog(),
    );
    if (password == null) return false;
    try {
      final created = await service.create(password, uid: uid);
      if (created == null) {
        say('A delete password was just created on another phone. Tap delete '
            'again and enter that password.');
        return false;
      }
      await guard.cacheHash(schoolId, created);
    } catch (e) {
      debugPrint('Could not save delete password: $e');
      say('Could not save the delete password. Check your connection and try '
          'again.');
      return false;
    }
    say('Delete password saved.');
  } else {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const EnterDeletePasswordDialog(),
    );
    if (password == null) return false;
    if (!stored.matches(password)) {
      final left = await guard.recordFailure(schoolId);
      say(left == 0
          ? 'Incorrect password. History not deleted. Too many wrong attempts: '
              'delete is locked on this phone for 5 minutes.'
          : 'Incorrect password. History not deleted. '
              '$left attempt${left == 1 ? '' : 's'} left.');
      return false;
    }
    await guard.clearFailures(schoolId);
  }

  if (!context.mounted) return false;
  return confirmDelete(
    context,
    title: 'Delete history post?',
    message: 'Are you sure you want to delete this history post?',
  );
}

String _minutesSeconds(Duration d) {
  final seconds = d.inSeconds + 1;
  final m = seconds ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

Future<void> _callDeveloper() async {
  final uri = Uri(scheme: 'tel', path: developerPhone.replaceAll('-', ''));
  try {
    await launchUrl(uri);
  } catch (e) {
    debugPrint('Could not open the dialer: $e');
  }
}

/// Password field with a show/hide toggle.
class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _hidden,
      autofocus: widget.autofocus,
      enableSuggestions: false,
      autocorrect: false,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          tooltip: _hidden ? 'Show password' : 'Hide password',
          icon: Icon(_hidden
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}

/// First-time setup. Pops the new password, or null when cancelled.
class CreateDeletePasswordDialog extends StatefulWidget {
  const CreateDeletePasswordDialog({super.key});

  @override
  State<CreateDeletePasswordDialog> createState() =>
      _CreateDeletePasswordDialogState();
}

class _CreateDeletePasswordDialogState
    extends State<CreateDeletePasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _understood = false;

  @override
  void initState() {
    super.initState();
    _password.addListener(_refresh);
    _confirm.addListener(_refresh);
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  bool get _longEnough => _password.text.length >= _minLength;
  bool get _matches => _password.text == _confirm.text;
  bool get _canSave => _longEnough && _matches && _understood;

  String? get _hint {
    if (_password.text.isNotEmpty && !_longEnough) {
      return 'Use at least $_minLength characters.';
    }
    if (_confirm.text.isNotEmpty && !_matches) {
      return 'The passwords do not match.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hint = _hint;
    return AlertDialog(
      title: const Text('Create Delete Password'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('School history can only be deleted with a password. '
              'Create it now.'),
          const SizedBox(height: 12),
          _PasswordField(
              controller: _password, label: 'Password', autofocus: true),
          const SizedBox(height: 8),
          _PasswordField(controller: _confirm, label: 'Confirm password'),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint,
                style: const TextStyle(color: AppColors.danger, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.danger, width: 1.5),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'IMPORTANT: The password you create now is the ONLY '
                    'password that can delete school history. You will need '
                    'to enter it every time you want to delete a history '
                    'post. If you forget it, you will NOT be able to delete '
                    'any school history. This password CANNOT be reset from '
                    'the app. To reset it, you must contact the software '
                    'developer: $developerPhone.',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _understood,
            onChanged: (v) => setState(() => _understood = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
                'I understand this password cannot be reset from the app.'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed:
              _canSave ? () => Navigator.pop(context, _password.text) : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Asks for the delete password. Pops what was typed, or null when cancelled.
class EnterDeletePasswordDialog extends StatefulWidget {
  const EnterDeletePasswordDialog({super.key});

  @override
  State<EnterDeletePasswordDialog> createState() =>
      _EnterDeletePasswordDialogState();
}

class _EnterDeletePasswordDialogState
    extends State<EnterDeletePasswordDialog> {
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty) return;
    Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter Delete Password'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PasswordField(
            controller: _password,
            label: 'Delete password',
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          const Text(
            'Forgot your password? It cannot be reset from the app. Contact '
            'the software developer:',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: _callDeveloper,
              icon: const Icon(Icons.phone, size: 18),
              label: const Text(developerPhone,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _password.text.isEmpty ? null : _submit,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
