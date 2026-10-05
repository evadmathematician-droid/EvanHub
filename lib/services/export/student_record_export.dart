import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../models/student.dart';
import '../file_actions.dart';
import 'student_record_pdf.dart';

enum RecordFormat { pdf, png }

/// Builds a student's record as a PDF or a PNG image and hands it over:
/// the share sheet on phones, a download on the web.
class StudentRecordExport {
  StudentRecordExport._();

  /// `<StudentID>_<StudentName>_<yyyy-MM-dd>.pdf` (or `.png`), with anything
  /// that isn't a letter, digit or dash turned into `_`.
  static String fileName(Student s, DateTime at, RecordFormat format) {
    String clean(String v) => v
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final id = clean(s.admissionNo).isEmpty ? clean(s.id) : clean(s.admissionNo);
    final date = DateFormat('yyyy-MM-dd').format(at);
    return '${id}_${clean(s.fullName)}_$date.${format.name}';
  }

  static Future<Uint8List> build(
      StudentRecordData data, RecordFormat format) async {
    final pdf = await buildStudentRecordPdfSafely(data);
    return format == RecordFormat.pdf ? pdf : _toPng(pdf);
  }

  /// Shares (phones) or downloads (web) the file.
  static Future<void> deliver(
      String fileName, Uint8List bytes, RecordFormat format) {
    final mime = format == RecordFormat.pdf ? 'application/pdf' : 'image/png';
    if (kIsWeb) return FileActions.save(fileName, bytes, mimeType: mime);
    return FileActions.share(fileName, bytes, mimeType: mime);
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
