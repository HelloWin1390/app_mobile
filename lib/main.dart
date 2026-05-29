import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_settings.dart';
import 'screens/auth_gate_screen.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  await SettingsService.load();

  runApp(const BpnaApp());
}

class BpnaApp extends StatelessWidget {
  const BpnaApp({super.key});

  ThemeData _darkTheme(bool accessibility) {
    final baseTextScale = accessibility ? 1.14 : 1.0;

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        surface: Color(0xFF171614),
        primary: Color(0xFF4F98A3),
        secondary: Color(0xFF6DAA45),
        error: Color(0xFFDD6974),
      ),
      scaffoldBackgroundColor: const Color(0xFF171614),
      useMaterial3: true,
      textTheme: Typography.whiteMountainView.apply(
        fontSizeFactor: baseTextScale,
      ),
      visualDensity: accessibility
          ? VisualDensity.comfortable
          : VisualDensity.standard,
    );
  }

  ThemeData _lightTheme(bool accessibility) {
    final baseTextScale = accessibility ? 1.14 : 1.0;

    return ThemeData(
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        surface: Color(0xFFF4F6F8),
        primary: Color(0xFF167C8C),
        secondary: Color(0xFF3F8F45),
        error: Color(0xFFC83A4A),
      ),
      scaffoldBackgroundColor: const Color(0xFFF4F6F8),
      useMaterial3: true,
      textTheme: Typography.blackMountainView.apply(
        fontSizeFactor: baseTextScale,
      ),
      visualDensity: accessibility
          ? VisualDensity.comfortable
          : VisualDensity.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettings>(
      valueListenable: SettingsService.settingsNotifier,
      builder: (context, settings, _) {
        final isLight = settings.themeMode == AppThemeMode.light;

        return MaterialApp(
          title: 'BPNA Control',
          debugShowCheckedModeBanner: false,
          theme: _lightTheme(settings.accessibilityMode),
          darkTheme: _darkTheme(settings.accessibilityMode),
          themeMode: isLight ? ThemeMode.light : ThemeMode.dark,
          builder: (context, child) {
            final media = MediaQuery.of(context);

            return MediaQuery(
              data: media.copyWith(
                textScaler: settings.accessibilityMode
                    ? const TextScaler.linear(1.14)
                    : TextScaler.noScaling,
                boldText: settings.accessibilityMode,
                highContrast: settings.accessibilityMode,
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const AuthGateScreen(),
        );
      },
    );
  }
}