import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'docx_export.dart';
import 'pdf_export.dart';
import 'register_export.dart';
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
/// [isDate] marks a column of dd/MM/yyyy dates, which the register layout
/// writes to Excel as real date cells.
class ExportColumn {
  const ExportColumn(this.title, {this.flex = 2, this.isDate = false});

  final String title;
  final double flex;
  final bool isDate;
}

/// How the table is laid out. [standard] is used by every list; [register]
/// is the full pupils register (many columns): landscape, small type, a
/// letterhead with the badge on every PDF page, a frozen, filterable header
/// row in Excel, and narrow margins in Word.
enum ExportLayout { standard, register }

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
    this.layout = ExportLayout.standard,
    this.heading,
    this.schoolAddress = '',
    this.logo,
    this.rowPhotos,
  }) : generatedAt = generatedAt ?? DateTime.now();

  final String schoolName;
  final String title;
  final List<String> filters;
  final List<ExportColumn> columns;
  final List<List<String>> rows;
  final DateTime generatedAt;

  final ExportLayout layout;

  /// Register layout only: the title printed on the pages (e.g. "Pupils
  /// Register - Class 4"); [title] still names the file.
  final String? heading;

  /// Register layout only: the school's address and badge for the letterhead.
  final String schoolAddress;
  final Uint8List? logo;

  /// Register layout only: a small passport photo per row (same order as
  /// [rows]), shown as the first column in PDF and Word. Null for no photo
  /// column; a null entry leaves that row's cell empty.
  final List<Uint8List?>? rowPhotos;

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

  /// Builds the file on a background isolate so a long list doesn't freeze
  /// the screen (on web, where isolates aren't available, it runs inline).
  Future<Uint8List> build(ExportFormat format) =>
      compute(_buildExport, (this, format));
}

Future<Uint8List> _buildExport((ExportTable, ExportFormat) job) async {
  final (table, format) = job;
  if (table.layout == ExportLayout.register) {
    return switch (format) {
      ExportFormat.pdf => await buildRegisterPdf(table),
      ExportFormat.word => buildRegisterDocx(table),
      ExportFormat.excel => buildRegisterXlsx(table),
    };
  }
  return switch (format) {
    ExportFormat.pdf => await buildPdf(table),
    ExportFormat.word => buildDocx(table),
    ExportFormat.excel => buildXlsx(table),
  };
}
