import 'package:flutter/material.dart';

class DetectionBox {
  final int x1;
  final int y1;
  final int x2;
  final int y2;
  final String label;
  final double conf;

  const DetectionBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.label,
    required this.conf,
  });

  factory DetectionBox.fromJson(Map<String, dynamic> json) {
    return DetectionBox(
      x1: _toInt(json['x1'] ?? json['xmin'] ?? json['left']),
      y1: _toInt(json['y1'] ?? json['ymin'] ?? json['top']),
      x2: _toInt(json['x2'] ?? json['xmax'] ?? json['right']),
      y2: _toInt(json['y2'] ?? json['ymax'] ?? json['bottom']),
      label: (json['label'] ?? json['class'] ?? json['name'] ?? 'object')
          .toString(),
      conf: _toDouble(json['conf'] ?? json['confidence'] ?? json['score']),
    );
  }

  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}

class DetectionPainter extends CustomPainter {
  final List<DetectionBox> boxes;
  final Size imageSize;
  final Size widgetSize;

  const DetectionPainter({
    required this.boxes,
    required this.imageSize,
    required this.widgetSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (boxes.isEmpty) return;
    if (imageSize.width <= 0 || imageSize.height <= 0) return;

    final paintSize = widgetSize.width > 0 && widgetSize.height > 0
        ? widgetSize
        : size;

    if (paintSize.width <= 0 || paintSize.height <= 0) return;

    /*
     * ВАЖНО:
     * Видео отображается через BoxFit.cover.
     * Поэтому рамки тоже масштабируем как cover,
     * иначе они будут смещены.
     */
final scaleX = paintSize.width / imageSize.width;
final scaleY = paintSize.height / imageSize.height;

// ВАЖНО:
// Видео теперь BoxFit.contain, поэтому берём меньший scale.
// Так рамки детекции не будут уезжать.
final scale = scaleX < scaleY ? scaleX : scaleY;

    final displayedWidth = imageSize.width * scale;
    final displayedHeight = imageSize.height * scale;

    final offsetX = (paintSize.width - displayedWidth) / 2;
    final offsetY = (paintSize.height - displayedHeight) / 2;

    final boxPaint = Paint()
      ..color = const Color(0xFF00FF88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;

    final glowPaint = Paint()
      ..color = const Color(0xFF00FF88).withOpacity(0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9;

    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.72)
      ..style = PaintingStyle.fill;

    for (final box in boxes) {
      final rect = Rect.fromLTRB(
        box.x1 * scale + offsetX,
        box.y1 * scale + offsetY,
        box.x2 * scale + offsetX,
        box.y2 * scale + offsetY,
      );

      final visibleRect = rect.intersect(
        Rect.fromLTWH(0, 0, paintSize.width, paintSize.height),
      );

      if (visibleRect.isEmpty) continue;

      final roundedRect = RRect.fromRectAndRadius(
        visibleRect,
        const Radius.circular(8),
      );

      canvas.drawRRect(roundedRect, glowPaint);
      canvas.drawRRect(roundedRect, boxPaint);

      _drawLabel(
        canvas: canvas,
        rect: visibleRect,
        label: box.label,
        conf: box.conf,
        bgPaint: bgPaint,
      );
    }
  }

  void _drawLabel({
    required Canvas canvas,
    required Rect rect,
    required String label,
    required double conf,
    required Paint bgPaint,
  }) {
    final labelText = '$label ${(conf * 100).clamp(0, 100).toStringAsFixed(0)}%';

    final tp = TextPainter(
      text: TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Color(0xFF00FF88),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final labelWidth = tp.width + 12;
    final labelHeight = tp.height + 7;

    final labelTop = rect.top - labelHeight < 0
        ? rect.top
        : rect.top - labelHeight;

    final labelRect = Rect.fromLTWH(
      rect.left,
      labelTop,
      labelWidth,
      labelHeight,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(6)),
      bgPaint,
    );

    tp.paint(
      canvas,
      Offset(labelRect.left + 6, labelRect.top + 3),
    );
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) {
    return oldDelegate.boxes != boxes ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.widgetSize != widgetSize;
  }
}