const String kServerHost = "bpna-production.up.railway.app";
const int    kServerPort = 443;
const bool   kServerSSL  = true;

const String kAutoLogin    = "operator";
const String kAutoPassword = "operator123";

String get kBaseUrl => "${kServerSSL ? 'https' : 'http'}://$kServerHost";
String get kWsBase  => "${kServerSSL ? 'wss' : 'ws'}://$kServerHost";