import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'config.dart';
import 'models/post.dart';

class ApiException implements Exception {
  final String message;
  final String? code;
  ApiException(this.message, [this.code]);
  @override
  String toString() => message;
}

/// 🤝 Transforme n'importe quelle erreur en message compréhensible.
/// À utiliser PARTOUT où l'on affiche une erreur à l'utilisateur :
/// jamais de jargon technique à l'écran.
String friendlyError(Object e) {
  if (e is ApiException) return e.message;
  if (e is SocketException || e is http.ClientException) {
    return 'Pas d\'Internet — vérifie ta connexion 📶';
  }
  if (e is TimeoutException) {
    return 'Le serveur met trop de temps à répondre — réessaie dans un instant';
  }
  return 'Un petit souci est survenu — réessaie 🙏';
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
          'Pas d\'Internet — vérifie ta connexion 📶', 'offline');
    } on http.ClientException {
      throw ApiException(
          'Pas d\'Internet — vérifie ta connexion 📶', 'offline');
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
          {String? name, String? referralCode}) async =>
      await _send('POST', '/auth/verify-otp', {
        'phone': phone,
        'code': code,
        if (name != null) 'name': name,
        if (referralCode != null && referralCode.isNotEmpty)
          'referral_code': referralCode,
      });
  Future<Map> me() async => await _send('GET', '/auth/me');
  Future<void> updateName(String name) async =>
      await _send('PUT', '/auth/me', {'name': name});

  /// 📷 Photo de profil (data-URI compressée) · null = supprimer
  Future<void> updateAvatar(String? dataUri) async =>
      await _send('PUT', '/auth/me', {'avatar': dataUri ?? ''});

  // ---- Wallet ----
  Future<Map> wallet() async => await _send('GET', '/wallet');

  /// 📊 Tableau de bord : solde, dépenses du jour et du mois, appels, SMS.
  /// Tous les chiffres viennent du grand livre du serveur (aucune estimation).
  Future<Map> walletSummary() async => await _send('GET', '/wallet/summary');

  /// 🧾 Grand livre filtrable : type, statut, période, pagination.
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

  /// 💸 Transfert de crédit MboteCall → MboteCall
  Future<Map> transfer(String toPhone, int amountCents) async => await _send(
      'POST',
      '/wallet/transfer',
      {'to_phone': toPhone, 'amount_cents': amountCents});

  // ---- 📦 Forfaits ----
  Future<List> packages() async => await _send('GET', '/packages');
  Future<List> myPackages() async => await _send('GET', '/packages/mine');
  Future<Map> buyPackage(int id) async =>
      await _send('POST', '/packages/$id/buy');

  // ---- 🛍️ Boutique (FlexPay : Mobile Money + carte Visa) ----
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

  // ---- 📱 Airtime : offrir du crédit GSM à un proche ----
  Future<Map> sendAirtime(String phone, int amountCents) async => await _send(
      'POST', '/airtime', {'phone': phone, 'amount_cents': amountCents});
  Future<List> airtimeHistory() async => await _send('GET', '/airtime');

  // ---- Parrainage ----
  Future<Map> referral() async => await _send('GET', '/referral');

  // ---- Promos actives (bannière) ----
  Future<List> promos() async => await _send('GET', '/rates/promos');

  // ---- 🗣️ Langues téléchargeables ----
  Future<List> availableLangs() async => await _send('GET', '/i18n');
  Future<Map> langPack(String code) async => await _send('GET', '/i18n/$code');

  // ---- Rates ----
  Future<Map> rateLookup(String phone) async =>
      await _send('GET', '/rates/lookup?phone=${Uri.encodeComponent(phone)}');
  Future<List> allRates() async => await _send('GET', '/rates');

  // ---- Contacts ----
  Future<List> contacts() async => await _send('GET', '/contacts');

  /// 📒 Lesquels de ces numéros ont un compte MboteCall ?
  /// Renvoie { "<numéro envoyé>": "<numéro normalisé>" } pour les comptes trouvés.
  Future<Map> checkMbote(List<String> phones) async {
    final r = await _send('POST', '/contacts/check', {'phones': phones});
    return r['mbote'] ?? {};
  }

  Future<Map> addContact(String name, String phone) async =>
      await _send('POST', '/contacts', {'name': name, 'phone': phone});
  Future<void> deleteContact(String id) async =>
      await _send('DELETE', '/contacts/$id');

  // ---- Calls ----
  Future<Map> startCall(String to) async =>
      await _send('POST', '/calls/start', {'to': to});
  Future<Map> callStatus(String id) async =>
      await _send('GET', '/calls/$id/status');

  /// 📥 Journalise un appel MboteCall reçu (répondu ou manqué)
  Future<void> logIncoming(String from, int billedSec) async => await _send(
      'POST', '/calls/log-incoming', {'from': from, 'billed_sec': billedSec});

  /// 🔔 Jeton de notification Firebase (appels app fermée)
  Future<void> sendFcmToken(String token) async =>
      await _send('POST', '/auth/fcm-token', {'token': token});

  /// 🔐 Réinitialisation SÉCURISÉE du code PIN :
  /// jeton du compte exigé + code SMS dédié (5 min, 3 essais, usage unique).
  /// Le code n'est jamais renvoyé par l'API — il arrive par SMS.
  Future<void> pinResetRequest() async =>
      await _send('POST', '/auth/pin-reset/request');
  Future<void> pinResetVerify(String code) async =>
      await _send('POST', '/auth/pin-reset/verify', {'code': code});

  // ---- 🗣️ LOKOTA : notes vocales traduites ----
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

  // ---- 💬 DISCUSSIONS : messages texte, photos et notes vocales ----
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
  }) async =>
      await _send('POST', '/messages/send', {
        'to': to,
        'text': text,
        'lang_from': langFrom,
        'lang_to': langTo,
        if (clientId != null) 'client_id': clientId,
      });

  /// 🗣️ Envoie une note vocale (stockée comme un message, donc dans le fil).
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

  /// 🖼️ Envoie une photo (ou un fichier) — corps binaire brut.
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
      throw ApiException('Pas d\'Internet — vérifie ta connexion 📶', 'offline');
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

  /// ✓✓ Marque comme lus les messages reçus de [phone].
  Future<void> markConversationRead(String phone) async =>
      await _send('POST', '/messages/with/${Uri.encodeComponent(phone)}/read');

  /// 🗑️ Supprime un message **pour tout le monde** (expéditeur seulement).
  Future<void> deleteMessageForAll(String id) async =>
      await _send('DELETE', '/messages/$id');

  /// 🗑️ Supprime des messages **pour moi** (masqués de mon fil uniquement).
  Future<void> deleteMessagesForMe(List<String> ids) async =>
      await _send('POST', '/messages/delete', {'ids': ids, 'scope': 'me'});

  /// 👂 Signale qu'une note vocale reçue a été écoutée.
  Future<void> markMessagePlayed(String id) async =>
      await _send('POST', '/messages/$id/played');

  /// URL de téléchargement d'une pièce jointe privée (protégée par le jeton).
  String messageMediaUrl(String id) => '${Config.apiBase}/messages/media/$id';

  Future<Map> hangup(String id) async =>
      await _send('POST', '/calls/$id/hangup');
  /// 📞 Historique filtrable côté serveur.
  /// [filter] : all | in | out | missed | internet | gsm · [q] : nom ou numéro
  Future<Map> history({String filter = 'all', String? q, int limit = 100}) async {
    final b = StringBuffer('/calls/history?filter=$filter&limit=$limit');
    if (q != null && q.trim().isNotEmpty) {
      b.write('&q=${Uri.encodeComponent(q.trim())}');
    }
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

  // ---- ✉️ SMS vers le réseau GSM (facturés) ----

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

  // ────────────────────────────────────────────────────────────────
  // 📰 FIL DE PUBLICATION
  // ────────────────────────────────────────────────────────────────

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
    PostVisibilite visibilite = PostVisibilite.contacts,
    PostOrigine origine = PostOrigine.rdc,
    PostDuree duree = PostDuree.permanent,
  }) async {
    final r = await _send('POST', '/feed/posts', {
      'type': postTypeToApi(type),
      'visibilite': postVisibiliteToApi(visibilite),
      'origine': origine == PostOrigine.diaspora ? 'diaspora' : 'rdc',
      'duree': duree == PostDuree.h24 ? 'h24' : 'permanent',
      if (texte != null && texte.trim().isNotEmpty) 'texte': texte.trim(),
      if (mediaUrl != null) 'media_url': mediaUrl,
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

  /// 🧾 Journalise le début d'un appel de groupe (visible dans l'historique).
  Future<Map> startGroupCall(String callId) async =>
      await _send('POST', '/calls/group/start', {'call_id': callId});

  /// 🧾 Clôt l'appel de groupe avec sa durée réelle.
  Future<Map> endGroupCall(String callId, int durationSec) async => await _send(
      'POST', '/calls/group/$callId/end', {'duration_sec': durationSec});

  /// 🗑️ Supprime une publication — le serveur refuse (403) si je n'en suis
  /// pas l'auteur, ce qui protège même si l'interface se trompe.
  Future<void> deletePost(String id) async =>
      await _send('DELETE', '/feed/posts/$id');

  /// 🗑️ Supprime un statut (auteur uniquement).
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

  Future<Map> addComment(String id, String texte) async {
    final r = await _send('POST', '/feed/posts/$id/comments', {'texte': texte});
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
  Future<String> uploadMedia(String filePath) async {
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
          'Pas d\'Internet — vérifie ta connexion 📶', 'offline');
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
    return url;
  }
}

/// Une page du fil + curseur de continuation.
class FeedPage {
  final List<Post> posts;
  final int? nextBefore;
  final String? nextCursor;

  const FeedPage({required this.posts, this.nextBefore, this.nextCursor});

  bool get hasMore => nextCursor != null;
}
