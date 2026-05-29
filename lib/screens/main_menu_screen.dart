import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/device_service.dart';
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

  @override
  void initState() {
    super.initState();
    _checkServer();
    _serverTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkServer(silent: true),
    );
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

  Future<void> _openControl() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DeviceSelectionScreen()),
    );

    await _checkServer(silent: true);
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );

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
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Widget _serverIndicator() {
    final color =
        _serverOnline ? const Color(0xFF6DAA45) : const Color(0xFFDD6974);
    final effectiveColor = _checkingServer ? const Color(0xFFD19900) : color;
    final text = _checkingServer
        ? 'Проверка'
        : (_serverOnline ? 'Сервер подключен' : 'Сервер недоступен');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1B19),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF393836)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
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
              fontSize: 12,
              fontWeight: FontWeight.w800,
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
    final accent = enabled ? const Color(0xFF4F98A3) : const Color(0xFF797876);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1B19),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF393836)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFFCDCCCA),
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF797876),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color:
                  enabled ? const Color(0xFF797876) : const Color(0xFF393836),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF171614),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Панель управления беспилотной наземной платформой',
                      style: TextStyle(
                        color: Color(0xFFCDCCCA),
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _serverIndicator(),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _loggingOut ? null : _logout,
                    icon: const Icon(Icons.logout, color: Color(0xFF797876)),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _menuButton(
                icon: Icons.flight_takeoff,
                title: 'Управление дроном',
                subtitle: 'Выбор онлайн-платформы, видео, моторы и телеметрия',
                onTap: _openControl,
              ),
              const SizedBox(height: 14),
              _menuButton(
                icon: Icons.settings,
                title: 'Настройки',
                subtitle: 'Тип нижней кнопки: кнопка, тумблер или слайдер',
                onTap: _openSettings,
              ),
              const SizedBox(height: 14),
              _menuButton(
                icon: Icons.insights,
                title: 'Телеметрия',
                subtitle: _controlledDeviceId == null
                    ? 'Доступна после взятия дрона под управление'
                    : 'История телеметрии из базы сервера',
                onTap: _controlledDeviceId == null ? null : _openTelemetry,
              ),
              const Spacer(),
              const Center(
                child: Text(
                  'BPNA Control Panel',
                  style: TextStyle(color: Color(0xFF5A5957), fontSize: 12),
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
