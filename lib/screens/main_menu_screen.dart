import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/settings_service.dart';
import 'drone_control_screen.dart';
import 'settings_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  AppSettings _settings = AppSettings.defaults();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await SettingsService.load();

    if (!mounted) return;

    setState(() {
      _settings = settings;
    });
  }

  String get _selectedDeviceLabel {
    if (_settings.selectedDeviceId.isEmpty) {
      return 'ESP не выбран';
    }

    final found = _settings.devices.where(
      (e) => e.id == _settings.selectedDeviceId,
    );

    if (found.isEmpty) {
      return _settings.selectedDeviceId;
    }

    final device = found.first;
    return '${device.name} · ${device.id}';
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SettingsScreen(),
      ),
    );

    await _load();
  }

  Future<void> _openControl() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const DroneControlScreen(),
      ),
    );

    await _load();
  }

  Widget _menuButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
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
                color: const Color(0xFF4F98A3).withOpacity(0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: const Color(0xFF4F98A3),
              ),
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
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF797876),
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
              const Text(
                'БПНА',
                style: TextStyle(
                  color: Color(0xFFCDCCCA),
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Панель управления дроном',
                style: TextStyle(
                  color: Color(0xFF797876),
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1B19),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF393836)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.memory,
                      color: Color(0xFF4F98A3),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selectedDeviceLabel,
                        style: const TextStyle(
                          color: Color(0xFFCDCCCA),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _menuButton(
                icon: Icons.flight_takeoff,
                title: 'Управление дроном',
                subtitle: 'Видео, моторы, фонарик, скриншот и доп-кнопка',
                onTap: _openControl,
              ),
              const SizedBox(height: 14),
              _menuButton(
                icon: Icons.settings,
                title: 'Настройки',
                subtitle: 'Телеметрия, ESP-устройства и настройка доп-кнопки',
                onTap: _openSettings,
              ),
              const Spacer(),
              const Center(
                child: Text(
                  'BPNA Control Panel',
                  style: TextStyle(
                    color: Color(0xFF5A5957),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}