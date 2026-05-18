import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class AuthService {
  static String? _token;

  static String? get token => _token;

  static Future<bool> login({
    String username = kAutoLogin,
    String password = kAutoPassword,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$kBaseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _token = data['access_token'];
        return _token != null;
      }
    } catch (_) {}
    return false;
  }

  static Future<bool> ensureAuth() async {
    if (_token != null) return true;
    return await login();
  }

  static Map<String, String> get authHeaders => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };
}