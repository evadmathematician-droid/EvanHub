import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'export_table.dart';

/// Brand colours (see `AppColors`), repeated here because the pdf package
/// has its own colour type.
final _primary = PdfColor.fromHex('#2E3192');
final _stripe = PdfColor.fromHex('#F1F2FA');
final _line = PdfColor.fromHex('#C5C8D6');
final _muted = PdfColor.fromHex('#5E6470');

/// The built-in PDF font covers Latin-1 only; anything else would print as a
/// blank box, so it is replaced with "?".
String _safe(String s) => String.fromCharCodes(
    s.runes.map((r) => r <= 0xFF ? r : 0x3F));

/// A4 PDF: school name as the heading, then the title, filters, date and
/// total, then the table. The table's header row repeats on every page and
/// each page is numbered.
Future<Uint8List> buildPdf(ExportTable t) async {
  final columns = t.numberedColumns;
  final doc = pw.Document(title: t.title, author: t.schoolName);

  doc.addPage(pw.MultiPage(
    pageFormat: t.landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 24),
    footer: (context) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(_safe('${t.schoolName}  |  ${t.title}'),
              style: pw.TextStyle(fontSize: 8, color: _muted)),
          pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 8, color: _muted)),
        ],
      ),
    ),
    build: (context) => [
      pw.Center(
        child: pw.Text(
          _safe(t.schoolName.toUpperCase()),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
              fontSize: 18, fontWeight: pw.FontWeight.bold, color: _primary),
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Center(
        child: pw.Text(_safe(t.title),
            style:
                pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      ),
      if (t.filters.isNotEmpty) ...[
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(_safe(t.filterLine),
              style: pw.TextStyle(fontSize: 10, color: _muted)),
        ),
      ],
      pw.SizedBox(height: 10),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Date: ${t.dateText}', style: const pw.TextStyle(fontSize: 9)),
          pw.Text(t.totalText,
              style:
                  pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        headers: [for (final c in columns) _safe(c.title)],
        data: [
          for (final row in t.numberedRows) [for (final v in row) _safe(v)],
        ],
        columnWidths: {
          for (var i = 0; i < columns.length; i++)
            i: pw.FlexColumnWidth(columns[i].flex),
        },
        border: pw.TableBorder.all(color: _line, width: 0.5),
        headerDecoration: pw.BoxDecoration(color: _primary),
        headerStyle: pw.TextStyle(
            fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerAlignment: pw.Alignment.centerLeft,
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignment: pw.Alignment.centerLeft,
        cellAlignments: {0: pw.Alignment.center},
        headerAlignments: {0: pw.Alignment.center},
        cellPadding:
            const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        oddRowDecoration: pw.BoxDecoration(color: _stripe),
      ),
      if (t.rows.isEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.all(12),
          child: pw.Center(
            child: pw.Text('No records match these filters.',
                style: pw.TextStyle(fontSize: 10, color: _muted)),
          ),
        ),
    ],
  ));

  return doc.save();
}
