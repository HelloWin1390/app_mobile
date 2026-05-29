import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/app_settings.dart';
import '../models/server_device.dart';
import 'auth_service.dart';
import 'settings_service.dart';

class DeviceService {
  static const String _controlledDeviceKey = 'bpna_controlled_device_id';
  static const Duration heartbeatInterval = Duration(seconds: 8);

  static String? _controlledDeviceId;
  static bool _loaded = false;
  static Timer? _heartbeatTimer;

  static String? get controlledDeviceId => _controlledDeviceId;

  static Future<void> _loadControlledDevice() async {
    if (_loaded) return;

    final prefs = await SharedPreferences.getInstance();
    _controlledDeviceId = prefs.getString(_controlledDeviceKey);
    _loaded = true;
  }

  static Future<void> _setControlledDevice(String? deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = deviceId?.trim();

    if (normalized == null || normalized.isEmpty) {
      await prefs.remove(_controlledDeviceKey);
      _controlledDeviceId = null;
      stopHeartbeat();
      return;
    }

    await prefs.setString(_controlledDeviceKey, normalized);
    _controlledDeviceId = normalized;
    startHeartbeat();
  }

  static Future<List<ServerDevice>> fetchDevices() async {
    await AuthService.ensureAuth();

    final res = await http.get(
      Uri.parse('$kBaseUrl/api/device/devices'),
      headers: AuthService.authHeaders,
    );

    if (res.statusCode == 401) {
      await AuthService.logout();
      await _setControlledDevice(null);
      throw Exception('Сессия истекла');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Не удалось загрузить список дронов');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! List) {
      return [];
    }

    final devices = decoded
        .whereType<Map>()
        .map((e) => ServerDevice.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.deviceId.trim().isNotEmpty)
        .toList();

    await cacheDevices(devices);
    await _loadControlledDevice();

    final controlled = _controlledDeviceId;
    if (controlled != null) {
      final stillOwned = devices.any(
        (device) => device.deviceId == controlled && device.youControl,
      );
      if (!stillOwned) {
        await _setControlledDevice(null);
      }
    }

    return devices;
  }

  static Future<void> cacheDevices(List<ServerDevice> devices) async {
    final current = await SettingsService.load();
    final knownIds = devices.map((e) => e.deviceId).toSet();
    final selectedStillExists = knownIds.contains(current.selectedDeviceId);

    await SettingsService.save(
      current.copyWith(
        devices: devices
            .map((e) => EspDevice(id: e.deviceId, name: e.displayName))
            .toList(),
        selectedDeviceId: selectedStillExists ? current.selectedDeviceId : '',
      ),
    );
  }

  static Future<void> selectDevice(
    ServerDevice device,
    List<ServerDevice> devices,
  ) async {
    final current = await SettingsService.load();

    await SettingsService.save(
      current.copyWith(
        selectedDeviceId: device.deviceId,
        devices: devices
            .map((e) => EspDevice(id: e.deviceId, name: e.displayName))
            .toList(),
      ),
    );
  }

  static Future<bool> claimDevice(String deviceId) async {
    await AuthService.ensureAuth();

    final res = await http.post(
      Uri.parse(
        '$kBaseUrl/api/device/devices/${Uri.encodeComponent(deviceId)}/claim',
      ),
      headers: AuthService.authHeaders,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      return false;
    }

    final ok = _responseSuccess(res.body);
    if (ok) {
      await _setControlledDevice(deviceId);
    }

    return ok;
  }

  static Future<void> resumeControl(String deviceId) async {
    await _setControlledDevice(deviceId);
  }

  static Future<bool> releaseDevice(String deviceId) async {
    await AuthService.ensureAuth();

    final res = await http.post(
      Uri.parse(
        '$kBaseUrl/api/device/devices/${Uri.encodeComponent(deviceId)}/release',
      ),
      headers: AuthService.authHeaders,
    );

    final ok =
        res.statusCode >= 200 &&
        res.statusCode < 300 &&
        _responseSuccess(res.body);

    if (_controlledDeviceId == deviceId || ok) {
      await _setControlledDevice(null);
    }

    return ok;
  }

  static Future<void> releaseCurrentDevice() async {
    await _loadControlledDevice();
    final deviceId = _controlledDeviceId;
    if (deviceId == null) return;

    try {
      await releaseDevice(deviceId);
    } catch (_) {
      await _setControlledDevice(null);
    }
  }

  static Future<bool> heartbeatDevice(String deviceId) async {
    await AuthService.ensureAuth();

    final res = await http.post(
      Uri.parse(
        '$kBaseUrl/api/device/devices/${Uri.encodeComponent(deviceId)}/heartbeat',
      ),
      headers: AuthService.authHeaders,
    );

    final ok =
        res.statusCode >= 200 &&
        res.statusCode < 300 &&
        _responseSuccess(res.body);
    if (!ok && _controlledDeviceId == deviceId) {
      await _setControlledDevice(null);
    }

    return ok;
  }

  static Future<void> ensureControlHeartbeat() async {
    await _loadControlledDevice();
    if (_controlledDeviceId != null) {
      startHeartbeat();
    }
  }

  static void startHeartbeat() {
    stopHeartbeat();

    final deviceId = _controlledDeviceId;
    if (deviceId == null) return;

    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) async {
      try {
        await heartbeatDevice(deviceId);
      } catch (_) {
        await _setControlledDevice(null);
      }
    });
  }

  static void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  static bool _responseSuccess(String body) {
    if (body.trim().isEmpty) {
      return true;
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded.containsKey('success')) {
        return decoded['success'] == true;
      }
    } catch (_) {}

    return true;
  }
}
