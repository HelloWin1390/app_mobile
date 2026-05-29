import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saver_gallery/saver_gallery.dart';

import '../models/app_settings.dart';
import '../models/telemetry.dart';
import '../models/wifi_heatmap.dart';
import '../services/auth_service.dart';
import '../services/command_service.dart';
import '../services/device_service.dart';
import '../services/mjpeg_avi_recorder.dart';
import '../services/settings_service.dart';
import '../services/wifi_map_service.dart';
import '../services/ws_service.dart';
import '../widgets/detection_painter.dart';
import '../widgets/trajectory_painter.dart';
import '../widgets/wifi_heatmap_panel.dart';

class DroneControlScreen extends StatefulWidget {
  const DroneControlScreen({super.key});

  @override
  State<DroneControlScreen> createState() => _DroneControlScreenState();
}

class _DroneControlScreenState extends State<DroneControlScreen> {
  final WsService _ws = WsService();
  final WifiMapService _wifiMap = WifiMapService();

  AppSettings _settings = AppSettings.defaults();
  TelemetryData _telemetry = TelemetryData.empty();

  Uint8List? _lastFrame;
  Size _imageSize = Size.zero;

  List<DetectionBox> _detectionBoxes = [];

  bool _videoConnected = false;
  bool _flashlightOn = false;
  bool _trajectoryEnabled = true;
  bool _detectionEnabled = true;
  bool _heatmapPanelVisible = false;
  bool _heatmapLoading = false;
  bool _recording = false;
  bool _recordingSaving = false;
  bool _routeDrawingEnabled = false;
  bool _routeAutoSavePending = false;
  bool _heatmapSaving = false;

  double _leftMotor = 0;
  double _rightMotor = 0;

  bool _extraToggleOn = false;
  double _extraSliderValue = 0;

  Timer? _motorTimer;
  Timer? _sessionTimer;
  Timer? _extraSliderTimer;
  Timer? _heatmapRefreshTimer;
  Timer? _recordingTimer;

  DateTime? _sessionStart;
  DateTime? _recordingStart;
  DateTime? _lastRecordedFrameAt;
  Duration _elapsed = Duration.zero;
  Duration _recordingElapsed = Duration.zero;

  StreamSubscription? _videoSub;
  StreamSubscription? _telemetrySub;
  StreamSubscription? _detectionSub;
  StreamSubscription? _wifiSub;

  WifiScanStatus _wifiScanStatus = WifiScanStatus.idle();
  WifiHeatmapData? _wifiHeatmap;
  List<WifiRoutePoint> _wifiRoutePoints = [];
  final List<Uint8List> _recordedFrames = [];

  String get _selectedDeviceId => _settings.selectedDeviceId;

  @override
  void initState() {
    super.initState();
    _setLandscapeMode();
    _init();
  }

  Future<void> _setLandscapeMode() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _restorePortraitMode() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  Future<void> _init() async {
    final settings = await SettingsService.load();

    if (!mounted) return;

    setState(() {
      _settings = settings;
    });

    await AuthService.ensureAuth();
    await DeviceService.ensureControlHeartbeat();

    _ws.reconnectAll(deviceId: settings.selectedDeviceId);

    _wifiSub = _wifiMap.eventStream.listen(_handleWifiEvent);

    if (settings.selectedDeviceId.trim().isNotEmpty) {
      _wifiMap.connect(deviceId: settings.selectedDeviceId);
      _loadWifiStatus();
      _refreshHeatmap();
    }

    _videoSub = _ws.videoStream.listen((frame) {
      if (!mounted) return;

      _captureRecordingFrame(frame);

      setState(() {
        _lastFrame = frame;

        if (!_videoConnected) {
          _videoConnected = true;
          _startSession();
        }
      });

      _decodeImageSize(frame);
    });

    _telemetrySub = _ws.telemetryStream.listen((data) {
      if (!mounted) return;

      setState(() {
        _telemetry = data;
      });
    });

    _detectionSub = _ws.detectionStream.listen((boxes) {
      if (!mounted) return;

      setState(() {
        _detectionBoxes = boxes;
      });
    });
  }

