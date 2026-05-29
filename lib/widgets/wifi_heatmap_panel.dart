import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/wifi_heatmap.dart';

class WifiHeatmapPanel extends StatelessWidget {
  final WifiHeatmapData? data;
  final WifiScanStatus status;
  final bool loading;
  final bool routeDrawingEnabled;
  final bool savingMap;
  final List<WifiRoutePoint> routePoints;
  final ValueChanged<WifiRoutePoint> onRoutePointAdded;
  final VoidCallback onRouteDrawingToggle;
  final VoidCallback onRouteClear;
  final VoidCallback onRouteStart;

  const WifiHeatmapPanel({
    super.key,
    required this.data,
    required this.status,
    required this.loading,
    required this.routeDrawingEnabled,
    required this.savingMap,
    required this.routePoints,
    required this.onRoutePointAdded,
    required this.onRouteDrawingToggle,
    required this.onRouteClear,
    required this.onRouteStart,
  });

  bool get _routeRunning => status.running && status.mode == 'route';

  @override
  Widget build(BuildContext context) {
    final heatmap =
        data ??
        WifiHeatmapData.empty(
          widthCells: status.width,
          heightCells: status.height,
          stepCm: status.stepCm,
        );

    return Container(
      width: 324,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.76),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status.running ? Icons.sensors : Icons.grid_view,
                color: status.running
                    ? const Color(0xFF6DAA45)
                    : const Color(0xFF4F98A3),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _title,
                  style: const TextStyle(
                    color: Color(0xFFCDCCCA),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              if (loading || savingMap)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF4F98A3),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: routeDrawingEnabled && !status.running
                      ? (details) =>
                            _addPoint(details.localPosition, size, heatmap)
                      : null,
                  onPanStart: routeDrawingEnabled && !status.running
                      ? (details) =>
                            _addPoint(details.localPosition, size, heatmap)
                      : null,
                  onPanUpdate: routeDrawingEnabled && !status.running
                      ? (details) =>
                            _addPoint(details.localPosition, size, heatmap)
                      : null,
                  child: CustomPaint(
                    painter: WifiHeatmapPainter(
                      data: heatmap,
                      currentX: status.x,
                      currentY: status.y,
                      routePoints: List<WifiRoutePoint>.of(routePoints),
                      routeActive: routeDrawingEnabled || _routeRunning,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _metric('Точек', heatmap.totalPoints.toString()),
              const SizedBox(width: 12),
              _metric('Позиция', '${status.x}, ${status.y}'),
              const SizedBox(width: 12),
              _metric('Шаг', '${status.stepCm} см'),
              const SizedBox(width: 12),
              _metric('Маршрут', routePoints.length.toString()),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _toolButton(
                icon: Icons.draw,
                active: routeDrawingEnabled,
                onPressed: status.running ? null : onRouteDrawingToggle,
              ),
              const SizedBox(width: 8),
              _toolButton(
                icon: Icons.play_arrow,
                active: _routeRunning,
                onPressed: status.running || routePoints.length < 2
                    ? null
                    : onRouteStart,
              ),
              const SizedBox(width: 8),
              _toolButton(
                icon: Icons.delete_outline,
                active: false,
                onPressed: status.running || routePoints.isEmpty
                    ? null
                    : onRouteClear,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _routeHint,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF797876),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (heatmap.error != null && heatmap.totalPoints < 3) ...[
            const SizedBox(height: 8),
            const Text(
              'Для интерполяции нужно минимум 3 точки',
              style: TextStyle(color: Color(0xFF797876), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  String get _title {
    if (_routeRunning) return 'Маршрут Wi-Fi выполняется';
    if (status.running) return 'Wi-Fi карта строится';
    return 'Wi-Fi карта';
  }

  String get _routeHint {
    if (_routeRunning) return 'автоскан';
    if (routeDrawingEnabled) return 'рисуйте по сетке';
    if (routePoints.length < 2) return 'нужно 2+ точки';
    return 'маршрут готов';
  }

  void _addPoint(Offset localPosition, Size size, WifiHeatmapData heatmap) {
    if (size.width <= 0 || size.height <= 0) return;

    final cols = math.max(1, heatmap.widthCells);
    final rows = math.max(1, heatmap.heightCells);
    final x = (localPosition.dx / (size.width / cols)).floor().clamp(
      0,
      cols - 1,
    );
    final y = (localPosition.dy / (size.height / rows)).floor().clamp(
      0,
      rows - 1,
    );

    onRoutePointAdded(WifiRoutePoint(x: x, y: y));
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF797876),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFCDCCCA),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required bool active,
    required VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;
    final color = !enabled
        ? const Color(0xFF5A5957)
        : (active ? const Color(0xFF6DAA45) : const Color(0xFF4F98A3));

    return SizedBox(
      width: 38,
      height: 34,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: const Color(0xFF1C1B19),
          side: BorderSide(color: Colors.white.withOpacity(0.12)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(icon, color: color, size: 19),
      ),
    );
  }
}

class WifiHeatmapPainter extends CustomPainter {
  final WifiHeatmapData data;
  final int currentX;
  final int currentY;
  final List<WifiRoutePoint> routePoints;
  final bool routeActive;

  const WifiHeatmapPainter({
    required this.data,
    required this.currentX,
    required this.currentY,
    this.routePoints = const [],
    this.routeActive = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFF09111F);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      background,
    );

    final cols = math.max(1, data.widthCells);
    final rows = math.max(1, data.heightCells);
    final cellW = size.width / cols;
    final cellH = size.height / rows;

    for (var y = 0; y < rows; y += 1) {
      for (var x = 0; x < cols; x += 1) {
        final value = y < data.cells.length && x < data.cells[y].length
            ? data.cells[y][x]
            : null;
        if (value == null) continue;

        final paint = Paint()..color = _rssiColor(value);
        canvas.drawRect(
          Rect.fromLTWH(x * cellW, y * cellH, cellW + 0.5, cellH + 0.5),
          paint,
        );
      }
    }

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.14)
      ..strokeWidth = 1;

    for (var x = 0; x <= cols; x += 1) {
      final dx = x * cellW;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), gridPaint);
    }

    for (var y = 0; y <= rows; y += 1) {
      final dy = y * cellH;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridPaint);
    }

