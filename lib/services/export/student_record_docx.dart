import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'docx_images.dart';
import 'student_record_content.dart';
import 'student_record_pdf.dart';

/// The student record as a Word (.docx) file, with the same content and
/// layout as the PDF (see [buildStudentRecordPdf]): letterhead with badge,
/// the photo beside the main details, every filled-in field, promotion
/// history, the certification box, signature line and stamp, and a footer
/// with the document reference. A4 portrait with narrow margins and 9–10 pt
/// text so it fits one page.
///
/// Written directly as Office Open XML, like the lists' Word export
/// (`docx_export.dart`), with the images embedded as pictures.
Uint8List buildStudentRecordDocx(StudentRecordData d) {
  final doc = _DocxWriter();
  final body = doc.body(d);
  final archive = Archive();
  void add(String name, List<int> bytes) =>
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
  void addText(String name, String xml) => add(name, utf8.encode(xml));

  addText('[Content_Types].xml', _contentTypes);
  addText('_rels/.rels', _rootRels);
  addText('word/document.xml', body);
  addText('word/footer1.xml', _footer(d));
  addText('word/_rels/document.xml.rels', doc.relationships());
  for (final (path, bytes) in doc.images.files) {
    add(path, bytes);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

// --- Writer ----------------------------------------------------------------

/// Dimensions are in twips (1/1440 inch).
class _DocxWriter {
  final images = DocxImages();

  /// A4 portrait, 1.1 cm side margins.
  static const _pageW = 11906;
  static const _pageH = 16838;
  static const _marginX = 624;
  static const _marginTop = 567;
  static const _marginBottom = 680;
  static const _usable = _pageW - 2 * _marginX;

  String relationships() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rIdFooter1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>'
      '${images.relationships}</Relationships>';

  /// An inline picture fitted to a [boxW] × [boxH] twip box (see
  /// [DocxImages.inline]). Empty when there is no usable image.
  String picture(Uint8List? bytes, int boxW, int boxH, {bool cover = false}) =>
      images.inline(bytes, boxW, boxH, cover: cover);

  String body(StudentRecordData d) {
    final sb = StringBuffer()
      ..write(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document '
        'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>',
      )
      ..write(_letterhead(d))
      ..write(
        _para(
          'STUDENT INFORMATION RECORD',
          size: 26,
          bold: true,
          color: _primary,
          align: 'center',
          before: 100,
          after: 100,
          spacing: 28,
        ),
      )
      ..write(_summary(d));
    for (final (title, rows) in recordSections(d)) {
      sb.write(_section(title, rows));
    }
    if (d.historyVisible && d.history.isNotEmpty) sb.write(_history(d.history));
    sb
      ..write(_certification(d))
      ..write(_authentication(d))
      ..write(
        '<w:sectPr><w:footerReference w:type="default" r:id="rIdFooter1"/>'
        '<w:pgSz w:w="$_pageW" w:h="$_pageH"/>'
        '<w:pgMar w:top="$_marginTop" w:right="$_marginX" w:bottom="$_marginBottom" '
        'w:left="$_marginX" w:header="340" w:footer="340" w:gutter="0"/></w:sectPr>'
        '</w:body></w:document>',
      );
    return sb.toString();
  }

  String _letterhead(StudentRecordData d) {
    const side = 1250;
    const center = _usable - 2 * side;
    final contact = contactLine(d);
    final middle = StringBuffer()
      ..write(
        _para(
          d.schoolName.trim().toUpperCase(),
          size: 38,
          bold: true,
          color: _primary,
          align: 'center',
          after: 20,
        ),
      );
    if (hasText(d.schoolAddress)) {
      middle.write(
        _para(d.schoolAddress.trim(), size: 20, align: 'center', after: 10),
      );
    }
    if (contact.isNotEmpty) {
      middle.write(
        _para(contact, size: 18, color: _muted, align: 'center', after: 10),
      );
    }
    if (hasText(d.motto)) {
      middle.write(
        _para(
          '"${d.motto.trim()}"',
          size: 20,
          italic: true,
          color: _primary,
          align: 'center',
          after: 0,
        ),
      );
    }
    final badge = picture(d.badge, side - 100, side - 100);
    final head = _table(
      [side, center, side],
      [
        _row([
          _cell(
            side,
            '<w:p><w:pPr><w:jc w:val="left"/></w:pPr>$badge</w:p>',
            vAlign: 'center',
          ),
          _cell(center, middle.toString(), vAlign: 'center'),
          _cell(side, '<w:p/>'),
        ]),
      ],
      borders: false,
    );
    // Double rule under the letterhead.
    return '$head<w:p><w:pPr><w:pBdr><w:bottom w:val="double" w:sz="6" w:space="1" '
        'w:color="$_primary"/></w:pBdr><w:spacing w:before="40" w:after="0"/>'
        '<w:rPr><w:sz w:val="4"/></w:rPr></w:pPr></w:p>';
  }

  String _summary(StudentRecordData d) {
    const photoW = 1600;
    const left = _usable - photoW;
    final details = StringBuffer()
      ..write(_para(d.student.fullName, size: 30, bold: true, after: 60));
    for (final (label, value) in recordSummary(d)) {
      details.write(
        '<w:p><w:pPr><w:spacing w:before="0" w:after="30"/></w:pPr>'
        '${_run('$label:  ', size: 19, color: _muted)}'
        '${_run(value, size: 21, bold: true)}</w:p>',
      );
    }
    // Passport-size frame (35 × 45 proportions) with a thin border; the
    // photo fills it, trimmed evenly if its shape differs.
    final photo = picture(d.photo, photoW - 140, 1930, cover: true);
    final photoCell = photo.isNotEmpty
        ? _cell(
            photoW,
            '<w:p><w:pPr><w:spacing w:before="0" w:after="0"/>'
            '<w:jc w:val="center"/></w:pPr>$photo</w:p>',
            borderColor: _muted,
          )
        : _cell(
            photoW,
            _para(
              'No photo',
              size: 17,
              color: _muted,
              align: 'center',
              after: 0,
            ),
            vAlign: 'center',
            fill: _band,
            borderColor: _line,
          );
    return _table(
      [left, photoW],
      [
        _row([
          _cell(left, details.toString()),
          photoCell,
        ], height: photo.isNotEmpty ? null : 1750),
      ],
      borders: false,
    );
  }

  String _section(String title, List<(String, String)> rows) {
    const labelW = 1900;
    const valueW = _usable ~/ 2 - labelW;
    final widths = [labelW, valueW, labelW, _usable - 2 * labelW - valueW];
    final trs = <String>[_bandRow(title, widths)];
    for (var i = 0; i < rows.length; i += 2) {
      final pair = rows.sublist(i, i + 2 > rows.length ? rows.length : i + 2);
      trs.add(
        _row([
          for (var k = 0; k < 2; k++) ...[
            _cell(
              widths[k * 2],
              _para(
                k < pair.length ? pair[k].$1 : '',
                size: 18,
                color: _muted,
                after: 0,
              ),
            ),
            _cell(
              widths[k * 2 + 1],
              _para(
                k < pair.length ? pair[k].$2 : '',
                size: 18,
                bold: true,
                after: 0,
              ),
            ),
          ],
        ]),
      );
    }
    return _table(widths, trs) + _gap(70);
  }

  String _history(List<HistoryLine> history) {
    const w = _usable ~/ 5;
    final widths = [w, w, w, w, _usable - 4 * w];
    final trs = <String>[
      _bandRow('PROMOTION HISTORY', widths),
      _row([
        for (final (i, h) in [
          'Year',
          'From class',
          'To class',
          'Result',
          'Date',
        ].indexed)
          _cell(
            widths[i],
            _para(h, size: 18, bold: true, after: 0),
            fill: _band,
          ),
      ], header: true),
      for (final h in history)
        _row([
          _cell(widths[0], _para(h.year, size: 18, after: 0)),
          _cell(widths[1], _para(h.from, size: 18, after: 0)),
          _cell(widths[2], _para(h.to, size: 18, after: 0)),
          _cell(widths[3], _para(h.outcome, size: 18, bold: true, after: 0)),
          _cell(widths[4], _para(h.date, size: 18, after: 0)),
        ]),
    ];
    return _table(widths, trs) + _gap(70);
  }

  String _certification(StudentRecordData d) {
    final content =
        _para(
          'CERTIFICATION',
          size: 20,
          bold: true,
          color: _primary,
          after: 40,
          spacing: 20,
        ) +
        _para(certificationText(d), size: 20, align: 'both', after: 0);
    return _table(
          [_usable],
          [
            _row([_cell(_usable, content)]),
          ],
          borderColor: _primary,
          borderSize: 8,
          cellMargin: 140,
        ) +
        _gap(200);
  }

  String _authentication(StudentRecordData d) {
    const stampBox = 1500;
    const right = 2400;
    const left = _usable - right;
    final sign = StringBuffer()
      ..write(_gap(360))
      ..write(
        _para('______________________________________', size: 20, after: 20),
      )
      ..write(
        _para('Head Teacher / Principal', size: 20, bold: true, after: 0),
      );
    if (hasText(d.headName)) {
      sign.write(_para(d.headName.trim(), size: 20, after: 0));
    }
    sign.write(
      _para('Date: ______________________', size: 20, before: 120, after: 0),
    );

    final stamp = picture(d.stamp, stampBox, stampBox);
    final stampXml = stamp.isNotEmpty
        ? '<w:p><w:pPr><w:jc w:val="right"/></w:pPr>$stamp</w:p>'
        // A dashed "Official Stamp" box, right-aligned.
        : '${_table(
            [stampBox],
            [
              _row(
                [_cell(
                  stampBox,
                  _para('Official Stamp', size: 18, color: _muted, align: 'center', after: 0),
                  vAlign: 'center',
                )],
                height: stampBox,
                exact: true,
              ),
            ],
            borderColor: _muted,
            borderStyle: 'dashed',
            align: 'right',
          )}<w:p/>';
    return _table(
      [left, right],
      [
        _row([
          _cell(left, sign.toString(), vAlign: 'bottom'),
          _cell(right, stampXml, vAlign: 'bottom'),
        ]),
      ],
      borders: false,
    );
  }

  String _bandRow(String title, List<int> widths) => _row([
    '<w:tc><w:tcPr><w:tcW w:w="${widths.reduce((a, b) => a + b)}" w:type="dxa"/>'
        '<w:gridSpan w:val="${widths.length}"/>'
        '<w:shd w:val="clear" w:color="auto" w:fill="$_primary"/></w:tcPr>'
        '${_para(title, size: 18, bold: true, color: 'FFFFFF', after: 0, spacing: 16)}</w:tc>',
  ], header: true);
}

