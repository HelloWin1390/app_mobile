import 'dart:async';

import 'package:flutter/material.dart';

import '../models/server_device.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadDevices(silent: true),
    );
  }

  Future<void> _loadDevices({bool silent = false}) async {
    if (!silent) {
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
    } catch (e) {
      if (!mounted) return;

      final sessionLost = AuthService.token == null;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = sessionLost ? 'Сессия истекла. Войдите заново.' : e.toString();
      });

      if (sessionLost) {
        _openLogin();
      }
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF2D2C2A)),
    );
  }

  Future<void> _selectDevice(ServerDevice device) async {
    await DeviceService.selectDevice(device, _devices);

    if (!mounted) return;

    if (widget.returnToPreviousOnSelect) {
      Navigator.pop(context);
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DroneControlScreen()),
    );
  }

  Future<void> _claimDevice(ServerDevice device) async {
    setState(() {
      _refreshing = true;
    });

    final ok = await DeviceService.claimDevice(device.deviceId);

    if (!mounted) return;

    setState(() {
      _refreshing = false;
    });

    if (!ok) {
      _showSnack('Дрон уже занят или недоступен');
      await _loadDevices(silent: true);
      return;
    }

    await _selectDevice(device);
  }

  Future<void> _resumeDevice(ServerDevice device) async {
    await DeviceService.resumeControl(device.deviceId);
    await _selectDevice(device);
  }

  Future<void> _releaseDevice(ServerDevice device) async {
    final ok = await DeviceService.releaseDevice(device.deviceId);
    _showSnack(ok ? 'Управление освобождено' : 'Не удалось освободить дрон');
    await _loadDevices(silent: true);
  }

  Future<void> _logout() async {
    await DeviceService.releaseCurrentDevice();
    await AuthService.logout();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _openLogin() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  String _statusLabel(ServerDevice device) {
    if (device.status == 'busy') return 'Занят';
    if (device.status == 'online') return 'Онлайн';
    return 'Оффлайн';
  }

  Color _statusColor(ServerDevice device) {
    if (device.status == 'busy') return const Color(0xFFD19900);
    if (device.status == 'online') return const Color(0xFF6DAA45);
    return const Color(0xFF797876);
  }

  String _formatLastSeen(String? value) {
    if (value == null || value.trim().isEmpty) return '-';

    try {
      final dt = DateTime.parse(value).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.'
          '${dt.month.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return value;
    }
  }

  Widget _statusBadge(ServerDevice device) {
    final color = _statusColor(device);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Text(
        _statusLabel(device),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _deviceButton(ServerDevice device) {
    if (device.youControl) {
      return ElevatedButton.icon(
        onPressed: _refreshing ? null : () => _resumeDevice(device),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Продолжить'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4F98A3),
          foregroundColor: Colors.white,
        ),
      );
    }

    if (device.isOnline) {
      return ElevatedButton.icon(
        onPressed: _refreshing ? null : () => _claimDevice(device),
        icon: const Icon(Icons.sports_esports),
        label: const Text('Взять управление'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4F98A3),
          foregroundColor: Colors.white,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: null,
      icon: const Icon(Icons.lock_outline),
      label: const Text('Занят'),
    );
  }

  Widget _deviceCard(ServerDevice device) {
    final controller = device.controllerUsername?.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1B19),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: device.youControl
              ? const Color(0xFF4F98A3)
              : const Color(0xFF393836),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF4F98A3).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.memory, color: Color(0xFF4F98A3)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.displayName,
                      style: const TextStyle(
                        color: Color(0xFFCDCCCA),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      device.deviceId,
                      style: const TextStyle(
                        color: Color(0xFF797876),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _statusBadge(device),
            ],
          ),
          const SizedBox(height: 14),
          _metaRow('Подключение', device.connected ? 'Есть' : 'Нет'),
          _metaRow('Последний сигнал', _formatLastSeen(device.lastSeen)),
          _metaRow(
            'Оператор',
            controller == null || controller.isEmpty ? '-' : controller,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _deviceButton(device)),
              if (device.youControl) ...[
                const SizedBox(width: 10),
                IconButton(
                  onPressed: _refreshing ? null : () => _releaseDevice(device),
                  style: IconButton.styleFrom(
                    foregroundColor: const Color(0xFFDD6974),
                    side: const BorderSide(color: Color(0xFF393836)),
                  ),
                  icon: const Icon(Icons.link_off),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF797876), fontSize: 12),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFCDCCCA),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final visibleDevices = _devices
        .where((device) => device.isOnline || device.youControl)
        .toList();

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF4F98A3)),
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 90),
          const Icon(Icons.cloud_off, color: Color(0xFF797876), size: 50),
          const SizedBox(height: 14),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF797876), fontSize: 14),
          ),
        ],
      );
    }

    if (visibleDevices.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: const [
          SizedBox(height: 90),
          Icon(Icons.memory, color: Color(0xFF797876), size: 50),
          SizedBox(height: 14),
          Text(
            'Онлайн-дронов пока нет',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF797876), fontSize: 14),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: visibleDevices.map(_deviceCard).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF171614),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1B19),
        foregroundColor: const Color(0xFFCDCCCA),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Онлайн-дроны'),
            if (user != null)
              Text(
                user.username,
                style: const TextStyle(color: Color(0xFF797876), fontSize: 12),
              ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _refreshing ? null : () => _loadDevices(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFF393836), height: 1),
        ),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF4F98A3),
        backgroundColor: const Color(0xFF1C1B19),
        onRefresh: () => _loadDevices(),
        child: _content(),
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
