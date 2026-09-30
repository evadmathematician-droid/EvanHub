// Print / export: PDF, Word and Excel files built from an ExportTable.
// Set EXPORT_SAMPLES=<folder> to also write the three files there to look at.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evangelistglobal/services/export/export_table.dart';

void main() {
  final table = ExportTable(
    schoolName: 'Evangelist Global Academy',
    title: 'Students',
    filters: const ['Primary', 'Class 4', 'Active'],
    columns: const [
      ExportColumn('Name', flex: 4),
      ExportColumn('Admission no.', flex: 2),
      ExportColumn('Class', flex: 2),
      ExportColumn('Gender', flex: 1.5),
      ExportColumn('Status', flex: 1.5),
    ],
    rows: [
      for (var i = 1; i <= 60; i++)
        [
          i == 3 ? 'Fatmata <Tia> & Sesay' : 'Pupil Number $i Kamara',
          'EG/2026/${i.toString().padLeft(3, '0')}',
          i.isEven ? 'Class 4 A' : 'Class 4 B',
          i.isEven ? 'Female' : 'Male',
          'Active',
        ],
    ],
    generatedAt: DateTime(2026, 9, 30, 14, 5),
  );

  final samples = Platform.environment['EXPORT_SAMPLES'];
  Future<void> keep(ExportFormat f, List<int> bytes) async {
    if (samples != null) {
      await File('$samples/${table.fileName(f)}').writeAsBytes(bytes);
    }
  }

  test('file names carry the title, filters and date', () {
    expect(table.fileName(ExportFormat.pdf),
        'Students - Primary - Class 4 - Active - 2026-09-30.pdf');
    final odd = ExportTable(
        schoolName: 'S', title: 'A/B: C?', columns: const [], rows: const []);
    expect(odd.fileName(ExportFormat.excel), startsWith('AB C - '));
  });

  test('PDF', () async {
    final bytes = await table.build(ExportFormat.pdf);
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    await keep(ExportFormat.pdf, bytes);
  });

  test('Word: heading, numbered rows, repeating header, escaped text',
      () async {
    final bytes = await table.build(ExportFormat.word);
    final zip = ZipDecoder().decodeBytes(bytes);
    expect(zip.findFile('[Content_Types].xml'), isNotNull);
    final xml = utf8.decode(zip.findFile('word/document.xml')!.content);
    expect(xml, contains('EVANGELIST GLOBAL ACADEMY'));
    expect(xml, contains('Primary  |  Class 4  |  Active'));
    expect(xml, contains('Total: 60'));
    expect(xml, contains('<w:tblHeader/>'));
    expect(xml, contains('Fatmata &lt;Tia&gt; &amp; Sesay'));
    expect('<w:tr>'.allMatches(xml).length, 61); // header + 60 rows
    await keep(ExportFormat.word, bytes);
  });

  test('Excel: heading rows, header row and data', () async {
    final bytes = await table.build(ExportFormat.excel);
    final excel = Excel.decodeBytes(bytes);
    expect(excel.tables.keys, ['Students']);
    final sheet = excel.tables['Students']!;
    String text(int col, int row) =>
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
            .value
            .toString();
    expect(text(0, 0), 'EVANGELIST GLOBAL ACADEMY');
    expect(text(0, 1), 'Students');
    expect(text(0, 2), 'Primary  |  Class 4  |  Active');
    // Row 3: date and total, row 4 blank, row 5 the table header.
    expect(text(0, 5), 'No.');
    expect(text(1, 5), 'Name');
    expect(text(1, 6), 'Pupil Number 1 Kamara');
    expect(sheet.maxRows, 6 + 60);
    await keep(ExportFormat.excel, bytes);
  });
}
