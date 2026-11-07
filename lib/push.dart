import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'screens/chat.dart';
import 'screens/chats.dart';
import 'liens.dart';
import 'screens/feed_screen.dart';
import 'screens/history.dart';
import 'screens/incoming_call.dart';

///Notifications d'appel (Firebase Cloud Messaging)
///
/// Enregistre ce téléphone auprès du serveur pour qu'il puisse le RÉVEILLER
/// quand quelqu'un appelle et que l'app est fermée (comme WhatsApp) :
///  1. on demande la permission notifications (popup Android 13+),
///  2. on récupère le jeton unique de ce téléphone,
///  3. on l'envoie au serveur (POST /auth/fcm-token).
///
/// Si Firebase n'est pas configuré (google-services.json absent) ou si
/// l'utilisateur refuse : tout est ignoré en silence, l'app marche comme avant.
/// Handler FCM d'arrière-plan (data-only reçu app en arrière-plan).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage m) async {
  // Sans ce handler, un « call_cancel » reçu app en arrière-plan serait
  // perdu silencieusement. Ici on se contente de consommer le message :
  // la fermeture de l'écran d'appel est gérée par le canal temps réel.
  Push.consommerArrierePlan(m.data);
}

class Push {
  static bool _done = false;
  static bool _listening = false;
  static bool _appelPushAffiche = false;

  /// 🔔 Rappel posé par l'UI (fil) pour rafraîchir le badge quand un push
  /// arrive app OUVERTE (le système n'affiche que les « notification »).
  static VoidCallback? surPushAuPremierPlan;

  /// Traite un data-only reçu hors premier plan (consommé, journalisé).
  static void consommerArrierePlan(Map<String, dynamic> data) {
    // Point d'extension : nettoyage de notifications système, synchro…
  }

  /// 🔔 Deep-linking PREMIUM : toucher une notification ouvre le bon écran.
  /// Appelé AU DÉMARRAGE de l'app (main), indépendamment de la connexion :
  /// une notification qui a réveillé l'app fermée ne doit jamais être
  /// perdue, même si l'auto-login n'a pas encore abouti.
  static void initDeepLinks(GlobalKey<NavigatorState> navKey) {
    if (_listening) return;
    _listening = true;
    try {
      // Notification touchée alors que l'app était en arrière-plan
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _handleTap(navKey, m.data));
      // 📳 Push reçu app OUVERTE (data-only uniquement : les « notification »
      // sont affichés par le système) → badge à jour + réveil d'appel FCM.
      FirebaseMessaging.onMessage.listen((m) {
        surPushAuPremierPlan?.call();
        final kind = (m.data['kind'] ?? m.data['type'] ?? '').toString();
        if (kind == 'incoming_call') _ouvrirAppelPush(navKey, m.data);
      });
      // Notification touchée alors que l'app était FERMÉE (cold start)
      FirebaseMessaging.instance
          .getInitialMessage()
          .then((m) {
            if (m != null) _quandNavPret(navKey, m.data);
          })
          .catchError((_) {});
    } catch (_) {
      // Firebase absent : aucun deep-linking, l'app marche comme avant
    }
  }

  /// Au cold start, `getInitialMessage` peut se résoudre AVANT que le
  /// Navigator racine existe : on attend la première frame (puis les
  /// suivantes) avant d'ouvrir l'écran, sinon la notification serait
  /// avalée en silence (« zone vide »).
  static void _quandNavPret(GlobalKey<NavigatorState> navKey, Map<String, dynamic> data) {
    if (navKey.currentState != null) {
      _handleTap(navKey, data);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _quandNavPret(navKey, data));
    }
  }

  /// Ouvre l'écran correspondant au payload du push.
  /// « kind » (push historique) avec repli sur « type » (notifications sociales
  /// du serveur) : les deux familles doivent atterrir au même endroit.
  static void _handleTap(GlobalKey<NavigatorState> navKey, Map<String, dynamic> data) {
    final nav = navKey.currentState;
    if (nav == null) return;
    final kind = (data['kind'] ?? data['type'] ?? '').toString();
    final phone = data['from_phone']?.toString() ?? '';
    final name = data['from_name']?.toString() ?? '';
    final postId = data['post_id']?.toString() ?? '';
    final commentId = data['comment_id']?.toString() ?? '';
    if (kind == 'incoming_call') {
      _ouvrirAppelPush(navKey, data);
      return;
    }
    Widget page;
    if (kind == 'call_cancel') {
      // Appel manqué / annulé → onglet Appels
      page = const HistoryScreen();
    } else if (postId.isNotEmpty &&
        [
          'post', 'comment', 'comment_reply', 'reaction', 'post_like',
          'post_comment', 'like', 'mention', 'share',
        ].contains(kind)) {
      // 🔔 Publication / commentaire / réaction / mention / partage →
      // le fil, directement sur la publication (et les commentaires si
      // c'est un commentaire ou une réponse).
      Liens.post.value = postId;
      if (commentId.isNotEmpty || kind == 'comment' || kind == 'comment_reply') {
        if (commentId.isNotEmpty) Liens.commentaire.value = commentId;
      }
      page = const FeedScreen();
    } else if (phone.isNotEmpty) {
      // Message / info d'une personne → conversation avec elle
      page = ChatScreen(peerPhone: phone, peerName: name.isEmpty ? null : name);
    } else {
      // Autre info (follow, présence…) → liste des discussions
      page = const ChatsScreen();
    }
    nav.push(MaterialPageRoute(builder: (_) => page));
  }

  /// 📞 Push d'appel (app fermée/ouverte) → vrai écran d'appel plein écran,
  /// comme WhatsApp : l'appelé peut répondre directement depuis la notif.
  static void _ouvrirAppelPush(GlobalKey<NavigatorState> navKey, Map<String, dynamic> data) {
    final nav = navKey.currentState;
    if (nav == null || _appelPushAffiche) return;
    _appelPushAffiche = true;
    nav
        .push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => IncomingCallScreen(offer: {
            'call_id': data['call_id'] ?? '',
            'from': data['from_phone'] ?? '',
            'from_name': data['from_name'] ?? '',
            'video': data['video'] == 'true' || data['video'] == true,
          }),
        ))
        .whenComplete(() => _appelPushAffiche = false);
  }

  /// [force] : ré-enregistre même si un jeton a déjà été envoyé (bouton
  /// « Réactiver » des réglages, après un refus ou une réinstallation).
  static Future<void> register(Api api, {bool force = false}) async {
    if (_done && !force) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm
          .requestPermission(); // Android 13+ : « Autoriser les notifications ? »
      //`getToken()` est marqué déprécié au profit de `register()`/
      // `onRegistered`, MAIS ces derniers renvoient l'identifiant
      // d'installation Firebase (FID), pas le jeton d'envoi FCM. Le serveur
      // envoie des notifications HTTP v1 à `message.token` : c'est donc bien
      // le jeton FCM qu'il faut transmettre, sinon plus aucune notification
      // n'arrive. On conserve l'API historique et on l'assume ici.
      // ignore: deprecated_member_use
      final token = await fm.getToken();
      if (token == null) return;
      await api.sendFcmToken(token);
      // Le jeton peut changer (réinstallation…) → on tient le serveur à jour
      // ignore: deprecated_member_use
      fm.onTokenRefresh.listen((t) {
        api.sendFcmToken(t).catchError((_) {});
      });
      _done = true;
    } catch (_) {
      // Firebase absent ou refusé : pas de push, mais l'app fonctionne
    }
  }
}
