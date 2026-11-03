import 'package:flutter/foundation.dart';

///Signal de rafraîchissement des onglets.
///
/// Toucher l'onglet déjà actif (comme dans WhatsApp) recharge son contenu :
/// le fil d'actualité remonte les nouveautés, l'historique d'appels et les
/// discussions se resynchronisent. Chaque écran s'abonne à son compteur.
class Tabs {
  static const int feed = 0;
  static const int calls = 1;
  static const int messages = 2;

  static final List<ValueNotifier<int>> _ticks =
      List<ValueNotifier<int>>.generate(3, (_) => ValueNotifier<int>(0));

  /// S'abonner aux demandes de rafraîchissement d'un onglet.
  static void listen(int tab, VoidCallback onRefresh) =>
      _ticks[tab].addListener(onRefresh);

  static void stopListening(int tab, VoidCallback onRefresh) =>
      _ticks[tab].removeListener(onRefresh);

  /// Demander à un onglet de se rafraîchir.
  static void refresh(int tab) => _ticks[tab].value++;

  /// Pour les tests : remet les compteurs à zéro.
  @visibleForTesting
  static void reset() {
    for (final t in _ticks) {
      t.value = 0;
    }
  }
}
