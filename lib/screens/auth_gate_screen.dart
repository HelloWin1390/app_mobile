import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/device_service.dart';
import 'login_screen.dart';
import 'main_menu_screen.dart';

class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final authenticated = await AuthService.restoreSession();
    await DeviceService.ensureControlHeartbeat();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            authenticated ? const MainMenuScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF171614),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF4F98A3))),
    );
  }
}
