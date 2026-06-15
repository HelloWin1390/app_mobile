import '../services/server_config_service.dart';

const String kAutoLogin = 'operator';
const String kAutoPassword = 'operator123';

String get kBaseUrl => ServerConfigService.baseUrl;
String get kWsBase => ServerConfigService.wsBase;
String get kFilesBaseUrl => ServerConfigService.filesBaseUrl;