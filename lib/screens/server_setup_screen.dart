import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/server_config_service.dart';
import 'auth_gate_screen.dart';

/// Экран настройки адреса сервера перед авторизацией.
///
/// Нужен, чтобы перед входом в приложение пользователь мог выбрать:
/// - Railway-сервер;
/// - локальный сервер на компьютере;
/// - другой сервер в сети.
class ServerSetupScreen extends StatefulWidget {
  /// Создаёт экран настройки сервера.
  const ServerSetupScreen({super.key});

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

/// Состояние экрана настройки сервера.
class _ServerSetupScreenState extends State<ServerSetupScreen> {
  /// Контроллер поля адреса сервера.
  final TextEditingController _serverController = TextEditingController();

  /// Признак проверки подключения.
  bool _checking = false;

  /// Сообщение для пользователя.
  String? _message;

  @override
  void initState() {
    super.initState();

    _serverController.text = ServerConfigService.baseUrl;
  }

  /// Убирает лишние слэши в конце адреса.
  String _cleanUrl(String value) {
    var url = value.trim();

    while (url.endsWith('/') && url.length > 1) {
      url = url.substring(0, url.length - 1);
    }

    return url;
  }

  /// Проверяет, что адрес начинается с http:// или https://.
  bool _isValidUrl(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  /// Проверяет доступность сервера через endpoint /health.
  Future<void> _checkConnection() async {
    final serverUrl = _cleanUrl(_serverController.text);

    if (serverUrl.isEmpty) {
      setState(() {
        _message = 'Укажите адрес сервера';
      });
      return;
    }

    if (!_isValidUrl(serverUrl)) {
      setState(() {
        _message = 'Адрес должен начинаться с http:// или https://';
      });
      return;
    }

    setState(() {
      _checking = true;
      _message = null;
    });

    try {
      final response = await http
          .get(Uri.parse('$serverUrl/health'))
          .timeout(const Duration(seconds: 5));

      if (!mounted) return;

      setState(() {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _message = 'Сервер доступен';
        } else {
          _message = 'Сервер ответил с кодом ${response.statusCode}';
        }
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _message = 'Не удалось подключиться к серверу';
      });
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }

  /// Сохраняет адрес сервера и переходит к авторизации.
  Future<void> _saveAndContinue() async {
    final serverUrl = _cleanUrl(_serverController.text);

    if (serverUrl.isEmpty) {
      setState(() {
        _message = 'Укажите адрес сервера';
      });
      return;
    }

    if (!_isValidUrl(serverUrl)) {
      setState(() {
        _message = 'Адрес должен начинаться с http:// или https://';
      });
      return;
    }

    await ServerConfigService.save(
      serverUrl: serverUrl,
      filesUrl: serverUrl,
    );

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const AuthGateScreen(),
      ),
    );
  }

  /// Сбрасывает адрес сервера на Railway.
  Future<void> _resetToRailway() async {
    await ServerConfigService.resetToDefault();

    if (!mounted) return;

    setState(() {
      _serverController.text = ServerConfigService.baseUrl;
      _message = 'Установлен сервер по умолчанию';
    });
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF171614);
    const panel = Color(0xFF1C1B19);
    const accent = Color(0xFF4F98A3);
    const text = Color(0xFFCDCCCA);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 520,
              ),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.10),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Подключение к серверу',
                      style: TextStyle(
                        color: text,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'Укажите адрес серверной части перед авторизацией.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(height: 22),

                    TextField(
                      controller: _serverController,
                      keyboardType: TextInputType.url,
                      style: const TextStyle(
                        color: text,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Адрес сервера',
                        hintText: 'http://192.168.0.44:8000',
                        labelStyle: TextStyle(
                          color: Colors.white.withOpacity(0.65),
                        ),
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.35),
                        ),
                        helperText:
                            'Для Railway: https://bpna-production.up.railway.app',
                        helperStyle: TextStyle(
                          color: Colors.white.withOpacity(0.35),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.18),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: accent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _message!,
                          style: const TextStyle(
                            color: Color(0xFFD19900),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _checking ? null : _checkConnection,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: text,
                              side: BorderSide(
                                color: Colors.white.withOpacity(0.25),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                            child: Text(
                              _checking ? 'Проверка...' : 'Проверить',
                            ),
                          ),
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saveAndContinue,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                            child: const Text(
                              'Продолжить',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _resetToRailway,
                        child: const Text(
                          'Сбросить на Railway-сервер',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}