class WifiMeasurement {
  final int x;
  final int y;
  final int rssi;

  const WifiMeasurement({required this.x, required this.y, required this.rssi});

  factory WifiMeasurement.fromJson(Map<String, dynamic> json) {
    return WifiMeasurement(
      x: (json['x'] as num?)?.toInt() ?? 0,
      y: (json['y'] as num?)?.toInt() ?? 0,
      rssi: (json['rssi'] as num?)?.toInt() ?? -90,
    );
  }
}

class WifiRoutePoint {
  final int x;
  final int y;

  const WifiRoutePoint({required this.x, required this.y});

  Map<String, int> toJson() {
    return {'x': x, 'y': y};
  }
}

class WifiHeatmapData {
  final List<List<double?>> cells;
  final List<WifiMeasurement> measurements;
  final int widthCells;
  final int heightCells;
  final int stepCm;
  final int totalPoints;
  final String? error;

  const WifiHeatmapData({
    required this.cells,
    required this.measurements,
    required this.widthCells,
    required this.heightCells,
    required this.stepCm,
    required this.totalPoints,
    this.error,
  });

  factory WifiHeatmapData.empty({
    int widthCells = 10,
    int heightCells = 10,
    int stepCm = 100,
    String? error,
  }) {
    return WifiHeatmapData(
      cells: List.generate(
        heightCells,
        (_) => List<double?>.filled(widthCells, null),
      ),
      measurements: const [],
      widthCells: widthCells,
      heightCells: heightCells,
      stepCm: stepCm,
      totalPoints: 0,
      error: error,
    );
  }

  factory WifiHeatmapData.fromJson(Map<String, dynamic> json) {
    final widthCells = (json['width_cells'] as num?)?.toInt() ?? 10;
    final heightCells = (json['height_cells'] as num?)?.toInt() ?? 10;
    final stepCm = (json['step_cm'] as num?)?.toInt() ?? 100;
    final rawMeasurements = json['measurements'];
    final rawHeatmap = json['heatmap'];

    final measurements = rawMeasurements is List
        ? rawMeasurements
              .whereType<Map>()
              .map(
                (e) => WifiMeasurement.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
        : <WifiMeasurement>[];

    final cells = List.generate(
      heightCells,
      (_) => List<double?>.filled(widthCells, null),
    );

    if (rawHeatmap is Map && rawHeatmap['z'] is List) {
      final rows = rawHeatmap['z'] as List;
      for (var y = 0; y < rows.length && y < heightCells; y += 1) {
        final row = rows[y];
        if (row is! List) continue;

        for (var x = 0; x < row.length && x < widthCells; x += 1) {
          final value = row[x];
          if (value is num) {
            cells[y][x] = value.toDouble();
          }
        }
      }
    } else {
      for (final point in measurements) {
        if (point.x >= 0 &&
            point.x < widthCells &&
            point.y >= 0 &&
            point.y < heightCells) {
          cells[point.y][point.x] = point.rssi.toDouble();
        }
      }
    }

    return WifiHeatmapData(
      cells: cells,
      measurements: measurements,
      widthCells: widthCells,
      heightCells: heightCells,
      stepCm: stepCm,
      totalPoints:
          (json['total_points'] as num?)?.toInt() ?? measurements.length,
      error: json['error']?.toString(),
    );
  }
}

class WifiScanStatus {
  final bool running;
  final String mode;
  final int width;
  final int height;
  final int stepCm;
  final int x;
  final int y;
  final int routePointCount;
  final String? status;
  final String? message;

  const WifiScanStatus({
    required this.running,
    required this.mode,
    required this.width,
    required this.height,
    required this.stepCm,
    required this.x,
    required this.y,
    required this.routePointCount,
    this.status,
    this.message,
  });

  factory WifiScanStatus.idle() {
    return const WifiScanStatus(
      running: false,
      mode: 'manual',
      width: 10,
      height: 10,
      stepCm: 100,
      x: 0,
      y: 0,
      routePointCount: 0,
    );
  }

  factory WifiScanStatus.fromJson(Map<String, dynamic> json) {
    return WifiScanStatus(
      running: json['running'] == true,
      mode: json['mode']?.toString() ?? 'manual',
      width: (json['width'] as num?)?.toInt() ?? 10,
      height: (json['height'] as num?)?.toInt() ?? 10,
      stepCm: (json['step_cm'] as num?)?.toInt() ?? 100,
      x: (json['x'] as num?)?.toInt() ?? 0,
      y: (json['y'] as num?)?.toInt() ?? 0,
      routePointCount: (json['route_points'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString(),
      message: json['message']?.toString(),
    );
  }

  WifiScanStatus copyWith({
    bool? running,
    String? mode,
    int? width,
    int? height,
    int? stepCm,
    int? x,
    int? y,
    int? routePointCount,
    String? status,
    String? message,
  }) {
    return WifiScanStatus(
      running: running ?? this.running,
      mode: mode ?? this.mode,
      width: width ?? this.width,
      height: height ?? this.height,
      stepCm: stepCm ?? this.stepCm,
      x: x ?? this.x,
      y: y ?? this.y,
      routePointCount: routePointCount ?? this.routePointCount,
      status: status ?? this.status,
      message: message ?? this.message,
    );
  }
}

class WifiRealtimeEvent {
  final String type;
  final WifiMeasurement? measurement;
  final WifiScanStatus? status;
  final String? message;
  final bool? completed;

  const WifiRealtimeEvent({
    required this.type,
    this.measurement,
    this.status,
    this.message,
    this.completed,
  });

  factory WifiRealtimeEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString() ?? '';

    return WifiRealtimeEvent(
      type: type,
      measurement: type == 'wifi_measurement'
          ? WifiMeasurement.fromJson(json)
          : null,
      status: type == 'scan_status' ? WifiScanStatus.fromJson(json) : null,
      message: json['message']?.toString(),
      completed: json['completed'] == true,
    );
  }
}
