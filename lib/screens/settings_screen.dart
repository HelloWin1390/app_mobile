import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/telemetry.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/ws_service.dart';
import '../widgets/telemetry_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final WsService _ws = WsService();

  final TextEditingController _deviceNameController =
      TextEditingController();
  final TextEditingController _deviceIdController =
      TextEditingController();

  StreamSubscription? _telemetrySub;

  AppSettings _settings = AppSettings.defaults();
  TelemetryData _telemetry = TelemetryData.empty();

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final settings = await SettingsService.load();

    if (!mounted) return;

    setState(() {
      _settings = settings;
      _loading = false;
    });

    await AuthService.ensureAuth();

    _ws.connectTelemetry(
      deviceId: settings.selectedDeviceId,
    );

    _telemetrySub = _ws.telemetryStream.listen((data) {
      if (!mounted) return;

      setState(() {
        _telemetry = data;
      });
    });
  }

  Future<void> _reloadSettings() async {
    final settings = await SettingsService.load();

    if (!mounted) return;

    setState(() {
      _settings = settings;
    });
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

  Future<void> _addDevice() async {
    final id = _deviceIdController.text.trim();
    final name = _deviceNameController.text.trim();

    if (id.isEmpty) {
      _showSnack('Введите Device ID / secret');
      return;
    }

    await SettingsService.addDevice(
      EspDevice(
        id: id,
        name: name.isEmpty ? id : name,
      ),
    );

    _deviceIdController.clear();
    _deviceNameController.clear();

    await _reloadSettings();

    _showSnack('ESP добавлен');
  }

  Future<void> _selectDevice(String id) async {
    await SettingsService.selectDevice(id);

    await _reloadSettings();

    _ws.connectTelemetry(deviceId: id);

    _showSnack('ESP выбран');
  }

  Future<void> _removeDevice(String id) async {
    await SettingsService.removeDevice(id);

    await _reloadSettings();

    _showSnack('ESP удалён');
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 10,
        top: 8,
      ),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF4F98A3),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1B19),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF393836)),
      ),
      child: child,
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(
        color: Color(0xFFCDCCCA),
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Color(0xFF797876),
        ),
        prefixIcon: Icon(
          icon,
          color: const Color(0xFF797876),
          size: 19,
        ),
        filled: true,
        fillColor: const Color(0xFF171614),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFF393836),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFF4F98A3),
          ),
        ),
      ),
    );
  }

  Widget _buildTelemetryDetails() {
    return TelemetryCard(data: _telemetry);
  }

  Widget _buildExtraControlSettings() {
    final selected = _settings.extraControlType;

    Widget option({
      required String type,
      required IconData icon,
      required String title,
      required String subtitle,
    }) {
      final isSelected = selected == type;

      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await SettingsService.saveExtraControlType(type);
          await _reloadSettings();

          _showSnack(
            'Тип доп-управления: ${ExtraControlType.title(type)}',
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF4F98A3).withOpacity(0.16)
                : const Color(0xFF171614),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF4F98A3)
                  : const Color(0xFF393836),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? const Color(0xFF4F98A3)
                    : const Color(0xFF797876),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFCDCCCA),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF797876),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF4F98A3),
                ),
            ],
          ),
        ),
      );
    }

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Тип нижнего элемента на экране управления',
            style: TextStyle(
              color: Color(0xFFCDCCCA),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          option(
            type: ExtraControlType.button,
            icon: Icons.smart_button,
            title: 'Кнопка',
            subtitle: 'Обычное нажатие. Отправляет extra-button.',
          ),
          option(
            type: ExtraControlType.toggle,
            icon: Icons.toggle_on,
            title: 'Переключатель',
            subtitle: 'Переключатель ON/OFF. Отправляет extra-toggle-on/off.',
          ),
          option(
            type: ExtraControlType.slider,
            icon: Icons.tune,
            title: 'Слайдер',
            subtitle: 'Плавное значение 0–100. Отправляет extra-slider.',
          ),
        ],
      ),
    );
  }

  Widget _buildDevices() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ESP, которыми можно управлять',
            style: TextStyle(
              color: Color(0xFFCDCCCA),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          _input(
            controller: _deviceNameController,
            label: 'Название ESP',
            icon: Icons.drive_file_rename_outline,
          ),
          const SizedBox(height: 10),
          _input(
            controller: _deviceIdController,
            label: 'Device ID / secret',
            icon: Icons.memory,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addDevice,
              icon: const Icon(Icons.add),
              label: const Text('Добавить ESP'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4F98A3),
                side: const BorderSide(
                  color: Color(0xFF4F98A3),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_settings.devices.isEmpty)
            const Text(
              'ESP пока не добавлены. Если оставить список пустым, приложение будет работать без выбора device_id.',
              style: TextStyle(
                color: Color(0xFF797876),
                fontSize: 12,
              ),
            )
          else
            ..._settings.devices.map(
              (device) {
                final selected = device.id == _settings.selectedDeviceId;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171614),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF4F98A3)
                          : const Color(0xFF393836),
                    ),
                  ),
                  child: ListTile(
                    leading: Radio<String>(
                      value: device.id,
                      groupValue: _settings.selectedDeviceId,
                      activeColor: const Color(0xFF4F98A3),
                      onChanged: (value) {
                        if (value != null) {
                          _selectDevice(value);
                        }
                      },
                    ),
                    title: Text(
                      device.name,
                      style: const TextStyle(
                        color: Color(0xFFCDCCCA),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      device.id,
                      style: const TextStyle(
                        color: Color(0xFF797876),
                        fontSize: 12,
                      ),
                    ),
                    trailing: IconButton(
                      onPressed: () => _removeDevice(device.id),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Color(0xFFDD6974),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF171614),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1B19),
        foregroundColor: const Color(0xFFCDCCCA),
        title: const Text('Настройки'),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: const Color(0xFF393836),
            height: 1,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF4F98A3),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionTitle('Телеметрия'),
                _buildTelemetryDetails(),
                const SizedBox(height: 18),
                _sectionTitle('Доп-управление'),
                _buildExtraControlSettings(),
                const SizedBox(height: 18),
                _sectionTitle('ESP устройства'),
                _buildDevices(),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _telemetrySub?.cancel();
    _ws.dispose();

    _deviceNameController.dispose();
    _deviceIdController.dispose();

    super.dispose();
  }
}