/// Configuration de l'application.
///
/// L'URL du backend est lisible depuis les variables de compilation :
///
/// ```bash
/// flutter run --dart-define=MBOTE_API=http://10.0.2.2:4000/api
/// ```
///
/// Sans `--dart-define`, on vise le serveur public Render (production).
///
/// `apiBase` est **modifiable à l'exécution** (et non plus `const`) : les tests
/// d'intégration le pointent vers un serveur local lancé à la volée.
class Config {
  /// Production par défaut.
  static const String defaultApi = 'https://mbote-backend-1.onrender.com/api';

  /// Surchargeable à la compilation : `--dart-define=MBOTE_API=…`
  static const String _fromEnv =
      String.fromEnvironment('MBOTE_API', defaultValue: '');

  /// Base effective des appels HTTP (sans slash final).
  static String apiBase = _fromEnv.isEmpty ? defaultApi : _fromEnv;

  /// Remet la configuration de production.
  static void reset() => apiBase = _fromEnv.isEmpty ? defaultApi : _fromEnv;

  /// Base du canal temps réel : https://…/api → wss://…/ws
  static String get wsUrl =>
      '$apiBase/ws'.replaceFirst('/api/ws', '/ws').replaceFirst('http', 'ws');
}
