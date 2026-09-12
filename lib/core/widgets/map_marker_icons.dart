import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Canvas-generated marker icons so every pin is visually distinct
/// (Uber / Bolt style):
/// - Pickup: plain green disc with a white ring (no lettering).
/// - Dropoff: red teardrop pin.
/// - Stops: numbered badges — white/black while pending, green when
///   completed, blue when arrived. Numbers are always kept.
/// - Driver: dark badge with a white car glyph.
/// - User: blue location dot with halo.
///
/// [scale] lets [PlatformMap] shrink/grow pins per map-zoom bucket so they
/// stay proportionate instead of one fixed giant size. Icons are cached
/// in-memory by (key, scale-bucket); callers get an instant hue fallback
/// from [PlatformMap] while the bitmap generates.
class MapMarkerIcons {
  const MapMarkerIcons._();

  static final Map<String, BitmapDescriptor> _cache = {};

  static String bucket(double zoom) {
    if (zoom < 11) return 'far';
    if (zoom < 14) return 'mid';
    if (zoom < 16.5) return 'near';
    return 'close';
  }

  static double bucketScale(String bucket) {
    switch (bucket) {
      case 'far':
        return 0.62;
      case 'mid':
        return 0.78;
      case 'close':
        return 1.12;
      case 'near':
      default:
        return 0.9;
    }
  }

  static Future<BitmapDescriptor> _cached(
    String key,
    Future<Uint8List> Function() draw,
  ) async {
    final hit = _cache[key];
    if (hit != null) return hit;
    final bytes = await draw();
    final icon = BitmapDescriptor.fromBytes(bytes);
    _cache[key] = icon;
    return icon;
  }

  /// Draw the design at a fixed coordinate space, then scale the whole
  /// canvas so glyphs, rings and text stay proportionate.
  static Future<Uint8List> _render(
    double w,
    double h,
    double scale,
    void Function(Canvas c) paint,
  ) async {
    final pic = ui.PictureRecorder();
    final c = Canvas(pic);
    c.scale(scale, scale);
    paint(c);
    return _toBytes(pic, (w * scale).round(), (h * scale).round());
  }

  static Future<BitmapDescriptor> pickup({double scale = 1}) =>
      _cached('pickup_$scale', () async {
        const size = 96.0;
        return _render(size, size, scale, (c) {
          // Plain green disc with white ring — no lettering.
          c.drawCircle(
            const Offset(size / 2, size / 2),
            42,
            Paint()..color = const Color(0xFF16A34A),
          );
          c.drawCircle(
            const Offset(size / 2, size / 2),
            42,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6,
          );
        });
      });

  static Future<BitmapDescriptor> dropoff({double scale = 1}) =>
      _cached('dropoff_$scale', () async {
        const w = 100.0;
        const h = 128.0;
        return _render(w, h, scale, (c) {
          final red = const Color(0xFFDC2626);
          final dark = const Color(0xFF991B1B);
          // Teardrop: round head + tail triangle.
          c.drawCircle(const Offset(w / 2, 44), 34, Paint()..color = red);
          final tail = Path()
            ..moveTo(w / 2 - 26, 62)
            ..lineTo(w / 2 + 26, 62)
            ..lineTo(w / 2, h - 6)
            ..close();
          c.drawPath(tail, Paint()..color = red);
          // Border ring around the head.
          c.drawCircle(
            const Offset(w / 2, 44),
            34,
            Paint()
              ..color = dark
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4,
          );
          // White hole in the middle (classic pin look).
          c.drawCircle(
            const Offset(w / 2, 44),
            13,
            Paint()..color = Colors.white,
          );
        });
      });

  static Future<BitmapDescriptor> stop({
    required int number,
    required Color bg,
    required Color fg,
    double scale = 1,
  }) =>
      _cached('stop_${number}_${bg.value}_${fg.value}_$scale', () async {
        const size = 96.0;
        const center = Offset(size / 2, size / 2);
        return _render(size, size, scale, (c) {
          // Black outer ring → bold numbered badge (number always kept).
          c.drawCircle(center, 42, Paint()..color = Colors.black);
          c.drawCircle(center, 35, Paint()..color = bg);
          _drawText(
            c,
            '$number',
            number > 9 ? 32 : 40,
            fg,
            center.translate(0, -1),
          );
        });
      });

  static Future<BitmapDescriptor> driver({double scale = 1}) =>
      _cached('driver_$scale', () async {
        const size = 104.0;
        const center = Offset(size / 2, size / 2);
        return _render(size, size, scale, (c) {
          // Dark navy disc with white ring (pops on any basemap).
          c.drawCircle(
            center,
            46,
            Paint()..color = const Color(0xFF0F172A),
          );
          c.drawCircle(
            center,
            46,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5,
          );
          // White side-view car glyph.
          const car = Colors.white;
          const glass = Color(0xFF0F172A);
          // Body.
          c.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(21, 51, 62, 18),
              const Radius.circular(6),
            ),
            Paint()..color = car,
          );
          // Cabin.
          c.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(36, 38, 28, 17),
              const Radius.circular(6),
            ),
            Paint()..color = car,
          );
          // Windows.
          c.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(39.5, 41, 21, 10.5),
              const Radius.circular(3.5),
            ),
            Paint()..color = glass,
          );
          // Wheels.
          for (final wx in [35.0, 69.0]) {
            c.drawCircle(Offset(wx, 70.5), 7.5, Paint()..color = glass);
            c.drawCircle(
              Offset(wx, 70.5),
              7.5,
              Paint()
                ..color = car
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3,
            );
          }
        });
      });

  static Future<BitmapDescriptor> userDot({double scale = 1}) =>
      _cached('user_$scale', () async {
        const size = 76.0;
        const center = Offset(size / 2, size / 2);
        return _render(size, size, scale, (c) {
          // Halo + blue dot with white ring (standard "you are here").
          c.drawCircle(
            center,
            34,
            Paint()..color = const Color(0x403B82F6),
          );
          c.drawCircle(
            center,
            20,
            Paint()..color = const Color(0xFF3B82F6),
          );
          c.drawCircle(
            center,
            20,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5,
          );
        });
      });

  static void _drawText(
    Canvas c,
    String text,
    double fontSize,
    Color color,
    Offset center,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    painter.paint(
      c,
      Offset(
        center.dx - painter.width / 2,
        center.dy - painter.height / 2,
      ),
    );
  }

  static Future<Uint8List> _toBytes(
    ui.PictureRecorder pic,
    int w,
    int h,
  ) async {
    final img = await pic.endRecording().toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }
}
