import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'report_card_data.dart';
import 'report_card_texts.dart';

/// The bundled Liberation fonts (assets/fonts), so the PDF prints offline
/// with curly quotes and dashes. If they can't be loaded the built-in
/// Times / Helvetica are used and [unicode] is false: text is then reduced
/// to plain quotes and hyphens, which those fonts can print.
class ReportCardFonts {
  const ReportCardFonts._({
    required this.serif,
    required this.serifBold,
    required this.serifItalic,
    required this.serifBoldItalic,
    required this.sans,
    required this.sansBold,
    required this.unicode,
  });

  final pw.Font serif;
  final pw.Font serifBold;
  final pw.Font serifItalic;
  final pw.Font serifBoldItalic;
  final pw.Font sans;
  final pw.Font sansBold;
  final bool unicode;

  static ReportCardFonts? _cached;

  static Future<ReportCardFonts> load() async {
    if (_cached != null) return _cached!;
    try {
      Future<pw.Font> ttf(String name) async =>
          pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
      final fonts = await Future.wait([
        ttf('LiberationSerif-Regular'),
        ttf('LiberationSerif-Bold'),
        ttf('LiberationSerif-Italic'),
        ttf('LiberationSerif-BoldItalic'),
        ttf('LiberationSans-Regular'),
        ttf('LiberationSans-Bold'),
      ]);
      return _cached = ReportCardFonts._(
        serif: fonts[0],
        serifBold: fonts[1],
        serifItalic: fonts[2],
        serifBoldItalic: fonts[3],
        sans: fonts[4],
        sansBold: fonts[5],
        unicode: true,
      );
    } catch (e) {
      debugPrint('Report cards: bundled fonts unavailable, using built-in: $e');
      return builtIn();
    }
  }

  /// Times / Helvetica, built into every PDF reader (Latin-1 only).
  static ReportCardFonts builtIn() => ReportCardFonts._(
        serif: pw.Font.times(),
        serifBold: pw.Font.timesBold(),
        serifItalic: pw.Font.timesItalic(),
        serifBoldItalic: pw.Font.timesBoldItalic(),
        sans: pw.Font.helvetica(),
        sansBold: pw.Font.helveticaBold(),
        unicode: false,
      );

  /// [s] as these fonts can print it.
  String text(String s) {
    if (unicode) return s;
    final plain = s
        .replaceAll(RegExp('[“”„]'), '"')
        .replaceAll(RegExp('[‘’]'), "'")
        .replaceAll(RegExp('[–—]'), '-')
        .replaceAll('…', '...');
    return String.fromCharCodes(plain.runes.map((r) => r <= 0xFF ? r : 0x3F));
  }
}

/// Everything shared by every page of one export: fonts and the decoded
/// logo (decoded once and reused, so a 30-page PDF holds the image once).
class ReportCardAssets {
  ReportCardAssets(this.fonts, {Uint8List? logoBytes})
      : logo = _image(logoBytes);

  final ReportCardFonts fonts;
  final pw.ImageProvider? logo;

  ReportCardAssets withoutLogo() => ReportCardAssets(fonts);

  static pw.ImageProvider? _image(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return pw.MemoryImage(bytes);
    } catch (e) {
      debugPrint('Report cards: logo could not be read: $e');
      return null;
    }
  }
}

final _red = PdfColor.fromHex('#D00000');
final _blue = PdfColor.fromHex('#0033CC');
final _green = PdfColor.fromHex('#008000');
const _black = PdfColors.black;

