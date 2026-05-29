import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/server_device.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../services/settings_service.dart';
import 'drone_control_screen.dart';
import 'login_screen.dart';

class DeviceSelectionScreen extends StatefulWidget {
  final bool returnToPreviousOnSelect;

  const DeviceSelectionScreen({
    super.key,
    this.returnToPreviousOnSelect = false,
  });

  @override
  State<DeviceSelectionScreen> createState() => _DeviceSelectionScreenState();
}

class _DeviceSelectionScreenState extends State<DeviceSelectionScreen> {
  List<ServerDevice> _devices = [];

  Timer? _pollTimer;

  bool _loading = true;
  bool _refreshing = false;
  bool _actionInProgress = false;

  String? _error;
  AppSettings _settings = AppSettings.defaults();

  bool get _accessibility => _settings.accessibilityMode;

  @override
  void initState() {
    super.initState();

    _loadSettings();
    _loadDevices();

    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadDevices(silent: true),
    );
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.load();

    if (!mounted) return;

    setState(() {
      _settings = settings;
    });
  }

  Future<void> _loadDevices({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _refreshing = true;
        _error = null;
      });
    }

    try {
      final devices = await DeviceService.fetchDevices();
      await DeviceService.ensureControlHeartbeat();

      if (!mounted) return;

      setState(() {
        _devices = devices;
        _loading = false;
        _refreshing = false;
        _error = null;
      });

      await _loadSettings();
    } catch (_) {
      if (!mounted) return;

      final sessionLost = AuthService.token == null;

      setState(() {
        _loading = false;
        _refreshing = false;
        _error = sessionLost
            ? 'Сессия истекла. Выполните вход повторно.'
            : 'Не удалось загрузить список платформ';
      });

      if (sessionLost) {
        _goLogin();
      }
    }
  }

  void _goLogin() {
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
      (_) => false,
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _isLight(context)
            ? const Color(0xFF263238)
            : const Color(0xFF2D2C2A),
      ),
    );
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
    return _isLight(context) ? Colors.white : const Color(0xFF1C1B19);
  }

  Color _border(BuildContext context) {
    return _isLight(context)
        ? const Color(0xFFD9DEE3)
        : const Color(0xFF393836);
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

  Color _statusColor(ServerDevice device) {
    if (device.youControl) {
      return const Color(0xFF4F98A3);
    }

    if (device.isOnline) {
      return const Color(0xFF6DAA45);
    }

    if (device.isBusy) {
      return const Color(0xFFD19900);
    }

    return const Color(0xFFDD6974);
  }

  String _statusText(ServerDevice device) {
    if (device.youControl) {
      return 'Под вашим управлением';
    }

    if (device.isOnline) {
      return 'Доступна';
    }

    if (device.isBusy) {
      final user = device.controllerUsername?.trim();

      return user == null || user.isEmpty
          ? 'Занята другим оператором'
          : 'Занята: $user';
    }

    return 'Офлайн';
  }

  Future<void> _openDevice(ServerDevice device) async {
    if (_actionInProgress) return;

    if (device.isOffline) {
      _showSnack('Платформа сейчас офлайн');
      return;
    }

    if (device.isBusy && !device.youControl) {
      _showSnack('Платформа уже занята другим оператором');
      return;
    }

    setState(() {
      _actionInProgress = true;
    });

    try {
      bool ok = true;

      if (device.youControl) {
        await DeviceService.resumeControl(device.deviceId);
      } else {
        ok = await DeviceService.claimDevice(device.deviceId);
      }

      if (!ok) {
        _showSnack('Не удалось взять платформу под управление');
        return;
      }

      await DeviceService.selectDevice(device, _devices);
      await _loadSettings();

      if (!mounted) return;

      if (widget.returnToPreviousOnSelect) {
        Navigator.pop(context, device.deviceId);
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const DroneControlScreen(),
        ),
      );

      await _loadDevices(silent: true);
    } catch (e) {
      _showSnack('Ошибка выбора платформы: $e');
    } finally {
      if (mounted) {
        setState(() {
          _actionInProgress = false;
        });
      }
    }
  }

  Future<void> _releaseDevice(ServerDevice device) async {
    if (_actionInProgress) return;

    setState(() {
      _actionInProgress = true;
    });

    try {
      final ok = await DeviceService.releaseDevice(device.deviceId);

      if (ok) {
        _showSnack('Управление платформой освобождено');
      } else {
        _showSnack('Не удалось освободить платформу');
      }

      await _loadDevices(silent: true);
    } catch (e) {
      _showSnack('Ошибка освобождения платформы: $e');
    } finally {
      if (mounted) {
        setState(() {
          _actionInProgress = false;
        });
      }
    }
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Нет доступных платформ.\nПроверьте подключение ESP32-CAM к серверу.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _muted(context),
            fontSize: _accessibility ? 17 : 14,
            height: 1.35,
            fontWeight: _accessibility ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: const Color(0xFFDD6974),
              size: _accessibility ? 48 : 40,
            ),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Ошибка загрузки',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _text(context),
                fontSize: _accessibility ? 17 : 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _refreshing ? null : () => _loadDevices(),
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent(context),
                side: BorderSide(
                  color: _accent(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceCard(ServerDevice device) {
    final statusColor = _statusColor(device);
    final selected = device.deviceId == _settings.selectedDeviceId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _panel(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? _accent(context) : _border(context),
          width: selected || _accessibility ? 2 : 1,
        ),
        boxShadow: _isLight(context)
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : [],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openDevice(device),
        child: Padding(
          padding: EdgeInsets.all(_accessibility ? 18 : 15),
          child: Row(
            children: [
              Container(
                width: _accessibility ? 58 : 50,
                height: _accessibility ? 58 : 50,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  device.connected
                      ? Icons.smart_toy_outlined
                      : Icons.wifi_off_outlined,
                  color: statusColor,
                  size: _accessibility ? 32 : 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _text(context),
                        fontSize: _accessibility ? 18 : 15,
                        fontWeight: FontWeight.w900,
                        height: 1.18,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      device.deviceId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _muted(context),
                        fontSize: _accessibility ? 14 : 12,
                        fontWeight: _accessibility
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: _accessibility ? 10 : 8,
                          height: _accessibility ? 10 : 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            _statusText(device),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: _accessibility ? 14 : 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (device.youControl)
                IconButton(
                  onPressed: () => _releaseDevice(device),
                  tooltip: 'Освободить',
                  icon: Icon(
                    Icons.logout,
                    color: const Color(0xFFDD6974),
                    size: _accessibility ? 30 : 24,
                  ),
                )
              else
                Icon(
                  Icons.chevron_right,
                  color: _muted(context),
                  size: _accessibility ? 32 : 26,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF4F98A3),
        ),
      );
    }

    if (_error != null) {
      return _errorState();
    }

    if (_devices.isEmpty) {
      return _emptyState();
    }

    return RefreshIndicator(
      onRefresh: () => _loadDevices(),
      color: _accent(context),
      child: ListView(
        padding: EdgeInsets.all(_accessibility ? 18 : 16),
        children: [
          Text(
            'Выберите платформу для управления',
            style: TextStyle(
              color: _text(context),
              fontSize: _accessibility ? 20 : 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Доступные устройства обновляются автоматически. Управление можно открыть только для онлайн-платформы.',
            style: TextStyle(
              color: _muted(context),
              fontSize: _accessibility ? 15 : 13,
              height: 1.3,
              fontWeight: _accessibility ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 18),
          ..._devices.map(_deviceCard),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg(context),
      appBar: AppBar(
        backgroundColor: _panel(context),
        foregroundColor: _text(context),
        elevation: 0,
        title: Text(
          'Выбор платформы',
          style: TextStyle(
            fontSize: _accessibility ? 21 : 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _refreshing ? null : () => _loadDevices(),
            icon: _refreshing
                ? SizedBox(
                    width: _accessibility ? 26 : 22,
                    height: _accessibility ? 26 : 22,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF4F98A3),
                    ),
                  )
                : Icon(
                    Icons.refresh,
                    size: _accessibility ? 30 : 24,
                  ),
          ),
        ],
      ),
      body: _content(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}