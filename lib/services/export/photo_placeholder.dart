import 'dart:typed_data';
import 'dart:ui' as ui;

/// A passport-shaped "No Photo" picture (grey silhouette and label) for
/// exports of pupils whose photo isn't available. Drawn once, then reused.
Future<Uint8List?> photoPlaceholderPng() => _cached ??= _draw();

Future<Uint8List?>? _cached;

Future<Uint8List?> _draw() async {
  try {
    const w = 300.0, h = 385.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, w, h),
        ui.Paint()..color = const ui.Color(0xFFE8E9F6));

    final grey = ui.Paint()..color = const ui.Color(0xFFB4B9C4);
    // Head.
    canvas.drawCircle(const ui.Offset(w / 2, 120), 58, grey);
    // Shoulders: the top of an ellipse, cut off above the label.
    canvas.save();
    canvas.clipRect(const ui.Rect.fromLTWH(0, 0, w, 300));
    canvas.drawOval(
        const ui.Rect.fromLTWH(w / 2 - 105, 192, 210, 220), grey);
    canvas.restore();

    final paragraph = (ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: ui.TextAlign.center,
      fontSize: 34,
      fontWeight: ui.FontWeight.w700,
    ))
          ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF5E6470)))
          ..addText('No Photo'))
        .build()
      ..layout(const ui.ParagraphConstraints(width: w));
    canvas.drawParagraph(paragraph, ui.Offset(0, 318 - paragraph.height / 2 + 12));

    final image =
        await recorder.endRecording().toImage(w.toInt(), h.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    _cached = null;
    return null; // The export then falls back to its plain "No photo" box.
  }
}
