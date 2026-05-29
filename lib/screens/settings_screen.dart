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

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  final WsService _ws = WsService();

  StreamSubscription? _telemetrySub;

  late final TabController _tabController;

  AppSettings _settings = AppSettings.defaults();
  TelemetryData _telemetry = TelemetryData.empty();

  bool _loading = true;

  bool get _accessibility => _settings.accessibilityMode;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 3,
      vsync: this,
    );

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

  Color _bg(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF171614)
        : const Color(0xFFF4F6F8);
  }

  Color _panelColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1C1B19)
        : Colors.white;
  }

  Color _innerColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF171614)
        : const Color(0xFFF8FAFC);
  }

  Color _borderColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF393836)
        : const Color(0xFFD9DEE3);
  }

  Color _textColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFCDCCCA)
        : const Color(0xFF1F2933);
  }

  Color _mutedColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF797876)
        : const Color(0xFF667085);
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(_accessibility ? 17 : 14),
      decoration: BoxDecoration(
        color: _panelColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _borderColor(context),
        ),
        boxShadow: Theme.of(context).brightness == Brightness.light
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : [],
      ),
      child: child,
    );
  }

  Widget _buildTelemetryTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TelemetryCard(data: _telemetry),
        const SizedBox(height: 16),
        Text(
          'Телеметрия вынесена в отдельную вкладку, чтобы данные не дублировались в других разделах настроек.',
          style: TextStyle(
            color: _mutedColor(context),
            fontSize: _accessibility ? 15 : 12,
            height: 1.35,
            fontWeight: _accessibility ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildInterfaceTab() {
    final isLight = _settings.themeMode == AppThemeMode.light;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Оформление приложения',
                style: TextStyle(
                  color: _textColor(context),
                  fontSize: _accessibility ? 18 : 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isLight,
                activeColor: const Color(0xFF4F98A3),
                title: Text(
                  'Светлая тема',
                  style: TextStyle(
                    color: _textColor(context),
                    fontSize: _accessibility ? 17 : 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  isLight
                      ? 'Сейчас используется светлое оформление'
                      : 'Сейчас используется тёмное оформление',
                  style: TextStyle(
                    color: _mutedColor(context),
                    fontSize: _accessibility ? 15 : 12,
                    height: 1.3,
                  ),
                ),
                secondary: Icon(
                  isLight ? Icons.light_mode : Icons.dark_mode,
                  color: const Color(0xFF4F98A3),
                  size: _accessibility ? 30 : 24,
                ),
                onChanged: (value) async {
                  await SettingsService.saveThemeMode(
                    value ? AppThemeMode.light : AppThemeMode.dark,
                  );

                  await _reloadSettings();

                  _showSnack(
                    value ? 'Включена светлая тема' : 'Включена тёмная тема',
                  );
                },
              ),
              Divider(
                color: _borderColor(context),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _settings.accessibilityMode,
                activeColor: const Color(0xFF4F98A3),
                title: Text(
                  'Версия для слабовидящих',
                  style: TextStyle(
                    color: _textColor(context),
                    fontSize: _accessibility ? 17 : 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  'Увеличенный текст, более крупные элементы и повышенная контрастность. Работает отдельно от темы.',
                  style: TextStyle(
                    color: _mutedColor(context),
                    fontSize: _accessibility ? 15 : 12,
                    height: 1.3,
                  ),
                ),
                secondary: Icon(
                  Icons.visibility,
                  color: const Color(0xFF4F98A3),
                  size: _accessibility ? 30 : 24,
                ),
                onChanged: (value) async {
                  await SettingsService.saveAccessibilityMode(value);

                  await _reloadSettings();

                  _showSnack(
                    value
                        ? 'Версия для слабовидящих включена'
                        : 'Версия для слабовидящих выключена',
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExtraControlTab() {
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
          padding: EdgeInsets.all(_accessibility ? 17 : 14),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF4F98A3).withOpacity(0.16)
                : _innerColor(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF4F98A3)
                  : _borderColor(context),
              width: isSelected && _accessibility ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? const Color(0xFF4F98A3)
                    : _mutedColor(context),
                size: _accessibility ? 32 : 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _textColor(context),
                        fontSize: _accessibility ? 17 : 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _mutedColor(context),
                        fontSize: _accessibility ? 15 : 12,
                        height: 1.25,
                        fontWeight:
                            _accessibility ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: const Color(0xFF4F98A3),
                  size: _accessibility ? 30 : 24,
                ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Тип нижнего элемента на экране управления',
                style: TextStyle(
                  color: _textColor(context),
                  fontSize: _accessibility ? 18 : 15,
                  fontWeight: FontWeight.w900,
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
                subtitle: 'ON/OFF. Отправляет extra-toggle-on/off.',
              ),
              option(
                type: ExtraControlType.slider,
                icon: Icons.tune,
                title: 'Слайдер',
                subtitle: 'Плавное значение 0–100. Отправляет extra-slider.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg(context),
      appBar: AppBar(
        backgroundColor: _panelColor(context),
        foregroundColor: _textColor(context),
        title: const Text('Настройки'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF4F98A3),
          labelColor: _textColor(context),
          unselectedLabelColor: _mutedColor(context),
          tabs: const [
            Tab(
              icon: Icon(Icons.monitor_heart_outlined),
              text: 'Телеметрия',
            ),
            Tab(
              icon: Icon(Icons.palette_outlined),
              text: 'Интерфейс',
            ),
            Tab(
              icon: Icon(Icons.tune),
              text: 'Доп',
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF4F98A3),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTelemetryTab(),
                _buildInterfaceTab(),
                _buildExtraControlTab(),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _telemetrySub?.cancel();
    _ws.dispose();

    _tabController.dispose();

    super.dispose();
  }
}