/// One complete A4 landscape cover page (the back of the folded card) for
/// [pupil]: star border; key + notice on the left; important points in the
/// middle; school, pupil, form and [principal] on the right. Later the
/// inside (results) pages are added after this for each pupil.
pw.Page buildCoverPage(
  ReportCardPupil pupil,
  ReportCardSchool school,
  ReportLevel level,
  String principal, {
  required ReportCardAssets assets,
}) {
  final f = assets.fonts;
  return pw.Page(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: pw.EdgeInsets.zero,
    build: (_) => pw.Stack(
      fit: pw.StackFit.expand,
      children: [
        pw.CustomPaint(painter: _paintStarBorder),
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(28, 26, 28, 26),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Expanded(flex: 32, child: _leftPanel(f)),
              pw.SizedBox(width: 10),
              pw.Expanded(flex: 24, child: _middlePanel(f)),
              pw.SizedBox(width: 10),
              pw.Expanded(
                flex: 40,
                child: _rightPanel(pupil, school, level, principal, assets),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The PDF for a whole class: one cover page per pupil, in the order given.
/// An unreadable logo never stops the export: the cards are then made
/// without it. Throws [ArgumentError] for an empty list.
Future<Uint8List> buildReportCardsPdf({
  required List<ReportCardPupil> pupils,
  required ReportCardSchool school,
  required ReportLevel level,
  required String principal,
  ReportCardFonts? fonts,
}) async {
  if (pupils.isEmpty) {
    throw ArgumentError.value(pupils, 'pupils', 'No pupils to print');
  }
  final assets =
      ReportCardAssets(fonts ?? await ReportCardFonts.load(), logoBytes: school.logo);

  Future<Uint8List> build(ReportCardAssets a) {
    final doc = pw.Document(
      title: '${pupils.first.form.label} Report Cards',
      creator: 'Evangelist Global',
    );
    for (final p in pupils) {
      doc.addPage(buildCoverPage(p, school, level, principal, assets: a));
    }
    return doc.save();
  }

  try {
    return await build(assets);
  } catch (e) {
    if (assets.logo == null) rethrow;
    debugPrint('Report cards: logo failed in the PDF, retrying without: $e');
    return build(assets.withoutLogo());
  }
}

// --- Star border ------------------------------------------------------------

/// Small black five-pointed stars all round the page edge, drawn as shapes.
void _paintStarBorder(PdfGraphics canvas, PdfPoint size) {
  const inset = 12.0; // page edge to star centres
  const radius = 4.6;
  const step = 13.0;

  final w = size.x - 2 * inset;
  final h = size.y - 2 * inset;
  final nx = math.max(1, (w / step).round());
  final ny = math.max(1, (h / step).round());

  canvas.setFillColor(_black);
  for (var i = 0; i <= nx; i++) {
    final x = inset + w * i / nx;
    _star(canvas, x, inset, radius);
    _star(canvas, x, size.y - inset, radius);
  }
  for (var j = 1; j < ny; j++) {
    final y = inset + h * j / ny;
    _star(canvas, inset, y, radius);
    _star(canvas, size.x - inset, y, radius);
  }
  canvas.fillPath();
}

void _star(PdfGraphics canvas, double cx, double cy, double r) {
  const inner = 0.382; // a regular five-pointed star
  for (var i = 0; i < 10; i++) {
    // PDF y points up, so 90° is the top point.
    final angle = math.pi / 2 + i * math.pi / 5;
    final len = i.isEven ? r : r * inner;
    final x = cx + len * math.cos(angle);
    final y = cy + len * math.sin(angle);
    i == 0 ? canvas.moveTo(x, y) : canvas.lineTo(x, y);
  }
  canvas.closePath();
}

// --- Left panel -------------------------------------------------------------

/// The key box takes two thirds of the panel height and the notice box the
/// last third. The wording is fixed (ReportCardTexts), so the sizes below
/// are chosen to fill each box without overflowing it.
pw.Widget _leftPanel(ReportCardFonts f) {
  const size = 9.0;
  final plain = pw.TextStyle(font: f.sans, fontSize: size, lineSpacing: 1.6);
  final heading = pw.TextStyle(
    font: f.sansBold,
    fontSize: size + 0.5,
    decoration: pw.TextDecoration.underline,
  );

  pw.Widget lines(List<String> items) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [for (final l in items) pw.Text(f.text(l), style: plain)],
      );

  pw.Widget headed(String title, String note) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 1.5),
        child: pw.RichText(
          text: pw.TextSpan(children: [
            pw.TextSpan(text: f.text(title), style: heading),
            pw.TextSpan(text: f.text(note), style: plain),
          ]),
        ),
      );

  pw.Widget section(String title, String note, List<String> items) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [headed(title, note), lines(items)],
      );

  // The sections are spread over the box height.
  final keyBox = pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(8, 7, 8, 7),
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 3.5)),
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(f.text(ReportCardTexts.keyLine), style: plain),
        section(ReportCardTexts.affectiveHeading, '', ReportCardTexts.affective),
        section(ReportCardTexts.psychomotorHeading,
            ReportCardTexts.psychomotorNote, ReportCardTexts.psychomotor),
        section(ReportCardTexts.cognitiveHeading,
            ReportCardTexts.cognitiveNote, ReportCardTexts.cognitive),
        pw.Text(f.text(ReportCardTexts.ratings), style: plain),
      ],
    ),
  );

  final noticeStyle =
      pw.TextStyle(font: f.sans, fontSize: 7.4, lineSpacing: 0.9);
  final noticeBox = pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(9, 6, 9, 6),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(width: 3, style: pw.BorderStyle.dashed),
    ),
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          f.text(ReportCardTexts.noticeHeading),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: f.sansBold, fontSize: 8.5),
        ),
        for (final para in ReportCardTexts.notice)
          pw.Text(f.text(para),
              style: noticeStyle, textAlign: pw.TextAlign.justify),
      ],
    ),
  );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Expanded(flex: 2, child: keyBox),
      pw.SizedBox(height: 8),
      pw.Expanded(flex: 1, child: noticeBox),
    ],
  );
}

