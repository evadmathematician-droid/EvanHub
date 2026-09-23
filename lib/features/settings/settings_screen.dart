import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/school.dart';
import '../../services/school_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/status_views.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = SchoolService();
  late final Stream<School> _school =
      _service.streamSchool(context.read<AuthController>().schoolId!);
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _loaded = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(SchoolMeta meta) {
    if (_loaded) return;
    _name.text = meta.name;
    _address.text = meta.address;
    _phone.text = meta.phone;
    _email.text = meta.email;
    _loaded = true;
  }

  Future<void> _save(String schoolId, SchoolMeta current) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _service.updateMeta(
        schoolId,
        current.copyWith(
          name: _name.text.trim(),
          address: _address.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
        ),
      );
      setState(() => _message = 'Saved.');
    } catch (e) {
      setState(() => _message = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final schoolId = auth.schoolId!;
    final canEdit = auth.role.canManageSchool;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: StreamBuilder<School>(
        stream: _school,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorView(message: '${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingView();
          final school = snapshot.data!;
          _fill(school.meta);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('School profile',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                enabled: canEdit,
                decoration: const InputDecoration(labelText: 'School name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                enabled: canEdit,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                enabled: canEdit,
                decoration: const InputDecoration(labelText: 'Contact phone'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                enabled: canEdit,
                decoration: const InputDecoration(labelText: 'Contact email'),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!,
                    style: const TextStyle(color: AppColors.primary)),
              ],
              if (canEdit) ...[
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed:
                      _busy ? null : () => _save(schoolId, school.meta),
                  child: const Text('Save profile'),
                ),
              ],
              const Divider(height: 40),
              Text('Account', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(auth.appUser?.email ?? ''),
                subtitle: Text(auth.role.label),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Subscription'),
                subtitle: Text(
                    '${school.subscription.plan}  •  ${school.subscription.status}'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.read<AuthController>().signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          );
        },
      ),
    );
  }
}
