import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/app_user.dart';

class AuthService {
  static const String _tokenKey = 'bpna_access_token';

  static String? _token;
  static AppUser? _currentUser;
  static bool _loaded = false;

  static String? get token => _token;
  static AppUser? get currentUser => _currentUser;

  static Future<void> _loadToken() async {
    if (_loaded) return;

    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _loaded = true;
  }

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

      if (res.statusCode != 200) {
        return false;
      }

      final data = jsonDecode(res.body);
      final nextToken = data['access_token']?.toString();
      if (nextToken == null || nextToken.isEmpty) {
        return false;
      }

      _token = nextToken;
      _loaded = true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, nextToken);

      _currentUser = await fetchCurrentUser();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> restoreSession() async {
    await _loadToken();
    if (_token == null) return false;

    final user = await fetchCurrentUser();
    if (user == null) {
      await logout();
      return false;
    }

    _currentUser = user;
    return true;
  }

  static Future<AppUser?> fetchCurrentUser() async {
    await _loadToken();
    if (_token == null) return null;

    try {
      final res = await http.get(
        Uri.parse('$kBaseUrl/api/auth/me'),
        headers: authHeaders,
      );

      if (res.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic>) {
        return AppUser.fromJson(data);
      }
    } catch (_) {}

    return null;
  }

  static Future<bool> ensureAuth() async {
    await _loadToken();
    return _token != null;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);

    _token = null;
    _currentUser = null;
    _loaded = true;
  }

  static Map<String, String> get authHeaders => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };
}