// --- Middle panel -----------------------------------------------------------

pw.Widget _middlePanel(ReportCardFonts f) {
  final style = pw.TextStyle(font: f.sans, fontSize: 8, lineSpacing: 1.6);
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(9, 12, 9, 12),
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          f.text(ReportCardTexts.pointsHeading),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            font: f.sansBold,
            fontSize: 9,
            decoration: pw.TextDecoration.underline,
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < ReportCardTexts.points.length; i++)
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: 12,
                      child: pw.Text('${i + 1}.', style: style),
                    ),
                    pw.Expanded(
                      child: pw.Text(f.text(ReportCardTexts.points[i]),
                          style: style),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

// --- Right panel ------------------------------------------------------------

/// One line of text in [height], its font size reduced until it fits the
/// available width. The text is measured, not scaled and clipped (some PDF
/// viewers cut scaled text off: "EVANGELIST ACADE").
pw.Widget _fitLine(String text, pw.TextStyle style,
        {required double height,
        pw.Alignment alignment = pw.Alignment.center}) =>
    pw.SizedBox(
      height: height,
      child: pw.LayoutBuilder(builder: (context, constraints) {
        final size = style.fontSize!;
        final maxWidth = constraints?.maxWidth ?? double.infinity;
        final unitWidth =
            style.font!.getFont(context).stringMetrics(text).advanceWidth;
        // A little spare width, so rounding never wraps the line.
        final fitted = unitWidth <= 0 || !maxWidth.isFinite
            ? size
            : math.min(size, maxWidth * 0.97 / unitWidth);
        return pw.Align(
          alignment: alignment,
          child: pw.Text(text, style: style.copyWith(fontSize: fitted)),
        );
      }),
    );

/// The school name as one or two lines: split at the space nearest the
/// middle when it is too long for one.
List<String> _nameLines(String name) {
  final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (name.length <= 20 || words.length < 2) return [name];
  var best = 1;
  var bestDiff = 1 << 30;
  for (var i = 1; i < words.length; i++) {
    final diff = (words.take(i).join(' ').length -
            words.skip(i).join(' ').length)
        .abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = i;
    }
  }
  return [words.take(best).join(' '), words.skip(best).join(' ')];
}

/// Stands in for the school badge when it could not be downloaded: a
/// circle outline marked "SCHOOL BADGE".
pw.Widget _logoPlaceholder(ReportCardFonts f) => pw.AspectRatio(
      aspectRatio: 1,
      child: pw.Container(
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          border: pw.Border.all(width: 1.5, color: PdfColors.grey600),
        ),
        alignment: pw.Alignment.center,
        child: pw.Text(
          f.text('SCHOOL\nBADGE'),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
              font: f.sansBold, fontSize: 11, color: PdfColors.grey600),
        ),
      ),
    );

