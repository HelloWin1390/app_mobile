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

  const AppSettings({
    required this.selectedDeviceId,
    required this.devices,
    required this.extraControlType,
  });

  factory AppSettings.defaults() {
    return const AppSettings(
      selectedDeviceId: '',
      devices: [],
      extraControlType: ExtraControlType.button,
    );
  }

  AppSettings copyWith({
    String? selectedDeviceId,
    List<EspDevice>? devices,
    String? extraControlType,
  }) {
    return AppSettings(
      selectedDeviceId: selectedDeviceId ?? this.selectedDeviceId,
      devices: devices ?? this.devices,
      extraControlType:
          ExtraControlType.normalize(extraControlType ?? this.extraControlType),
    );
  }

  Map<String, dynamic> toJson() => {
        'selectedDeviceId': selectedDeviceId,
        'devices': devices.map((e) => e.toJson()).toList(),
        'extraControlType': extraControlType,
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
    } catch (_) {}

    return AppSettings.defaults();
  }

  String encode() => jsonEncode(toJson());
}