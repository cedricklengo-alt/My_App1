import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'config.dart';
import 'models/post.dart';
import 'models/social.dart';

class ApiException implements Exception {
  final String message;
  final String? code;
  ApiException(this.message, [this.code]);
  @override
  String toString() => message;
}

///Transforme n'importe quelle erreur en message compréhensible.
/// À utiliser PARTOUT où l'on affiche une erreur à l'utilisateur :
/// jamais de jargon technique à l'écran.
String friendlyError(Object e) {
  if (e is ApiException) return e.message;
  if (e is SocketException || e is http.ClientException) {
    return 'Pas d\'Internet — vérifie ta connexion';
  }
  if (e is TimeoutException) {
    return 'Le serveur met trop de temps à répondre — réessaie dans un instant';
  }
  return 'Un petit souci est survenu — réessaie';
}

/// Client HTTP unique vers le backend MboteCall
class Api {
  String? token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// En-têtes pour les widgets qui vont chercher un fichier privé
  /// (`Image.network`, lecteur audio) : mêmes droits que l'API.
  Map<String, String> get authHeaders =>
      {if (token != null) 'Authorization': 'Bearer $token'};

  static const _timeout = Duration(seconds: 20);

  Future<dynamic> _send(String method, String path, [Map? body]) async {
    final uri = Uri.parse('${Config.apiBase}$path');
    late http.Response r;
    try {
      switch (method) {
        case 'GET':
          r = await http.get(uri, headers: _headers).timeout(_timeout);
        case 'POST':
          r = await http
              .post(uri, headers: _headers, body: jsonEncode(body ?? {}))
              .timeout(_timeout);
        case 'PUT':
          r = await http
              .put(uri, headers: _headers, body: jsonEncode(body ?? {}))
              .timeout(_timeout);
        case 'DELETE':
          r = await http.delete(uri, headers: _headers).timeout(_timeout);
      }
    } on SocketException {
      throw ApiException(
          'Pas d\'Internet — vérifie ta connexion', 'offline');
    } on http.ClientException {
      throw ApiException(
          'Pas d\'Internet — vérifie ta connexion', 'offline');
    } on TimeoutException {
      throw ApiException(
          'Le serveur met trop de temps à répondre — réessaie dans un instant',
          'timeout');
    }
    dynamic data;
    try {
      data = r.body.isEmpty ? {} : jsonDecode(r.body);
    } catch (_) {
      data = {};
    }
    if (r.statusCode >= 400) {
      // Le serveur parle déjà en clair (messages en français) ; sinon,
      // on couvre avec un message générique compréhensible.
      throw ApiException(
          data is Map
              ? (data['error'] ??
                  'Service momentanément indisponible — réessaie')
              : 'Service momentanément indisponible — réessaie',
          data is Map ? data['code'] : null);
    }
    return data;
  }

  // ---- Auth ----
  Future<Map> requestOtp(String phone) async =>
      await _send('POST', '/auth/request-otp', {'phone': phone});
  Future<Map> verifyOtp(String phone, String code,
          {String? name,
          String? referralCode,
          String? dialCode,
          String? country,
          String? appVersion,
          String? language}) async =>
      await _send('POST', '/auth/verify-otp', {
        'phone': phone,
        'code': code,
        if (name != null) 'name': name,
        if (referralCode != null && referralCode.isNotEmpty)
          'referral_code': referralCode,
        if (dialCode != null) 'dial_code': dialCode,
        if (country != null) 'country': country,
        if (appVersion != null) 'app_version': appVersion,
        if (language != null) 'language': language,
      });

  /// Valide la session au démarrage (splash → accueil direct).
  Future<Map> checkSession() async => await _send('GET', '/auth/session');

  /// Rotation du refresh token → nouveaux jetons.
  Future<Map> refreshSession(String refreshToken) async =>
      await _send('POST', '/auth/refresh', {'refresh_token': refreshToken});

  /// Déconnexion volontaire côté serveur (révoque la session).
  Future<void> logoutServer(String? refreshToken) async {
    try {
      await _send('POST', '/auth/logout',
          refreshToken != null ? {'refresh_token': refreshToken} : null);
    } catch (_) {/* réseau coupé : la session locale est quand même effacée */}
  }
  Future<Map> me() async => await _send('GET', '/auth/me');
  Future<void> updateName(String name) async =>
      await _send('PUT', '/auth/me', {'name': name});

  ///Photo de profil (data-URI compressée) · null = supprimer
  Future<void> updateAvatar(String? dataUri) async =>
      await _send('PUT', '/auth/me', {'avatar': dataUri ?? ''});

  // ---- Wallet ----
  Future<Map> wallet() async => await _send('GET', '/wallet');

  ///Tableau de bord : solde, dépenses du jour et du mois, appels, SMS.
  /// Tous les chiffres viennent du grand livre du serveur (aucune estimation).
  Future<Map> walletSummary() async => await _send('GET', '/wallet/summary');

  ///Grand livre filtrable : type, statut, période, pagination.
  Future<Map> walletTransactions({
    String type = 'all',
    String status = 'all',
    int? from,
    int? to,
    int limit = 50,
    int offset = 0,
  }) async {
    final q = StringBuffer('/wallet/transactions?type=$type&status=$status'
        '&limit=$limit&offset=$offset');
    if (from != null) q.write('&from=$from');
    if (to != null) q.write('&to=$to');
    return await _send('GET', q.toString());
  }

