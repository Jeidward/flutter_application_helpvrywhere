import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Helpers for rendering custom map pins to PNG bytes that can be passed
/// directly to `PointAnnotationOptions.image` in mapbox_maps_flutter.
///
/// Two pin styles are provided:
///   - [buildUserAvatarMarker]   — circular avatar with initials (or icon
///                                 fallback) wrapped in a colored ring.
///                                 Used for the current volunteer.
///   - [buildNumberedRequestMarker] — orange numbered pin used for help
///                                    requests on the map.
///
/// Both render at 3x device scale internally so they stay crisp on
/// high-DPI screens.

const double _kPixelRatio = 3.0;

/// Generates a circular avatar marker. If [initials] is empty the person
/// icon is used as a fallback.
Future<Uint8List> buildUserAvatarMarker({
  String initials = '',
  Color ringColor = const Color(0xFF4A90E2),
  Color fillColor = const Color(0xFFBFD4F2),
  Color textColor = const Color(0xFF1F2A44),
  double diameter = 56,
}) async {
  final recorder = ui.PictureRecorder();
  final size = diameter * _kPixelRatio;
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

  final center = Offset(size / 2, size / 2);

  final shadowPaint = Paint()
    ..color = ringColor.withOpacity(0.25)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
  canvas.drawCircle(center, size / 2 - 4, shadowPaint);

  final ringPaint = Paint()..color = Colors.white;
  canvas.drawCircle(center, size / 2 - 4, ringPaint);

  final fillPaint = Paint()..color = fillColor;
  canvas.drawCircle(center, size / 2 - 10, fillPaint);

  if (initials.trim().isNotEmpty) {
    final tp = TextPainter(
      text: TextSpan(
        text: initials.trim().toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: size * 0.32,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  } else {
    final iconSize = size * 0.55;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.person.codePoint),
        style: TextStyle(
          fontFamily: Icons.person.fontFamily,
          package: Icons.person.fontPackage,
          color: textColor,
          fontSize: iconSize,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  return _pictureToPng(recorder, size);
}

/// Generates a numbered orange request pin (matches the Figma).
Future<Uint8List> buildNumberedRequestMarker({
  required int number,
  Color color = const Color(0xFFD2502A),
  double diameter = 36,
}) async {
  final recorder = ui.PictureRecorder();
  final size = diameter * _kPixelRatio;
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
  final center = Offset(size / 2, size / 2);

  final shadowPaint = Paint()
    ..color = Colors.black.withOpacity(0.25)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  canvas.drawCircle(center, size / 2 - 4, shadowPaint);

  canvas.drawCircle(center, size / 2 - 4, Paint()..color = Colors.white);
  canvas.drawCircle(center, size / 2 - 8, Paint()..color = color);

  final tp = TextPainter(
    text: TextSpan(
      text: '$number',
      style: TextStyle(
        color: Colors.white,
        fontSize: size * 0.42,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(
    canvas,
    Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
  );

  return _pictureToPng(recorder, size);
}

/// Generates a single destination pin (no number) for the directions view.
Future<Uint8List> buildDestinationMarker({
  Color color = const Color(0xFFD2502A),
  double diameter = 40,
}) async {
  final recorder = ui.PictureRecorder();
  final size = diameter * _kPixelRatio;
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
  final center = Offset(size / 2, size / 2);

  final shadowPaint = Paint()
    ..color = Colors.black.withOpacity(0.25)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
  canvas.drawCircle(center, size / 2 - 4, shadowPaint);

  canvas.drawCircle(center, size / 2 - 4, Paint()..color = Colors.white);
  canvas.drawCircle(center, size / 2 - 9, Paint()..color = color);
  canvas.drawCircle(center, size * 0.08, Paint()..color = Colors.white);

  return _pictureToPng(recorder, size);
}

Future<Uint8List> _pictureToPng(
    ui.PictureRecorder recorder, double size) async {
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

/// Computes 1- or 2-letter initials from a person's name.
String initialsFromName(String name) {
  final parts = name
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first.substring(0, 1);
  return parts.first.substring(0, 1) + parts.last.substring(0, 1);
}
