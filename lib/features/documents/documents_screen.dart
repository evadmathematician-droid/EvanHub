import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/internet_check.dart';
import '../../models/school_document.dart';
import '../../services/document_service.dart';
import '../../services/file_actions.dart';
import '../../state/auth_controller.dart';
import '../../widgets/delete_helpers.dart';
import '../../widgets/status_views.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  bool _uploading = false;

  /// Documents being downloaded for Open / Download.
  final Set<String> _fetching = {};

  /// Title plus the file's extension from its URL, e.g. "Timetable.pdf".
  String _fileName(SchoolDocument d) {
    final path = Uri.tryParse(d.downloadUrl)?.pathSegments.lastOrNull ?? '';
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot).toLowerCase();
    final title = d.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    final base = title.isEmpty ? 'document' : title;
    return base.toLowerCase().endsWith(ext) ? base : '$base$ext';
  }

  /// Downloads [d], then opens it in the phone's app for its type or lets
  /// the user save it (e.g. to Downloads).
  Future<void> _fetch(SchoolDocument d, {required bool save}) async {
    if (_fetching.contains(d.id)) return;
    setState(() => _fetching.add(d.id));
    try {
      final bytes = await FileActions.download(d.downloadUrl);
      final name = _fileName(d);
      if (save) {
        if (await FileActions.save(name, bytes)) _snack('Saved $name');
      } else {
        await FileActions.open(name, bytes);
      }
    } catch (e) {
      _snack(e is FileActionException ? e.message : 'Could not get the file: $e');
    } finally {
      if (mounted) setState(() => _fetching.remove(d.id));
    }
  }

  Future<void> _pickAndUpload() async {
    final auth = context.read<AuthController>();
    final result = await FilePicker.pickFiles();
    if (!mounted || result.isEmpty) return;
    final file = result.single;
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      _snack('Could not read the selected file.');
      return;
    }

    final title = await _askTitle(file.name);
    if (!mounted || title == null || title.isEmpty) return;

    setState(() => _uploading = true);
    try {
      await DocumentService(auth.tenant!).upload(
        title: title,
        category: 'general',
        fileName: file.name,
        bytes: bytes,
        uploadedBy: auth.appUser?.uid ?? '',
      );
      _snack('Uploaded.');
    } catch (e) {
      _snack(uploadFailedMessage(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<String?> _askTitle(String suggested) {
    final controller = TextEditingController(text: suggested);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Document title'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(DocumentService service, SchoolDocument d) async {
    final ok = await confirmDelete(
      context,
      title: 'Delete document?',
      message: '"${d.title}" will be removed from the documents list.',
    );
    if (!ok || !mounted) return;
    await runDelete(context, () => service.delete(d),
        done: '"${d.title}" deleted.');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    final service = DocumentService(auth.tenant!);
    final canUpload = auth.role.canManageStudents;

    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      floatingActionButton: canUpload
          ? FloatingActionButton.extended(
              onPressed: _uploading ? null : _pickAndUpload,
              icon: _uploading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(_uploading ? 'Uploading…' : 'Upload'),
            )
          : null,
      body: StreamListView<SchoolDocument>(
        stream: service.watchAll(),
        emptyMessage: 'No documents uploaded yet.',
        emptyIcon: Icons.folder_open,
        itemBuilder: (context, d) {
          // The uploader or an admin may delete (database rules).
          final canDelete = canUpload &&
              (auth.isAdmin || d.uploadedBy == auth.appUser?.uid);
          final busy = _fetching.contains(d.id);
          return Card(
            child: ListTile(
              leading: busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.description_outlined),
              title: Text(d.title),
              subtitle: Text('${d.category}  •  ${_size(d.sizeBytes)}'),
              onTap: busy ? null : () => _fetch(d, save: false),
              trailing: PopupMenuButton<String>(
                tooltip: 'Document options',
                enabled: !busy,
                onSelected: (action) => switch (action) {
                  'open' => _fetch(d, save: false),
                  'download' => _fetch(d, save: true),
                  _ => _delete(service, d),
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'open',
                    child: ListTile(
                      leading: Icon(Icons.open_in_new),
                      title: Text('Open'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'download',
                    child: ListTile(
                      leading: Icon(Icons.download_outlined),
                      title: Text('Download'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (canDelete)
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
