import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'config.dart';

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
      throw ApiException('Pas d\'Internet — vérifie ta connexion 📶', 'offline');
    } on http.ClientException {
      throw ApiException('Pas d\'Internet — vérifie ta connexion 📶', 'offline');
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
              ? (data['error'] ?? 'Service momentanément indisponible — réessaie')
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
  Future<Map> transfer(String toPhone, int amountCents) async =>
      await _send('POST', '/wallet/transfer',
          {'to_phone': toPhone, 'amount_cents': amountCents});

  // ---- 📦 Forfaits ----
  Future<List> packages() async => await _send('GET', '/packages');
  Future<List> myPackages() async => await _send('GET', '/packages/mine');
  Future<Map> buyPackage(int id) async =>
      await _send('POST', '/packages/$id/buy');

  // ---- 📱 Airtime : offrir du crédit GSM à un proche ----
  Future<Map> sendAirtime(String phone, int amountCents) async =>
      await _send('POST', '/airtime',
          {'phone': phone, 'amount_cents': amountCents});
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
  Future<void> logIncoming(String from, int billedSec) async =>
      await _send('POST', '/calls/log-incoming',
          {'from': from, 'billed_sec': billedSec});

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

  Future<Map> hangup(String id) async =>
      await _send('POST', '/calls/$id/hangup');
  Future<Map> history() async => await _send('GET', '/calls/history');
}