  /// Lance une recharge Mobile Money : le backend déclenche un USSD Push
  /// sur le téléphone payeur → renvoie {payment_id, status:'pending', message}.
  Future<Map> topup(int amountCents, String method, {String? phone}) async =>
      await _send('POST', '/wallet/topup', {
        'amount_cents': amountCents,
        'method': method,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      });

  /// Suivi du paiement (polling toutes les 2 s) :
  /// {status: pending|success|failed, credited_cents, bonus_cents, balance_cents}
  Future<Map> topupStatus(String paymentId) async =>
      await _send('GET', '/wallet/topup/$paymentId/status');

  ///Transfert de crédit MboteCall → MboteCall
  Future<Map> transfer(String toPhone, int amountCents) async => await _send(
      'POST',
      '/wallet/transfer',
      {'to_phone': toPhone, 'amount_cents': amountCents});

  // ----Forfaits ----
  Future<List> packages() async => await _send('GET', '/packages');
  Future<List> myPackages() async => await _send('GET', '/packages/mine');
  Future<Map> buyPackage(int id) async =>
      await _send('POST', '/packages/$id/buy');

  // ----Boutique (FlexPay : Mobile Money + carte Visa) ----
  //
  // Parcours : catalogue → commande (prix figé) → paiement → statut vérifié
  // côté serveur → activation du forfait. L'app ne fait JAMAIS confiance à un
  // retour d'URL : elle interroge le statut réel.

  /// Catalogue des forfaits actifs (catégories, prix, volumes, validité).
  Future<List> shopCatalog() async {
    final r = await _send('GET', '/shop/catalog');
    return (r['packages'] as List?) ?? const [];
  }

  /// Crée une commande : le prix et le contenu du forfait sont figés.
  Future<Map> createShopOrder(int packageId) async {
    final r = await _send('POST', '/shop/orders', {'package_id': packageId});
    return (r['order'] as Map?) ?? const {};
  }

  /// Initie le paiement. `method` : mpesa | orange | airtel | card.
  /// Renvoie { payment, redirect_url?, message }.
  Future<Map> payShopOrder(String orderId, String method, {String? phone}) async =>
      await _send('POST', '/shop/orders/$orderId/pay', {
        'method': method,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      });

  /// Statut réel de la commande (et du paiement) — source de vérité.
  Future<Map> shopOrderStatus(String orderId) async =>
      await _send('GET', '/shop/orders/$orderId/status');

  /// Interroge le fournisseur et active le forfait si le paiement est confirmé.
  Future<Map> shopPayStatus(String orderId) async =>
      await _send('GET', '/shop/orders/$orderId/pay/status');

  /// Mes forfaits actifs (quotas restants, expiration).
  Future<List> myPlans() async {
    final r = await _send('GET', '/shop/my-plans');
    return (r['plans'] as List?) ?? const [];
  }

  /// Tous mes forfaits (historique : épuisés, expirés).
  Future<List> myPlansAll() async {
    final r = await _send('GET', '/shop/my-plans/all');
    return (r['plans'] as List?) ?? const [];
  }

  // ----Airtime : offrir du crédit GSM à un proche ----
  Future<Map> sendAirtime(String phone, int amountCents) async => await _send(
      'POST', '/airtime', {'phone': phone, 'amount_cents': amountCents});
  Future<List> airtimeHistory() async => await _send('GET', '/airtime');

  // ---- Parrainage ----
  Future<Map> referral() async => await _send('GET', '/referral');

  // ---- Promos actives (bannière) ----
  Future<List> promos() async => await _send('GET', '/rates/promos');

  // ----Langues téléchargeables ----
  Future<List> availableLangs() async => await _send('GET', '/i18n');
  Future<Map> langPack(String code) async => await _send('GET', '/i18n/$code');

  // ---- Rates ----
  Future<Map> rateLookup(String phone) async =>
      await _send('GET', '/rates/lookup?phone=${Uri.encodeComponent(phone)}');
  Future<List> allRates() async => await _send('GET', '/rates');

  // ---- Contacts ----
  Future<List> contacts() async => await _send('GET', '/contacts');

  ///Lesquels de ces numéros ont un compte MboteCall ?
  /// Renvoie { "<numéro envoyé>": "<numéro normalisé>" } pour les comptes trouvés.
  Future<Map> checkMbote(List<String> phones) async {
    final r = await _send('POST', '/contacts/check', {'phones': phones});
    return r['mbote'] ?? {};
  }

  Future<Map> addContact(String name, String phone) async =>
      await _send('POST', '/contacts', {'name': name, 'phone': phone});
  Future<void> deleteContact(String id) async =>
      await _send('DELETE', '/contacts/$id');

  /// Profil public d'un contact : présence visible, `online`, `last_seen_at`
  /// et `reminder_active` (rappel « reviens en ligne » en cours).
  Future<Map> contactProfile(String phone) async => await _send(
      'GET', '/contacts/profile/${Uri.encodeComponent(phone)}');

