import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:saver_gallery/saver_gallery.dart';
import '../models/telemetry.dart';
import '../services/auth_service.dart';
import '../services/ws_service.dart';
import '../widgets/motor_slider.dart';
import '../widgets/telemetry_card.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _ws = WsService();

  TelemetryData _telemetry   = TelemetryData.empty();
  Uint8List?    _lastFrame;
  bool          _videoConnected = false;
  bool          _menuOpen = false;

  DateTime? _sessionStart;
  Timer?    _sessionTimer;
  Duration  _elapsed = Duration.zero;

  StreamSubscription? _videoSub;
  StreamSubscription? _telemetrySub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await AuthService.ensureAuth();
    _ws.connectVideo();
    _ws.connectTelemetry();

    _videoSub = _ws.videoStream.listen((frame) {
      setState(() {
        _lastFrame = frame;
        if (!_videoConnected) {
          _videoConnected = true;
          _startSession();
        }
      });
    });

    _telemetrySub = _ws.telemetryStream.listen((t) {
      setState(() {
        _telemetry = t;
        if (!t.connected && _videoConnected) {
          _videoConnected = false;
          _stopSession();
        }
      });
    });
  }

  void _startSession() {
    _sessionStart = DateTime.now();
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed = DateTime.now().difference(_sessionStart!));
    });
  }

  void _stopSession() {
    _sessionTimer?.cancel();
  }

  String get _elapsedStr {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes % 60;
    final s = _elapsed.inSeconds % 60;
    return '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
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
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF2D2C2A)),
    );
  }

  Widget _buildVideo() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF171614),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF393836)),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: _lastFrame != null
            ? Image.memory(_lastFrame!, gaplessPlayback: true, fit: BoxFit.cover)
            : const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.videocam_off, color: Color(0xFF5A5957), size: 48),
                  SizedBox(height: 12),
                  Text('Нет видео сигнала', style: TextStyle(color: Color(0xFF797876))),
                ]),
              ),
      ),
    );
  }

  Widget _buildTimer() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1B19),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFF393836)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.timer, size: 14,
        color: _videoConnected ? const Color(0xFF4F98A3) : const Color(0xFF5A5957)),
      const SizedBox(width: 6),
      Text(_elapsedStr,
        style: TextStyle(
          color: _videoConnected ? const Color(0xFFCDCCCA) : const Color(0xFF5A5957),
          fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.w600,
        ),
      ),
    ]),
  );

  Widget _buildMenuOverlay() => GestureDetector(
    onTap: () => setState(() => _menuOpen = false),
    child: Container(
      color: Colors.black54,
      child: Align(
        alignment: Alignment.topRight,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            margin: const EdgeInsets.only(top: 60, right: 16),
            width: 200,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1B19),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF393836)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _menuItem(Icons.link, 'Подключиться', () async {
                setState(() => _menuOpen = false);
                final ok = await AuthService.login();
                if (ok) { _ws.connectVideo(); _ws.connectTelemetry(); }
                _showSnack(ok ? 'Подключено' : 'Ошибка подключения');
              }),
              const Divider(color: Color(0xFF262523), height: 1),
              _menuItem(Icons.settings, 'Настройки', () {
                setState(() => _menuOpen = false);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              }),
            ]),
          ),
        ),
      ),
    ),
  );

  Widget _menuItem(IconData icon, String label, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(icon, size: 18, color: const Color(0xFF4F98A3)),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: Color(0xFFCDCCCA), fontSize: 14)),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF171614),
      body: Stack(children: [
        SafeArea(child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              Container(width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _videoConnected ? const Color(0xFF6DAA45) : const Color(0xFF797876),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _videoConnected ? 'Подключено' : 'Не подключено',
                style: TextStyle(
                  color: _videoConnected ? const Color(0xFF6DAA45) : const Color(0xFF797876),
                  fontSize: 13, fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _buildTimer(),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.camera_alt, color: Color(0xFF4F98A3)),
                onPressed: _takeSnapshot,
              ),
              IconButton(
                icon: const Icon(Icons.menu, color: Color(0xFFCDCCCA)),
                onPressed: () => setState(() => _menuOpen = !_menuOpen),
              ),
            ]),
          ),

          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              _buildVideo(),
              const SizedBox(height: 16),
              TelemetryCard(data: _telemetry),
              const SizedBox(height: 16),
              Row(children: const [
                Text('Управление', style: TextStyle(color: Color(0xFFCDCCCA), fontSize: 15, fontWeight: FontWeight.w600)),
                Spacer(),
                Text('Тяните слайдеры вверх/вниз', style: TextStyle(color: Color(0xFF797876), fontSize: 12)),
              ]),
              const SizedBox(height: 12),
              const SizedBox(height: 280, child: DualMotorSlider()),
              const SizedBox(height: 24),
            ]),
          )),
        ])),

        if (_menuOpen) _buildMenuOverlay(),
      ]),
    );
  }

  @override
  void dispose() {
    _videoSub?.cancel();
    _telemetrySub?.cancel();
    _sessionTimer?.cancel();
    _ws.dispose();
    super.dispose();
  }
}