import 'package:firebase_messaging/firebase_messaging.dart';
import 'api.dart';

/// 🔔 Notifications d'appel (Firebase Cloud Messaging)
///
/// Enregistre ce téléphone auprès du serveur pour qu'il puisse le RÉVEILLER
/// quand quelqu'un appelle et que l'app est fermée (comme WhatsApp) :
///  1. on demande la permission notifications (popup Android 13+),
///  2. on récupère le jeton unique de ce téléphone,
///  3. on l'envoie au serveur (POST /auth/fcm-token).
///
/// Si Firebase n'est pas configuré (google-services.json absent) ou si
/// l'utilisateur refuse : tout est ignoré en silence, l'app marche comme avant.
class Push {
  static bool _done = false;

  static Future<void> register(Api api) async {
    if (_done) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission(); // Android 13+ : « Autoriser les notifications ? »
      final token = await fm.getToken();
      if (token == null) return;
      await api.sendFcmToken(token);
      // Le jeton peut changer (réinstallation…) → on tient le serveur à jour
      fm.onTokenRefresh.listen((t) {
        api.sendFcmToken(t).catchError((_) {});
      });
      _done = true;
    } catch (_) {
      // Firebase absent ou refusé : pas de push, mais l'app fonctionne
    }
  }
}
