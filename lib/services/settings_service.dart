import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class SettingsService {
  static const String _key = 'bpna_app_settings';

  static final ValueNotifier<AppSettings> settingsNotifier =
      ValueNotifier<AppSettings>(AppSettings.defaults());

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings.decode(
      prefs.getString(_key),
    );

    settingsNotifier.value = settings;

    return settings;
  }

  static Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _key,
      settings.encode(),
    );

    settingsNotifier.value = settings;
  }

  static Future<void> saveExtraControlType(String type) async {
    final current = await load();

    await save(
      current.copyWith(
        extraControlType: ExtraControlType.normalize(type),
      ),
    );
  }

  static Future<void> saveThemeMode(String themeMode) async {
    final current = await load();

    await save(
      current.copyWith(
        themeMode: AppThemeMode.normalize(themeMode),
      ),
    );
  }

  static Future<void> saveAccessibilityMode(bool enabled) async {
    final current = await load();

    await save(
      current.copyWith(
        accessibilityMode: enabled,
      ),
    );
  }

  static Future<void> addDevice(EspDevice device) async {
    final current = await load();

    final filtered = current.devices
        .where((e) => e.id.trim() != device.id.trim())
        .toList();

    final updated = [
      ...filtered,
      device,
    ];

    await save(
      current.copyWith(
        devices: updated,
        selectedDeviceId:
            current.selectedDeviceId.isEmpty ? device.id : current.selectedDeviceId,
      ),
    );
  }

  static Future<void> removeDevice(String deviceId) async {
    final current = await load();

    final updated = current.devices
        .where((e) => e.id.trim() != deviceId.trim())
        .toList();

    final selectedStillExists = updated.any(
      (e) => e.id.trim() == current.selectedDeviceId.trim(),
    );

    await save(
      current.copyWith(
        devices: updated,
        selectedDeviceId: selectedStillExists ? current.selectedDeviceId : '',
      ),
    );
  }

  static Future<void> selectDevice(String deviceId) async {
    final current = await load();

    await save(
      current.copyWith(
        selectedDeviceId: deviceId,
      ),
    );
  }
}