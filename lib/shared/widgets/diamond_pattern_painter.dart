// lib/shared/widgets/diamond_pattern_painter.dart
//
// Subtle diamond-grid background texture used behind Pusaka-styled canvas /
// header surfaces (floor-plan canvas, reservation tile headers, etc.).
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class DiamondPatternPainter extends CustomPainter {
  final double step;
  final Color? color;

  const DiamondPatternPainter({this.step = 22, this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (color ?? AppColors.border).withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (double y = -step; y < size.height + step; y += step) {
      for (double x = -step; x < size.width + step; x += step) {
        final path = Path()
          ..moveTo(x, y - 5)
          ..lineTo(x + 5, y)
          ..lineTo(x, y + 5)
          ..lineTo(x - 5, y)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DiamondPatternPainter oldDelegate) =>
      oldDelegate.step != step || oldDelegate.color != color;
}
