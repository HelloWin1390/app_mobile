class TelemetryData {
  final String? deviceId;
  final double? battery;
  final double? temperature;
  final int? freeHeap;
  final int? uptime;
  final double? cpuLoad;
  final bool wifiConnected;
  final bool connected;
  final String? lastSeen;

  final int? wifiRssiDbm;
  final double? pingMs;
  final bool pingOk;

  const TelemetryData({
    this.deviceId,
    this.battery,
    this.temperature,
    this.freeHeap,
    this.uptime,
    this.cpuLoad,
    this.wifiConnected = false,
    this.connected = false,
    this.lastSeen,
    this.wifiRssiDbm,
    this.pingMs,
    this.pingOk = false,
  });

  factory TelemetryData.empty() => const TelemetryData();

  factory TelemetryData.fromJson(Map<String, dynamic> j) {
    return TelemetryData(
      deviceId: j['device_id']?.toString(),
      battery: (j['battery'] as num?)?.toDouble(),
      temperature: (j['temperature'] as num?)?.toDouble(),
      freeHeap: (j['free_heap'] as num?)?.toInt(),
      uptime: (j['uptime'] as num?)?.toInt(),
      cpuLoad: (j['cpu_load'] as num?)?.toDouble(),
      wifiConnected: j['wifi_connected'] == true,
      connected: j['connected'] == true || j['wifi_connected'] == true,
      lastSeen: j['last_seen']?.toString() ?? j['created_at']?.toString(),
      wifiRssiDbm: (j['wifi_rssi_dbm'] as num?)?.toInt(),
      pingMs: (j['ping_ms'] as num?)?.toDouble(),
      pingOk: j['ping_ok'] == true,
    );
  }

  String get batteryStr {
    if (battery == null) return '-';
    return '${battery!.toStringAsFixed(0)}%';
  }

  String get uptimeStr {
    final s = uptime ?? 0;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '${h}h ${m}m ${sec}s';
  }

  String get freeHeapStr {
    if (freeHeap == null) return '-';
    return '${(freeHeap! / 1024).round()} KB';
  }

  String get rssiStr {
    if (wifiRssiDbm == null) return '-';
    return '$wifiRssiDbm dBm';
  }

  String get pingStr {
    if (pingMs == null || pingMs! < 0) return '-';
    return '${pingMs!.toStringAsFixed(1)} ms';
  }

  String get pingStatusStr {
    return pingOk ? 'OK' : 'Нет ответа';
  }

  String get linkQuality {
    if (!wifiConnected) return 'Offline';
    if (!pingOk) return 'Unstable';

    final r = wifiRssiDbm;
    final p = pingMs;

    if (r == null || p == null || p < 0) return 'Online';

    if (r > -55 && p < 10) return 'Excellent';
    if (r > -67 && p < 30) return 'Good';
    if (r > -75 && p < 80) return 'Fair';

    return 'Poor';
  }

  static const Map<String, int> _qualityColors = {
    'Excellent': 0xFF6DAA45,
    'Good': 0xFF4F98A3,
    'Fair': 0xFFD19900,
    'Poor': 0xFFBB653B,
    'Unstable': 0xFFDD6974,
    'Offline': 0xFF797876,
    'Online': 0xFF4F98A3,
  };

  int get linkQualityColor {
    return _qualityColors[linkQuality] ?? 0xFF797876;
  }
}