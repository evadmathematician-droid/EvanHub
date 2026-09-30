import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/school.dart';
import '../../services/auth_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';

/// The acceptance-criteria path: a brand-new school signs up and gets its own
/// isolated tenant. Creates the admin's Firebase Auth account, then provisions
/// `schools/{schoolId}` + the admin membership + the `users/{uid}` binding.
class SchoolOnboardingScreen extends StatefulWidget {
  const SchoolOnboardingScreen({super.key});

  @override
  State<SchoolOnboardingScreen> createState() => _SchoolOnboardingScreenState();
}

class _SchoolOnboardingScreenState extends State<SchoolOnboardingScreen> {
  int _step = 0;
  bool _busy = false;
  String? _error;

  final _schoolFormKey = GlobalKey<FormState>();
  final _adminFormKey = GlobalKey<FormState>();

  final _schoolName = TextEditingController();
  final _address = TextEditingController();
  final _schoolPhone = TextEditingController();
  final _schoolEmail = TextEditingController();

  final _adminName = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminPassword = TextEditingController();

  bool get _alreadySignedIn =>
      context.read<AuthController>().firebaseUser != null;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthController>().firebaseUser;
    if (user != null) {
      _adminEmail.text = user.email ?? '';
      _adminName.text = user.displayName ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [
      _schoolName,
      _address,
      _schoolPhone,
      _schoolEmail,
      _adminName,
      _adminEmail,
      _adminPassword,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthController>().onboardNewSchool(
            adminName: _adminName.text.trim(),
            adminEmail: _adminEmail.text.trim(),
            adminPassword: _adminPassword.text,
            meta: SchoolMeta(
              name: _schoolName.text.trim(),
              address: _address.text.trim(),
              phone: _schoolPhone.text.trim(),
              email: _schoolEmail.text.trim(),
            ),
          );
      // Router redirect sends us to the dashboard once `users/{uid}` is written.
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not create the school: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    if (_step == 0) {
      if (!_schoolFormKey.currentState!.validate()) return;
      setState(() => _step = 1);
    } else if (_step == 1) {
      if (!_alreadySignedIn && !_adminFormKey.currentState!.validate()) return;
      setState(() => _step = 2);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step -= 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register your school'),
        actions: [
          // Joining an existing school instead of creating one.
          TextButton.icon(
            onPressed: _busy ? null : () => context.push(Routes.join),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.vpn_key_outlined),
            label: const Text('Invite code'),
          ),
        ],
      ),
      body: Stepper(
        currentStep: _step,
        onStepContinue: _busy ? null : _next,
        onStepCancel: _busy ? null : _back,
        controlsBuilder: (context, details) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: details.onStepContinue,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_step == 2 ? 'Create school' : 'Continue'),
                ),
              ),
              if (_step > 0)
                TextButton(
                  onPressed: details.onStepCancel,
                  child: const Text('Back'),
                ),
            ],
          ),
        ),
        steps: [
          Step(
            title: const Text('School details'),
            isActive: _step >= 0,
            content: Form(
              key: _schoolFormKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _schoolName,
                    decoration:
                        const InputDecoration(labelText: 'School name *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    decoration: const InputDecoration(labelText: 'Address'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _schoolPhone,
                    keyboardType: TextInputType.phone,
                    decoration:
                        const InputDecoration(labelText: 'Contact phone'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _schoolEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration:
                        const InputDecoration(labelText: 'Contact email'),
                  ),
                ],
              ),
            ),
          ),
          Step(
            title: const Text('Admin account'),
            isActive: _step >= 1,
            content: _alreadySignedIn
                ? const Text(
                    'You are already signed in — this account will become the '
                    'School Admin.',
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                : Form(
                    key: _adminFormKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _adminName,
                          decoration: const InputDecoration(
                              labelText: 'Your full name *'),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _adminEmail,
                          keyboardType: TextInputType.emailAddress,
                          decoration:
                              const InputDecoration(labelText: 'Email *'),
                          validator: (v) => (v == null || !v.contains('@'))
                              ? 'Enter a valid email'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _adminPassword,
                          obscureText: true,
                          decoration: const InputDecoration(
                              labelText: 'Password (min 6 chars) *'),
                          validator: (v) => (v == null || v.length < 6)
                              ? 'At least 6 characters'
                              : null,
                        ),
                      ],
                    ),
                  ),
          ),
          Step(
            title: const Text('Confirm'),
            isActive: _step >= 2,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('School: ${_schoolName.text}'),
                Text('Admin: ${_adminName.text} (${_adminEmail.text})'),
                const SizedBox(height: 12),
                const Text(
                  'A new isolated workspace will be created. Only members you '
                  'invite can access its data.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(color: AppColors.danger)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
