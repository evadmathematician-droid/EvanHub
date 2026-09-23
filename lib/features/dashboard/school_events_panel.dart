import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/image_url.dart';
import '../../models/school_event.dart';
import '../../services/event_service.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/delete_helpers.dart';

/// "School events" panel for the dashboard: newest posts first, with an Add
/// button for admins and teachers (the same people the database rules let
/// write events).
class SchoolEventsPanel extends StatefulWidget {
  const SchoolEventsPanel({super.key});

  @override
  State<SchoolEventsPanel> createState() => _SchoolEventsPanelState();
}

class _SchoolEventsPanelState extends State<SchoolEventsPanel> {
  static const _collapsedCount = 3;
  bool _showAll = false;

  Future<void> _add() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddEventSheet(),
    );
  }

  Future<void> _delete(EventService service, SchoolEvent e) async {
    final ok = await confirmDelete(
      context,
      title: 'Delete event?',
      message: '"${e.title}" will be removed.',
    );
    if (!ok || !mounted) return;
    await runDelete(context, () => service.delete(e.id),
        done: 'Event deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    final service = EventService(auth.tenant!);
    final canPost = auth.role.canManageStudents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('School events',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800)),
            ),
            if (canPost)
              FilledButton.tonalIcon(
                onPressed: _add,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add event'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<SchoolEvent>>(
          stream: service.watchAll(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Could not load events.\n${snapshot.error}',
                  style: const TextStyle(color: AppColors.danger));
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final events = snapshot.data!;
            if (events.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(Icons.event_note_outlined,
                          size: 36, color: AppColors.textMuted),
                      const SizedBox(height: 8),
                      Text(
                        canPost
                            ? 'No events yet. Tap "Add event" to post the first one.'
                            : 'No events yet.',
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              );
            }
            final visible =
                _showAll ? events : events.take(_collapsedCount).toList();
            return Column(
              children: [
                for (final e in visible)
                  _EventCard(
                    event: e,
                    // The author or an admin may delete (database rules).
                    onDelete: canPost &&
                            (auth.isAdmin || e.authorUid == auth.appUser?.uid)
                        ? () => _delete(service, e)
                        : null,
                  ),
                if (events.length > _collapsedCount)
                  TextButton(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    child: Text(_showAll
                        ? 'Show fewer'
                        : 'Show all ${events.length} events'),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, this.onDelete});

  final SchoolEvent event;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final date = event.createdAt == null
        ? ''
        : DateFormat('d MMM yyyy').format(event.createdAt!);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (event.imageUrl.isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: cloudinaryResized(event.imageUrl, width: 900),
                fit: BoxFit.cover,
                placeholder: (_, _) => const ColoredBox(
                  color: AppColors.divider,
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, _, _) => const ColoredBox(
                  color: AppColors.divider,
                  child: Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: AppColors.textMuted, size: 36),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (onDelete != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Delete event',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: onDelete,
                      ),
                  ],
                ),
                if (date.isNotEmpty)
                  Text(date,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),
                if (event.text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(event.text,
                        style: const TextStyle(
                            color: AppColors.textSecondary, height: 1.4)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddEventSheet extends StatefulWidget {
  const _AddEventSheet();

  @override
  State<_AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<_AddEventSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _text = TextEditingController();
  Uint8List? _imageBytes;
  String? _imageName;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result.isEmpty) return;
    final file = result.single;
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _imageBytes = bytes;
      _imageName = file.name;
    });
  }

  Future<void> _post() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthController>();
    try {
      await EventService(auth.tenant!).add(
        title: _title.text.trim(),
        text: _text.text.trim(),
        authorUid: auth.appUser?.uid ?? '',
        imageBytes: _imageBytes,
        imageName: _imageName,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not post: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('New school event',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Heading *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _text,
                maxLines: 4,
                decoration:
                    const InputDecoration(labelText: 'Write the event…'),
              ),
              const SizedBox(height: 12),
              if (_imageBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.memory(_imageBytes!, fit: BoxFit.cover),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(_imageBytes == null ? 'Add image' : 'Change image'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _busy ? null : _post,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Post event'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