// --- XML helpers -----------------------------------------------------------

const _primary = '2E3192';
const _band = 'E8E9F6';
const _line = 'C5C8D6';
const _muted = '5E6470';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// One run of text. [size] is in half-points (Word's unit); [spacing] is
/// extra letter spacing in twentieths of a point.
String _run(
  String text, {
  int size = 20,
  bool bold = false,
  bool italic = false,
  String? color,
  int spacing = 0,
}) =>
    '<w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/>'
    '${bold ? '<w:b/>' : ''}${italic ? '<w:i/>' : ''}'
    '${color == null ? '' : '<w:color w:val="$color"/>'}'
    '${spacing == 0 ? '' : '<w:spacing w:val="$spacing"/>'}'
    '<w:sz w:val="$size"/><w:szCs w:val="$size"/></w:rPr>'
    '<w:t xml:space="preserve">${_esc(text)}</w:t></w:r>';

String _para(
  String text, {
  int size = 20,
  bool bold = false,
  bool italic = false,
  String? color,
  String align = 'left',
  int before = 0,
  int after = 40,
  int spacing = 0,
}) =>
    '<w:p><w:pPr>'
    '<w:spacing w:before="$before" w:after="$after" w:line="240" w:lineRule="auto"/>'
    '<w:jc w:val="$align"/></w:pPr>'
    '${_run(text, size: size, bold: bold, italic: italic, color: color, spacing: spacing)}</w:p>';

