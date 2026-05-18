import 'package:flutter/material.dart';

import '../models/telemetry.dart';

class TelemetryCard extends StatelessWidget {
  final TelemetryData data;

  const TelemetryCard({
    super.key,
    required this.data,
  });

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF797876),
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFCDCCCA),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  String _formatLastSeen(String? value) {
    if (value == null || value.trim().isEmpty) return '-';

    try {
      final dt = DateTime.parse(value).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}:'
          '${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = data;

    final connectionColor =
        d.connected ? const Color(0xFF4F98A3) : const Color(0xFFDD6974);

    final wifiColor =
        d.wifiConnected ? const Color(0xFF6DAA45) : const Color(0xFFDD6974);

    final pingColor =
        d.pingOk ? const Color(0xFF6DAA45) : const Color(0xFFDD6974);

    final linkColor = Color(d.linkQualityColor);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1B19),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF393836)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connectionColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                d.connected ? 'Подключено' : 'Нет соединения',
                style: TextStyle(
                  color: connectionColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),

          const Divider(color: Color(0xFF262523), height: 24),

          _row('Device ID', d.deviceId ?? '-'),
          _row('Батарея', d.batteryStr),
          _row(
            'Температура',
            d.temperature != null
                ? '${d.temperature!.toStringAsFixed(1)}°C'
                : '-',
          ),
          _row('Свободная память', d.freeHeapStr),
          _row('Uptime', d.uptime != null ? d.uptimeStr : '-'),
          _row(
            'CPU Load',
            d.cpuLoad != null ? '${d.cpuLoad!.toStringAsFixed(0)}%' : '-',
          ),

          const SizedBox(height: 8),
          const Divider(color: Color(0xFF262523), height: 18),

          const Text(
            'СЕТЬ И ПИНГ',
            style: TextStyle(
              color: Color(0xFF797876),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),

          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'WiFi',
                style: TextStyle(
                  color: Color(0xFF797876),
                  fontSize: 13,
                ),
              ),
              _statusBadge(
                d.wifiConnected ? 'Online' : 'Offline',
                wifiColor,
              ),
            ],
          ),

          const SizedBox(height: 8),

          _row('WiFi RSSI', d.rssiStr),
          _row('Ping', d.pingStr),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Ping status',
                style: TextStyle(
                  color: Color(0xFF797876),
                  fontSize: 13,
                ),
              ),
              _statusBadge(d.pingStatusStr, pingColor),
            ],
          ),

          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Качество канала',
                style: TextStyle(
                  color: Color(0xFF797876),
                  fontSize: 13,
                ),
              ),
              _statusBadge(d.linkQuality, linkColor),
            ],
          ),

          const Divider(color: Color(0xFF262523), height: 24),

          _row('Обновлено', _formatLastSeen(d.lastSeen)),
        ],
      ),
    );
  }
}