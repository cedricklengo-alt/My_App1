// Ce que voit l'utilisateur quand un appel n'aboutit pas.
//
// Cas réel (3 novembre 2026) : « les appels ne passent pas ». Le serveur ne
// fournissait que des serveurs STUN, or sur réseau mobile les téléphones sont
// derrière un NAT symétrique (CGNAT) : sans relais TURN, aucun chemin direct
// n'existe. L'écran d'appel se fermait alors sur un « Appel terminé » muet.
//
// Ces tests portent sur la table des libellés (lib/call_status.dart), qui est
// maintenant séparée de l'interface pour être vérifiable sans téléphone.
import 'package:flutter_test/flutter_test.dart';
import 'package:mbote/call_status.dart';

void main() {
  group('Libellé pendant l’appel', () {
    test('connexion en cours', () {
      expect(libelleAppel(status: 'connexion'), 'Connexion…');
    });

    test('ça sonne', () {
      expect(libelleAppel(status: 'ringing'), 'Ça sonne…');
    });

    test('notification envoyée quand l’app d’en face est fermée', () {
      expect(libelleAppel(status: 'ringing', pushSent: true),
          'Notification envoyée…');
    });

    test('en ligne', () {
      expect(libelleAppel(status: 'answered'), 'EN LIGNE · HD');
    });

    test('gros titre sans espace parasite', () {
      expect(libelleAppel(status: 'answered').startsWith(' '), isFalse);
    });
  });

  group('Fin d’appel : chaque cause a son message', () {
    test('fin normale', () {
      expect(libelleAppel(status: 'ended'), 'Appel terminé');
    });

    test('crédit épuisé', () {
      expect(libelleAppel(status: 'ended', endReason: 'no_credit'),
          'Crédit épuisé');
    });

    test('occupé', () {
      expect(libelleAppel(status: 'ended', endReason: 'rejected'),
          'Occupé — réessaie plus tard');
    });

    test('pas de réponse', () {
      expect(libelleAppel(status: 'ended', endReason: 'unreachable'),
          'Pas de réponse — réessaie plus tard');
    });

    test('échec réseau : le message explique au lieu de rester muet', () {
      final msg = libelleAppel(status: 'ended', endReason: 'network');
      expect(msg, contains('Réseau'));
      expect(msg, contains('Wi-Fi'));
      expect(msg, isNot('Appel terminé'));
    });

    test('echecReseau reconnaît ce cas et seulement lui', () {
      expect(echecReseau(status: 'ended', endReason: 'network'), isTrue);
      expect(echecReseau(status: 'ended', endReason: 'rejected'), isFalse);
      expect(echecReseau(status: 'answered', endReason: 'network'), isFalse);
      expect(echecReseau(status: 'ended'), isFalse);
    });
  });

  group('Choix du transport de l’appel', () {
    test('un appel MboteCall → MboteCall passe par la vraie voix (WebRTC)', () {
      expect(appelViaRtc('mbote'), isTrue);
    });

    test('un appel vers un GSM ne passe pas par WebRTC', () {
      expect(appelViaRtc(null), isFalse);
      expect(appelViaRtc(''), isFalse);
      expect(appelViaRtc('package'), isFalse);
    });

    test('le choix ne dépend PAS de rtc_online (bug du 3 novembre 2026)', () {
      // Le serveur ne renvoyait pas ce champ ; exiger rtc_online == true
      // faisait tomber tous les appels dans la simulation.
      expect(appelViaRtc('mbote'), isTrue,
          reason: 'rtc_online ne doit plus conditionner le transport');
    });
  });

  group('Erreur', () {
    test('erreur de démarrage', () {
      expect(libelleAppel(status: 'error'), 'Erreur');
    });
  });
}
