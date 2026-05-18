import 'dart:math' as math;
import 'package:flutter/material.dart';

class TrajectoryPainter extends CustomPainter {
  final double leftMotor;
  final double rightMotor;

  const TrajectoryPainter({
    required this.leftMotor,
    required this.rightMotor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const deadZone = 0.03;

    final left = leftMotor.clamp(-1.0, 1.0).toDouble();
    final right = rightMotor.clamp(-1.0, 1.0).toDouble();

    if (left.abs() < deadZone && right.abs() < deadZone) {
      return;
    }

    final averagePower = ((left + right) / 2).abs().clamp(0.22, 1.0).toDouble();

    // Сырая разница между моторами.
    final rawSteer = ((left - right) / 2).clamp(-1.0, 1.0).toDouble();

    /*
     * ВАЖНО:
     * Рулевой ноль. Если разница между слайдерами маленькая,
     * считаем, что дрон едет прямо.
     *
     * Поэтому при 100% и 97% траектория больше не будет ломаться.
     */
    const steeringDeadZone = 0.08;

    double steer = 0.0;

    if (rawSteer.abs() > steeringDeadZone) {
      final normalized =
          ((rawSteer.abs() - steeringDeadZone) / (1.0 - steeringDeadZone))
              .clamp(0.0, 1.0)
              .toDouble();

      steer = rawSteer.sign * _smoothStep(normalized);
    }

    // Верхний предел: траектория наземная, не уходит к верху экрана.
    final startY = size.height * 0.94;
    final farY = _lerp(size.height * 0.72, size.height * 0.52, averagePower);

    final leftTMax = steer < 0 ? _innerLineLimit(steer.abs()) : 1.0;
    final rightTMax = steer > 0 ? _innerLineLimit(steer.abs()) : 1.0;

    final leftLine = _buildLine(
      size: size,
      side: -1,
      tMax: leftTMax,
      startY: startY,
      farY: farY,
      steer: steer,
    );

    final rightLine = _buildLine(
      size: size,
      side: 1,
      tMax: rightTMax,
      startY: startY,
      farY: farY,
      steer: steer,
    );

    if (leftLine.length < 2 || rightLine.length < 2) {
      return;
    }

    final whiteGlow = Paint()
      ..color = Colors.white.withOpacity(0.14)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final whiteLine = Paint()
      ..color = Colors.white.withOpacity(0.96)
      ..strokeWidth = 4.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final startDotPaint = Paint()
      ..color = Colors.white.withOpacity(0.95)
      ..style = PaintingStyle.fill;

    final leftPath = _pointsToPath(leftLine);
    final rightPath = _pointsToPath(rightLine);

    canvas.drawPath(leftPath, whiteGlow);
    canvas.drawPath(rightPath, whiteGlow);

    canvas.drawPath(leftPath, whiteLine);
    canvas.drawPath(rightPath, whiteLine);

    canvas.drawCircle(
      Offset(size.width / 2, startY),
      4.5,
      startDotPaint,
    );

    _drawColoredStripes(
      canvas: canvas,
      size: size,
      side: -1,
      tMax: leftTMax,
      startY: startY,
      farY: farY,
      steer: steer,
    );

    _drawColoredStripes(
      canvas: canvas,
      size: size,
      side: 1,
      tMax: rightTMax,
      startY: startY,
      farY: farY,
      steer: steer,
    );

    _drawBottomRedArc(
      canvas: canvas,
      leftStart: leftLine.first,
      rightStart: rightLine.first,
      size: size,
    );
  }

  double _innerLineLimit(double steerAbs) {
    // Чем сильнее поворот, тем короче внутренняя линия.
    return _lerp(1.0, 0.68, _smoothStep(steerAbs));
  }

  List<Offset> _buildLine({
    required Size size,
    required double side,
    required double tMax,
    required double startY,
    required double farY,
    required double steer,
  }) {
    const samples = 60;
    final points = <Offset>[];

    for (int i = 0; i < samples; i++) {
      final localT = i / (samples - 1);
      final t = localT * tMax;

      points.add(
        _linePoint(
          size: size,
          side: side,
          t: t,
          startY: startY,
          farY: farY,
          steer: steer,
        ),
      );
    }

    return points;
  }

  Offset _linePoint({
    required Size size,
    required double side,
    required double t,
    required double startY,
    required double farY,
    required double steer,
  }) {
    final clampedT = t.clamp(0.0, 1.0).toDouble();
    final easedT = _smoothStep(clampedT);

    final y = _lerp(startY, farY, easedT);

    /*
     * Центр траектории.
     * Это не normal-offset, а стабильная экранная модель парковочных линий.
     * Поэтому линии не скручиваются и не прыгают.
     */
    final bendProgress = math.pow(easedT, 1.55).toDouble();
    final centerX = size.width / 2 + steer * size.width * 0.34 * bendProgress;

    // Снизу широко, сверху уже.
    final halfWidth = _lerp(
      size.width * 0.31,
      size.width * 0.075,
      easedT,
    );

    return Offset(
      centerX + side * halfWidth,
      y,
    );
  }

  Path _pointsToPath(List<Offset> points) {
    final path = Path();

    if (points.isEmpty) {
      return path;
    }

    path.moveTo(points.first.dx, points.first.dy);

    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    return path;
  }

  void _drawColoredStripes({
    required Canvas canvas,
    required Size size,
    required double side,
    required double tMax,
    required double startY,
    required double farY,
    required double steer,
  }) {
    const stripeCount = 24;

    for (int i = 1; i < stripeCount; i++) {
      final localT = i / stripeCount;
      final t = localT * tMax;

      final point = _linePoint(
        size: size,
        side: side,
        t: t,
        startY: startY,
        farY: farY,
        steer: steer,
      );

      final prev = _linePoint(
        size: size,
        side: side,
        t: (t - 0.01).clamp(0.0, 1.0).toDouble(),
        startY: startY,
        farY: farY,
        steer: steer,
      );

      final next = _linePoint(
        size: size,
        side: side,
        t: (t + 0.01).clamp(0.0, 1.0).toDouble(),
        startY: startY,
        farY: farY,
        steer: steer,
      );

      final tangent = next - prev;
      final tangentLength = tangent.distance;

      if (tangentLength <= 0) {
        continue;
      }

      final tangentUnit = Offset(
        tangent.dx / tangentLength,
        tangent.dy / tangentLength,
      );

      // Смещение цветных штрихов внутрь от белой линии.
      final inward = Offset(-side, 0);
      final halfWidth = _lerp(
        size.width * 0.31,
        size.width * 0.075,
        _smoothStep(t),
      );

      final stripeCenter = point + inward * halfWidth * 0.13;

      final zone = (t / tMax).clamp(0.0, 1.0).toDouble();
      final color = _zoneColor(zone);

      final dashLength = _lerp(22.0, 11.0, zone);

      final a = stripeCenter - tangentUnit * (dashLength / 2);
      final b = stripeCenter + tangentUnit * (dashLength / 2);

      final glowPaint = Paint()
        ..color = color.withOpacity(0.18)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final dashPaint = Paint()
        ..color = color.withOpacity(0.98)
        ..strokeWidth = 3.8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(a, b, glowPaint);
      canvas.drawLine(a, b, dashPaint);
    }
  }

  Color _zoneColor(double t) {
    if (t < 0.33) {
      return Colors.redAccent;
    }

    if (t < 0.66) {
      return Colors.amber;
    }

    return Colors.lightGreenAccent.shade400;
  }

  void _drawBottomRedArc({
    required Canvas canvas,
    required Offset leftStart,
    required Offset rightStart,
    required Size size,
  }) {
    final center = Offset(
      size.width / 2,
      size.height * 0.97,
    );

    final radius = (rightStart.dx - leftStart.dx).abs() * 0.57;

    final rect = Rect.fromCircle(
      center: center,
      radius: radius,
    );

    final dashPaint = Paint()
      ..color = Colors.redAccent.withOpacity(0.96)
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const startAngle = math.pi * 0.13;
    const sweepAngle = math.pi * 0.74;

    _drawDashedArc(
      canvas: canvas,
      rect: rect,
      startAngle: startAngle,
      sweepAngle: sweepAngle,
      dashAngle: 0.11,
      gapAngle: 0.07,
      paint: dashPaint,
    );
  }

  void _drawDashedArc({
    required Canvas canvas,
    required Rect rect,
    required double startAngle,
    required double sweepAngle,
    required double dashAngle,
    required double gapAngle,
    required Paint paint,
  }) {
    double current = startAngle;
    final end = startAngle + sweepAngle;

    while (current < end) {
      final next = math.min(current + dashAngle, end);

      canvas.drawArc(
        rect,
        current,
        next - current,
        false,
        paint,
      );

      current = next + gapAngle;
    }
  }

  double _smoothStep(double t) {
    final x = t.clamp(0.0, 1.0).toDouble();
    return x * x * (3 - 2 * x);
  }

  double _lerp(double a, double b, double t) {
    final x = t.clamp(0.0, 1.0).toDouble();
    return a + (b - a) * x;
  }

  @override
  bool shouldRepaint(covariant TrajectoryPainter oldDelegate) {
    return oldDelegate.leftMotor != leftMotor ||
        oldDelegate.rightMotor != rightMotor;
  }
}