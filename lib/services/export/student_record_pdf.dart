import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/student.dart';
import 'student_record_content.dart';

/// One line of a student's promotion history, already in words.
class HistoryLine {
  const HistoryLine({
    required this.year,
    required this.from,
    required this.to,
    required this.outcome,
    required this.date,
  });

  final String year;
  final String from;
  final String to;
  final String outcome;
  final String date;
}

/// Everything the student record PDF prints. Images are raw JPG/PNG bytes;
/// any of them may be missing.
class StudentRecordData {
  const StudentRecordData({
    required this.student,
    required this.className,
    required this.history,
    required this.schoolName,
    required this.exportedAt,
    this.schoolId = '',
    this.historyVisible = true,
    this.schoolAddress = '',
    this.schoolPhone = '',
    this.schoolEmail = '',
    this.motto = '',
    this.headName = '',
    this.badge,
    this.stamp,
    this.photo,
  });

  final Student student;
  final String className;
  final List<HistoryLine> history;

  /// False for users who may not read promotion history (teachers).
  final bool historyVisible;

  /// The signed-in user's own school (multi-tenant): used for the document
  /// reference when the school name gives no letters.
  final String schoolId;
  final String schoolName;
  final String schoolAddress;
  final String schoolPhone;
  final String schoolEmail;

  /// Printed in italics under the address; the line is left out when empty.
  final String motto;

  /// Head Teacher / Principal, printed under the signature line.
  final String headName;
  final Uint8List? badge;
  final Uint8List? stamp;
  final Uint8List? photo;
  final DateTime exportedAt;

  /// `<schoolCode>-<studentId>-<yyyyMMddHHmm>`, e.g. `EMS-EG2024017-202610051430`.
  /// The school code is the initials of the school name (up to 4 letters),
  /// or the start of the school id when the name has no letters.
  String get reference {
    final initials = schoolName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(w[0]))
        .map((w) => w[0].toUpperCase())
        .take(4)
        .join();
    final code = initials.isNotEmpty
        ? initials
        : _alnum(schoolId).toUpperCase().padRight(4, 'X').substring(0, 4);
    final id = _alnum(student.admissionNo).isNotEmpty
        ? _alnum(student.admissionNo).toUpperCase()
        : _alnum(student.id).toUpperCase();
    return '$code-$id-${DateFormat('yyyyMMddHHmm').format(exportedAt)}';
  }

  /// The same record with no images, for when an image can't be decoded.
  StudentRecordData withoutImages() => StudentRecordData(
        student: student,
        className: className,
        history: history,
        historyVisible: historyVisible,
        schoolId: schoolId,
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        schoolPhone: schoolPhone,
        schoolEmail: schoolEmail,
        motto: motto,
        headName: headName,
        exportedAt: exportedAt,
      );
}

String _alnum(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');

/// Brand colours (see `AppColors`), repeated here because the pdf package
/// has its own colour type.
final _primary = PdfColor.fromHex('#2E3192');
final _band = PdfColor.fromHex('#E8E9F6');
final _line = PdfColor.fromHex('#C5C8D6');
final _muted = PdfColor.fromHex('#5E6470');


/// The built-in PDF font covers Latin-1 only; anything else would print as a
/// blank box, so it is replaced with "?".
String _safe(String s) =>
    String.fromCharCodes(s.runes.map((r) => r <= 0xFF ? r : 0x3F));

bool _has(String? s) => s != null && s.trim().isNotEmpty;

/// A4 "STUDENT INFORMATION RECORD", laid out to fit one page: letterhead
/// (badge, school name, address, contacts, motto), the student's details
/// with photo, every filled-in field in compact tables, promotion history,
/// the certification box, signature line and stamp, and a footer with the
/// document reference. Only a very long promotion history runs onto a
/// second page, which then gets a small repeated header and page numbers.
Future<Uint8List> buildStudentRecordPdf(StudentRecordData d) async {
  final s = d.student;
  final doc = pw.Document(
    title: _safe('Student record - ${s.fullName}'),
    author: _safe(d.schoolName),
    creator: 'Evangelist Global',
  );
  pw.ImageProvider? image(Uint8List? bytes) =>
      bytes == null ? null : pw.MemoryImage(bytes);

  final badge = image(d.badge);
  final stamp = image(d.stamp);
  final photo = image(d.photo);
  final exported = _safe(exportedAtText(d));
  final reference = _safe(d.reference);

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(32, 26, 32, 20),
    header: (context) => context.pageNumber == 1
        ? pw.SizedBox()
        : _smallHeader(d, context.pageNumber),
    footer: (context) => _footer(context, exported, reference),
    build: (context) => [
      _letterhead(d, badge),
      pw.SizedBox(height: 8),
      pw.Center(
        child: pw.Text('STUDENT INFORMATION RECORD',
            style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.4,
                color: _primary)),
      ),
      pw.SizedBox(height: 8),
      _summary(d, photo),
      pw.SizedBox(height: 8),
      ..._sections(d),
      if (d.historyVisible && d.history.isNotEmpty) _history(d.history),
      pw.SizedBox(height: 4),
      _certification(d),
      pw.SizedBox(height: 14),
      _authentication(d, stamp),
    ],
  ));
  return doc.save();
}

