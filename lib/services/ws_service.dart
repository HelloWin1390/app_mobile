import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants.dart';
import '../models/telemetry.dart';
import '../widgets/detection_painter.dart';
import 'auth_service.dart';

class WsService {
  WebSocketChannel? _videoChannel;
  WebSocketChannel? _telemetryChannel;

  String? _videoDeviceId;
  String? _telemetryDeviceId;

  bool _disposed = false;

  final _videoController      = StreamController<Uint8List>.broadcast();
  final _telemetryController  = StreamController<TelemetryData>.broadcast();
  final _detectionController  = StreamController<List<DetectionBox>>.broadcast();

  Stream<Uint8List>         get videoStream      => _videoController.stream;
  Stream<TelemetryData>     get telemetryStream  => _telemetryController.stream;
  Stream<List<DetectionBox>> get detectionStream => _detectionController.stream;

  // ─── URI builder ────────────────────────────────────────────────────────────
  Uri _buildWsUri(String path, String token, String? deviceId) {
    return Uri.parse('$kWsBase$path').replace(
      queryParameters: {
        'token': token,
        if (deviceId != null && deviceId.trim().isNotEmpty)
          'device_id': deviceId.trim(),
      },
    );
  }

  // ─── Video ──────────────────────────────────────────────────────────────────
  void connectVideo({String? deviceId}) {
    _videoDeviceId = deviceId;

    _videoChannel?.sink.close();
    _videoChannel = null;

    final token = AuthService.token;
    if (token == null || _disposed) return;

    final uri = _buildWsUri('/ws/view', token, deviceId);
    _videoChannel = WebSocketChannel.connect(uri);

    _videoChannel!.stream.listen(
      (data) {
        if (_disposed) return;

        // Бинарный кадр — JPEG bytes
        if (data is Uint8List) {
          _videoController.add(data);
          return;
        }
        if (data is List<int>) {
          _videoController.add(Uint8List.fromList(data));
          return;
        }

        // Текстовое сообщение — JSON (боксы детекции и прочее)
        if (data is String) {
          _handleVideoText(data);
          return;
        }
      },
      onDone: () {
        _videoChannel = null;
        if (!_disposed) {
          Future.delayed(
            const Duration(seconds: 3),
            () => connectVideo(deviceId: _videoDeviceId),
          );
        }
      },
      onError: (_) {
        _videoChannel = null;
        if (!_disposed) {
          Future.delayed(
            const Duration(seconds: 3),
            () => connectVideo(deviceId: _videoDeviceId),
          );
        }
      },
    );
  }

void _handleVideoText(String text) {
  try {
    final decoded = jsonDecode(text);

    List<dynamic>? rawBoxes;

    // Вариант 1:
    // Сервер отправляет просто массив:
    // [{"x1":..., "y1":..., "x2":..., "y2":..., "label":..., "conf":...}]
    if (decoded is List) {
      rawBoxes = decoded;
    }

    // Вариант 2:
    // Сервер отправляет объект:
    // {"type":"detections","boxes":[...]}
    if (decoded is Map<String, dynamic>) {
      final type = decoded['type'];

      if (type == 'detections') {
        final boxes = decoded['boxes'];
        if (boxes is List) {
          rawBoxes = boxes;
        }
      }

      // Дополнительно: если сервер отправит просто {"boxes":[...]}
      if (rawBoxes == null && decoded['boxes'] is List) {
        rawBoxes = decoded['boxes'] as List;
      }
    }

    if (rawBoxes == null) return;

    final boxes = rawBoxes
        .whereType<Map>()
        .map((e) => DetectionBox.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    if (!_detectionController.isClosed) {
      _detectionController.add(boxes);
    }
  } catch (_) {
    // Игнорируем битые JSON-сообщения, чтобы не ронять приложение.
  }
}

  // ─── Telemetry ──────────────────────────────────────────────────────────────
  void connectTelemetry({String? deviceId}) {
    _telemetryDeviceId = deviceId;

    _telemetryChannel?.sink.close();
    _telemetryChannel = null;

    final token = AuthService.token;
    if (token == null || _disposed) return;

    final uri = _buildWsUri('/ws/telemetry', token, deviceId);
    _telemetryChannel = WebSocketChannel.connect(uri);

    _telemetryChannel!.stream.listen(
      (data) {
        if (_disposed) return;

        try {
          final decoded = jsonDecode(data.toString());
          if (decoded is Map<String, dynamic>) {
            _telemetryController.add(TelemetryData.fromJson(decoded));
          }
        } catch (_) {}
      },
      onDone: () {
        _telemetryChannel = null;
        if (!_disposed) {
          Future.delayed(
            const Duration(seconds: 3),
            () => connectTelemetry(deviceId: _telemetryDeviceId),
          );
        }
      },
      onError: (_) {
        _telemetryChannel = null;
        if (!_disposed) {
          Future.delayed(
            const Duration(seconds: 3),
            () => connectTelemetry(deviceId: _telemetryDeviceId),
          );
        }
      },
    );
  }

  // ─── Reconnect ──────────────────────────────────────────────────────────────
  Future<void> reconnectAll({String? deviceId}) async {
    await AuthService.ensureAuth();
    connectVideo(deviceId: deviceId);
    connectTelemetry(deviceId: deviceId);
  }

  // ─── Dispose ────────────────────────────────────────────────────────────────
  void dispose() {
    _disposed = true;

    _videoChannel?.sink.close();
    _telemetryChannel?.sink.close();

    _videoController.close();
    _telemetryController.close();
    _detectionController.close();
  }
}