  Future<void> _decodeImageSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      if (!mounted) return;

      final newSize = Size(image.width.toDouble(), image.height.toDouble());

      if (newSize != _imageSize) {
        setState(() {
          _imageSize = newSize;
        });
      }
    } catch (_) {
      // Если размер кадра не удалось получить, оставляем Size.zero.
    }
  }

  void _handleWifiEvent(WifiRealtimeEvent event) {
    if (!mounted) return;

    if (event.status != null) {
      final status = event.status!;
      setState(() {
        _wifiScanStatus = status;
        if (status.running && status.mode == 'route') {
          _routeAutoSavePending = true;
          _routeDrawingEnabled = false;
        }
      });
    }

    if (event.type == 'scan_complete') {
      final shouldSaveRouteMap =
          _routeAutoSavePending && event.completed == true;

      setState(() {
        _wifiScanStatus = _wifiScanStatus.copyWith(
          running: false,
          mode: 'manual',
          status: 'scan_complete',
        );
        _routeDrawingEnabled = false;
      });

      if (shouldSaveRouteMap) {
        _handleCompletedRouteScan();
      } else {
        _routeAutoSavePending = false;
      }
    }

    if (event.type == 'wifi_measurement' ||
        event.type == 'scan_status' ||
        event.type == 'scan_complete') {
      _scheduleHeatmapRefresh();
    }

    if (event.type == 'scan_notice' && event.message != null) {
      _showSnack(event.message!);
    }
  }

  void _scheduleHeatmapRefresh() {
    if (_heatmapRefreshTimer?.isActive ?? false) return;

    _heatmapRefreshTimer = Timer(
      const Duration(milliseconds: 650),
      _refreshHeatmap,
    );
  }

  Future<void> _loadWifiStatus() async {
    final deviceId = _selectedDeviceId;
    if (deviceId.isEmpty) return;

    try {
      final status = await _wifiMap.loadStatus(deviceId);
      if (!mounted) return;

      setState(() {
        _wifiScanStatus = status;
      });
    } catch (_) {}
  }

  Future<void> _refreshHeatmap() async {
    final deviceId = _selectedDeviceId;
    if (deviceId.isEmpty) return;

    setState(() {
      _heatmapLoading = true;
    });

    try {
      final heatmap = await _wifiMap.loadHeatmap(
        deviceId: deviceId,
        widthCells: _wifiScanStatus.width,
        heightCells: _wifiScanStatus.height,
        stepCm: _wifiScanStatus.stepCm,
      );

      if (!mounted) return;

      setState(() {
        _wifiHeatmap = heatmap;
        _heatmapLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _heatmapLoading = false;
      });
    }
  }

  Future<void> _toggleHeatmapScan() async {
    final deviceId = _selectedDeviceId;
    if (deviceId.isEmpty) {
      _showSnack('Сначала выбери онлайн-дрон');
      return;
    }

    if (DeviceService.controlledDeviceId != deviceId) {
      _showSnack('Сначала возьми платформу под управление');
      return;
    }

    setState(() {
      _heatmapLoading = true;
      _heatmapPanelVisible = true;
    });

    try {
      final nextStatus = _wifiScanStatus.running
          ? await _wifiMap.stopScan(deviceId)
          : await _wifiMap.startScan(deviceId: deviceId);

      if (!mounted) return;

      setState(() {
        _wifiScanStatus = nextStatus;
        _heatmapLoading = false;
        if (!nextStatus.running || nextStatus.mode != 'route') {
          _routeAutoSavePending = false;
        }
      });

      await _refreshHeatmap();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _heatmapLoading = false;
      });
      _showSnack('Не удалось переключить построение Wi-Fi карты');
    }
  }

  void _addWifiRoutePoint(WifiRoutePoint point) {
    if (_wifiScanStatus.running) return;

    final lastPoint = _wifiRoutePoints.isEmpty ? null : _wifiRoutePoints.last;
    if (lastPoint != null && lastPoint.x == point.x && lastPoint.y == point.y) {
      return;
    }

    setState(() {
      _wifiRoutePoints = [..._wifiRoutePoints, point];
    });
  }

  void _toggleRouteDrawing() {
    if (_wifiScanStatus.running) return;

    setState(() {
      _heatmapPanelVisible = true;
      _routeDrawingEnabled = !_routeDrawingEnabled;
    });
  }

  void _clearWifiRoute() {
    if (_wifiScanStatus.running) return;

    setState(() {
      _wifiRoutePoints = [];
      _routeDrawingEnabled = false;
    });
  }

  Future<void> _startRouteScan() async {
    final deviceId = _selectedDeviceId;
    if (deviceId.isEmpty) {
      _showSnack('Сначала выбери онлайн-дрон');
      return;
    }

    if (DeviceService.controlledDeviceId != deviceId) {
      _showSnack('Сначала возьми платформу под управление');
      return;
    }

    if (_wifiRoutePoints.length < 2) {
      _showSnack('Для маршрута нужно минимум 2 точки');
      return;
    }

    setState(() {
      _heatmapLoading = true;
      _heatmapPanelVisible = true;
      _routeDrawingEnabled = false;
    });

    try {
      final nextStatus = await _wifiMap.startRouteScan(
        deviceId: deviceId,
        width: _wifiScanStatus.width,
        height: _wifiScanStatus.height,
        stepCm: _wifiScanStatus.stepCm,
        points: _wifiRoutePoints,
      );

      if (!mounted) return;

      if (nextStatus.status == 'error') {
        setState(() {
          _heatmapLoading = false;
          _routeAutoSavePending = false;
        });
        _showSnack(nextStatus.message ?? 'Не удалось запустить маршрут');
        return;
      }

      setState(() {
        _wifiScanStatus = nextStatus;
        _routeAutoSavePending =
            nextStatus.running && nextStatus.mode == 'route';
        _heatmapLoading = false;
      });

      await _refreshHeatmap();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _heatmapLoading = false;
        _routeAutoSavePending = false;
      });
      _showSnack('Не удалось запустить маршрут Wi-Fi карты');
    }
  }

  Future<void> _handleCompletedRouteScan() async {
    _routeAutoSavePending = false;
    await _refreshHeatmap();
    await _saveHeatmapToGallery(saveOnServer: true);
  }

  Future<void> _saveHeatmapToGallery({required bool saveOnServer}) async {
    final deviceId = _selectedDeviceId;
    final heatmap = _wifiHeatmap ??
        WifiHeatmapData.empty(
          widthCells: _wifiScanStatus.width,
          heightCells: _wifiScanStatus.height,
          stepCm: _wifiScanStatus.stepCm,
        );

    if (deviceId.isEmpty || heatmap.totalPoints == 0) {
      _showSnack('Нет данных Wi-Fi карты для сохранения');
      return;
    }

    setState(() {
      _heatmapSaving = true;
    });

    try {
      final bytes = await _renderHeatmapPng(heatmap);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'bpna_wifi_map_$stamp.png';

      final result = await SaverGallery.saveImage(
        bytes,
        quality: 100,
        fileName: fileName,
        androidRelativePath: 'Pictures/BPNA/WiFi',
        skipIfExists: false,
      );

      if (saveOnServer) {
        await _wifiMap.saveHeatmapSnapshot(
          deviceId: deviceId,
          name: 'route_$stamp',
        );
      }

      _showSnack(
        result.isSuccess
            ? 'Wi-Fi карта сохранена в галерею'
            : 'Ошибка сохранения карты: ${result.errorMessage ?? 'неизвестная ошибка'}',
      );
    } catch (e) {
      _showSnack('Ошибка сохранения Wi-Fi карты: $e');
    } finally {
      if (mounted) {
        setState(() {
          _heatmapSaving = false;
        });
      }
    }
  }

  Future<Uint8List> _renderHeatmapPng(WifiHeatmapData heatmap) async {
    const imageSize = Size(900, 900);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    WifiHeatmapPainter(
      data: heatmap,
      currentX: _wifiScanStatus.x,
      currentY: _wifiScanStatus.y,
      routePoints: _wifiRoutePoints,
      routeActive: _wifiScanStatus.mode == 'route',
    ).paint(canvas, imageSize);

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      imageSize.width.round(),
      imageSize.height.round(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();

    if (byteData == null) {
      throw StateError('Не удалось собрать PNG Wi-Fi карты');
    }

    return byteData.buffer.asUint8List();
  }

  void _startSession() {
    _sessionStart = DateTime.now();

    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _sessionStart == null) return;

      setState(() {
        _elapsed = DateTime.now().difference(_sessionStart!);
      });
    });
  }

  String get _elapsedStr {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes % 60;
    final s = _elapsed.inSeconds % 60;

    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  void _showSnack(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF2D2C2A)),
    );
  }

  Future<void> _takeSnapshot() async {
    if (_lastFrame == null) {
      _showSnack('Нет кадра');
      return;
    }

    try {
      final result = await SaverGallery.saveImage(
        _lastFrame!,
        quality: 90,
        fileName: 'bpna_${DateTime.now().millisecondsSinceEpoch}.jpg',
        androidRelativePath: 'Pictures/BPNA',
        skipIfExists: false,
      );

      _showSnack(
        result.isSuccess
            ? 'Снимок сохранён в галерею'
            : 'Ошибка сохранения: ${result.errorMessage ?? 'неизвестная ошибка'}',
      );
    } catch (e) {
      _showSnack('Ошибка: $e');
    }
  }

  void _captureRecordingFrame(Uint8List frame) {
    if (!_recording) return;

    final now = DateTime.now();
    final last = _lastRecordedFrameAt;
    if (last != null && now.difference(last).inMilliseconds < 125) {
      return;
    }

    _lastRecordedFrameAt = now;
    _recordedFrames.add(Uint8List.fromList(frame));
  }

  String get _recordingElapsedStr {
    final m = _recordingElapsed.inMinutes;
    final s = _recordingElapsed.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  void _startRecording() {
    if (_lastFrame == null) {
      _showSnack('Нет видео для записи');
      return;
    }

    _recordedFrames
      ..clear()
      ..add(Uint8List.fromList(_lastFrame!));
    _recordingStart = DateTime.now();
    _lastRecordedFrameAt = _recordingStart;
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _recordingStart == null) return;
      setState(() {
        _recordingElapsed = DateTime.now().difference(_recordingStart!);
      });
    });

    setState(() {
      _recording = true;
      _recordingElapsed = Duration.zero;
    });
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;

    final frames = List<Uint8List>.from(_recordedFrames);
    _recordingTimer?.cancel();

    setState(() {
      _recording = false;
      _recordingSaving = true;
    });

    if (frames.isEmpty) {
      setState(() {
        _recordingSaving = false;
      });
      _showSnack('Запись пустая');
      return;
    }

    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'bpna_record_$stamp.avi';
      final file = await MjpegAviRecorder.writeAvi(
        frames: frames,
        width: _imageSize.width > 0 ? _imageSize.width.round() : 640,
        height: _imageSize.height > 0 ? _imageSize.height.round() : 480,
        fps: 8,
        fileName: fileName,
      );

      final result = await SaverGallery.saveFile(
        filePath: file.path,
        fileName: fileName,
        androidRelativePath: 'Movies/BPNA',
        skipIfExists: false,
      );

      try {
        await file.delete();
      } catch (_) {}

      _showSnack(
        result.isSuccess
            ? 'Запись сохранена в галерею'
            : 'Ошибка сохранения записи: ${result.errorMessage ?? 'неизвестная ошибка'}',
      );
    } catch (e) {
      _showSnack('Ошибка записи: $e');
    } finally {
      if (mounted) {
        setState(() {
          _recordingSaving = false;
          _recordedFrames.clear();
        });
      } else {
        _recordedFrames.clear();
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_recordingSaving) return;
    if (_recording) {
      await _stopRecording();
    } else {
      _startRecording();
    }
  }

  Future<void> _toggleFlashlight() async {
    final ok = await CommandService.sendFlashlightToggle(
      deviceId: _selectedDeviceId,
    );

    if (!mounted) return;

    if (ok) {
      setState(() {
        _flashlightOn = !_flashlightOn;
      });
    } else {
      _showSnack(
        'Не удалось отправить команду фонарика. Проверь сервер и Device ID.',
      );
    }
  }

  Future<void> _sendExtraButtonCommand() async {
    final ok = await CommandService.sendExtraControl(
      type: ExtraControlType.button,
      deviceId: _selectedDeviceId,
    );

    _showSnack(ok ? 'Доп-команда отправлена' : 'Ошибка отправки команды');
  }

  Future<void> _setExtraToggle(bool value) async {
    setState(() {
      _extraToggleOn = value;
    });

    final ok = await CommandService.sendExtraControl(
      type: ExtraControlType.toggle,
      enabled: value,
      deviceId: _selectedDeviceId,
    );

    if (!ok) {
      _showSnack('Ошибка отправки тумблера');
    }
  }

  void _setExtraSlider(double value) {
    setState(() {
      _extraSliderValue = value;
    });

    _extraSliderTimer?.cancel();
    _extraSliderTimer = Timer(const Duration(milliseconds: 120), () async {
      final percent = (_extraSliderValue * 100).round();

      final ok = await CommandService.sendExtraControl(
        type: ExtraControlType.slider,
        value: percent.toDouble(),
        deviceId: _selectedDeviceId,
      );

      if (!ok) {
        _showSnack('Ошибка отправки значения слайдера');
      }
    });
  }

  String _getDriveCommand() {
    final l = _leftMotor;
    final r = _rightMotor;

    const threshold = 0.03;

    final leftForward = l > threshold;
    final rightForward = r > threshold;
    final leftBackward = l < -threshold;
    final rightBackward = r < -threshold;

    if (leftForward && rightForward) {
      return 'forward';
    }

    if (leftBackward || rightBackward) {
      return 'backward';
    }

    if (leftForward && !rightForward) {
      return 'left-forward';
    }

    if (rightForward && !leftForward) {
      return 'right-forward';
    }

    return 'stop';
  }

  void _startMotorLoop() {
    _motorTimer?.cancel();

    _motorTimer = Timer.periodic(
      const Duration(milliseconds: 160),
      (_) => _sendMotors(),
    );

    _sendMotors();
  }

  void _stopMotorLoop() {
    _motorTimer?.cancel();
    _motorTimer = null;
  }

  Future<void> _sendMotors() async {
    final command = _getDriveCommand();

    await CommandService.send(command, deviceId: _selectedDeviceId);
  }

  Future<void> _releaseMotors() async {
    setState(() {
      _leftMotor = 0;
      _rightMotor = 0;
    });

    _stopMotorLoop();

    await CommandService.send('stop', deviceId: _selectedDeviceId);
  }

  void _onLeftChanged(double value) {
    setState(() {
      _leftMotor = value;
    });

    if (!(_motorTimer?.isActive ?? false)) {
      _startMotorLoop();
    }
  }

  void _onRightChanged(double value) {
    setState(() {
      _rightMotor = value;
    });

    if (!(_motorTimer?.isActive ?? false)) {
      _startMotorLoop();
    }
  }

  Widget _buildVideoBackground() {
    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: _lastFrame != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    _lastFrame!,
                    gaplessPlayback: true,
                    fit: BoxFit.contain,
                  ),
                  if (_detectionEnabled && _detectionBoxes.isNotEmpty)
                    IgnorePointer(
                      child: LayoutBuilder(
                        builder: (ctx, constraints) {
                          return CustomPaint(
                            painter: DetectionPainter(
                              boxes: _detectionBoxes,
                              imageSize: _imageSize.isEmpty
                                  ? Size(
                                      constraints.maxWidth,
                                      constraints.maxHeight,
                                    )
                                  : _imageSize,
                              widgetSize: Size(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              )
            : const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.videocam_off,
                      color: Color(0xFF5A5957),
                      size: 54,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Нет видео сигнала',
                      style: TextStyle(color: Color(0xFF797876), fontSize: 15),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  int get _signalBars {
    if (!_videoConnected && !_telemetry.connected) return 0;

    final rssi = _telemetry.wifiRssiDbm;
    if (rssi == null) return 2;
    if (rssi >= -55) return 4;
    if (rssi >= -67) return 3;
    if (rssi >= -78) return 2;
    return 1;
  }

  Color get _signalColor {
    switch (_signalBars) {
      case 4:
      case 3:
        return const Color(0xFF6DAA45);
      case 2:
        return const Color(0xFFD19900);
      case 1:
        return const Color(0xFFBB653B);
      default:
        return const Color(0xFFDD6974);
    }
  }

  Widget _signalQuality() {
    final bars = _signalBars;
    final color = _signalColor;

    return SizedBox(
      width: 24,
      height: 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (index) {
          final active = index < bars;
          return Container(
            width: 4,
            height: 6.0 + index * 3.0,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: active ? color : Colors.white.withOpacity(0.22),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }

  Widget _statusItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFFCDCCCA), size: 16),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFFCDCCCA),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _topStatusBar() {
    final tempText = _telemetry.temperature != null
        ? '${_telemetry.temperature!.toStringAsFixed(1)}°C'
        : '-°C';
    final batteryText = _telemetry.battery != null
        ? '${_telemetry.battery!.toStringAsFixed(0)}%'
        : '-%';
    final pingText = _telemetry.pingStr;

    final deviceText = _telemetry.deviceId?.trim().isNotEmpty == true
        ? _telemetry.deviceId!
        : (_selectedDeviceId.isNotEmpty ? _selectedDeviceId : '-');

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.90),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          _signalQuality(),
          const SizedBox(width: 18),
          _statusItem(Icons.thermostat, tempText),
          const SizedBox(width: 18),
          _statusItem(Icons.battery_charging_full, batteryText),
          const SizedBox(width: 18),
          _statusItem(Icons.speed, pingText),
          const SizedBox(width: 18),
          _statusItem(Icons.timer, _elapsedStr),
          const SizedBox(width: 18),
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.memory, color: Color(0xFFCDCCCA), size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'ID: $deviceText',
                    style: const TextStyle(
                      color: Color(0xFFCDCCCA),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required VoidCallback onPressed,
    bool active = false,
    Color? activeColor,
  }) {
    final color = active
        ? (activeColor ?? const Color(0xFF4F98A3))
        : const Color(0xFFCDCCCA);

    return IconButton(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withOpacity(0.62),
        side: BorderSide(color: Colors.white.withOpacity(0.12)),
      ),
      icon: Icon(icon, color: color, size: 22),
    );
  }

  Widget _recordingStatusChip() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1B19).withOpacity(0.90),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFFDD6974),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            _recordingSaving ? 'SAVE' : _recordingElapsedStr,
            style: const TextStyle(
              color: Color(0xFFCDCCCA),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordActionButton() {
    return _actionButton(
      icon: _recording ? Icons.stop : Icons.fiber_manual_record,
      active: _recording || _recordingSaving,
      activeColor: const Color(0xFFDD6974),
      onPressed: _recordingSaving ? () {} : _toggleRecording,
    );
  }

  Widget _heatmapActionButton() {
    final active = _wifiScanStatus.running || _heatmapPanelVisible;
    final color = _wifiScanStatus.running
        ? const Color(0xFF6DAA45)
        : (active ? const Color(0xFF4F98A3) : const Color(0xFFCDCCCA));

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _actionButton(
          icon: Icons.grid_view,
          active: active,
          activeColor: color,
          onPressed: () {
            if (_wifiScanStatus.running) {
              setState(() {
                _heatmapPanelVisible = !_heatmapPanelVisible;
              });
            } else if (_heatmapPanelVisible) {
              setState(() {
                _heatmapPanelVisible = false;
                _routeDrawingEnabled = false;
              });
            } else {
              setState(() {
                _heatmapPanelVisible = true;
              });
              _loadWifiStatus();
              _refreshHeatmap();
            }
          },
        ),
        Positioned(
          right: 2,
          top: 2,
          child: GestureDetector(
            onTap: _toggleHeatmapScan,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: _wifiScanStatus.running
                    ? const Color(0xFF6DAA45)
                    : const Color(0xFF4F98A3),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 2),
              ),
              child: _heatmapLoading
                  ? const Padding(
                      padding: EdgeInsets.all(2),
                      child: CircularProgressIndicator(
                        strokeWidth: 1.4,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _wifiScanStatus.running ? Icons.stop : Icons.play_arrow,
                      color: Colors.white,
                      size: 10,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _rightActionBar() {
    return Positioned(
      right: 12,
      top: 62,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.42),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_recording || _recordingSaving) ...[
              _recordingStatusChip(),
              const SizedBox(width: 4),
            ],
            _recordActionButton(),
            _actionButton(icon: Icons.camera_alt, onPressed: _takeSnapshot),
            _actionButton(
              icon: _flashlightOn ? Icons.flashlight_on : Icons.flashlight_off,
              active: _flashlightOn,
              activeColor: const Color(0xFFFFD166),
              onPressed: _toggleFlashlight,
            ),
            _actionButton(
              icon: Icons.route,
              active: _trajectoryEnabled,
              onPressed: () {
                setState(() {
                  _trajectoryEnabled = !_trajectoryEnabled;
                });
              },
            ),
            _actionButton(
              icon: Icons.center_focus_strong,
              active: _detectionEnabled,
              onPressed: () {
                setState(() {
                  _detectionEnabled = !_detectionEnabled;
                });
              },
            ),
            _heatmapActionButton(),
          ],
        ),
      ),
    );
  }

  Widget _heatmapOverlay() {
    return Positioned(
      top: 116,
      right: 118,
      child: WifiHeatmapPanel(
        data: _wifiHeatmap,
        status: _wifiScanStatus,
        loading: _heatmapLoading,
        routeDrawingEnabled: _routeDrawingEnabled,
        savingMap: _heatmapSaving,
        routePoints: _wifiRoutePoints,
        onRoutePointAdded: _addWifiRoutePoint,
        onRouteDrawingToggle: _toggleRouteDrawing,
        onRouteClear: _clearWifiRoute,
        onRouteStart: _startRouteScan,
      ),
    );
  }

  Widget _bottomExtraButton() {
    final type = _settings.extraControlType;

    if (type == ExtraControlType.toggle) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: 18,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.62),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.14)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ДОП',
                  style: TextStyle(
                    color: Color(0xFFCDCCCA),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: _extraToggleOn,
                  activeColor: const Color(0xFF4F98A3),
                  onChanged: _setExtraToggle,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (type == ExtraControlType.slider) {
      return Positioned(
        left: 170,
        right: 170,
        bottom: 18,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.62),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
          ),
          child: Row(
            children: [
              const Text(
                'ДОП',
                style: TextStyle(
                  color: Color(0xFFCDCCCA),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Slider(
                  value: _extraSliderValue,
                  min: 0,
                  max: 1,
                  activeColor: const Color(0xFF4F98A3),
                  inactiveColor: const Color(0xFF393836),
                  onChanged: _setExtraSlider,
                ),
              ),
              SizedBox(
                width: 42,
                child: Text(
                  '${(_extraSliderValue * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFFCDCCCA),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 18,
      child: Center(
        child: ElevatedButton(
          onPressed: _sendExtraButtonCommand,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F98A3),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            elevation: 8,
          ),
          child: const Text(
            'ДОП КНОПКА',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              letterSpacing: 0.7,
            ),
          ),
        ),
      ),
    );
  }

  Widget _backButton() {
    return Positioned(
      left: 10,
      top: 6,
      child: IconButton(
        onPressed: () async {
          if (_recording) {
            await _stopRecording();
          }

          if (!mounted) return;
          Navigator.pop(context);
        },
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withOpacity(0.58),
        ),
        icon: const Icon(Icons.arrow_back, color: Color(0xFFCDCCCA)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    final sliderTrackHeight =
        (size.height - 145).clamp(170.0, 280.0).toDouble();

    return Scaffold(
      backgroundColor: const Color(0xFF171614),
      body: Stack(
        children: [
          _buildVideoBackground(),
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.10)),
          ),
          if (_trajectoryEnabled)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: TrajectoryPainter(
                    leftMotor: _leftMotor,
                    rightMotor: _rightMotor,
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Stack(
              children: [
                _backButton(),
                Positioned(left: 66, right: 10, top: 6, child: _topStatusBar()),
                _rightActionBar(),
                if (_heatmapPanelVisible) _heatmapOverlay(),
                Positioned(
                  left: 16,
                  top: 70,
                  bottom: 12,
                  child: Center(
                    child: _MotorSlider(
                      value: _leftMotor,
                      trackHeight: sliderTrackHeight,
                      onChanged: _onLeftChanged,
                      onRelease: _releaseMotors,
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  top: 70,
                  bottom: 12,
                  child: Center(
                    child: _MotorSlider(
                      value: _rightMotor,
                      trackHeight: sliderTrackHeight,
                      onChanged: _onRightChanged,
                      onRelease: _releaseMotors,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _bottomExtraButton(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _videoSub?.cancel();
    _telemetrySub?.cancel();
    _detectionSub?.cancel();
    _wifiSub?.cancel();

    _motorTimer?.cancel();
    _sessionTimer?.cancel();
    _extraSliderTimer?.cancel();
    _heatmapRefreshTimer?.cancel();
    _recordingTimer?.cancel();

    CommandService.stop(deviceId: _selectedDeviceId);

    _ws.dispose();
    _wifiMap.dispose();

    _restorePortraitMode();

    super.dispose();
  }
}

class _MotorSlider extends StatelessWidget {
  final double value;
  final double trackHeight;
  final ValueChanged<double> onChanged;
  final VoidCallback onRelease;

  const _MotorSlider({
    required this.value,
    required this.trackHeight,
    required this.onChanged,
    required this.onRelease,
  });

  String get _label {
    if (value > 0.10) return 'FWD';
    if (value < -0.10) return 'BWD';
    return 'STOP';
  }

  int get _percent => (value.abs() * 100).round();

  void _updateValueFromPosition(Offset localPosition) {
    final y = localPosition.dy.clamp(0.0, trackHeight);

    final normalized = 1.0 - (y / trackHeight);
    final newValue = (normalized * 2.0 - 1.0).clamp(-1.0, 1.0);

    onChanged(newValue);
  }

  @override
  Widget build(BuildContext context) {
    final thumbY = (1 - (value + 1) / 2) * trackHeight;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 82,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.62),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Column(
            children: [
              Text(
                '$_label $_percent%',
                style: const TextStyle(
                  color: Color(0xFF4F98A3),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            _updateValueFromPosition(details.localPosition);
          },
          onTapUp: (_) => onRelease(),
          onTapCancel: onRelease,
          onVerticalDragStart: (details) {
            _updateValueFromPosition(details.localPosition);
          },
          onVerticalDragUpdate: (details) {
            _updateValueFromPosition(details.localPosition);
          },
          onVerticalDragEnd: (_) => onRelease(),
          onVerticalDragCancel: onRelease,
          child: SizedBox(
            width: 86,
            height: trackHeight,
            child: Center(
              child: Container(
                width: 64,
                height: trackHeight,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.58),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: Colors.white.withOpacity(0.16)),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Container(
                        width: 4,
                        height: trackHeight - 24,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    Positioned(
                      top: trackHeight / 2 - 1,
                      left: 12,
                      right: 12,
                      child: Container(
                        height: 2,
                        color: Colors.white.withOpacity(0.38),
                      ),
                    ),
                    if (value.abs() > 0.04)
                      Positioned(
                        top: value >= 0
                            ? trackHeight / 2 - value * trackHeight / 2
                            : trackHeight / 2,
                        left: 0,
                        right: 0,
                        height: value.abs() * trackHeight / 2,
                        child: Center(
                          child: Container(
                            width: 5,
                            decoration: BoxDecoration(
                              color: const Color(0xFF4F98A3),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: thumbY - 23,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 60),
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: value.abs() > 0.04
                                ? const Color(0xFF4F98A3)
                                : const Color(0xFF2D2C2A),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.20),
                            ),
                            boxShadow: value.abs() > 0.04
                                ? [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF4F98A3,
                                      ).withOpacity(0.48),
                                      blurRadius: 18,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : [],
                          ),
                          child: const Icon(
                            Icons.drag_handle,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