  /// Active le rappel « rappelle-moi quand <phone> revient en ligne ».
  /// Réponse : { ok, already_online, active }.
  Future<Map> setPresenceReminder(String phone) async => await _send(
      'POST', '/contacts/${Uri.encodeComponent(phone)}/reminder');

  /// Annule le rappel de présence pour <phone>.
  Future<void> deletePresenceReminder(String phone) async => await _send(
      'DELETE', '/contacts/${Uri.encodeComponent(phone)}/reminder');

  // ---- Calls ----
  Future<Map> startCall(String to, {bool forceGsm = false}) async =>
      await _send('POST', '/calls/start', {'to': to, 'force_gsm': forceGsm});
  Future<Map> callStatus(String id) async =>
      await _send('GET', '/calls/$id/status');

  ///Journalise un appel MboteCall reçu (répondu ou manqué)
  Future<void> logIncoming(String from, int billedSec) async => await _send(
      'POST', '/calls/log-incoming', {'from': from, 'billed_sec': billedSec});

  ///Jeton de notification Firebase (appels app fermée)
  Future<void> sendFcmToken(String token) async =>
      await _send('POST', '/auth/fcm-token', {'token': token});

  ///Réinitialisation SÉCURISÉE du code PIN :
  /// jeton du compte exigé + code SMS dédié (5 min, 3 essais, usage unique).
  /// Le code n'est jamais renvoyé par l'API — il arrive par SMS.
  Future<void> pinResetRequest() async =>
      await _send('POST', '/auth/pin-reset/request');
  Future<void> pinResetVerify(String code) async =>
      await _send('POST', '/auth/pin-reset/verify', {'code': code});

  // ----LOKOTA : notes vocales traduites ----
  Future<Map> lokotaSend(String to, String audioDataUri, int durationSec,
          String langFrom, String langTo) async =>
      await _send('POST', '/lokota/send', {
        'to': to,
        'audio': audioDataUri,
        'duration_sec': durationSec,
        'lang_from': langFrom,
        'lang_to': langTo,
      });
  Future<List> lokotaThreads() async => await _send('GET', '/lokota/threads');
  Future<Map> lokotaWith(String phone) async =>
      await _send('GET', '/lokota/with/${Uri.encodeComponent(phone)}');
  Future<void> lokotaMarkRead(String phone) async =>
      await _send('POST', '/lokota/with/${Uri.encodeComponent(phone)}/read');

  // ----DISCUSSIONS : messages texte, photos et notes vocales ----
  //
  // Tout passe par les mêmes tables côté serveur (`messages`) : un fil unique
  // par personne, que l'on écrive, qu'on envoie une photo ou qu'on parle.
  // Les notes vocales utilisent `/konversations` (même stockage que le texte).

  /// Fils de discussion (dernier message + compteurs non lus).
  Future<List> messageThreads() async => await _send('GET', '/messages/threads');

  /// Messages échangés avec [phone] (50 plus récents, `before` pour remonter).
  Future<Map> conversation(String phone, {int? before}) async {
    final q = StringBuffer('/messages/with/${Uri.encodeComponent(phone)}');
    if (before != null) q.write('?before=$before');
    return await _send('GET', q.toString());
  }

  /// Envoie un message texte. [clientId] rend l'envoi idempotent (renvoi après
  /// coupure réseau : pas de doublon).
  Future<Map> sendMessage(
    String to,
    String text, {
    String? clientId,
    String langFrom = 'fr',
    String langTo = 'fr',
    String kind = 'text',
  }) async =>
      await _send('POST', '/messages/send', {
        'to': to,
        'text': text,
        'lang_from': langFrom,
        'lang_to': langTo,
        'kind': kind,
        if (clientId != null) 'client_id': clientId,
      });

  /// Messages reçus/envoyés depuis un curseur (ms epoch) — synchro globale
  /// utilisée par l'architecture local-first (récupération hors ligne).
  /// Le serveur renvoie au plus [limit] messages avec created_at > since.
  Future<Map> messagesSince(int since, {int limit = 200}) async =>
      await _send('GET', '/messages/since?since=$since&limit=$limit');

  /// Téléchargement brut d'un média privé (retourne les octets).
  Future<List<int>> rawGet(Uri url) async {
    final r = await http.get(url, headers: authHeaders).timeout(_timeout);
    if (r.statusCode >= 400) {
      throw ApiException('Média indisponible', 'http_${r.statusCode}');
    }
    return r.bodyBytes;
  }

  ///Envoie une note vocale (stockée comme un message, donc dans le fil).
  Future<Map> sendVoiceNote(
    String to, {
    required List<int> bytes,
    required int durationSec,
    String langFrom = 'fr',
    String langTo = 'ln',
    List<int>? wave,
    String? clientId,
  }) async =>
      await _send('POST', '/konversations/send', {
        'to': to,
        'audio': 'data:audio/m4a;base64,${base64Encode(bytes)}',
        'duration_sec': durationSec,
        'lang_from': langFrom,
        'lang_to': langTo,
        if (wave != null) 'wave': wave,
        if (clientId != null) 'client_id': clientId,
      });

