import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../models/telemetry.dart';
import 'auth_service.dart';

class TelemetryHistoryRecord {
  final int id;
  final String createdAt;
  final TelemetryData data;

  const TelemetryHistoryRecord({
    required this.id,
    required this.createdAt,
    required this.data,
  });

  factory TelemetryHistoryRecord.fromJson(Map<String, dynamic> json) {
    return TelemetryHistoryRecord(
      id: (json['id'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at']?.toString() ?? '',
      data: TelemetryData.fromJson(json),
    );
  }
}

class TelemetryHistoryService {
  static Future<List<TelemetryHistoryRecord>> fetchHistory({
    required String deviceId,
    int limit = 100,
  }) async {
    await AuthService.ensureAuth();

    final uri = Uri.parse('$kBaseUrl/api/telemetry/history').replace(
      queryParameters: {
        'device_id': deviceId,
        'limit': limit.toString(),
      },
    );

    final res = await http.get(uri, headers: AuthService.authHeaders);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Не удалось загрузить телеметрию');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! List) {
      return [];
    }

    return decoded
        .whereType<Map>()
        .map((e) =>
            TelemetryHistoryRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
