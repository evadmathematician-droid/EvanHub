import 'dart:typed_data';

/// Pictures embedded in a hand-written Word (.docx) file: each [inline] call
/// returns the XML for one picture and remembers the file, and the builder
/// then adds [relationships] and [files] to the package. PNG and JPEG only;
/// anything else (or an unreadable file) is simply left out.
class DocxImages {
  final _pictures = <_Picture>[];

  /// Twips (1/1440 inch) to EMU (1/914400 inch).
  static const _emuPerTwip = 635;

  /// `<Default>` entries for `[Content_Types].xml`.
  static const contentTypes =
      '<Default Extension="png" ContentType="image/png"/>'
      '<Default Extension="jpeg" ContentType="image/jpeg"/>';

  /// One `<Relationship>` per picture, for `word/_rels/document.xml.rels`.
  String get relationships => [
        for (final p in _pictures)
          '<Relationship Id="${p.relId}" '
              'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
              'Target="media/${p.fileName}"/>',
      ].join();

  /// (`word/media/...` path, bytes) for every picture.
  Iterable<(String, Uint8List)> get files =>
      _pictures.map((p) => ('word/media/${p.fileName}', p.bytes));

  bool get isEmpty => _pictures.isEmpty;

  /// An inline picture run, scaled to fit a [boxW] × [boxH] twip box keeping
  /// its proportions — or, with [cover], filling the box and cropping the
  /// overflow evenly (a passport frame). Empty when [bytes] isn't a usable
  /// PNG / JPEG. The document needs the `r`, `wp`, `a` and `pic` namespaces.
  String inline(Uint8List? bytes, int boxW, int boxH, {bool cover = false}) {
    final p = _Picture.read(bytes);
    if (p == null) return '';
    final n = _pictures.length + 1;
    p
      ..fileName = 'image$n.${p.ext}'
      ..relId = 'rIdImg$n';
    _pictures.add(p);

    final sx = boxW / p.width, sy = boxH / p.height;
    final scale = cover ? (sx > sy ? sx : sy) : (sx < sy ? sx : sy);
    final w = cover ? boxW : (p.width * scale).round();
    final h = cover ? boxH : (p.height * scale).round();
    // Cropping (cover): the share of each side cut away, in 1/100000ths.
    var crop = '';
    if (cover) {
      final cutX = ((1 - boxW / (p.width * scale)) / 2 * 100000).round();
      final cutY = ((1 - boxH / (p.height * scale)) / 2 * 100000).round();
      if (cutX > 0 || cutY > 0) {
        crop = '<a:srcRect l="$cutX" t="$cutY" r="$cutX" b="$cutY"/>';
      }
    }
    final cx = w * _emuPerTwip, cy = h * _emuPerTwip;
    return '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$n" name="Picture $n"/>'
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic><pic:nvPicPr><pic:cNvPr id="$n" name="${p.fileName}"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="${p.relId}"/>$crop<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
        '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';
  }

  /// Namespace declarations for a `<w:document>` that holds pictures.
  static const namespaces =
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"';
}

/// A PNG or JPEG with its pixel size, read from the file header.
class _Picture {
  _Picture(this.bytes, this.ext, this.width, this.height);

  final Uint8List bytes;
  final String ext;
  final int width;
  final int height;
  late String fileName;
  late String relId;

  static _Picture? read(Uint8List? b) {
    if (b == null || b.length < 24) return null;
    int be16(int i) => (b[i] << 8) | b[i + 1];
    int be32(int i) =>
        (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    // PNG: signature, then the IHDR chunk with width and height.
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      final w = be32(16), h = be32(20);
      return w > 0 && h > 0 ? _Picture(b, 'png', w, h) : null;
    }
    // JPEG: walk the segments to the frame header (SOF0–SOF15).
    if (b[0] == 0xFF && b[1] == 0xD8) {
      var i = 2;
      while (i + 9 < b.length) {
        if (b[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = b[i + 1];
        if (marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC) {
          final h = be16(i + 5), w = be16(i + 7);
          return w > 0 && h > 0 ? _Picture(b, 'jpeg', w, h) : null;
        }
        if (marker == 0xD8 ||
            marker == 0x01 ||
            (marker >= 0xD0 && marker <= 0xD7)) {
          i += 2;
          continue;
        }
        i += 2 + be16(i + 2);
      }
    }
    return null;
  }
}
