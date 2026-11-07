import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'screens/chat.dart';
import 'screens/chats.dart';
import 'liens.dart';
import 'screens/feed_screen.dart';
import 'screens/history.dart';

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
class Push {
  static bool _done = false;


  /// 🔔 Deep-linking PREMIUM : toucher une notification ouvre le bon écran.
  /// Appelé une fois au démarrage de l'app.
  static void initDeepLinks(GlobalKey<NavigatorState> navKey) {
    try {
      // Notification touchée alors que l'app était en arrière-plan
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _handleTap(navKey, m.data));
      // Notification touchée alors que l'app était FERMÉE (cold start)
      FirebaseMessaging.instance
          .getInitialMessage()
          .then((m) { if (m != null) _handleTap(navKey, m.data); })
          .catchError((_) {});
    } catch (_) {
      // Firebase absent : aucun deep-linking, l'app marche comme avant
    }
  }

  /// Ouvre l'écran correspondant au payload du push.
  static void _handleTap(GlobalKey<NavigatorState> navKey, Map<String, dynamic> data) {
    final nav = navKey.currentState;
    if (nav == null) return;
    final kind = data['kind']?.toString() ?? '';
    final phone = data['from_phone']?.toString() ?? '';
    final name = data['from_name']?.toString() ?? '';
    final postId = data['post_id']?.toString() ?? '';
    final commentId = data['comment_id']?.toString() ?? '';
    Widget page;
    if (kind == 'incoming_call' || kind == 'call_cancel') {
      // Appel (manqué) → onglet Appels
      page = const HistoryScreen();
    } else if (postId.isNotEmpty &&
        ['post', 'comment', 'reaction', 'post_like', 'post_comment', 'like']
            .contains(kind)) {
      // 🔔 Publication / commentaire / réaction → le fil, directement sur
      // la publication (et les commentaires si c'est un commentaire).
      Liens.post.value = postId;
      if (commentId.isNotEmpty) Liens.commentaire.value = commentId;
      page = const FeedScreen();
    } else if (phone.isNotEmpty) {
      // Message / info d'une personne → conversation avec elle
      page = ChatScreen(peerPhone: phone, peerName: name.isEmpty ? null : name);
    } else {
      // Autre info → liste des discussions
      page = const ChatsScreen();
    }
    nav.push(MaterialPageRoute(builder: (_) => page));
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