pw.Widget _rightPanel(
  ReportCardPupil pupil,
  ReportCardSchool school,
  ReportLevel level,
  String principal,
  ReportCardAssets assets,
) {
  final f = assets.fonts;
  pw.TextStyle serifBold(double size, {PdfColor color = _black}) =>
      pw.TextStyle(font: f.serifBold, fontSize: size, color: color);

  final name = school.nameWithoutLevel.toUpperCase();
  final nameLines = name.isEmpty ? const <String>[] : _nameLines(name);
  final twoLines = nameLines.length > 1;
  final motto = school.motto.trim().replaceAll(RegExp('^["“”]+|["“”]+\$'), '');
  final admission = pupil.admissionNo.trim();
  final principalName = principal.trim();

  final children = <pw.Widget>[
    for (final line in nameLines)
      _fitLine(f.text(line), serifBold(twoLines ? 24 : 30),
          height: twoLines ? 27 : 34),
    pw.SizedBox(height: 2),
    _fitLine(f.text(level.levelLine), serifBold(15), height: 18),
    if (school.town.isNotEmpty)
      _fitLine(f.text(school.town.toUpperCase()), serifBold(12.5), height: 15),
    if (school.district.isNotEmpty)
      _fitLine(
        f.text(school.district.toUpperCase()),
        pw.TextStyle(font: f.serifBoldItalic, fontSize: 12.5),
        height: 15,
      ),

    // The crest takes whatever height is left, centred; a plain badge
    // outline when it could not be downloaded.
    pw.Expanded(
      child: pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Center(
          child: pw.ConstrainedBox(
            constraints:
                const pw.BoxConstraints(maxHeight: 140, maxWidth: 160),
            child: assets.logo == null
                ? _logoPlaceholder(f)
                : pw.Image(assets.logo!, fit: pw.BoxFit.contain),
          ),
        ),
      ),
    ),

    if (motto.isNotEmpty)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.RichText(
          textAlign: pw.TextAlign.center,
          maxLines: 2,
          text: pw.TextSpan(children: [
            pw.TextSpan(
                text: f.text(ReportCardTexts.mottoLabel),
                style: pw.TextStyle(font: f.serif, fontSize: 11.5)),
            pw.TextSpan(text: f.text('“$motto”'), style: serifBold(11.5)),
          ]),
        ),
      ),

    pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 2.5)),
      child: pw.Column(
        children: [
          pw.Text(
            f.text(ReportCardTexts.foundedLabel +
                (school.founded.isEmpty
                    ? ReportCardTexts.dots
                    : school.founded)),
            style: pw.TextStyle(font: f.sansBold, fontSize: 10.5),
          ),
          pw.SizedBox(height: 2),
          _fitLine(f.text(ReportCardTexts.assessmentLine), serifBold(13.5),
              height: 17),
        ],
      ),
    ),
    pw.SizedBox(height: 10),

    // Name of Pupil: CONTEH AMARA PATRICK (red, on a green line)
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(f.text(ReportCardTexts.pupilNameLabel), style: serifBold(11)),
        pw.Expanded(
          child: pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border(
                  bottom: pw.BorderSide(color: _green, width: 1.4)),
            ),
            child: _fitLine(
              f.text(pupil.printedName),
              serifBold(14, color: _red),
              height: 17,
              alignment: pw.Alignment.centerLeft,
            ),
          ),
        ),
      ],
    ),
    pw.SizedBox(height: 7),

    // Admission Number: …      Form: JSS-2
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(f.text(ReportCardTexts.admissionLabel), style: serifBold(9.5)),
        pw.Expanded(
          child: _fitLine(
            f.text(admission.isEmpty ? ReportCardTexts.dots : admission),
            serifBold(11, color: admission.isEmpty ? _black : _red),
            height: 14,
            alignment: pw.Alignment.centerLeft,
          ),
        ),
        pw.SizedBox(width: 6),
        pw.Text(f.text(ReportCardTexts.formLabel), style: serifBold(10)),
        pw.Text(
          f.text(pupil.form.label),
          style: serifBold(12, color: _blue).copyWith(
            decoration: pw.TextDecoration.underline,
            decorationColor: _blue,
          ),
        ),
      ],
    ),
    pw.SizedBox(height: 12),

    _fitLine(
      f.text(principalName.isEmpty ? ReportCardTexts.dots : principalName),
      serifBold(13),
      height: 16,
    ),
    pw.Text(
      f.text(ReportCardTexts.principalLabel),
      style: pw.TextStyle(font: f.serifBoldItalic, fontSize: 12),
    ),
  ];

  return pw.Container(
    padding: const pw.EdgeInsets.all(2.5),
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 3)),
    child: pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: children,
      ),
    ),
  );
}
