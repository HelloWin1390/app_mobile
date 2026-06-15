import 'package:shared_preferences/shared_preferences.dart';

class ServerConfigService {
  static const String _serverUrlKey = 'bpna_server_url';
  static const String _filesUrlKey = 'bpna_files_url';

  static const String defaultServerUrl = 'https://bpna-production.up.railway.app';

  static String _serverUrl = defaultServerUrl;
  static String _filesUrl = defaultServerUrl;

  static String get serverUrl => _serverUrl;
  static String get filesUrl => _filesUrl;

  static String get baseUrl {
    return _serverUrl.replaceAll(RegExp(r'/+$'), '');
  }

  static String get filesBaseUrl {
    return _filesUrl.replaceAll(RegExp(r'/+$'), '');
  }

  static String get wsBase {
    final clean = baseUrl;

    if (clean.startsWith('https://')) {
      return clean.replaceFirst('https://', 'wss://');
    }

    if (clean.startsWith('http://')) {
      return clean.replaceFirst('http://', 'ws://');
    }

    return clean;
  }

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    _serverUrl = prefs.getString(_serverUrlKey) ?? defaultServerUrl;
    _filesUrl = prefs.getString(_filesUrlKey) ?? _serverUrl;

    _serverUrl = _normalizeUrl(_serverUrl);
    _filesUrl = _normalizeUrl(_filesUrl);
  }

  static Future<void> save({
    required String serverUrl,
    String? filesUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    _serverUrl = _normalizeUrl(serverUrl);
    _filesUrl = _normalizeUrl(
      filesUrl == null || filesUrl.trim().isEmpty ? serverUrl : filesUrl,
    );

    await prefs.setString(_serverUrlKey, _serverUrl);
    await prefs.setString(_filesUrlKey, _filesUrl);
  }

  static Future<void> resetToDefault() async {
    await save(
      serverUrl: defaultServerUrl,
      filesUrl: defaultServerUrl,
    );
  }

  static String _normalizeUrl(String value) {
    var url = value.trim();

    while (url.endsWith('/') && url.length > 1) {
      url = url.substring(0, url.length - 1);
    }

    return url;
  }
}