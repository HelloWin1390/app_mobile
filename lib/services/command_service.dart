import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import 'auth_service.dart';

class CommandService {
  static Map<String, String> get _headers {
    return {
      ...AuthService.authHeaders,
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };
  }

  static Future<bool> send(
    String command, {
    String? deviceId,
  }) async {
    await AuthService.ensureAuth();

    try {
      final deviceSecret = deviceId?.trim();

      final body = <String, dynamic>{
        'command': command,
        if (deviceSecret != null && deviceSecret.isNotEmpty)
          'device_id': deviceSecret,
        if (deviceSecret != null && deviceSecret.isNotEmpty)
          'secret': deviceSecret,
        if (deviceSecret != null && deviceSecret.isNotEmpty)
          'device_secret': deviceSecret,
      };

      final res = await http.post(
        Uri.parse('$kBaseUrl/api/device/command'),
        headers: _headers,
        body: jsonEncode(body),
      );

      debugPrint('[COMMAND] POST $kBaseUrl/api/device/command');
      debugPrint('[COMMAND] body: ${jsonEncode(body)}');
      debugPrint('[COMMAND] status: ${res.statusCode}');
      debugPrint('[COMMAND] response: ${res.body}');

      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[COMMAND] error: $e');
      return false;
    }
  }

  static Future<bool> sendFlashlightToggle({
    String? deviceId,
  }) async {
    return send(
      'flashlight-toggle',
      deviceId: deviceId,
    );
  }

  static Future<bool> sendExtraControl({
    required String type,
    String? deviceId,
    double? value,
    bool? enabled,
  }) async {
    await AuthService.ensureAuth();

    try {
      final deviceSecret = deviceId?.trim();

      String command;

      if (type == 'toggle') {
        command = enabled == true ? 'extra-toggle-on' : 'extra-toggle-off';
      } else if (type == 'slider') {
        command = 'extra-slider';
      } else {
        command = 'extra-button';
      }

      final body = <String, dynamic>{
        'command': command,
        'extra_type': type,
        if (value != null) 'value': value,
        if (value != null) 'extra_value': value,
        if (enabled != null) 'enabled': enabled,
        if (deviceSecret != null && deviceSecret.isNotEmpty)
          'device_id': deviceSecret,
        if (deviceSecret != null && deviceSecret.isNotEmpty)
          'secret': deviceSecret,
        if (deviceSecret != null && deviceSecret.isNotEmpty)
          'device_secret': deviceSecret,
      };

      final res = await http.post(
        Uri.parse('$kBaseUrl/api/device/command'),
        headers: _headers,
        body: jsonEncode(body),
      );

      debugPrint('[EXTRA] POST $kBaseUrl/api/device/command');
      debugPrint('[EXTRA] body: ${jsonEncode(body)}');
      debugPrint('[EXTRA] status: ${res.statusCode}');
      debugPrint('[EXTRA] response: ${res.body}');

      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[EXTRA] error: $e');
      return false;
    }
  }

  static Future<void> stop({String? deviceId}) async {
    await send(
      'stop',
      deviceId: deviceId,
    );
  }
}