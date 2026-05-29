import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saver_gallery/saver_gallery.dart';

import '../models/app_settings.dart';
import '../models/telemetry.dart';
import '../services/auth_service.dart';
import '../services/command_service.dart';
import '../services/device_service.dart';
import '../services/mjpeg_avi_recorder.dart';
import '../services/settings_service.dart';
import '../services/ws_service.dart';
import '../widgets/detection_painter.dart';
import '../widgets/trajectory_painter.dart';

class DroneControlScreen extends StatefulWidget {
  const DroneControlScreen({super.key});

  @override
  State<DroneControlScreen> createState() => _DroneControlScreenState();
}

class _DroneControlScreenState extends State<DroneControlScreen> {
  final WsService _ws = WsService();

  AppSettings _settings = AppSettings.defaults();
  TelemetryData _telemetry = TelemetryData.empty();

  Uint8List? _lastFrame;
  Size _imageSize = Size.zero;

  List<DetectionBox> _detectionBoxes = [];

  bool _videoConnected = false;
  bool _flashlightOn = false;
  bool _trajectoryEnabled = true;
  bool _detectionEnabled = true;

  bool _recording = false;
  bool _recordingSaving = false;

  double _leftMotor = 0;
  double _rightMotor = 0;

  bool _extraToggleOn = false;
  double _extraSliderValue = 0;

  Timer? _motorTimer;
  Timer? _sessionTimer;
  Timer? _extraSliderTimer;
  Timer? _recordingTimer;

  DateTime? _sessionStart;
  DateTime? _recordingStart;
  DateTime? _lastRecordedFrameAt;

  Duration _elapsed = Duration.zero;
  Duration _recordingElapsed = Duration.zero;

  StreamSubscription? _videoSub;
  StreamSubscription? _telemetrySub;
  StreamSubscription? _detectionSub;

  final List<Uint8List> _recordedFrames = [];

  String get _selectedDeviceId => _settings.selectedDeviceId;

  bool get _leftMotorActive => _leftMotor.abs() > 0.03;
  bool get _rightMotorActive => _rightMotor.abs() > 0.03;

  bool get _accessibility => _settings.accessibilityMode;

  @override
  void initState() {
    super.initState();
    _setLandscapeMode();
    _init();
  }

  bool _isLight(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light;
  }

  Color _bg(BuildContext context) {
    return _isLight(context)
        ? const Color(0xFFF4F6F8)
        : const Color(0xFF171614);
  }

  Color _panel(BuildContext context) {
    return _isLight(context)
        ? Colors.white.withOpacity(0.92)
        : Colors.black.withOpacity(0.90);
  }

  Color _panelStrong(BuildContext context) {
    return _isLight(context)
        ? Colors.white.withOpacity(0.96)
        : const Color(0xFF1C1B19).withOpacity(0.90);
  }

  Color _border(BuildContext context) {
    return _isLight(context)
        ? const Color(0xFFD9DEE3)
        : Colors.white.withOpacity(0.12);
  }

  Color _text(BuildContext context) {
    return _isLight(context)
        ? const Color(0xFF1F2933)
        : const Color(0xFFCDCCCA);
  }

  Color _muted(BuildContext context) {
    return _isLight(context)
        ? const Color(0xFF667085)
        : const Color(0xFF797876);
  }

  Color _accent(BuildContext context) {
    return _isLight(context)
        ? const Color(0xFF167C8C)
        : const Color(0xFF4F98A3);
  }

