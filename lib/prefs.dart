import 'package:shared_preferences/shared_preferences.dart';

///Préférences d'appel : sonnerie choisie + vibration.
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


/// Traduction des discussions (Lokota), réglée une fois pour toutes par
/// l'utilisateur depuis la Discussion.
///
/// Lokota n'est plus une rubrique du menu : c'est une option de la Discussion,
/// pilotée par un bouton flottant. Ces valeurs sont lues par ChatScreen pour
/// décider ce qui part au serveur (`lang_from` / `lang_to`) et ce qui s'affiche
/// sous les bulles.
class TradPrefs {
 /// Traduction globale activée ou non.
  static bool actif = false;

 /// Langue que je parle (celle de mes messages).
  static String maLangue = 'fr';

 /// Langue dans laquelle je veux lire les messages de l'autre.
  static String cible = 'ln';

 /// Transcrire et traduire aussi les notes vocales.
  static bool audio = true;

 /// Codes proposés par l'application.
  static const List<String> codes = ['fr','ln','sw'];

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      actif = p.getBool('trad_actif') ?? false;
      maLangue = p.getString('trad_ma') ??'fr';
      cible = p.getString('trad_cible') ??'ln';
      audio = p.getBool('trad_audio') ?? true;
    } catch (_) {/* valeurs par défaut */}
  }

 /// Met à jour un ou plusieurs réglages et les enregistre.
  static Future<void> set({
    bool? actif,
    String? maLangue,
    String? cible,
    bool? audio,
  }) async {
    if (actif != null) TradPrefs.actif = actif;
    if (maLangue != null && codes.contains(maLangue)) TradPrefs.maLangue = maLangue;
    if (cible != null && codes.contains(cible)) TradPrefs.cible = cible;
    if (audio != null) TradPrefs.audio = audio;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('trad_actif', TradPrefs.actif);
      await p.setString('trad_ma', TradPrefs.maLangue);
      await p.setString('trad_cible', TradPrefs.cible);
      await p.setBool('trad_audio', TradPrefs.audio);
    } catch (_) {}
  }

 /// Paire de langues à envoyer au serveur : sans traduction active, on envoie
 /// la même langue des deux côtés — le serveur ne traduit alors rien.
  static String get langFrom => maLangue;
  static String get langTo => actif ? cible : maLangue;

 /// Remet les valeurs d'origine (utile aux tests et au bouton « réinitialiser »).
  static void reset() {
    actif = false;
    maLangue = 'fr';
    cible = 'ln';
    audio = true;
  }
}