/// [buildStudentRecordPdf], falling back to a copy without images if one of
/// them is corrupt or in a format the PDF can't hold — an export should
/// never fail just because of a picture.
Future<Uint8List> buildStudentRecordPdfSafely(StudentRecordData d) async {
  try {
    return await buildStudentRecordPdf(d);
  } catch (_) {
    return buildStudentRecordPdf(d.withoutImages());
  }
}

pw.Widget _letterhead(StudentRecordData d, pw.ImageProvider? badge) {
  final contact = contactLine(d);
  const side = 62.0;
  return pw.Column(
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SizedBox(
            width: side,
            height: side,
            child: badge == null
                ? null
                : pw.Image(badge, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.Text(_safe(d.schoolName.trim().toUpperCase()),
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                        fontSize: 19,
                        fontWeight: pw.FontWeight.bold,
                        color: _primary)),
                if (_has(d.schoolAddress)) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(_safe(d.schoolAddress.trim()),
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 10)),
                ],
                if (contact.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(_safe(contact),
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(fontSize: 9, color: _muted)),
                ],
                if (_has(d.motto)) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(_safe('"${d.motto.trim()}"'),
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontStyle: pw.FontStyle.italic,
                          color: _primary)),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          // Balances the badge so the name stays centred on the page.
          pw.SizedBox(width: side),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Divider(color: _primary, thickness: 1.8, height: 1.8),
      pw.SizedBox(height: 1.5),
      pw.Divider(color: _primary, thickness: 0.5, height: 0.5),
    ],
  );
}

/// Pages 2+ only: the school name and title in one small line.
pw.Widget _smallHeader(StudentRecordData d, int page) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 3),
      decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _primary, width: 1))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(_safe(d.schoolName.trim().toUpperCase()),
              style: pw.TextStyle(
                  fontSize: 9, fontWeight: pw.FontWeight.bold, color: _primary)),
          pw.Text(
              _safe('Student Information Record - ${d.student.fullName} '
                  '(continued)'),
              style: pw.TextStyle(fontSize: 8, color: _muted)),
        ],
      ),
    );

pw.Widget _footer(pw.Context context, String exported, String reference) =>
    pw.Container(
      margin: const pw.EdgeInsets.only(top: 6),
      padding: const pw.EdgeInsets.only(top: 3),
      decoration: pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _line, width: 0.5))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Generated by Evangelist Global on $exported',
              style: pw.TextStyle(fontSize: 7.5, color: _muted)),
          pw.Text(
              context.pagesCount > 1
                  ? 'Ref: $reference   |   Page ${context.pageNumber} of '
                      '${context.pagesCount}'
                  : 'Ref: $reference',
              style: pw.TextStyle(fontSize: 7.5, color: _muted)),
        ],
      ),
    );

