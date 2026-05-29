import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../services/settings_service.dart';
import 'device_selection_screen.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'telemetry_history_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  Timer? _serverTimer;

  bool _serverOnline = false;
  bool _checkingServer = true;
  bool _loggingOut = false;

  String? _controlledDeviceId;
  AppSettings _settings = AppSettings.defaults();

  bool get _accessibility => _settings.accessibilityMode;

  @override
  void initState() {
    super.initState();

    _loadSettings();
    _checkServer();

    _serverTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkServer(silent: true),
    );
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.load();

    if (!mounted) return;

    setState(() {
      _settings = settings;
    });
  }

  Future<void> _checkServer({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _checkingServer = true;
      });
    }

    final user = await AuthService.fetchCurrentUser();

    await DeviceService.ensureControlHeartbeat();

    if (!mounted) return;

    setState(() {
      _serverOnline = user != null;
      _checkingServer = false;
      _controlledDeviceId = DeviceService.controlledDeviceId;
    });
  }

  Future<void> _playMenuFeedback() async {
    await SystemSound.play(SystemSoundType.click);
    await HapticFeedback.selectionClick();
  }

  void _handleMenuTap(VoidCallback? action) {
    if (action == null) return;

    unawaited(_playMenuFeedback());
    action();
  }

  Future<void> _openControl() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const DeviceSelectionScreen(),
      ),
    );

    await _loadSettings();
    await _checkServer(silent: true);
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SettingsScreen(),
      ),
    );

    await _loadSettings();
    await _checkServer(silent: true);
  }

  Future<void> _openTelemetry() async {
    final deviceId = _controlledDeviceId;

    if (deviceId == null || deviceId.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TelemetryHistoryScreen(deviceId: deviceId),
      ),
    );

    await _checkServer(silent: true);
  }

  Future<void> _logout() async {
    setState(() {
      _loggingOut = true;
    });

    await DeviceService.releaseCurrentDevice();
    await AuthService.logout();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
      (_) => false,
    );
  }

  Color _bg(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF171614)
        : const Color(0xFFF4F6F8);
  }

  Color _panel(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1C1B19)
        : Colors.white;
  }

  Color _border(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF393836)
        : const Color(0xFFD9DEE3);
  }

  Color _text(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFCDCCCA)
        : const Color(0xFF1F2933);
  }

  Color _muted(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF797876)
        : const Color(0xFF667085);
  }

  Widget _serverIndicator() {
    final color = _serverOnline
        ? const Color(0xFF6DAA45)
        : const Color(0xFFDD6974);

    final effectiveColor = _checkingServer
        ? const Color(0xFFD19900)
        : color;

    final text = _checkingServer
        ? 'Проверка'
        : (_serverOnline ? 'Сервер подключен' : 'Сервер недоступен');

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _accessibility ? 13 : 10,
        vertical: _accessibility ? 9 : 7,
      ),
      decoration: BoxDecoration(
        color: _panel(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _accessibility ? 10 : 8,
            height: _accessibility ? 10 : 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: effectiveColor,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              color: effectiveColor,
              fontSize: _accessibility ? 14 : 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final accent = enabled ? const Color(0xFF4F98A3) : _muted(context);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: enabled ? () => _handleMenuTap(onTap) : null,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(_accessibility ? 20 : 18),
        decoration: BoxDecoration(
          color: _panel(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border(context)),
          boxShadow: Theme.of(context).brightness == Brightness.light
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: _accessibility ? 56 : 48,
              height: _accessibility ? 56 : 48,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: accent,
                size: _accessibility ? 30 : 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _text(context),
                      fontSize: _accessibility ? 19 : 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: _muted(context),
                      fontSize: _accessibility ? 15 : 13,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: enabled ? _muted(context) : _border(context),
              size: _accessibility ? 30 : 24,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg(context),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(_accessibility ? 22 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: _accessibility ? 60 : 54,
                    height: _accessibility ? 60 : 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F98A3).withOpacity(0.16),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF4F98A3).withOpacity(0.35),
                      ),
                    ),
                    child: Icon(
                      Icons.smart_toy_outlined,
                      color: const Color(0xFF4F98A3),
                      size: _accessibility ? 34 : 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BPNA Control',
                          style: TextStyle(
                            color: _text(context),
                            fontSize: _accessibility ? 32 : 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Управление наземной беспилотной платформой',
                          style: TextStyle(
                            color: _muted(context),
                            fontSize: _accessibility ? 16 : 14,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: _loggingOut ? null : _logout,
                    icon: Icon(
                      Icons.logout,
                      color: _muted(context),
                      size: _accessibility ? 30 : 24,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _serverIndicator(),
              const SizedBox(height: 24),
              _menuButton(
                icon: Icons.videogame_asset,
                title: 'Управление платформой',
                subtitle:
                    'Выбор онлайн-платформы, видеопоток, моторы и команды',
                onTap: _openControl,
              ),
              const SizedBox(height: 14),
              _menuButton(
                icon: Icons.settings,
                title: 'Настройки',
                subtitle:
                    'Тема интерфейса, версия для слабовидящих и доп-управление',
                onTap: _openSettings,
              ),
              const SizedBox(height: 14),
              _menuButton(
                icon: Icons.monitor_heart_outlined,
                title: 'Телеметрия',
                subtitle: _controlledDeviceId == null
                    ? 'Доступна после взятия платформы под управление'
                    : 'История телеметрии выбранного устройства',
                onTap: _controlledDeviceId == null ? null : _openTelemetry,
              ),
              const Spacer(),
              Center(
                child: Text(
                  'Mobile operator panel',
                  style: TextStyle(
                    color: _muted(context).withOpacity(0.8),
                    fontSize: _accessibility ? 14 : 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _serverTimer?.cancel();
    super.dispose();
  }
}