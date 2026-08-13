import 'dart:math';

import 'package:flutter/material.dart';

import 'whatsapp_style.dart';

/// WhatsApp-style chat wallpaper: the base beige/charcoal tone with a soft
/// repeating doodle pattern painted on top.
class WhatsAppWallpaper extends StatelessWidget {
  const WhatsAppWallpaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final WhatsAppStyle style = WhatsAppStyle.of(context);
    return CustomPaint(
      painter: _WallpaperPainter(
        base: style.wallpaperBase,
        doodle: style.wallpaperDoodle,
      ),
      child: child,
    );
  }
}

class _WallpaperPainter extends CustomPainter {
  const _WallpaperPainter({required this.base, required this.doodle});

  final Color base;
  final Color doodle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    final Paint stroke = Paint()
      ..color = doodle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final Paint dot = Paint()..color = doodle;

    final Random random = Random(7);
    const double spacing = 36;
    for (double y = 0; y < size.height + spacing; y += spacing) {
      for (double x = 0; x < size.width + spacing; x += spacing) {
        final double cx = x + random.nextDouble() * 12;
        final double cy = y + random.nextDouble() * 12;
        switch (random.nextInt(4)) {
          case 0: // small outline circle
            canvas.drawCircle(
              Offset(cx, cy),
              3 + random.nextDouble() * 2,
              stroke,
            );
          case 1: // plus/cross
            canvas.drawLine(Offset(cx - 4, cy - 4), Offset(cx + 4, cy + 4),
                stroke);
            canvas.drawLine(Offset(cx + 4, cy - 4), Offset(cx - 4, cy + 4),
                stroke);
          case 2: // arc
            canvas.drawArc(
              Rect.fromCircle(center: Offset(cx, cy), radius: 5),
              0,
              pi * 1.5,
              false,
              stroke,
            );
          default: // filled dot
            canvas.drawCircle(Offset(cx, cy), 1.5, dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WallpaperPainter oldDelegate) =>
      oldDelegate.base != base || oldDelegate.doodle != doodle;
}
