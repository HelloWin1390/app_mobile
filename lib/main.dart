import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/auth_gate_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const BpnaApp());
}

class BpnaApp extends StatelessWidget {
  const BpnaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'БПНА Управление',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF171614),
          primary: Color(0xFF4F98A3),
        ),
        scaffoldBackgroundColor: const Color(0xFF171614),
        useMaterial3: true,
      ),
      home: const AuthGateScreen(),
    );
  }
}
