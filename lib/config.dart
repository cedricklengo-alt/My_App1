/// Configuration de l'application.
///
/// ✅ URL configurée sur VOTRE serveur public Render (production).
///
/// Pour le développement local, remplacez par :
///  - Émulateur Android  : http://10.0.2.2:4000/api
///  - Téléphone physique : `adb reverse tcp:4000 tcp:4000` puis
///                         http://127.0.0.1:4000/api
class Config {
  static const String apiBase = 'https://mbote-backend-1.onrender.com/api';
}
