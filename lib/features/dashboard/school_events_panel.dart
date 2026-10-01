import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/image_url.dart';
import '../../core/internet_check.dart';
import '../../models/pending_event.dart';
import '../../models/school_event.dart';
import '../../services/event_service.dart';
import '../../services/pending_event_store.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/adaptive_image.dart';
import '../../widgets/delete_helpers.dart';
import '../../widgets/delete_password_dialogs.dart';

const _offlineMessage = 'No internet at the moment. Your post has been saved '
    'on this phone and will upload automatically when you\'re back online.';

/// "School events" panel for the dashboard: newest posts first, with an Add
/// button for admins and teachers (the same people the database rules let
/// write events). Posts saved offline show on top with a "Waiting to upload"
/// badge until the sync sends them.
class SchoolEventsPanel extends StatefulWidget {
  const SchoolEventsPanel({super.key});

  @override
  State<SchoolEventsPanel> createState() => _SchoolEventsPanelState();
}

class _SchoolEventsPanelState extends State<SchoolEventsPanel> {
  static const _collapsedCount = 3;
  bool _showAll = false;

  late final EventService _service;
  late final String _schoolId;

  /// Created once: a stream built inside build() would re-subscribe (and flash
  /// the spinner) on every rebuild.
  late final Stream<List<SchoolEvent>> _events;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController>();
    _schoolId = auth.schoolId!;
    _service = EventService(auth.tenant!);
    _events = _service.watchAll();
  }

  Future<void> _add() async {
    final savedOffline = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddEventSheet(service: _service),
    );
    if (savedOffline != true || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.cloud_off_outlined),
        title: const Text('Saved on this phone'),
        content: const Text(_offlineMessage),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
        ],
      ),
    );
  }

  /// Delete password, then "Are you sure?" (see [confirmHistoryDelete]).
  Future<bool> _confirmDelete() {
    final auth = context.read<AuthController>();
    return confirmHistoryDelete(context,
        refs: auth.tenant!, uid: auth.appUser?.uid ?? '');
  }

  Future<void> _delete(SchoolEvent e) async {
    if (!await _confirmDelete() || !mounted) return;
    await runDelete(context, () => _service.delete(e.id),
        done: 'History post deleted.');
  }

  /// A post still waiting to upload is removed from this phone only.
  Future<void> _deletePending(PendingEvent e) async {
    if (!await _confirmDelete() || !mounted) return;
    await runDelete(context, () => PendingEventStore.instance!.remove(e),
        done: 'History post deleted.');
  }

  /// Rebuilds [builder] whenever a pending post is added or removed.
  Widget _withPending(Widget Function(List<PendingEvent> pending) builder) {
    final store = PendingEventStore.instance;
    if (store == null) return builder(const []);
    return ValueListenableBuilder(
      valueListenable: store.listenable(),
      builder: (_, _, _) => builder(store.forSchool(_schoolId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    final canPost = auth.role.canManageStudents;
    bool canDelete(String authorUid) =>
        canPost && (auth.isAdmin || authorUid == auth.appUser?.uid);

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
          stream: _events,
          builder: (context, snapshot) => _withPending((allPending) {
            final events = snapshot.data ?? const <SchoolEvent>[];
            // Hide a pending post once its uploaded copy has arrived.
            final uploadedIds = {for (final e in events) e.id};
            final pending = allPending
                .where((p) => !uploadedIds.contains(p.id))
                .toList();

            final cards = <Widget>[
              for (final p in pending)
                _EventCard(
                  title: p.title,
                  text: p.text,
                  date: p.createdAt,
                  image: p.imagePath.isEmpty
                      ? null
                      : AdaptiveImage(image: FileImage(File(p.imagePath))),
                  pending: true,
                  onDelete: canDelete(p.authorUid)
                      ? () => _deletePending(p)
                      : null,
                ),
              for (final e in events)
                _EventCard(
                  title: e.title,
                  text: e.text,
                  date: e.createdAt,
                  image: e.imageUrl.isEmpty
                      ? null
                      : AdaptiveImage(
                          image: CachedNetworkImageProvider(
                              cloudinaryResized(e.imageUrl, width: 900)),
                          // Sharper copy for pinch-to-zoom.
                          fullImage: CachedNetworkImageProvider(
                              cloudinaryResized(e.imageUrl, width: 2000)),
                        ),
                  // The author or an admin may delete (database rules).
                  onDelete:
                      canDelete(e.authorUid) ? () => _delete(e) : null,
                ),
            ];

            final status = <Widget>[
              if (snapshot.hasError)
                Text('Could not load events.\n${snapshot.error}',
                    style: const TextStyle(color: AppColors.danger))
              else if (!snapshot.hasData)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (cards.isEmpty)
                _EmptyCard(canPost: canPost),
            ];

            final visible =
                _showAll ? cards : cards.take(_collapsedCount).toList();
            return Column(
              children: [
                ...visible,
                ...status,
                if (cards.length > _collapsedCount)
                  TextButton(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    child: Text(_showAll
                        ? 'Show fewer'
                        : 'Show all ${cards.length} events'),
                  ),
              ],
            );
          }),
        ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.canPost});

  final bool canPost;

  @override
  Widget build(BuildContext context) {
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
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small "Waiting to upload" label on posts saved offline.
class _PendingBadge extends StatelessWidget {
  const _PendingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_upload_outlined,
              size: 14, color: Colors.orange.shade800),
          const SizedBox(width: 4),
          Text('Waiting to upload',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade800)),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.title,
    required this.text,
    this.date,
    this.image,
    this.pending = false,
    this.onDelete,
  });

  final String title;
  final String text;
  final DateTime? date;
  final Widget? image;
  final bool pending;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final dateText = date == null ? '' : DateFormat('d MMM yyyy').format(date!);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The whole picture at its real proportions (see AdaptiveImage).
          if (image != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: image,
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
                        title,
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
                if (pending) ...[
                  const _PendingBadge(),
                  const SizedBox(height: 4),
                ],
                if (dateText.isNotEmpty)
                  Text(dateText,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(text,
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

/// Pops `true` when the post was saved on the phone instead of uploaded.
class _AddEventSheet extends StatefulWidget {
  const _AddEventSheet({required this.service});

  final EventService service;

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
    final store = PendingEventStore.instance;
    // One id for this post, whether it uploads now or later.
    final id = widget.service.newId();

    Future<void> saveOffline() async {
      await store!.save(
        id: id,
        schoolId: auth.schoolId!,
        title: _title.text.trim(),
        text: _text.text.trim(),
        authorUid: auth.appUser?.uid ?? '',
        imageBytes: _imageBytes,
        imageName: _imageName,
      );
      if (mounted) Navigator.of(context).pop(true);
    }

    try {
      if (store != null && !await hasInternet()) {
        await saveOffline();
        return;
      }
      await widget.service.add(
        id: id,
        title: _title.text.trim(),
        text: _text.text.trim(),
        authorUid: auth.appUser?.uid ?? '',
        imageBytes: _imageBytes,
        imageName: _imageName,
      );
      if (mounted) Navigator.of(context).pop(false);
    } catch (e) {
      // The connection dropped part-way: keep the post for the sync.
      if (store != null && isNetworkError(e)) {
        try {
          await saveOffline();
          return;
        } catch (saveError) {
          if (mounted) setState(() => _error = 'Could not save: $saveError');
          return;
        }
      }
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
              if (_imageBytes != null) ...[
                AdaptiveImage(
                  image: MemoryImage(_imageBytes!),
                  maxHeightFraction: 0.4,
                  enableFullScreen: false,
                ),
                const SizedBox(height: 8),
              ],
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