/// An empty paragraph [twips] tall.
String _gap(int twips) =>
    '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="$twips" w:lineRule="exact"/>'
    '<w:rPr><w:sz w:val="2"/></w:rPr></w:pPr></w:p>';

String _cell(
  int width,
  String content, {
  String? vAlign,
  String? fill,
  String? borderColor,
}) {
  final borders = borderColor == null
      ? ''
      : '<w:tcBorders><w:top w:val="single" w:sz="4" w:color="$borderColor"/>'
            '<w:left w:val="single" w:sz="4" w:color="$borderColor"/>'
            '<w:bottom w:val="single" w:sz="4" w:color="$borderColor"/>'
            '<w:right w:val="single" w:sz="4" w:color="$borderColor"/></w:tcBorders>';
  return '<w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/>$borders'
      '${fill == null ? '' : '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>'}'
      '${vAlign == null ? '' : '<w:vAlign w:val="$vAlign"/>'}</w:tcPr>$content</w:tc>';
}

String _row(
  List<String> cells, {
  bool header = false,
  int? height,
  bool exact = false,
}) =>
    '<w:tr><w:trPr><w:cantSplit/>${header ? '<w:tblHeader/>' : ''}'
    '${height == null ? '' : '<w:trHeight w:val="$height" w:hRule="${exact ? 'exact' : 'atLeast'}"/>'}'
    '</w:trPr>${cells.join()}</w:tr>';

