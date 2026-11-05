/// Le libellé affiché sous le nom pendant un appel.
///
/// Extrait de l'écran d'appel pour être testable sans monter l'interface :
/// c'est ici que se joue la différence entre « l'appel ne passe pas » (aucun
/// message utile) et une explication claire pour l'utilisateur.
library;

/// États possibles : connexion · ringing · answered · ended · error.
///
/// [endReason] précise *pourquoi* l'appel s'est terminé :
/// `no_credit`, `rejected`, `unreachable`, `network` (aucun chemin réseau),
/// `busy`… Sinon « Appel terminé ».
///
/// [pushSent] : l'appelé ne répond pas encore mais une notification est partie.
String libelleAppel({
  required String status,
  String? endReason,
  bool pushSent = false,
}) {
  switch (status) {
    case 'connexion':
      return 'Connexion…';
    case 'ringing':
      return pushSent ? 'Notification envoyée…' : 'Ça sonne…';
    case 'answered':
      return 'EN LIGNE · HD';
    case 'ended':
      switch (endReason) {
        case 'no_credit':
          return 'Crédit épuisé';
        case 'rejected':
          return 'Occupé — réessaie plus tard';
        case 'unreachable':
          return 'Pas de réponse — réessaie plus tard';
        case 'network':
          // Cas réel : deux téléphones derrière un NAT symétrique (réseau
          // mobile) sans relais TURN ne trouvent aucun chemin. On explique
          // au lieu d'afficher un « Appel terminé » muet.
          return 'Réseau trop restrictif — réessaie en Wi-Fi ou en 4G';
        default:
          return 'Appel terminé';
      }
    default:
      return 'Erreur';
  }
}

/// Faut-il passer par la VRAIE voix (WebRTC) pour cet appel ?
///
/// Un appel MboteCall → MboteCall est gratuit et passe par le standardiste :
/// la voix circule de téléphone à téléphone. Le drapeau `rtc_online` renvoyé
/// par le serveur ne doit PAS conditionner ce choix : il indique seulement si
/// l'appelé a déjà son canal ouvert. Un appelé hors ligne reçoit une
/// notification et l'offre l'attend côté serveur.
///
/// Bug corrigé (journaux Render du 3 novembre 2026) : l'application exigeait
/// `rtc_online == true`, champ qui n'était jamais renvoyé — donc TOUS les
/// appels tombaient dans la simulation, l'appelé ne sonnait jamais et l'appel
/// « ne passait pas ».
bool appelViaRtc(String? freeReason) => freeReason == 'mbote';

/// L'appel s'est-il terminé faute de chemin réseau ? (pour proposer un conseil)
bool echecReseau({required String status, String? endReason}) =>
    status == 'ended' && endReason == 'network';
