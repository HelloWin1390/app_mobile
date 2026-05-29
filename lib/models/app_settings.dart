import 'dart:convert';

class ExtraControlType {
  static const String button = 'button';
  static const String toggle = 'toggle';
  static const String slider = 'slider';

  static const List<String> values = [
    button,
    toggle,
    slider,
  ];

  static String normalize(String? value) {
    if (value == null) return button;
    return values.contains(value) ? value : button;
  }

  static String title(String value) {
    switch (normalize(value)) {
      case toggle:
        return 'Тумблер';
      case slider:
        return 'Слайдер';
      case button:
      default:
        return 'Кнопка';
    }
  }
}

class AppThemeMode {
  static const String dark = 'dark';
  static const String light = 'light';

  static const List<String> values = [
    dark,
    light,
  ];

  static String normalize(String? value) {
    if (value == null) return dark;
    return values.contains(value) ? value : dark;
  }

  static String title(String value) {
    switch (normalize(value)) {
      case light:
        return 'Светлая тема';
      case dark:
      default:
        return 'Тёмная тема';
    }
  }
}

class EspDevice {
  final String id;
  final String name;

  const EspDevice({
    required this.id,
    required this.name,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };

  factory EspDevice.fromJson(Map<String, dynamic> json) {
    return EspDevice(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}

class AppSettings {
  final String selectedDeviceId;
  final List<EspDevice> devices;

  /// button / toggle / slider
  final String extraControlType;

  /// dark / light
  final String themeMode;

  /// Отдельная версия интерфейса для слабовидящих
  final bool accessibilityMode;

  const AppSettings({
    required this.selectedDeviceId,
    required this.devices,
    required this.extraControlType,
    required this.themeMode,
    required this.accessibilityMode,
  });

  factory AppSettings.defaults() {
    return const AppSettings(
      selectedDeviceId: '',
      devices: [],
      extraControlType: ExtraControlType.button,
      themeMode: AppThemeMode.dark,
      accessibilityMode: false,
    );
  }

  AppSettings copyWith({
    String? selectedDeviceId,
    List<EspDevice>? devices,
    String? extraControlType,
    String? themeMode,
    bool? accessibilityMode,
  }) {
    return AppSettings(
      selectedDeviceId: selectedDeviceId ?? this.selectedDeviceId,
      devices: devices ?? this.devices,
      extraControlType: ExtraControlType.normalize(
        extraControlType ?? this.extraControlType,
      ),
      themeMode: AppThemeMode.normalize(
        themeMode ?? this.themeMode,
      ),
      accessibilityMode: accessibilityMode ?? this.accessibilityMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'selectedDeviceId': selectedDeviceId,
        'devices': devices.map((e) => e.toJson()).toList(),
        'extraControlType': extraControlType,
        'themeMode': themeMode,
        'accessibilityMode': accessibilityMode,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final rawDevices = json['devices'];

    return AppSettings(
      selectedDeviceId: json['selectedDeviceId']?.toString() ?? '',
      devices: rawDevices is List
          ? rawDevices
              .whereType<Map>()
              .map((e) => EspDevice.fromJson(Map<String, dynamic>.from(e)))
              .where((e) => e.id.trim().isNotEmpty)
              .toList()
          : [],
      extraControlType: ExtraControlType.normalize(
        json['extraControlType']?.toString(),
      ),
      themeMode: AppThemeMode.normalize(
        json['themeMode']?.toString(),
      ),
      accessibilityMode: json['accessibilityMode'] == true,
    );
  }

  static AppSettings decode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return AppSettings.defaults();
    }

    try {
      final decoded = jsonDecode(value);

      if (decoded is Map<String, dynamic>) {
        return AppSettings.fromJson(decoded);
      }

      if (decoded is Map) {
        return AppSettings.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {}

    return AppSettings.defaults();
  }

  String encode() => jsonEncode(toJson());
}