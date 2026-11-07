// lib/liens.dart
// LIENS PROFONDS — mbote://post/<id>
//
// La page publique /p/<id> propose « Ouvrir dans MboteCall ». Sans réception
// de ce lien, ce bouton ne ferait rien : c'est la moitié manquante du partage.
// Ici, l'application écoute le schéma `mbote://` et retient la publication
// demandée, que le fil vient ouvrir.
//
// Android : l'intent-filter du manifeste déclare le schéma `mbote`, et
// MainActivity transmet le lien par le canal `mbote/liens`.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class Liens {
  /// Identifiant de la publication à ouvrir. Le fil l'écoute : dès qu'une
  /// valeur arrive, il l'ouvre puis la remet à null.
  static final ValueNotifier<String?> post = ValueNotifier<String?>(null);

  /// Commentaire à ouvrir directement (notification « Nouveau commentaire ») :
  /// le fil ouvre la publication puis sa feuille de commentaires.
  static final ValueNotifier<String?> commentaire = ValueNotifier<String?>(null);

  /// Dernier identifiant traité, pour ne pas rouvrir deux fois la même
  /// publication quand le système relivre l'intent.
  static String? _dernierTraite;

  static const MethodChannel _canal = MethodChannel('mbote/liens');

  static bool _branche = false;

  /// Branche l'écoute. Appelée une fois au démarrage ; sans effet en test.
  static Future<void> demarrer() async {
    if (_branche) return;
    _branche = true;
    _canal.setMethodCallHandler((call) async {
      if (call.method == 'lien' && call.arguments is String) {
        traiter(call.arguments as String);
      }
    });
    try {
      // Lien qui a lancé l'application (app fermée).
      final initial = await _canal.invokeMethod<String>('lienInitial');
      if (initial != null && initial.isNotEmpty) traiter(initial);
    } catch (_) {
      // Canal absent (test, bureau) : rien à faire.
    }
  }

  /// Analyse `mbote://post/<id>` (ou `post/<id>`, forme transmise par Android).
  /// Renvoie l'identifiant, ou null si le lien n'est pas reconnu.
  @visibleForTesting
  static String? idDepuisLien(String lien) {
    final brut = lien.trim();
    if (brut.isEmpty) return null;
    var chemin = brut;
    if (chemin.startsWith('mbote://')) {
      chemin = chemin.substring('mbote://'.length);
    } else if (chemin.contains('://')) {
      return null; // un autre schéma ne nous concerne pas
    }
    if (chemin.startsWith('post/')) chemin = chemin.substring('post/'.length);
    // On ne garde que l'identifiant : ni barre oblique, ni paramètre d'URL.
    final id = chemin.split(RegExp(r'[/?#]')).first.trim();
    return id.isEmpty ? null : id;
  }

  /// Retient la publication demandée par un lien.
  static void traiter(String lien) {
    final id = idDepuisLien(lien);
    if (id == null || id == _dernierTraite) return;
    _dernierTraite = id;
    post.value = id;
  }

  /// Réinitialise (tests).
  @visibleForTesting
  static void reset() {
    _dernierTraite = null;
    post.value = null;
    _branche = false;
  }
}