/// Name, ID, class and status beside the photo (top-right).
pw.Widget _summary(StudentRecordData d, pw.ImageProvider? photo) {
  final s = d.student;
  pw.Widget line(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.RichText(
          text: pw.TextSpan(children: [
            pw.TextSpan(
                text: '$label:  ',
                style: pw.TextStyle(fontSize: 9.5, color: _muted)),
            pw.TextSpan(
                text: _safe(value.trim()),
                style: pw.TextStyle(
                    fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
      );
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(_safe(s.fullName),
                style: pw.TextStyle(
                    fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            for (final (label, value) in recordSummary(d)) line(label, value),
          ],
        ),
      ),
      pw.SizedBox(width: 12),
      pw.Container(
        width: 78,
        height: 94,
        decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _line), color: _band),
        child: photo != null
            ? pw.Image(photo, fit: pw.BoxFit.cover)
            : pw.Center(
                child: pw.Text('No photo',
                    style: pw.TextStyle(fontSize: 8.5, color: _muted))),
      ),
    ],
  );
}

/// Every filled-in field, grouped as in the app's details popup (see
/// [recordSections]).
List<pw.Widget> _sections(StudentRecordData d) => [
      for (final (title, rows) in recordSections(d)) _section(title, rows),
    ];

/// A banded heading, then label / value pairs two to a row.
pw.Widget _section(String title, List<(String, String)> rows) {
  final cells = <pw.TableRow>[];
  for (var i = 0; i < rows.length; i += 2) {
    final pair = rows.sublist(i, i + 2 > rows.length ? rows.length : i + 2);
    cells.add(pw.TableRow(children: [
      for (final (label, value) in pair) ...[
        _cell(label, muted: true),
        _cell(value.trim(), bold: true),
      ],
      if (pair.length == 1) ...[_cell(''), _cell('')],
    ]));
  }
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _sectionBand(title),
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.05),
            1: pw.FlexColumnWidth(1.65),
            2: pw.FlexColumnWidth(1.05),
            3: pw.FlexColumnWidth(1.65),
          },
          children: cells,
        ),
      ],
    ),
  );
}

pw.Widget _history(List<HistoryLine> history) {
  const header = ['Year', 'From class', 'To class', 'Result', 'Date'];
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _sectionBand('PROMOTION HISTORY'),
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.5),
          children: [
            pw.TableRow(
              repeat: true,
              decoration: pw.BoxDecoration(color: _band),
              children: [for (final h in header) _cell(h, bold: true)],
            ),
            for (final h in history)
              pw.TableRow(children: [
                _cell(h.year),
                _cell(h.from),
                _cell(h.to),
                _cell(h.outcome, bold: true),
                _cell(h.date),
              ]),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _certification(StudentRecordData d) {
  final text = certificationText(d);
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(10, 7, 10, 8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _primary, width: 0.9),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('CERTIFICATION',
            style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1,
                color: _primary)),
        pw.SizedBox(height: 3),
        pw.Text(_safe(text),
            textAlign: pw.TextAlign.justify,
            style: const pw.TextStyle(fontSize: 10, lineSpacing: 2)),
      ],
    ),
  );
}

/// Signature line on the left, stamp (or a dashed "Official Stamp" box) on
/// the right.
pw.Widget _authentication(StudentRecordData d, pw.ImageProvider? stamp) {
  const box = 92.0;
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 26),
          pw.Container(width: 190, height: 0.8, color: PdfColors.black),
          pw.SizedBox(height: 3),
          pw.Text('Head Teacher / Principal',
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold)),
          if (_has(d.headName))
            pw.Text(_safe(d.headName.trim()),
                style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 8),
          pw.Text('Date: ____________________',
              style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
      stamp != null
          ? pw.SizedBox(
              width: box,
              height: box,
              child: pw.Image(stamp, fit: pw.BoxFit.contain))
          : pw.Container(
              width: box,
              height: box,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                    color: _muted, width: 0.8, style: pw.BorderStyle.dashed),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Center(
                child: pw.Text('Official Stamp',
                    style: pw.TextStyle(fontSize: 9, color: _muted)),
              ),
            ),
    ],
  );
}

pw.Widget _sectionBand(String title) => pw.Container(
      color: _primary,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      child: pw.Text(title,
          style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.8)),
    );

pw.Widget _cell(String text, {bool bold = false, bool muted = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: pw.Text(_safe(text),
          style: pw.TextStyle(
            fontSize: 9.5,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: muted ? _muted : null,
          )),
    );
