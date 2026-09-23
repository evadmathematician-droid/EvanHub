import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/school_document.dart';
import '../../services/document_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/status_views.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  bool _uploading = false;

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
      _snack('Upload failed: $e');
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
        itemBuilder: (context, d) => Card(
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(d.title),
            subtitle: Text('${d.category}  •  ${_size(d.sizeBytes)}'),
            trailing: canUpload
                ? IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => service.delete(d),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
