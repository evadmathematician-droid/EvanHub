import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'export_table.dart';

/// An Excel (.xlsx) sheet: school name, title, filters and date/total in
/// merged rows across the top, then a bordered table with a coloured header
/// row. The "No." column holds real numbers so the sheet sorts correctly.
Uint8List buildXlsx(ExportTable t) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet()!;
  // Sheet names: max 31 characters, no []:*?/\ .
  var sheetName = t.title.replaceAll(RegExp(r'[\[\]:*?/\\]'), '').trim();
  if (sheetName.isEmpty) sheetName = 'Sheet';
  if (sheetName.length > 31) sheetName = sheetName.substring(0, 31);
  final sheet = excel[sheetName];
  excel.setDefaultSheet(sheetName);
  if (defaultSheet != sheetName) excel.delete(defaultSheet);

  final columns = t.numberedColumns;
  final last = columns.length - 1;
  final thin = Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: ExcelColor.fromHexString('#FFC5C8D6'));

  CellIndex at(int col, int row) =>
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row);

  var row = 0;
  void banner(String text, CellStyle style) {
    sheet.updateCell(at(0, row), TextCellValue(text), cellStyle: style);
    sheet.merge(at(0, row), at(last, row));
    row++;
  }

  banner(
      t.schoolName.toUpperCase(),
      CellStyle(
        bold: true,
        fontSize: 16,
        fontColorHex: ExcelColor.fromHexString('#FF2E3192'),
        horizontalAlign: HorizontalAlign.Center,
      ));
  banner(
      t.title,
      CellStyle(
          bold: true, fontSize: 13, horizontalAlign: HorizontalAlign.Center));
  if (t.filters.isNotEmpty) {
    banner(
        t.filterLine,
        CellStyle(
          fontColorHex: ExcelColor.fromHexString('#FF5E6470'),
          horizontalAlign: HorizontalAlign.Center,
        ));
  }
  banner('Date: ${t.dateText}     ${t.totalText}',
      CellStyle(horizontalAlign: HorizontalAlign.Center));
  row++; // blank line before the table

  final headerStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('#FF2E3192'),
    leftBorder: thin,
    rightBorder: thin,
    topBorder: thin,
    bottomBorder: thin,
  );
  for (var c = 0; c < columns.length; c++) {
    sheet.updateCell(at(c, row), TextCellValue(columns[c].title),
        cellStyle: headerStyle);
  }
  row++;

  final plain = CellStyle(
      leftBorder: thin, rightBorder: thin, topBorder: thin, bottomBorder: thin);
  final striped = CellStyle(
    backgroundColorHex: ExcelColor.fromHexString('#FFF1F2FA'),
    leftBorder: thin,
    rightBorder: thin,
    topBorder: thin,
    bottomBorder: thin,
  );
  final rows = t.numberedRows;
  for (var r = 0; r < rows.length; r++) {
    final style = r.isOdd ? striped : plain;
    for (var c = 0; c < columns.length; c++) {
      final value = rows[r][c];
      sheet.updateCell(
        at(c, row),
        c == 0 ? IntCellValue(r + 1) : TextCellValue(value),
        cellStyle: style,
      );
    }
    row++;
  }

  for (var c = 0; c < columns.length; c++) {
    sheet.setColumnWidth(c, c == 0 ? 6 : 8 + columns[c].flex * 6);
  }

  return Uint8List.fromList(excel.encode()!);
}
