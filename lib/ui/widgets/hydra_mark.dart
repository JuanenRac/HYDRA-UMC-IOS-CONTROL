// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - ui/widgets/hydra_mark.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
// =============================================================================

import 'package:flutter/material.dart';

/// The mark of HYDRA-UMC (a hexagon with an H and a stem), drawn in code so that
/// the start-up and the sign-in need no picture. Same drawing as the logo of the
/// Android app.
class HydraMark extends StatelessWidget {
  const HydraMark({super.key, this.size = 84});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HydraMarkPainter()),
    );
  }
}

class _HydraMarkPainter extends CustomPainter {
  static const _green = Color(0xFF2E7D32);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 240.0;
    Offset p(double x, double y) => Offset(x * k, y * k);

    final hex = Path()
      ..moveTo(120 * k, 20 * k)
      ..lineTo(220 * k, 77.7 * k)
      ..lineTo(220 * k, 193.2 * k)
      ..lineTo(120 * k, 220 * k)
      ..lineTo(20 * k, 193.2 * k)
      ..lineTo(20 * k, 77.7 * k)
      ..close();
    final green = Paint()
      ..color = _green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12 * k
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(hex, green);
    canvas.drawLine(p(120, 20), p(120, 60), green);

    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20 * k
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(p(70, 90), p(70, 160), white);
    canvas.drawLine(p(170, 90), p(170, 160), white);
    canvas.drawLine(p(70, 125), p(170, 125), white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
