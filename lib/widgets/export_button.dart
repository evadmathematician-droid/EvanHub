import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/export/export_table.dart';
import '../services/file_actions.dart';
import '../theme/app_colors.dart';

/// A compact "Print" button offering PDF, Word and Excel. [buildTable] runs
/// when a format is chosen, so the file always matches the current filters.
/// When the file is ready a sheet offers Open, Print (PDF), Save and Share.
class ExportButton extends StatefulWidget {
  const ExportButton({super.key, required this.buildTable});

  final Future<ExportTable> Function() buildTable;

  @override
  State<ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends State<ExportButton> {
  bool _busy = false;

  static const _icons = {
    ExportFormat.pdf: Icons.picture_as_pdf_outlined,
    ExportFormat.word: Icons.description_outlined,
    ExportFormat.excel: Icons.table_chart_outlined,
  };

  Future<void> _export(ExportFormat format) async {
    setState(() => _busy = true);
    try {
      final table = await widget.buildTable();
      final bytes = await table.build(format);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => _FileReadySheet(
          fileName: table.fileName(format),
          bytes: bytes,
          format: format,
          records: table.rows.length,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not create the file: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final f in ExportFormat.values)
          MenuItemButton(
            leadingIcon: Icon(_icons[f], size: 20),
            onPressed: () => _export(f),
            child: Text(f.label),
          ),
      ],
      builder: (context, menu, _) => FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: _busy ? null : () => menu.isOpen ? menu.close() : menu.open(),
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.print_outlined, size: 18),
        label: const Text('Print'),
      ),
    );
  }
}

/// What to do with a file that has just been created.
class _FileReadySheet extends StatelessWidget {
  const _FileReadySheet({
    required this.fileName,
    required this.bytes,
    required this.format,
    required this.records,
  });

  final String fileName;
  final Uint8List bytes;
  final ExportFormat format;
  final int records;

  @override
  Widget build(BuildContext context) {
    Future<void> run(Future<void> Function() action, {String? done}) async {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      try {
        await action();
        if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('$e')));
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle, color: AppColors.success),
              title: Text('${format.label} ready',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('$fileName\n$records record(s)'),
              isThreeLine: true,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open'),
              onTap: () => run(() => FileActions.open(fileName, bytes)),
            ),
            if (format == ExportFormat.pdf)
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: const Text('Print'),
                onTap: () => run(() => FileActions.printPdf(fileName, bytes)),
              ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Save to phone'),
              subtitle: const Text('Choose a folder, e.g. Downloads'),
              onTap: () => run(() async {
                final saved = await FileActions.save(fileName, bytes,
                    mimeType: format.mimeType);
                if (!saved) throw const FileActionException('Not saved.');
              }, done: 'Saved $fileName'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              subtitle: const Text('WhatsApp, email, Drive …'),
              onTap: () => run(() => FileActions.share(fileName, bytes,
                  mimeType: format.mimeType)),
            ),
          ],
        ),
      ),
    );
  }
}
