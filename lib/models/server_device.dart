class ServerDevice {
  final int id;
  final String deviceId;
  final String name;
  final String status;
  final bool connected;
  final bool youControl;
  final String? controllerUsername;
  final String? lastSeen;

  const ServerDevice({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.status,
    required this.connected,
    required this.youControl,
    this.controllerUsername,
    this.lastSeen,
  });

  factory ServerDevice.fromJson(Map<String, dynamic> json) {
    return ServerDevice(
      id: (json['id'] as num?)?.toInt() ?? 0,
      deviceId: json['device_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      status: json['status']?.toString() ?? 'offline',
      connected: json['connected'] == true,
      youControl: json['you_control'] == true,
      controllerUsername: json['controller_username']?.toString(),
      lastSeen: json['last_seen']?.toString(),
    );
  }

  String get displayName => name.trim().isEmpty ? deviceId : name;

  bool get isOnline => status == 'online';
  bool get isBusy => status == 'busy';
  bool get isOffline => status == 'offline';
}
