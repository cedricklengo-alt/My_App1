import 'package:shared_preferences/shared_preferences.dart';

/// 🔔 Préférences d'appel : sonnerie choisie + vibration.
/// Sauvegardées sur le téléphone, chargées au démarrage (main.dart).
class CallPrefs {
  /// 'classique' (sonnerie du téléphone) · 'douce' (notification)
  /// · 'forte' (alarme) · 'silencieux'
  static String ringtone = 'classique';
  static bool vibration = true;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      ringtone = p.getString('ring_type') ?? 'classique';
      vibration = p.getBool('ring_vibration') ?? true;
    } catch (_) {/* valeurs par défaut */}
  }

  static Future<void> setRingtone(String v) async {
    ringtone = v;
    try {
      (await SharedPreferences.getInstance()).setString('ring_type', v);
    } catch (_) {}
  }

  static Future<void> setVibration(bool v) async {
    vibration = v;
    try {
      (await SharedPreferences.getInstance()).setBool('ring_vibration', v);
    } catch (_) {}
  }
}
