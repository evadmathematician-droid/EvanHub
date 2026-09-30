import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../core/invite_code.dart';
import '../../models/invite.dart';
import '../../models/user_role.dart';
import '../../services/auth_service.dart';
import '../../services/invite_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';

/// "I have an invite code": check the code, show the school and role, create
/// an account or sign in, then join in ONE atomic update.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _service = InviteService();
  final _codeForm = GlobalKey<FormState>();
  final _accountForm = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  Invite? _invite;
  bool _newAccount = true;
  bool _busy = false;
  bool _joined = false;
  String? _error;

  /// Set when the signed-in account is already a member of this school.
  bool _alreadyMember = false;

  late final AuthController _auth;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthController>();
    _auth.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    for (final c in [_code, _name, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  /// After a successful join, wait until the new membership is active, then
  /// open the app.
  void _onAuthChanged() {
    if (!_joined || !mounted) return;
    switch (_auth.status) {
      case AuthStatus.ready:
        context.go(Routes.dashboard);
      case AuthStatus.parentPortal:
        context.go(Routes.parentPortal);
      default:
        break;
    }
  }

  String _date(DateTime d) => DateFormat('d MMM yyyy').format(d);

  String _problemMessage(InviteProblem problem, Invite? invite) {
    final school = invite?.schoolName ?? 'the school';
    return switch (problem) {
      InviteProblem.notFound =>
        "We couldn't find that code. Check it and try again.",
      InviteProblem.expired => 'This code expired on '
          '${_date(invite!.expiresAt)}. Ask $school for a new one.',
      InviteProblem.used => 'This code has already been used. Each code works '
          'once. Ask $school for a new one.',
    };
  }

  Future<void> _check() async {
    if (!_codeForm.currentState!.validate()) return;
    final code = InviteCode.normalize(_code.text)!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.lookup(code);
      if (!mounted) return;
      setState(() {
        if (result.ok) {
          _invite = result.invite;
        } else {
          _error = _problemMessage(result.problem!, result.invite);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not check the code. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final invite = _invite!;
    final signedIn = _auth.firebaseUser;
    if (signedIn == null && !_accountForm.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _alreadyMember = false;
    });
    try {
      // 1. Account.
      final user = signedIn ??
          (_newAccount
              ? await _auth.register(
                  name: _name.text.trim(),
                  email: _email.text.trim(),
                  password: _password.text)
              : await _auth.signIn(
                  email: _email.text.trim(), password: _password.text));

      // 2. One school per account.
      final current = await _service.activeSchoolOf(user.uid);
      if (current == invite.schoolId) {
        setState(() => _alreadyMember = true);
        return;
      }
      if (current != null) {
        setState(() => _error = 'This account already belongs to another '
            'school. Sign in with a different email, or ask that school\'s '
            'admin to remove you first.');
        return;
      }

      // 3. Join (one atomic update).
      final email = user.email ?? _email.text.trim();
      final name = (user.displayName?.isNotEmpty ?? false)
          ? user.displayName!
          : (_name.text.trim().isNotEmpty
              ? _name.text.trim()
              : email.split('@').first);
      await _service.join(
        invite: invite,
        uid: user.uid,
        displayName: name,
        email: email,
      );
      _joined = true;
      _onAuthChanged(); // In case the membership is already active.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on FirebaseException catch (_) {
      // Rejected by the rules: find out why from the code itself.
      final again = await _service.lookup(invite.code).catchError(
          (_) => const InviteLookup(null, InviteProblem.notFound));
      if (mounted) {
        setState(() => _error = again.ok
            ? "Couldn't join ${invite.schoolName}. The code may have just "
                'been changed or cancelled. Ask for a new one.'
            : _problemMessage(again.problem!, again.invite ?? invite));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not join. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;
    return Scaffold(
      appBar: AppBar(title: const Text('Join with an invite code')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (invite == null) _codeStep() else _confirmStep(invite),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!,
                        style: const TextStyle(color: AppColors.danger)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _codeStep() {
    return Form(
      key: _codeForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.vpn_key_outlined,
              size: 48, color: AppColors.primary),
          const SizedBox(height: 12),
          const Text(
            'Enter the 8-character code your school sent you.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _code,
            autofocus: true,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [InviteCodeFormatter()],
            style: const TextStyle(
                fontSize: 24, letterSpacing: 4, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(hintText: 'XXXX-XXXX'),
            validator: (v) => InviteCode.normalize(v ?? '') == null
                ? 'Codes have 8 letters and numbers, like K7PM-X3QD '
                    '(no O, 0, I or 1).'
                : null,
            onFieldSubmitted: (_) => _busy ? null : _check(),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _busy ? null : _check,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Check code'),
          ),
        ],
      ),
    );
  }

  Widget _confirmStep(Invite invite) {
    // Watch so the screen updates after signing in or out.
    final signedIn = context.watch<AuthController>().firebaseUser;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('You are invited to',
                    style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text(invite.schoolName,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      invite.role == UserRole.teacher
                          ? Icons.co_present_outlined
                          : Icons.family_restroom,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text('as ${invite.role.label}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Code ${InviteCode.format(invite.code)} · valid until '
                  '${_date(invite.expiresAt)}',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_alreadyMember) ...[
          Text('You are already a member of ${invite.schoolName}.',
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => context.go(Routes.dashboard),
            child: const Text('Open the app'),
          ),
        ] else if (signedIn != null) ...[
          Text('Joining as ${signedIn.email ?? ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _busy ? null : _join,
            child: _busyOr('Join ${invite.schoolName}'),
          ),
          TextButton(
            onPressed: _busy ? null : _auth.signOut,
            child: const Text('Use a different account'),
          ),
        ] else
          _accountFields(),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _invite = null;
                    _error = null;
                    _alreadyMember = false;
                  }),
          child: const Text('Use a different code'),
        ),
      ],
    );
  }

  Widget _accountFields() {
    return Form(
      key: _accountForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('New account')),
              ButtonSegment(value: false, label: Text('I have an account')),
            ],
            selected: {_newAccount},
            onSelectionChanged: (s) => setState(() {
              _newAccount = s.first;
              _error = null;
            }),
          ),
          const SizedBox(height: 16),
          if (_newAccount) ...[
            TextFormField(
              controller: _name,
              maxLength: 100,
              decoration: const InputDecoration(
                  labelText: 'Your full name', counterText: ''),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            maxLength: 120,
            decoration:
                const InputDecoration(labelText: 'Email', counterText: ''),
            validator: (v) => (v == null || !v.contains('@'))
                ? 'Enter a valid email'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
                labelText:
                    _newAccount ? 'Choose a password (min 6)' : 'Password'),
            validator: (v) =>
                (v == null || v.length < 6) ? 'At least 6 characters' : null,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _busy ? null : _join,
            child: _busyOr(
                _newAccount ? 'Create account & join' : 'Sign in & join'),
          ),
        ],
      ),
    );
  }

  Widget _busyOr(String label) => _busy
      ? const SizedBox(
          height: 20,
          width: 20,
          child:
              CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        )
      : Text(label);
}
