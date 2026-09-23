import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/announcement.dart';
import '../../models/school_class.dart';
import '../../services/announcement_service.dart';
import '../../services/class_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';

class AnnouncementFormScreen extends StatefulWidget {
  const AnnouncementFormScreen({super.key});

  @override
  State<AnnouncementFormScreen> createState() => _AnnouncementFormScreenState();
}

class _AnnouncementFormScreenState extends State<AnnouncementFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _audience = Announcement.audienceSchool;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthController>();
    try {
      await AnnouncementService(auth.tenant!).create(
        Announcement(
          id: '',
          title: _title.text.trim(),
          body: _body.text.trim(),
          audience: _audience,
          authorUid: auth.appUser?.uid ?? '',
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Could not post: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final classService = ClassService(context.read<AuthController>().tenant!);

    return Scaffold(
      appBar: AppBar(title: const Text('New announcement')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _body,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Message *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<SchoolClass>>(
              stream: classService.watchAll(),
              builder: (context, snapshot) {
                final classes = snapshot.data ?? const <SchoolClass>[];
                return DropdownButtonFormField<String>(
                  initialValue: _audience,
                  decoration: const InputDecoration(labelText: 'Audience'),
                  items: [
                    const DropdownMenuItem(
                      value: Announcement.audienceSchool,
                      child: Text('Whole school'),
                    ),
                    ...classes.map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text('Class: ${c.name}'),
                        )),
                  ],
                  onChanged: (v) => setState(
                      () => _audience = v ?? Announcement.audienceSchool),
                );
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _busy ? null : _post,
              child: const Text('Post announcement'),
            ),
          ],
        ),
      ),
    );
  }
}
