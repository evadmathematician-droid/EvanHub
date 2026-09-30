import 'dart:typed_data';

import 'package:intl/intl.dart';

import 'docx_export.dart';
import 'pdf_export.dart';
import 'xlsx_export.dart';

/// The file types a list screen can print / export to.
enum ExportFormat {
  pdf('PDF', 'pdf', 'application/pdf'),
  word('Word', 'docx',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
  excel('Excel', 'xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');

  const ExportFormat(this.label, this.extension, this.mimeType);

  final String label;
  final String extension;
  final String mimeType;
}

/// One column of an exported table. [flex] sets its share of the page width.
class ExportColumn {
  const ExportColumn(this.title, {this.flex = 2});

  final String title;
  final double flex;
}

/// A list screen's records as a table, ready to become a PDF, Word or Excel
/// file. Every format has the same layout:
///
///   SCHOOL NAME                (heading)
///   Students                   (title)
///   Primary | Class 4 | Active (the filters in use)
///   Date: 30 Sep 2026, 14:05        Total: 24
///   ┌─────┬──────────┬────── …
///   │ No. │ Name     │ …           (a "No." column is added automatically)
class ExportTable {
  ExportTable({
    required this.schoolName,
    required this.title,
    required this.columns,
    required this.rows,
    this.filters = const [],
    DateTime? generatedAt,
  }) : generatedAt = generatedAt ?? DateTime.now();

  final String schoolName;
  final String title;
  final List<String> filters;
  final List<ExportColumn> columns;
  final List<List<String>> rows;
  final DateTime generatedAt;

  /// Wide tables print sideways.
  bool get landscape => columns.length > 6;

  String get filterLine => filters.join('  |  ');

  String get dateText => DateFormat('d MMM yyyy, HH:mm').format(generatedAt);

  String get totalText => 'Total: ${rows.length}';

  /// Columns and rows with the "No." column in front.
  List<ExportColumn> get numberedColumns =>
      [const ExportColumn('No.', flex: 0.7), ...columns];

  List<List<String>> get numberedRows => [
        for (var i = 0; i < rows.length; i++) ['${i + 1}', ...rows[i]],
      ];

  /// e.g. "Students - Class 4 - Active - 2026-09-30.pdf". Characters that
  /// file systems reject are removed.
  String fileName(ExportFormat format) {
    final base = [
      title,
      ...filters,
      DateFormat('yyyy-MM-dd').format(generatedAt),
    ].join(' - ').replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    return '$base.${format.extension}';
  }

  Future<Uint8List> build(ExportFormat format) async => switch (format) {
        ExportFormat.pdf => await buildPdf(this),
        ExportFormat.word => buildDocx(this),
        ExportFormat.excel => buildXlsx(this),
      };
}
