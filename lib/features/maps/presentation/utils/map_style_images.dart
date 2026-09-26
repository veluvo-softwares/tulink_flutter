import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Icons Tulink draws itself and registers on the map style.
///
/// Mapbox style sprites differ between styles and versions: the Maki
/// `triangle-stroked-15` icon that earlier code relied on does not exist in
/// the v12 Streets/Outdoors/Satellite sprites, so a SymbolLayer using it
/// rendered nothing. Registering our own images removes that dependency.
/// Images belong to the style, so they must be re-registered whenever the
/// style or map surface is replaced; [ensureMapStyleImage] is idempotent.
const navigationPuckImageId = 'tulink-navigation-puck';
const headingArrowImageId = 'tulink-heading-arrow';

/// Pixel density the images are drawn at; Mapbox scales them to points.
const double _imageScale = 3.0;

/// Registers [imageId] on the current style if it is missing and reports
/// whether the style now has it. Never throws.
Future<bool> ensureMapStyleImage(MapboxMap map, String imageId) async {
  try {
    if (await map.style.hasStyleImage(imageId)) return true;
    final image = switch (imageId) {
      navigationPuckImageId => await _drawNavigationPuck(),
      headingArrowImageId => await _drawHeadingArrow(),
      _ => null,
    };
    if (image == null) return false;
    await map.style.addStyleImage(
      imageId,
      _imageScale,
      image,
      false,
      const [],
      const [],
      null,
    );
    return await map.style.hasStyleImage(imageId);
  } catch (_) {
    return false;
  }
}

/// A blue disc with a white border and a white arrow pointing north; the
/// layer rotates it by heading.
Future<MbxImage> _drawNavigationPuck() {
  const logicalSize = 34.0;
  return _render(logicalSize, (canvas, size) {
    final center = ui.Offset(size / 2, size / 2);
    final radius = size / 2;
    canvas.drawCircle(
      center,
      radius,
      ui.Paint()..color = const ui.Color(0x33000000),
    );
    canvas.drawCircle(
      center,
      radius * 0.92,
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      center,
      radius * 0.76,
      ui.Paint()..color = const ui.Color(0xFF1E6FFF),
    );
    final arrow = ui.Path()
      ..moveTo(center.dx, center.dy - radius * 0.52)
      ..lineTo(center.dx + radius * 0.36, center.dy + radius * 0.38)
      ..lineTo(center.dx, center.dy + radius * 0.2)
      ..lineTo(center.dx - radius * 0.36, center.dy + radius * 0.38)
      ..close();
    canvas.drawPath(arrow, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  });
}

/// A small north-pointing triangle used as a convoy member heading tip.
Future<MbxImage> _drawHeadingArrow() {
  const logicalSize = 18.0;
  return _render(logicalSize, (canvas, size) {
    final path = ui.Path()
      ..moveTo(size / 2, size * 0.08)
      ..lineTo(size * 0.9, size * 0.9)
      ..lineTo(size / 2, size * 0.7)
      ..lineTo(size * 0.1, size * 0.9)
      ..close();
    canvas.drawPath(path, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    canvas.drawPath(
      path,
      ui.Paint()
        ..color = const ui.Color(0xFF1F2933)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = size * 0.08
        ..strokeJoin = ui.StrokeJoin.round,
    );
  });
}

Future<MbxImage> _render(
  double logicalSize,
  void Function(ui.Canvas canvas, double size) paint,
) async {
  final pixels = (logicalSize * _imageScale).round();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paint(canvas, pixels.toDouble());
  final picture = recorder.endRecording();
  final image = await picture.toImage(pixels, pixels);
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    // The platform plugins decode `data` as an encoded image (PNG), matching
    // the SDK example, despite the raw-RGBA wording in its API docs.
    return MbxImage(
      width: pixels,
      height: pixels,
      data: Uint8List.view(png!.buffer),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}
