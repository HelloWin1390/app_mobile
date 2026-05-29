import 'package:flutter/material.dart';

import '../services/telemetry_history_service.dart';

class TelemetryHistoryScreen extends StatefulWidget {
  final String deviceId;

  const TelemetryHistoryScreen({
    super.key,
    required this.deviceId,
  });

  @override
  State<TelemetryHistoryScreen> createState() => _TelemetryHistoryScreenState();
}

class _TelemetryHistoryScreenState extends State<TelemetryHistoryScreen> {
  late Future<List<TelemetryHistoryRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<TelemetryHistoryRecord>> _load() {
    return TelemetryHistoryService.fetchHistory(deviceId: widget.deviceId);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  String _formatDate(String value) {
    if (value.trim().isEmpty) return '-';

    try {
      final dt = DateTime.parse(value).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.'
          '${dt.month.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}:'
          '${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return value;
    }
  }

  Widget _row(String label, String value) {
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
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(TelemetryHistoryRecord record) {
    final data = record.data;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1B19),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF393836)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.insights,
                color: Color(0xFF4F98A3),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _formatDate(record.createdAt),
                  style: const TextStyle(
                    color: Color(0xFFCDCCCA),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF262523), height: 20),
          _row('Device ID', data.deviceId ?? widget.deviceId),
          _row('Батарея', data.batteryStr),
          _row(
            'Температура',
            data.temperature != null
                ? '${data.temperature!.toStringAsFixed(1)}°C'
                : '-',
          ),
          _row('Wi-Fi RSSI', data.rssiStr),
          _row('Ping', data.pingStr),
          _row('Ping status', data.pingStatusStr),
          _row('Качество канала', data.linkQuality),
          _row('Свободная память', data.freeHeapStr),
          _row('Uptime', data.uptime != null ? data.uptimeStr : '-'),
          _row(
            'CPU Load',
            data.cpuLoad != null ? '${data.cpuLoad!.toStringAsFixed(0)}%' : '-',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF171614),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1B19),
        foregroundColor: const Color(0xFFCDCCCA),
        title: const Text('Телеметрия'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<TelemetryHistoryRecord>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF4F98A3)),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  snapshot.error.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF797876)),
                ),
              ),
            );
          }

          final records = snapshot.data ?? [];
          if (records.isEmpty) {
            return const Center(
              child: Text(
                'Записей телеметрии пока нет',
                style: TextStyle(color: Color(0xFF797876)),
              ),
            );
          }

          return RefreshIndicator(
            color: const Color(0xFF4F98A3),
            backgroundColor: const Color(0xFF1C1B19),
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: records.map(_card).toList(),
            ),
          );
        },
      ),
    );
  }
}