  Future<void> _setLandscapeMode() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
  }

  Future<void> _restorePortraitMode() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  Future<void> _init() async {
    final settings = await SettingsService.load();

    if (!mounted) return;

    setState(() {
      _settings = settings;
    });

    await AuthService.ensureAuth();
    await DeviceService.ensureControlHeartbeat();

    _ws.reconnectAll(
      deviceId: settings.selectedDeviceId,
    );

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

      final newSize = Size(
        image.width.toDouble(),
        image.height.toDouble(),
      );

      image.dispose();

      if (newSize != _imageSize) {
        setState(() {
          _imageSize = newSize;
        });
      }
    } catch (_) {
      // Если размер кадра не удалось получить, оставляем Size.zero.
    }
  }

  void _startSession() {
    _sessionStart = DateTime.now();

    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted || _sessionStart == null) return;

        setState(() {
          _elapsed = DateTime.now().difference(_sessionStart!);
        });
      },
    );
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
      SnackBar(
        content: Text(msg),
        backgroundColor: _isLight(context)
            ? const Color(0xFF263238)
            : const Color(0xFF2D2C2A),
      ),
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
    _recordingTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted || _recordingStart == null) return;

        setState(() {
          _recordingElapsed = DateTime.now().difference(_recordingStart!);
        });
      },
    );

    setState(() {
      _recording = true;
      _recordingElapsed = Duration.zero;
    });

    _showSnack('Запись начата');
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

    _showSnack(
      ok ? 'Доп-команда отправлена' : 'Ошибка отправки команды',
    );
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
    _extraSliderTimer = Timer(
      const Duration(milliseconds: 120),
      () async {
        final percent = (_extraSliderValue * 100).round();

        final ok = await CommandService.sendExtraControl(
          type: ExtraControlType.slider,
          value: percent.toDouble(),
          deviceId: _selectedDeviceId,
        );

        if (!ok) {
          _showSnack('Ошибка отправки значения слайдера');
        }
      },
    );
  }

  int _motorPercentFromSlider(double value) {
    final normalized = value.clamp(-1.0, 1.0);
    return (normalized * 100).round().clamp(-100, 100);
  }

  void _startMotorLoop() {
    _motorTimer?.cancel();

    _motorTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _sendMotors(),
    );

    _sendMotors();
  }

  void _stopMotorLoop() {
    _motorTimer?.cancel();
    _motorTimer = null;
  }

  Future<void> _sendMotors() async {
    final leftPower = _motorPercentFromSlider(_leftMotor);
    final rightPower = _motorPercentFromSlider(_rightMotor);

    await CommandService.sendMotorPower(
      leftPower: leftPower,
      rightPower: rightPower,
      deviceId: _selectedDeviceId,
    );
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

  void _releaseLeftMotor() {
    setState(() {
      _leftMotor = 0;
    });

    if (!_rightMotorActive) {
      _stopMotorLoop();
    }

    unawaited(_sendMotors());
  }

  void _releaseRightMotor() {
    setState(() {
      _rightMotor = 0;
    });

    if (!_leftMotorActive) {
      _stopMotorLoop();
    }

    unawaited(_sendMotors());
  }

  Future<void> _releaseMotors() async {
    setState(() {
      _leftMotor = 0;
      _rightMotor = 0;
    });

    _stopMotorLoop();

    await CommandService.sendMotorPower(
      leftPower: 0,
      rightPower: 0,
      deviceId: _selectedDeviceId,
    );
  }

  Widget _buildVideoBackground() {
    return Positioned.fill(
      child: Container(
        color: _isLight(context)
            ? const Color(0xFFE8EEF2)
            : Colors.black,
        child: _lastFrame != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: Colors.black,
                    child: Image.memory(
                      _lastFrame!,
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                    ),
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
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.videocam_off,
                      color: _muted(context),
                      size: _accessibility ? 64 : 54,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Нет видео сигнала',
                      style: TextStyle(
                        color: _muted(context),
                        fontSize: _accessibility ? 18 : 15,
                        fontWeight:
                            _accessibility ? FontWeight.w800 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  int get _signalBars {
    if (!_videoConnected && !_telemetry.connected) {
      return 0;
    }

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
    final inactive = _isLight(context)
        ? const Color(0xFFD1D5DB)
        : Colors.white.withOpacity(0.22);

    return SizedBox(
      width: _accessibility ? 30 : 24,
      height: _accessibility ? 22 : 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(
          4,
          (index) {
            final active = index < bars;

            return Container(
              width: _accessibility ? 5 : 4,
              height: 6.0 + index * 3.0,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: active ? color : inactive,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _statusItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: _text(context),
          size: _accessibility ? 19 : 16,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: _text(context),
            fontSize: _accessibility ? 14 : 12,
            fontWeight: FontWeight.w900,
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
      height: _accessibility ? 58 : 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _panel(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _border(context),
        ),
        boxShadow: _isLight(context)
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : [],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
            Icon(
              Icons.memory,
              color: _text(context),
              size: _accessibility ? 19 : 16,
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: _accessibility ? 230 : 190,
              child: Text(
                'ID: $deviceText',
                style: TextStyle(
                  color: _text(context),
                  fontSize: _accessibility ? 14 : 12,
                  fontWeight: FontWeight.w900,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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
        ? (activeColor ?? _accent(context))
        : _text(context);

    return IconButton(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: _panel(context),
        side: BorderSide(
          color: _border(context),
        ),
      ),
      icon: Icon(
        icon,
        color: color,
        size: _accessibility ? 26 : 22,
      ),
    );
  }

  Widget _recordingStatusChip() {
    return Container(
      height: _accessibility ? 40 : 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _panelStrong(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _border(context),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _accessibility ? 10 : 8,
            height: _accessibility ? 10 : 8,
            decoration: const BoxDecoration(
              color: Color(0xFFDD6974),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            _recordingSaving ? 'SAVE' : _recordingElapsedStr,
            style: TextStyle(
              color: _text(context),
              fontSize: _accessibility ? 14 : 12,
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

Widget _rightActionBar() {
  final actionBarRightOffset = _accessibility ? 132.0 : 118.0;

  return Positioned(
    right: actionBarRightOffset,
    top: 62,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: _panel(context).withOpacity(_isLight(context) ? 0.72 : 0.42),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _border(context),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_recording || _recordingSaving) ...[
            _recordingStatusChip(),
            const SizedBox(width: 4),
          ],
          _recordActionButton(),
          _actionButton(
            icon: Icons.camera_alt,
            onPressed: _takeSnapshot,
          ),
          _actionButton(
            icon: _flashlightOn
                ? Icons.flashlight_on
                : Icons.flashlight_off,
            active: _flashlightOn,
            activeColor: const Color(0xFFFFB703),
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
        ],
      ),
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
            padding: EdgeInsets.symmetric(
              horizontal: _accessibility ? 18 : 16,
              vertical: _accessibility ? 12 : 10,
            ),
            decoration: BoxDecoration(
              color: _panel(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _border(context),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ДОП',
                  style: TextStyle(
                    color: _text(context),
                    fontWeight: FontWeight.w900,
                    fontSize: _accessibility ? 16 : 14,
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: _extraToggleOn,
                  activeColor: _accent(context),
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
          padding: EdgeInsets.symmetric(
            horizontal: _accessibility ? 18 : 16,
            vertical: _accessibility ? 12 : 10,
          ),
          decoration: BoxDecoration(
            color: _panel(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _border(context),
            ),
          ),
          child: Row(
            children: [
              Text(
                'ДОП',
                style: TextStyle(
                  color: _text(context),
                  fontWeight: FontWeight.w900,
                  fontSize: _accessibility ? 16 : 14,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Slider(
                  value: _extraSliderValue,
                  min: 0,
                  max: 1,
                  activeColor: _accent(context),
                  inactiveColor: _isLight(context)
                      ? const Color(0xFFD1D5DB)
                      : const Color(0xFF393836),
                  onChanged: _setExtraSlider,
                ),
              ),
              SizedBox(
                width: _accessibility ? 52 : 42,
                child: Text(
                  '${(_extraSliderValue * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: _text(context),
                    fontWeight: FontWeight.w900,
                    fontSize: _accessibility ? 15 : 14,
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
            backgroundColor: _accent(context),
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: _accessibility ? 38 : 34,
              vertical: _accessibility ? 17 : 15,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            elevation: 8,
          ),
          child: Text(
            'ДОП КНОПКА',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: _accessibility ? 17 : 15,
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

          await _releaseMotors();

          if (!mounted) return;

          Navigator.pop(context);
        },
        style: IconButton.styleFrom(
          backgroundColor: _panel(context),
          side: BorderSide(
            color: _border(context),
          ),
        ),
        icon: Icon(
          Icons.arrow_back,
          color: _text(context),
          size: _accessibility ? 30 : 24,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    final sliderTrackHeight =
        (size.height - 145).clamp(170.0, 280.0).toDouble();

    return Scaffold(
      backgroundColor: _bg(context),
      body: Stack(
        children: [
          _buildVideoBackground(),
          Positioned.fill(
            child: Container(
              color: _isLight(context)
                  ? Colors.white.withOpacity(0.04)
                  : Colors.black.withOpacity(0.10),
            ),
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
                Positioned(
                  left: 66,
                  right: 10,
                  top: 6,
                  child: _topStatusBar(),
                ),
                _rightActionBar(),
                Positioned(
                  left: 16,
                  top: 70,
                  bottom: 12,
                  child: Center(
                    child: _MotorSlider(
                      value: _leftMotor,
                      trackHeight: sliderTrackHeight,
                      onChanged: _onLeftChanged,
                      onRelease: _releaseLeftMotor,
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
                      onRelease: _releaseRightMotor,
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

    _motorTimer?.cancel();
    _sessionTimer?.cancel();
    _extraSliderTimer?.cancel();
    _recordingTimer?.cancel();

    CommandService.stop(
      deviceId: _selectedDeviceId,
    );

    _ws.dispose();
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

  bool _isLight(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light;
  }

  Color _panel(BuildContext context) {
    return _isLight(context)
        ? Colors.white.withOpacity(0.92)
        : Colors.black.withOpacity(0.62);
  }

  Color _track(BuildContext context) {
    return _isLight(context)
        ? const Color(0xFFF8FAFC)
        : Colors.black.withOpacity(0.58);
  }

  Color _border(BuildContext context) {
    return _isLight(context)
        ? const Color(0xFFD9DEE3)
        : Colors.white.withOpacity(0.16);
  }

  Color _text(BuildContext context) {
    return _isLight(context)
        ? const Color(0xFF1F2933)
        : const Color(0xFFCDCCCA);
  }

  Color _muted(BuildContext context) {
    return _isLight(context)
        ? const Color(0xFF667085)
        : const Color(0xFF797876);
  }

  Color _accent(BuildContext context) {
    return _isLight(context)
        ? const Color(0xFF167C8C)
        : const Color(0xFF4F98A3);
  }

  void _softSliderHaptic() {
    unawaited(HapticFeedback.selectionClick());
  }

  void _releaseSliderHaptic() {
    unawaited(HapticFeedback.lightImpact());
  }

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
    final accessibility = MediaQuery.textScalerOf(context).scale(10) > 11;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: accessibility ? 94 : 82,
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: _panel(context),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: _border(context),
            ),
            boxShadow: _isLight(context)
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : [],
          ),
          child: Column(
            children: [
              Text(
                '$_label $_percent%',
                style: TextStyle(
                  color: value.abs() > 0.04
                      ? _accent(context)
                      : _muted(context),
                  fontSize: accessibility ? 13 : 11,
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
            _softSliderHaptic();
            _updateValueFromPosition(details.localPosition);
          },
          onTapUp: (_) {
            _releaseSliderHaptic();
            onRelease();
          },
          onTapCancel: () {
            _releaseSliderHaptic();
            onRelease();
          },
          onVerticalDragStart: (details) {
            _softSliderHaptic();
            _updateValueFromPosition(details.localPosition);
          },
          onVerticalDragUpdate: (details) {
            _updateValueFromPosition(details.localPosition);
          },
          onVerticalDragEnd: (_) {
            _releaseSliderHaptic();
            onRelease();
          },
          onVerticalDragCancel: () {
            _releaseSliderHaptic();
            onRelease();
          },
          child: SizedBox(
            width: accessibility ? 94 : 86,
            height: trackHeight,
            child: Center(
              child: Container(
                width: accessibility ? 72 : 64,
                height: trackHeight,
                decoration: BoxDecoration(
                  color: _track(context),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(
                    color: _border(context),
                    width: accessibility ? 2 : 1,
                  ),
                  boxShadow: _isLight(context)
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.07),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : [],
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Container(
                        width: accessibility ? 5 : 4,
                        height: trackHeight - 24,
                        decoration: BoxDecoration(
                          color: _isLight(context)
                              ? const Color(0xFFD1D5DB)
                              : Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    Positioned(
                      top: trackHeight / 2 - 1,
                      left: 12,
                      right: 12,
                      child: Container(
                        height: accessibility ? 3 : 2,
                        color: _isLight(context)
                            ? const Color(0xFF9CA3AF)
                            : Colors.white.withOpacity(0.38),
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
                            width: accessibility ? 7 : 5,
                            decoration: BoxDecoration(
                              color: _accent(context),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: thumbY - (accessibility ? 27 : 23),
                      left: 0,
                      right: 0,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 60),
                          width: accessibility ? 54 : 46,
                          height: accessibility ? 54 : 46,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: value.abs() > 0.04
                                ? _accent(context)
                                : (_isLight(context)
                                    ? Colors.white
                                    : const Color(0xFF2D2C2A)),
                            border: Border.all(
                              color: _isLight(context)
                                  ? const Color(0xFFD1D5DB)
                                  : Colors.white.withOpacity(0.20),
                              width: accessibility ? 2 : 1,
                            ),
                            boxShadow: value.abs() > 0.04
                                ? [
                                    BoxShadow(
                                      color: _accent(context).withOpacity(0.42),
                                      blurRadius: 18,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : [
                                    if (_isLight(context))
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                  ],
                          ),
                          child: Icon(
                            Icons.drag_handle,
                            color: value.abs() > 0.04
                                ? Colors.white
                                : _text(context),
                            size: accessibility ? 26 : 22,
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