  ///Envoie une photo (ou un fichier) — corps binaire brut.
  Future<Map> sendMessageMedia(
    String to, {
    required List<int> bytes,
    required String kind, // 'image' | 'file'
    required String mime,
    required String name,
    String? clientId,
    String text = '',
  }) async {
    final q = <String>[
      'to=${Uri.encodeComponent(to)}',
      'kind=$kind',
      'mime=${Uri.encodeComponent(mime)}',
      'name=${Uri.encodeComponent(name)}',
      if (text.isNotEmpty) 'text=${Uri.encodeComponent(text)}',
      if (clientId != null) 'client_id=$clientId',
    ].join('&');
    late http.Response r;
    try {
      r = await http
          .post(
            Uri.parse('${Config.apiBase}/messages/send-media?$q'),
            headers: {
              'Content-Type': 'application/octet-stream',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 60));
    } on SocketException {
      throw ApiException('Pas d\'Internet — vérifie ta connexion', 'offline');
    } on TimeoutException {
      throw ApiException('Envoi trop lent — réessaie', 'timeout');
    }
    dynamic data;
    try {
      data = r.body.isEmpty ? {} : jsonDecode(r.body);
    } catch (_) {
      data = {};
    }
    if (r.statusCode >= 400) {
      throw ApiException(
          data is Map ? (data['error'] ?? 'Envoi impossible — réessaie') : 'Envoi impossible — réessaie');
    }
    return data is Map ? data : {};
  }

  ///Marque comme lus les messages reçus de [phone].
  Future<void> markConversationRead(String phone) async =>
      await _send('POST', '/messages/with/${Uri.encodeComponent(phone)}/read');

  ///Supprime un message **pour tout le monde** (expéditeur seulement).
  Future<void> deleteMessageForAll(String id) async =>
      await _send('DELETE', '/messages/$id');

  ///Supprime des messages **pour moi** (masqués de mon fil uniquement).
  Future<void> deleteMessagesForMe(List<String> ids) async =>
      await _send('POST', '/messages/delete', {'ids': ids, 'scope': 'me'});

  ///Signale qu'une note vocale reçue a été écoutée.
  Future<void> markMessagePlayed(String id) async =>
      await _send('POST', '/messages/$id/played');

  /// URL de téléchargement d'une pièce jointe privée (protégée par le jeton).
  String messageMediaUrl(String id) => '${Config.apiBase}/messages/media/$id';

  Future<Map> hangup(String id) async =>
      await _send('POST', '/calls/$id/hangup');
  ///Historique filtrable côté serveur.
  /// [filter] : all | in | out | missed | internet | gsm · [q] : nom ou numéro
  Future<Map> history(
      {String filter = 'all', String? q, int limit = 100, int? since}) async {
    final b = StringBuffer('/calls/history?filter=$filter&limit=$limit');
    if (q != null && q.trim().isNotEmpty) {
      b.write('&q=${Uri.encodeComponent(q.trim())}');
    }
    if (since != null) b.write('&since=$since');
    return await _send('GET', b.toString());
  }

  /// Détail d'un appel (tarif appliqué, durée facturée, canal, cause de fin).
  Future<Map> callDetail(String id) async {
    final r = await _send('GET', '/calls/$id');
    return (r['call'] as Map?) ?? const {};
  }

  /// Masque une entrée pour MOI. La donnée comptable reste côté serveur.
  Future<void> hideCall(String id) async =>
      await _send('POST', '/calls/$id/hide');

  /// Programme un rappel « appeler plus tard » (exécuté côté serveur à
  /// l'heure dite). [scheduledAt] en ms epoch, dans le futur.
  Future<Map> dialLater(String targetPhone,
      {String? targetName, required int scheduledAt, int tzOffset = 0}) async {
    return await _send('POST', '/dial-later', {
      'target_phone': targetPhone,
      'target_name': targetName ?? '',
      'scheduled_at': scheduledAt,
      'tz_offset': tzOffset,
    });
  }

  /// Liste des rappels programmés (consultable aussi hors ligne via le cache).
  Future<List> dialLaterList() async => await _send('GET', '/dial-later');

  // ----SMS vers le réseau GSM (facturés) ----

  /// Prix d'un SMS et couverture par un forfait, AVANT envoi.
  Future<Map> smsQuote(String phone) async =>
      await _send('GET', '/sms/quote?to=${Uri.encodeComponent(phone)}');

  /// Envoie un SMS. `clientId` rend l'appel idempotent (pas de double envoi).
  Future<Map> sendSms(String phone, String text, {String? clientId}) async =>
      await _send('POST', '/sms/send', {
        'to': phone,
        'text': text,
        if (clientId != null) 'client_id': clientId,
      });

  /// Historique des SMS envoyés (statut fournisseur inclus).
  Future<List> smsHistory() async {
    final r = await _send('GET', '/sms');
    return (r['messages'] as List?) ?? const [];
  }

 //─────────────────────────────────────────────────────────────
  //FIL DE PUBLICATION
 //─────────────────────────────────────────────────────────────

