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

  double _leftMotor = 0;
  double _rightMotor = 0;

  bool _extraToggleOn = false;
  double _extraSliderValue = 0;

  Timer? _motorTimer;
  Timer? _sessionTimer;
  Timer? _extraSliderTimer;

  DateTime? _sessionStart;
  Duration _elapsed = Duration.zero;

  StreamSubscription? _videoSub;
  StreamSubscription? _telemetrySub;
  StreamSubscription? _detectionSub;

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

    _ws.reconnectAll(
      deviceId: settings.selectedDeviceId,
    );

    _videoSub = _ws.videoStream.listen((frame) {
      if (!mounted) return;

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
        backgroundColor: const Color(0xFF2D2C2A),
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

    await CommandService.send(
      command,
      deviceId: _selectedDeviceId,
    );
  }

  Future<void> _releaseMotors() async {
    setState(() {
      _leftMotor = 0;
      _rightMotor = 0;
    });

    _stopMotorLoop();

    await CommandService.send(
      'stop',
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
                      style: TextStyle(
                        color: Color(0xFF797876),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _topStatusBar() {
    final tempText = _telemetry.temperature != null
        ? '${_telemetry.temperature!.toStringAsFixed(1)}°C'
        : '-°C';

    final deviceText = _telemetry.deviceId?.trim().isNotEmpty == true
        ? _telemetry.deviceId!
        : (_selectedDeviceId.isNotEmpty ? _selectedDeviceId : '-');

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.68),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _videoConnected ? Icons.circle : Icons.circle_outlined,
            color: _videoConnected
                ? const Color(0xFF6DAA45)
                : const Color(0xFFDD6974),
            size: 13,
          ),
          const SizedBox(width: 6),
          Text(
            _videoConnected ? 'ONLINE' : 'OFFLINE',
            style: TextStyle(
              color: _videoConnected
                  ? const Color(0xFF6DAA45)
                  : const Color(0xFFDD6974),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 18),
          const Icon(
            Icons.thermostat,
            color: Color(0xFFCDCCCA),
            size: 17,
          ),
          const SizedBox(width: 4),
          Text(
            tempText,
            style: const TextStyle(
              color: Color(0xFFCDCCCA),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 18),
          const Icon(
            Icons.timer,
            color: Color(0xFFCDCCCA),
            size: 17,
          ),
          const SizedBox(width: 4),
          Text(
            _elapsedStr,
            style: const TextStyle(
              color: Color(0xFFCDCCCA),
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 18),
          const Icon(
            Icons.memory,
            color: Color(0xFFCDCCCA),
            size: 17,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'ID: $deviceText',
              style: const TextStyle(
                color: Color(0xFFCDCCCA),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: _takeSnapshot,
            icon: const Icon(
              Icons.camera_alt,
              color: Color(0xFF4F98A3),
              size: 22,
            ),
          ),
          IconButton(
            onPressed: _toggleFlashlight,
            icon: Icon(
              _flashlightOn ? Icons.flashlight_on : Icons.flashlight_off,
              color: _flashlightOn
                  ? const Color(0xFFFFD166)
                  : const Color(0xFFCDCCCA),
              size: 22,
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _trajectoryEnabled = !_trajectoryEnabled;
              });
            },
            icon: Icon(
              Icons.route,
              color: _trajectoryEnabled
                  ? const Color(0xFF4F98A3)
                  : const Color(0xFFCDCCCA),
              size: 22,
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _detectionEnabled = !_detectionEnabled;
              });
            },
            icon: Icon(
              Icons.center_focus_strong,
              color: _detectionEnabled
                  ? const Color(0xFF4F98A3)
                  : const Color(0xFFCDCCCA),
              size: 22,
            ),
          ),
        ],
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
            padding: const EdgeInsets.symmetric(
              horizontal: 34,
              vertical: 15,
            ),
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
        onPressed: () => Navigator.pop(context),
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withOpacity(0.58),
        ),
        icon: const Icon(
          Icons.arrow_back,
          color: Color(0xFFCDCCCA),
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
      backgroundColor: const Color(0xFF171614),
      body: Stack(
        children: [
          _buildVideoBackground(),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.10),
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
                Positioned(
                  left: 16,
                  top: 70,
                  bottom: 12,
                  child: Center(
                    child: _MotorSlider(
                      title: 'ЛЕВЫЙ',
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
                      title: 'ПРАВЫЙ',
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

    _motorTimer?.cancel();
    _sessionTimer?.cancel();
    _extraSliderTimer?.cancel();

    CommandService.stop(
      deviceId: _selectedDeviceId,
    );

    _ws.dispose();

    _restorePortraitMode();

    super.dispose();
  }
}

class _MotorSlider extends StatelessWidget {
  final String title;
  final double value;
  final double trackHeight;
  final ValueChanged<double> onChanged;
  final VoidCallback onRelease;

  const _MotorSlider({
    required this.title,
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
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.62),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: Colors.white.withOpacity(0.12),
            ),
          ),
          child: Column(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFCDCCCA),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
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
                  border: Border.all(
                    color: Colors.white.withOpacity(0.16),
                  ),
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
                                      color: const Color(0xFF4F98A3)
                                          .withOpacity(0.48),
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