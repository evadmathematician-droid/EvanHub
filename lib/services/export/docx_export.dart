import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'export_table.dart';

/// A Word (.docx) file: school name as the heading, then the title, filters,
/// date and total, then a bordered table whose coloured header row repeats
/// on every page. Written directly as Office Open XML (a .docx is a zip of
/// XML files), so no template is needed.
Uint8List buildDocx(ExportTable t) {
  final archive = Archive();
  void add(String name, String xml) {
    final bytes = utf8.encode(xml);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('[Content_Types].xml', _contentTypes);
  add('_rels/.rels', _rels);
  add('word/document.xml', _document(t));
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

const _contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '</Types>';

const _rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '</Relationships>';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// A paragraph with one run. [size] is in half-points (Word's unit).
String _para(
  String text, {
  int size = 20,
  bool bold = false,
  String? color,
  String align = 'left',
  int after = 60,
}) =>
    '<w:p><w:pPr><w:jc w:val="$align"/><w:spacing w:before="0" w:after="$after"/></w:pPr>'
    '<w:r><w:rPr>${bold ? '<w:b/>' : ''}'
    '${color == null ? '' : '<w:color w:val="$color"/>'}'
    '<w:sz w:val="$size"/></w:rPr>'
    '<w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p>';

String _cell(String text, int width,
        {bool header = false, String? fill, String align = 'left'}) =>
    '<w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/>'
    '${fill == null ? '' : '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>'}'
    '<w:vAlign w:val="center"/></w:tcPr>'
    '<w:p><w:pPr><w:jc w:val="$align"/><w:spacing w:before="40" w:after="40"/></w:pPr>'
    '<w:r><w:rPr>${header ? '<w:b/><w:color w:val="FFFFFF"/>' : ''}<w:sz w:val="18"/></w:rPr>'
    '<w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p></w:tc>';

String _document(ExportTable t) {
  // A4 in twips (1/1440 inch) with 2 cm margins.
  final pageW = t.landscape ? 16838 : 11906;
  final pageH = t.landscape ? 11906 : 16838;
  const margin = 1134;
  final usable = pageW - 2 * margin;

  final columns = t.numberedColumns;
  final totalFlex = columns.fold<double>(0, (sum, c) => sum + c.flex);
  final widths = [for (final c in columns) (usable * c.flex / totalFlex).floor()];

  const border = 'w:val="single" w:sz="4" w:space="0" w:color="C5C8D6"';
  final table = StringBuffer()
    ..write('<w:tbl><w:tblPr><w:tblW w:w="$usable" w:type="dxa"/>'
        '<w:tblBorders><w:top $border/><w:left $border/><w:bottom $border/>'
        '<w:right $border/><w:insideH $border/><w:insideV $border/></w:tblBorders>'
        '<w:tblLayout w:type="fixed"/>'
        '<w:tblCellMar><w:left w:w="80" w:type="dxa"/><w:right w:w="80" w:type="dxa"/></w:tblCellMar>'
        '</w:tblPr><w:tblGrid>')
    ..writeAll([for (final w in widths) '<w:gridCol w:w="$w"/>'])
    ..write('</w:tblGrid>')
    // Header row, repeated at the top of every page.
    ..write('<w:tr><w:trPr><w:tblHeader/><w:cantSplit/></w:trPr>')
    ..writeAll([
      for (var i = 0; i < columns.length; i++)
        _cell(columns[i].title, widths[i],
            header: true, fill: '2E3192', align: i == 0 ? 'center' : 'left'),
    ])
    ..write('</w:tr>');

  final rows = t.numberedRows;
  for (var r = 0; r < rows.length; r++) {
    table.write('<w:tr><w:trPr><w:cantSplit/></w:trPr>');
    for (var i = 0; i < columns.length; i++) {
      table.write(_cell(rows[r][i], widths[i],
          fill: r.isOdd ? 'F1F2FA' : null, align: i == 0 ? 'center' : 'left'));
    }
    table.write('</w:tr>');
  }
  table.write('</w:tbl>');

  // Date on the left, total on the right, via a right-aligned tab stop.
  final dateTotal = '<w:p><w:pPr><w:tabs><w:tab w:val="right" w:pos="$usable"/></w:tabs>'
      '<w:spacing w:before="120" w:after="80"/></w:pPr>'
      '<w:r><w:rPr><w:sz w:val="18"/></w:rPr><w:t xml:space="preserve">Date: ${_esc(t.dateText)}</w:t></w:r>'
      '<w:r><w:rPr><w:b/><w:sz w:val="18"/></w:rPr><w:tab/><w:t>${_esc(t.totalText)}</w:t></w:r></w:p>';

  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>'
      '${_para(t.schoolName.toUpperCase(), size: 36, bold: true, color: '2E3192', align: 'center', after: 40)}'
      '${_para(t.title, size: 28, bold: true, align: 'center', after: 20)}'
      '${t.filters.isEmpty ? '' : _para(t.filterLine, size: 20, color: '5E6470', align: 'center', after: 20)}'
      '$dateTotal'
      '$table'
      '${t.rows.isEmpty ? _para('No records match these filters.', size: 20, color: '5E6470', align: 'center') : ''}'
      '<w:sectPr><w:pgSz w:w="$pageW" w:h="$pageH"${t.landscape ? ' w:orient="landscape"' : ''}/>'
      '<w:pgMar w:top="$margin" w:right="$margin" w:bottom="$margin" w:left="$margin" '
      'w:header="567" w:footer="567" w:gutter="0"/></w:sectPr>'
      '</w:body></w:document>';
}