  /// Une page du fil. `next` sert de curseur pour la page suivante.
  Future<FeedPage> feedPage({int? before, String? cursor}) async {
    final q = StringBuffer('/feed');
    if (before != null) q.write('?before=$before');
    if (cursor != null) q.write(before != null ? '&cursor=' : '?cursor=');
    if (cursor != null) q.write(Uri.encodeComponent(cursor));
    final r = await _send('GET', q.toString());
    final list = (r['posts'] as List? ?? const [])
        .map((e) => Post.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final next = r['next'];
    return FeedPage(
      posts: list,
      nextBefore: next is Map ? (next['before'] as num?)?.toInt() : null,
      nextCursor: next is Map ? next['cursor']?.toString() : null,
    );
  }

  // ── v4.1 FIL RANKÉ ─────────────────────────────────────────────

  /// Fil personnalisé par l'algorithme (35/25/15/15/10).
  /// tab = for_you | following | trending
  Future<FeedPage> feedRanked({required String tab, String? cursor, int limit = 20}) async {
    final q = StringBuffer('/rank/ranked?tab=$tab&limit=$limit');
    if (cursor != null) q.write('&cursor=${Uri.encodeComponent(cursor)}');
    final r = await _send('GET', q.toString());
    final list = (r['posts'] as List? ?? const [])
        .map((e) => Post.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return FeedPage(posts: list, nextCursor: r['nextCursor']?.toString());
  }

  /// Événement de lecture (recalcule le score côté serveur).
  Future<void> feedEvent(String type, {String? postId, String? authorId, String? tag, Map? meta}) async {
    await _send('POST', '/rank/events', {
      'type': type, 'postId': postId, 'authorId': authorId, 'tag': tag, 'meta': meta,
    });
  }

  /// Réaction Facebook-like (8 types) sur une publication.
  Future<Map<String, int>> reactPost(String postId, String type) async {
    final r = await _send('POST', '/rank/posts/$postId/react', {'type': type});
    final counts = <String, int>{};
    for (final e in (r['reactions'] as List? ?? const [])) {
      counts[e['type'].toString()] = (e['n'] as num).toInt();
    }
    return counts;
  }

  Future<void> unreactPost(String postId) async {
    await _send('DELETE', '/rank/posts/$postId/react');
  }

  Future<void> reactComment(String commentId, String type) async {
    await _send('POST', '/rank/comments/$commentId/react', {'type': type});
  }

  /// Hashtags tendance (24 h).
  Future<List<Map<String, dynamic>>> trendingHashtags() async {
    final r = await _send('GET', '/rank/hashtags/trending');
    return (r['tags'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Recherche @ dynamique.
  Future<List<Map<String, dynamic>>> searchMentions(String q) async {
    final r = await _send('GET', '/rank/mentions/search?q=${Uri.encodeComponent(q)}');
    return (r['users'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// DÉCOUVERTE — publications publiques du réseau, pour la partie
  /// « Tendances » du fil.
  ///
  /// `sort = 'tendances'` classe par intérêt (j'aime, commentaires, vues)
  /// pondéré par la fraîcheur ; `sort = 'recent'` trie par date. Les
  /// publications limitées aux contacts n'y figurent jamais : c'est le serveur
  /// qui applique la règle, pas l'application.
  Future<FeedPage> discoverPage({
    String sort = 'tendances',
    String? tag,
    String? ville,
    int? offset,
  }) async {
    final q = StringBuffer('/feed/discover?sort=$sort');
    if (tag != null && tag.isNotEmpty) {
      q.write('&tag=${Uri.encodeComponent(tag)}');
    }
    if (ville != null && ville.isNotEmpty) {
      q.write('&ville=${Uri.encodeComponent(ville)}');
    }
    if (offset != null) q.write('&offset=$offset');
    final r = await _send('GET', q.toString());
    final list = (r['posts'] as List? ?? const [])
        .map((e) => Post.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final next = r['next'];
    return FeedPage(
      posts: list,
      nextOffset: next is Map ? (next['offset'] as num?)?.toInt() : null,
    );
  }

  /// Fil « Abonnements » : les publications des auteurs que je suis.
  Future<FeedPage> followingPage({int? before, String? cursor}) async {
    final q = StringBuffer('/feed/following');
    if (before != null) q.write('?before=$before');
    if (cursor != null) q.write(before != null ? '&cursor=' : '?cursor=');
    if (cursor != null) q.write(Uri.encodeComponent(cursor));
    final r = await _send('GET', q.toString());
    final list = (r['posts'] as List? ?? const [])
        .map((e) => Post.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final next = r['next'];
    return FeedPage(
      posts: list,
      nextBefore: next is Map ? (next['before'] as num?)?.toInt() : null,
      nextCursor: next is Map ? next['cursor']?.toString() : null,
    );
  }

  /// Mots-clés en tendance sur les 7 derniers jours.
  Future<List<Map>> trendingTags({int limit = 20}) async {
    final r = await _send('GET', '/feed/tags?limit=$limit');
    return (r['tags'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Publications portant un mot-clé.
  Future<List<Post>> postsByTag(String tag) async {
    final r = await _send('GET', '/feed/tags/${Uri.encodeComponent(tag)}');
    return (r['posts'] as List? ?? const [])
        .map((e) => Post.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ── HASHTAGS ────────────────────────────────────────────────────────────
  // `tri` : recentes | populaires | videos | photos (les onglets de la page).

  /// Page d'un hashtag : en-tête (publications, abonnés, suivi) + publications.
  Future<Map<String, dynamic>> pageHashtag(String tag, {String tri = 'recentes'}) async {
    final r = await _send('GET',
        '/feed/tags/${Uri.encodeComponent(tag)}?tri=${Uri.encodeComponent(tri)}');
    return Map<String, dynamic>.from(r as Map);
  }

  /// Autocomplétion pendant la frappe (`#`).
  Future<List<Hashtag>> suggestionsHashtags({String q = '', int limit = 8}) async {
    final r = await _send('GET',
        '/feed/tags/suggest?q=${Uri.encodeComponent(q)}&limit=$limit');
    return (r['tags'] as List? ?? const [])
        .map((e) => Hashtag.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Suivre un hashtag.
  Future<Hashtag> suivreHashtag(String tag) async =>
      Hashtag.fromJson(Map<String, dynamic>.from(
          await _send('POST', '/feed/tags/${Uri.encodeComponent(tag)}/follow') as Map));

  /// Ne plus suivre un hashtag.
  Future<Hashtag> nePlusSuivreHashtag(String tag) async =>
      Hashtag.fromJson(Map<String, dynamic>.from(
          await _send('DELETE', '/feed/tags/${Uri.encodeComponent(tag)}/follow') as Map));

  /// Mes hashtags suivis.
  Future<List<Hashtag>> hashtagsSuivis() async {
    final r = await _send('GET', '/feed/tags/followed');
    return (r['tags'] as List? ?? const [])
        .map((e) => Hashtag.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Tendances détaillées (`ville` pour les hashtags géographiques).
  Future<List<Hashtag>> tendances({int limit = 15, String? ville}) async {
    final q = StringBuffer('/feed/tendances?limit=$limit');
    if (ville != null && ville.trim().isNotEmpty) {
      q.write('&ville=${Uri.encodeComponent(ville.trim())}');
    }
    final r = await _send('GET', q.toString());
    return (r['tags'] as List? ?? const [])
        .map((e) => Hashtag.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ── MENTIONS ────────────────────────────────────────────────────────────

  /// Personnes à mentionner (`@`) : nom, identifiant, contacts d'abord.
  Future<List<Personne>> suggestionsMentions({String q = '', int limit = 8}) async {
    final r = await _send('GET',
        '/feed/mentions/suggest?q=${Uri.encodeComponent(q)}&limit=$limit');
    return (r['personnes'] as List? ?? const [])
        .map((e) => Personne.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Suggestions assistées de hashtags pour un brouillon (prêtes pour l'IA).
  Future<List<Hashtag>> suggererHashtags(String texte) async {
    final r = await _send('GET',
        '/feed/suggestions?texte=${Uri.encodeComponent(texte)}');
    return (r['hashtags'] as List? ?? const [])
        .map((e) => Hashtag.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Mes statistiques de mentions.
  Future<AnalytiqueMentions> analytiqueMentions() async =>
      AnalytiqueMentions.fromJson(
          Map<String, dynamic>.from(await _send('GET', '/feed/mentions/analytique') as Map));

  // ── FIL PERSONNALISÉ ────────────────────────────────────────────────────

  /// Fil « Pour toi » : classé par affinité (hashtags suivis, auteurs, ville).
  ///
  /// Si le classement n'est pas disponible (serveur plus ancien, réseau), on
  /// retombe sur le fil chronologique : le fil ne doit jamais rester vide parce
  /// qu'une amélioration manque à l'appel.
  Future<FeedPage> filPersonnalise({int offset = 0, int limit = 20}) async {
    try {
      final r = await _send('GET', '/feed/pourtoi?offset=$offset&limit=$limit');
      final list = (r['posts'] as List? ?? const [])
          .map((e) => Post.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final next = r['next'];
      return FeedPage(
        posts: list,
        nextOffset: next is Map ? (next['offset'] as num?)?.toInt() : null,
      );
    } catch (_) {
      if (offset > 0) return const FeedPage(posts: []);
      return feedPage();
    }
  }

  // ── RECHERCHE UNIVERSELLE ───────────────────────────────────────────────

  /// Une seule barre : `#hashtag`, `@personne` ou texte libre.
  Future<ResultatsRecherche> rechercher(String q) async =>
      ResultatsRecherche.fromJson(Map<String, dynamic>.from(
          await _send('GET', '/search?q=${Uri.encodeComponent(q)}') as Map));

  // ── NOTIFICATIONS ───────────────────────────────────────────────────────

  /// Boîte de réception : `{notifications, non_lues, next}`.
  Future<Map<String, dynamic>> notifications({int? before, int limite = 30}) async {
    final q = StringBuffer('/notifications?limite=$limite');
    if (before != null) q.write('&before=$before');
    return Map<String, dynamic>.from(await _send('GET', q.toString()) as Map);
  }

  /// Badge de l'en-tête : nombre de notifications non lues.
  Future<int> notificationsNonLues() async {
    final r = await _send('GET', '/notifications/count');
    return (r['non_lues'] as num?)?.toInt() ?? 0;
  }

  /// Statistiques d'engagement : `{engagement: {likes, commentaires,
  /// partages, taux, top[]}, hashtags_suivis[], mentions{}}`.
  ///
  /// Le champ `engagement` vient d'être ajouté au serveur ; l'application lit
  /// donc aussi l'ancienne forme pour rester compatible avec un backend qui
  /// n'aurait pas encore été redéployé.
  Future<Map<String, dynamic>> analytiqueEngagement() async {
    final r = Map<String, dynamic>.from(await _send('GET', '/feed/analytique') as Map);
    r['engagement'] ??= <String, dynamic>{};
    return r;
  }

  /// Tout marquer comme lu.
  Future<void> marquerNotificationsLues() async =>
      await _send('POST', '/notifications/lues');

  /// Marquer une notification.
  Future<void> marquerNotificationLue(String id) async =>
      await _send('POST', '/notifications/$id/lue');

  /// S'abonner à un auteur. Renvoie `{suivi, abonnes}`.
  Future<Map> followAuthor(String auteurId) async =>
      await _send('POST', '/feed/authors/$auteurId/follow');

  /// Se désabonner. Renvoie `{suivi, abonnes}`.
  Future<Map> unfollowAuthor(String auteurId) async =>
      await _send('DELETE', '/feed/authors/$auteurId/follow');

  /// Profil public d'un auteur : `{auteur, posts}`.
  Future<Map> authorProfile(String auteurId) async =>
      await _send('GET', '/feed/authors/$auteurId');

  /// Lit une publication précise, par son identifiant. Sert quand un lien
  /// partagé ramène dans l'application (`mbote://post/<id>`).
  Future<Post> lirePublication(String id) async {
    final r = await _send('GET', '/feed/posts/$id');
    return Post.fromJson(Map<String, dynamic>.from(r['post'] as Map));
  }

  /// Signale un partage (lien copié ou envoi vers une autre application).
  /// Renvoie `{partages, share_url}`.
  Future<Map> markShared(String id) async =>
      await _send('POST', '/feed/posts/$id/share');

  /// Compte une vue. Le serveur ignore un second appel du même lecteur et la
  /// vue de l'auteur : le chiffre ne peut donc pas être gonflé.
  Future<Map> viewPost(String id) async =>
      await _send('POST', '/feed/posts/$id/view');

  /// Change l'audience d'UNE de mes publications (`public`, `communaute`,
  /// `contacts`).
  Future<Map> setPostVisibility(String id, PostVisibilite v) async =>
      await _send('PATCH', '/feed/posts/$id/visibilite',
          {'visibilite': postVisibiliteToApi(v)});

  /// Ouvre TOUTES mes publications à la même audience.
  ///
  /// Sert à réparer l'effet du formulaire qui proposait « Mes contacts » par
  /// défaut : ces publications n'ont jamais été vues par personne. Rien n'est
  /// changé sans que l'auteur l'ait demandé.
  Future<Map> setAllPostsVisibility(PostVisibilite v) async => await _send(
      'PUT', '/feed/posts/visibilite', {'visibilite': postVisibiliteToApi(v)});

  /// Publie une publication (texte, photo, clip ou événement).
  Future<Post> createPost({
    required PostType type,
    String? texte,
    String? mediaUrl,
    String? eventTitle,
    DateTime? eventDate,
    String? eventLieu,
    List<String> eventTags = const [],
    int? clipDureeSeconds,
    String? ville,
    String? thumbUrl,
    PostVisibilite visibilite = PostVisibilite.public,
    PostOrigine origine = PostOrigine.rdc,
    PostDuree duree = PostDuree.permanent,
    bool allowCalls = true,
  }) async {
    final r = await _send('POST', '/feed/posts', {
      'type': postTypeToApi(type),
      'allow_calls': allowCalls,
      'visibilite': postVisibiliteToApi(visibilite),
      'origine': origine == PostOrigine.diaspora ? 'diaspora' : 'rdc',
      'duree': duree == PostDuree.h24 ? 'h24' : 'permanent',
      if (texte != null && texte.trim().isNotEmpty) 'texte': texte.trim(),
      if (mediaUrl != null) 'media_url': mediaUrl,
      if (thumbUrl != null && thumbUrl.isNotEmpty) 'thumb_url': thumbUrl,
      if (eventTitle != null) 'event_title': eventTitle,
      if (eventDate != null) 'event_date': eventDate.millisecondsSinceEpoch,
      if (eventLieu != null) 'event_lieu': eventLieu,
      if (eventTags.isNotEmpty) 'event_tags': eventTags,
      if (clipDureeSeconds != null) 'clip_duree_seconds': clipDureeSeconds,
      if (ville != null && ville.trim().isNotEmpty) 'ville': ville.trim(),
    });
    return Post.fromJson(Map<String, dynamic>.from(r['post'] as Map));
  }

  // ---- Appels de groupe « Mbote Famille » (gratuits) ----

  ///Journalise le début d'un appel de groupe (visible dans l'historique).
  Future<Map> startGroupCall(String callId) async =>
      await _send('POST', '/calls/group/start', {'call_id': callId});

  ///Clôt l'appel de groupe avec sa durée réelle.
  Future<Map> endGroupCall(String callId, int durationSec) async => await _send(
      'POST', '/calls/group/$callId/end', {'duration_sec': durationSec});

  ///Supprime une publication — le serveur refuse (403) si je n'en suis
  /// pas l'auteur, ce qui protège même si l'interface se trompe.
  Future<void> deletePost(String id) async =>
      await _send('DELETE', '/feed/posts/$id');

  ///Supprime un statut (auteur uniquement).
  Future<void> deleteStory(String id) async =>
      await _send('DELETE', '/feed/stories/$id');

  /// Bascule « j'aime ». Renvoie l'état faisant foi côté serveur.
  Future<Map> likePost(String id) async =>
      await _send('POST', '/feed/posts/$id/like');

  Future<List<Map>> postComments(String id) async {
    final r = await _send('GET', '/feed/posts/$id/comments');
    return (r['comments'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// [parentId] rattache le commentaire à un autre : c'est ce qui fait une
  /// réponse, et c'est le serveur qui en déduit la notification
  /// « a répondu à votre commentaire ».
  Future<Map> addComment(String id, String texte, {String? parentId}) async {
    final r = await _send('POST', '/feed/posts/$id/comments', {
      'texte': texte,
      if (parentId != null) 'parent_id': parentId,
    });
    return Map<String, dynamic>.from(r['comment'] as Map);
  }

  /// Bande de statuts (les 24 dernières heures, non vues d'abord).
  Future<List<Story>> feedStories() async {
    final r = await _send('GET', '/feed/stories');
    return (r['stories'] as List? ?? const [])
        .map((e) => Story.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> postStory({String? mediaUrl, String? texte}) async =>
      await _send('POST', '/feed/stories', {
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (texte != null && texte.trim().isNotEmpty) 'texte': texte.trim(),
      });

  Future<void> markStorySeen(String storyId) async =>
      await _send('POST', '/feed/stories/$storyId/seen');

  /// Type MIME déduit de l'extension — le serveur n'accepte que les images et
  /// les vidéos (`application/octet-stream` est refusé). Sans cela, tout envoi
  /// de photo renvoyait « Aucun fichier valide reçu ».
  static String mimeForPath(String filePath) {
    final ext = filePath.contains('.')
        ? filePath.split('.').last.toLowerCase().trim()
        : '';
    return switch (ext) {
      'jpg' || 'jpeg' || 'jfif' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'avi' => 'video/x-msvideo',
      // Extension inconnue (fichier sans suffixe) : on parie sur l'image,
      // c'est le cas de 99 % des envois depuis l'application.
      _ => 'image/jpeg',
    };
  }

  /// Envoie un fichier (multipart `file`) et renvoie son URL publique.
  /// Envoi d'un fichier, avec la MINIATURE quand le serveur en produit une.
  ///
  /// Une vidéo revient avec `thumb_url` : la première image, capturée par le
  /// serveur au moment de l'envoi. On la transmet ensuite à la publication, ce
  /// qui permet au fil d'afficher un aperçu sans télécharger la vidéo.
  Future<UploadResult> uploadMediaFull(String filePath) async {
    final uri = Uri.parse('${Config.apiBase}/upload');
    final req = http.MultipartRequest('POST', uri);
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.files.add(await http.MultipartFile.fromPath(
      'file',
      filePath,
      contentType: MediaType.parse(mimeForPath(filePath)),
    ));
    late http.Response r;
    try {
      final streamed = await req.send().timeout(const Duration(seconds: 60));
      r = await http.Response.fromStream(streamed);
    } on SocketException {
      throw ApiException(
          'Pas d\'Internet — vérifie ta connexion', 'offline');
    } on TimeoutException {
      throw ApiException('Envoi trop lent — réessaie', 'timeout');
    }
    dynamic data;
    try {
      data = r.body.isEmpty ? {} : jsonDecode(r.body);
    } catch (_) {
      data = {};
    }
    if (r.statusCode >= 400) {
      throw ApiException(data is Map
          ? (data['error'] ?? 'Envoi impossible — réessaie')
          : 'Envoi impossible — réessaie');
    }
    final url = data is Map ? data['url']?.toString() : null;
    if (url == null || url.isEmpty) {
      throw ApiException('Réponse d’envoi invalide');
    }
    final thumb = data is Map ? data['thumb_url']?.toString() : null;
    return UploadResult(
      url: url,
      thumbUrl: (thumb == null || thumb.isEmpty) ? null : thumb,
      estVideo: data is Map && data['type'] == 'video',
    );
  }

  /// Compatibilité : l'ancien appel ne garde que l'URL du fichier.
  Future<String> uploadMedia(String filePath) async =>
      (await uploadMediaFull(filePath)).url;
}

/// Une page du fil + curseur de continuation.
/// Résultat d'un envoi de fichier.
class UploadResult {
  /// URL du fichier envoyé (photo ou vidéo).
  final String url;

  /// Miniature produite par le serveur (vidéos uniquement, `null` sinon).
  final String? thumbUrl;

  /// Le fichier envoyé est-il une vidéo ?
  final bool estVideo;

  const UploadResult({
    required this.url,
    this.thumbUrl,
    this.estVideo = false,
  });
}

class FeedPage {
  final List<Post> posts;

  /// Curseur des fils chronologiques (fil principal, abonnements).
  final int? nextBefore;
  final String? nextCursor;

  /// Curseur de la découverte par tendances : le classement par intérêt se
  /// fait côté serveur, on avance donc par décalage.
  final int? nextOffset;

  const FeedPage({
    required this.posts,
    this.nextBefore,
    this.nextCursor,
    this.nextOffset,
  });

  bool get hasMore => nextCursor != null || nextOffset != null;
}