    _drawRoute(canvas, size, cellW, cellH, cols, rows);
    _drawCurrentMarker(canvas, cellW, cellH, cols, rows);
  }

  void _drawRoute(
    Canvas canvas,
    Size size,
    double cellW,
    double cellH,
    int cols,
    int rows,
  ) {
    if (routePoints.isEmpty) return;

    final linePaint = Paint()
      ..color =
          (routeActive ? const Color(0xFF6DAA45) : const Color(0xFF4F98A3))
              .withOpacity(0.90)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3;

    final haloPaint = Paint()
      ..color = Colors.black.withOpacity(0.58)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 7;

    final centers = routePoints
        .map(
          (point) => Offset(
            (point.x.clamp(0, cols - 1).toDouble() + 0.5) * cellW,
            (point.y.clamp(0, rows - 1).toDouble() + 0.5) * cellH,
          ),
        )
        .toList();

    if (centers.length > 1) {
      final path = Path()..moveTo(centers.first.dx, centers.first.dy);
      for (final point in centers.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, haloPaint);
      canvas.drawPath(path, linePaint);
    }

    final fill = Paint()
      ..color = routeActive ? const Color(0xFF6DAA45) : const Color(0xFF4F98A3);
    final stroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (var index = 0; index < centers.length; index += 1) {
      final point = centers[index];
      canvas.drawCircle(point, index == 0 ? 5.5 : 4.5, fill);
      canvas.drawCircle(point, index == 0 ? 5.5 : 4.5, stroke);
    }
  }

  void _drawCurrentMarker(
    Canvas canvas,
    double cellW,
    double cellH,
    int cols,
    int rows,
  ) {
    final markerX = (currentX.clamp(0, cols - 1).toDouble() + 0.5) * cellW;
    final markerY = (currentY.clamp(0, rows - 1).toDouble() + 0.5) * cellH;
    final markerPaint = Paint()..color = Colors.white;
    final markerStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF4F98A3);

    canvas.drawCircle(Offset(markerX, markerY), 5, markerStroke);
    canvas.drawCircle(Offset(markerX, markerY), 2.5, markerPaint);
  }

  Color _rssiColor(double rssi) {
    if (rssi >= -50) return const Color(0xFF35D7A0);
    if (rssi >= -60) return const Color(0xFF88D04B);
    if (rssi >= -70) return const Color(0xFFD1B000);
    if (rssi >= -80) return const Color(0xFFDD8748);
    return const Color(0xFFDD6974);
  }

  @override
  bool shouldRepaint(covariant WifiHeatmapPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.currentX != currentX ||
        oldDelegate.currentY != currentY ||
        oldDelegate.routePoints != routePoints ||
        oldDelegate.routeActive != routeActive;
  }
}
