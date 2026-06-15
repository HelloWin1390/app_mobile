  import 'package:flutter/material.dart';
  import 'package:flutter/services.dart';

  import 'screens/server_setup_screen.dart';
  import 'services/server_config_service.dart';
  import 'models/app_settings.dart';
  import 'screens/auth_gate_screen.dart';
  import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ServerConfigService.load();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  await SettingsService.load();

  runApp(const BpnaApp());
}

class BpnaApp extends StatelessWidget {
  const BpnaApp({super.key});

  ThemeData _darkTheme(bool accessibility) {
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
      visualDensity: accessibility
          ? VisualDensity.comfortable
          : VisualDensity.standard,
    );
  }

  ThemeData _lightTheme(bool accessibility) {
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
        final accessibility = settings.accessibilityMode;

        return MaterialApp(
          title: 'BPNA Control',
          debugShowCheckedModeBanner: false,
          theme: _lightTheme(accessibility),
          darkTheme: _darkTheme(accessibility),
          themeMode: isLight ? ThemeMode.light : ThemeMode.dark,
          builder: (context, child) {
            final media = MediaQuery.of(context);

            return MediaQuery(
              data: media.copyWith(
                textScaler: accessibility
                    ? const TextScaler.linear(1.18)
                    : const TextScaler.linear(1.0),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const ServerSetupScreen(),
        );
      },
    );
  }
}