String _table(
  List<int> widths,
  List<String> rows, {
  bool borders = true,
  String borderColor = _line,
  int borderSize = 4,
  String borderStyle = 'single',
  int cellMargin = 70,
  String align = 'left',
}) {
  final total = widths.reduce((a, b) => a + b);
  final b =
      'w:val="$borderStyle" w:sz="$borderSize" w:space="0" w:color="$borderColor"';
  final none = 'w:val="nil"';
  final edge = borders ? b : none;
  return '<w:tbl><w:tblPr><w:tblW w:w="$total" w:type="dxa"/><w:jc w:val="$align"/>'
      '<w:tblBorders><w:top $edge/><w:left $edge/><w:bottom $edge/><w:right $edge/>'
      '<w:insideH $edge/><w:insideV $edge/></w:tblBorders>'
      '<w:tblLayout w:type="fixed"/>'
      '<w:tblCellMar><w:top w:w="${cellMargin ~/ 3}" w:type="dxa"/>'
      '<w:left w:w="$cellMargin" w:type="dxa"/>'
      '<w:bottom w:w="${cellMargin ~/ 3}" w:type="dxa"/>'
      '<w:right w:w="$cellMargin" w:type="dxa"/></w:tblCellMar>'
      '</w:tblPr><w:tblGrid>${[for (final w in widths) '<w:gridCol w:w="$w"/>'].join()}'
      '</w:tblGrid>${rows.join()}</w:tbl>';
}

String _footer(StudentRecordData d) {
  const usable = _DocxWriter._usable;
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:p><w:pPr><w:pBdr><w:top w:val="single" w:sz="4" w:space="2" w:color="$_line"/></w:pBdr>'
      '<w:tabs><w:tab w:val="right" w:pos="$usable"/></w:tabs>'
      '<w:spacing w:before="0" w:after="0"/></w:pPr>'
      '${_run('Generated by Evangelist Global on ${exportedAtText(d)}', size: 15, color: _muted)}'
      '<w:r><w:tab/></w:r>'
      '${_run('Ref: ${d.reference}', size: 15, color: _muted)}'
      '</w:p></w:ftr>';
}

const _contentTypes =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="png" ContentType="image/png"/>'
    '<Default Extension="jpeg" ContentType="image/jpeg"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
    '</Types>';

const _rootRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '</Relationships>';
