import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants.dart';
import '../models/wifi_heatmap.dart';
import 'auth_service.dart';

class WifiMapService {
  WebSocketChannel? _channel;
  String? _deviceId;
  bool _disposed = false;

  final _eventController = StreamController<WifiRealtimeEvent>.broadcast();

  Stream<WifiRealtimeEvent> get eventStream => _eventController.stream;

  Uri _apiUri(String path, Map<String, String> queryParameters) {
    return Uri.parse(
      '$kBaseUrl/api/wifi$path',
    ).replace(queryParameters: queryParameters);
  }

  Uri _wsUri(String deviceId) {
    final token = AuthService.token;
    return Uri.parse('$kWsBase/ws/wifi-measurements').replace(
      queryParameters: {
        if (token != null) 'token': token,
        'device_id': deviceId,
      },
    );
  }

  void connect({required String deviceId}) {
    _deviceId = deviceId;
    _channel?.sink.close();
    _channel = null;

    final token = AuthService.token;
    if (_disposed || token == null || deviceId.trim().isEmpty) {
      return;
    }

    _channel = WebSocketChannel.connect(_wsUri(deviceId));
    _channel!.stream.listen(
      (data) {
        if (_disposed || data is! String) return;

        try {
          final decoded = jsonDecode(data);
          if (decoded is Map<String, dynamic>) {
            _eventController.add(WifiRealtimeEvent.fromJson(decoded));
          }
        } catch (_) {}
      },
      onDone: _reconnect,
      onError: (_) => _reconnect(),
    );
  }

  void _reconnect() {
    _channel = null;
    final deviceId = _deviceId;
    if (_disposed || deviceId == null) return;

    Future.delayed(
      const Duration(seconds: 3),
      () => connect(deviceId: deviceId),
    );
  }

  Future<WifiScanStatus> loadStatus(String deviceId) async {
    final res = await http.get(
      _apiUri('/status', {'device_id': deviceId}),
      headers: AuthService.authHeaders,
    );
    return _decodeStatusResponse(res);
  }

  Future<WifiScanStatus> startScan({
    required String deviceId,
    int width = 10,
    int height = 10,
    int stepCm = 100,
  }) async {
    final res = await http.post(
      _apiUri('/start', {
        'device_id': deviceId,
        'width': width.toString(),
        'height': height.toString(),
        'step_cm': stepCm.toString(),
        'mode': 'manual',
      }),
      headers: AuthService.authHeaders,
    );
    return _decodeStatusResponse(res);
  }

  Future<WifiScanStatus> startRouteScan({
    required String deviceId,
    required List<WifiRoutePoint> points,
    int width = 10,
    int height = 10,
    int stepCm = 100,
  }) async {
    final res = await http.post(
      _apiUri('/route', {'device_id': deviceId}),
      headers: AuthService.authHeaders,
      body: jsonEncode({
        'width': width,
        'height': height,
        'step_cm': stepCm,
        'points': points.map((point) => point.toJson()).toList(),
      }),
    );
    return _decodeStatusResponse(res);
  }

  Future<WifiScanStatus> stopScan(String deviceId) async {
    final res = await http.post(
      _apiUri('/stop', {'device_id': deviceId}),
      headers: AuthService.authHeaders,
    );
    return _decodeStatusResponse(res);
  }

  Future<WifiHeatmapData> loadHeatmap({
    required String deviceId,
    int widthCells = 10,
    int heightCells = 10,
    int stepCm = 100,
  }) async {
    final res = await http.get(
      _apiUri('/heatmap', {
        'device_id': deviceId,
        'width_cells': widthCells.toString(),
        'height_cells': heightCells.toString(),
        'step_cm': stepCm.toString(),
      }),
      headers: AuthService.authHeaders,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      return WifiHeatmapData.empty(
        widthCells: widthCells,
        heightCells: heightCells,
        stepCm: stepCm,
        error: 'Не удалось загрузить карту',
      );
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) {
      return WifiHeatmapData.fromJson(decoded);
    }

    return WifiHeatmapData.empty(
      widthCells: widthCells,
      heightCells: heightCells,
      stepCm: stepCm,
    );
  }

  Future<bool> saveHeatmapSnapshot({
    required String deviceId,
    required String name,
  }) async {
    final res = await http.post(
      _apiUri('/save', {'device_id': deviceId, 'name': name}),
      headers: AuthService.authHeaders,
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  WifiScanStatus _decodeStatusResponse(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return WifiScanStatus.idle();
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) {
      return WifiScanStatus.fromJson(decoded);
    }

    return WifiScanStatus.idle();
  }

  void dispose() {
    _disposed = true;
    _channel?.sink.close();
    _eventController.close();
  }
}
