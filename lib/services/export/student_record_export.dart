import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

import '../../models/student.dart';
import '../file_actions.dart';
import 'student_record_pdf.dart';

enum RecordFormat { pdf, png }

/// What to do with the exported record.
enum RecordAction {
  /// The system share sheet (WhatsApp, Telegram, Gmail, Bluetooth, Drive …).
  /// On the web: the browser's share option where supported, else a download.
  share,

  /// Save to the phone (the user picks the folder). On the web: a download.
  save,
}

/// Builds a student's record as a PDF or a PNG image and hands it over.
class StudentRecordExport {
  StudentRecordExport._();

  /// `<StudentID>_<StudentName>_Record.pdf` (or `.png`): letters and digits
  /// only, words joined by `_`.
  static String fileName(Student s, RecordFormat format) {
    String clean(String v) => v
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final id = clean(s.admissionNo).isEmpty ? clean(s.id) : clean(s.admissionNo);
    final name = clean(s.fullName);
    final base = [id, if (name.isNotEmpty) name, 'Record'].join('_');
    return '$base.${format.name}';
  }

  static Future<Uint8List> build(
      StudentRecordData data, RecordFormat format) async {
    final pdf = await buildStudentRecordPdfSafely(data);
    return format == RecordFormat.pdf ? pdf : _toPng(pdf);
  }

  /// Shares or saves the file. Returns false when the user cancelled a save.
  static Future<bool> deliver(String fileName, Uint8List bytes,
      RecordFormat format, RecordAction action) async {
    final mime = format == RecordFormat.pdf ? 'application/pdf' : 'image/png';
    if (action == RecordAction.save) {
      return FileActions.save(fileName, bytes, mimeType: mime);
    }
    if (kIsWeb) {
      // Not every browser can share files; those download it instead.
      try {
        await FileActions.share(fileName, bytes, mimeType: mime);
      } catch (_) {
        await FileActions.save(fileName, bytes, mimeType: mime);
      }
      return true;
    }
    await FileActions.share(fileName, bytes, mimeType: mime);
    return true;
  }

  /// The PDF drawn as an image at print quality (150 dpi), so the PNG looks
  /// exactly like the PDF. Several pages are stacked top to bottom with a
  /// thin grey gap between them.
  static Future<Uint8List> _toPng(Uint8List pdf) async {
    final pages = <ui.Image>[];
    await for (final page in Printing.raster(pdf, dpi: 150)) {
      pages.add(await page.toImage());
    }
    if (pages.isEmpty) throw StateError('The record has no pages.');

    const gap = 16;
    final width = pages.map((p) => p.width).reduce((a, b) => a > b ? a : b);
    final height = pages.fold<int>(0, (h, p) => h + p.height) +
        gap * (pages.length - 1);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFE2E5EA),
    );
    var y = 0.0;
    for (final page in pages) {
      canvas.drawImage(page, ui.Offset(0, y), ui.Paint());
      y += page.height + gap;
    }
    final image = await recorder.endRecording().toImage(width, height);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    for (final p in pages) {
      p.dispose();
    }
    image.dispose();
    return png!.buffer.asUint8List();
  }
}
