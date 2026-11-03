// Le canal temps réel doit rester vivant — sinon l'appel part dans le vide.
//
// Cas réel (3 novembre 2026) : « les appels ne passent pas ». Un canal WebSocket
// resté muet est fermé par les intermédiaires (proxy de l'hébergeur, NAT de
// l'opérateur) au bout d'une minute environ. L'app se croyait alors joignable
// alors que le serveur ne la voyait plus : l'appel n'arrivait jamais.
//
// Ces tests montent un VRAI serveur WebSocket local (dart:io) et vérifient :
//   - que l'app ouvre le canal et s'annonce ;
//   - qu'elle envoie un `ping` régulier (battement de cœur) ;
//   - qu'elle se reconnecte après une coupure réseau ;
//   - qu'elle abandonne un canal devenu muet.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mbote/config.dart';
import 'package:mbote/rtc.dart';

/// Petit « standardiste » de test : accepte les connexions et note les messages.
class FauxStandardiste {
  FauxStandardiste._(this._serveur);

  final HttpServer _serveur;
  final List<List<Map>> sessions = []; // messages reçus, par connexion
  final List<WebSocket> _sockets = [];

  static Future<FauxStandardiste> demarrer() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final faux = FauxStandardiste._(s);
    s.listen((req) async {
      if (!WebSocketTransformer.isUpgradeRequest(req)) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(req);
      final recus = <Map>[];
      faux.sessions.add(recus);
      faux._sockets.add(ws);
      ws.listen((data) {
        try {
          recus.add(jsonDecode(data as String) as Map);
        } catch (_) {}
      }, onError: (_) {}, cancelOnError: false);
    });
    return faux;
  }

  int get port => _serveur.port;
  int get connexions => sessions.length;

  /// Coupe toutes les connexions ouvertes (comme le ferait un proxy).
  Future<void> couperTout() async {
    for (final ws in _sockets) {
      try {
        await ws.close();
      } catch (_) {}
    }
    _sockets.clear();
  }

  bool aRecu(String type) => sessions.any((s) => s.any((m) => m['type'] == type));

  Future<void> fermer() async {
    await couperTout();
    await _serveur.close(force: true);
  }
}

/// Attend qu'une condition devienne vraie (max [ms]).
Future<bool> attendre(bool Function() cond, {int ms = 4000}) async {
  final fin = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(fin)) {
    if (cond()) return true;
    await Future.delayed(const Duration(milliseconds: 30));
  }
  return cond();
}

void main() {
  late FauxStandardiste faux;
  late String baseOrigine;

  setUp(() async {
    baseOrigine = Config.apiBase;
    faux = await FauxStandardiste.demarrer();
    Config.apiBase = 'http://127.0.0.1:${faux.port}/api';
    // Raccourci les délais pour que le test dure des millisecondes.
    Rtc.pingInterval = const Duration(milliseconds: 120);
    Rtc.silenceMax = const Duration(milliseconds: 400);
  });

  tearDown(() async {
    Rtc.disconnect();
    Config.apiBase = baseOrigine;
    Rtc.pingInterval = const Duration(seconds: 25);
    Rtc.silenceMax = const Duration(seconds: 70);
    await faux.fermer();
    await Future.delayed(const Duration(milliseconds: 50));
  });

  test('l’app ouvre le canal et s’annonce au serveur', () async {
    Rtc.connect('jeton-test');
    expect(await attendre(() => faux.connexions == 1), isTrue,
        reason: 'aucune connexion reçue');
    expect(await attendre(() => faux.aRecu('presence')), isTrue,
        reason: 'l’app ne s’est pas annoncée');
    expect(Rtc.connected.value, isTrue);
  });

  test('l’URL du canal pointe sur /ws et passe en wss', () async {
    Config.apiBase = 'https://mbote-backend-1.onrender.com/api';
    // On vérifie la transformation utilisée pour la connexion réelle.
    final url = Config.apiBase
        .replaceFirst('/api', '/ws')
        .replaceFirst('http', 'ws');
    expect(url, 'wss://mbote-backend-1.onrender.com/ws');
  });

  test('le canal envoie un battement de cœur régulier', () async {
    Rtc.connect('jeton-test');
    expect(await attendre(() => faux.connexions == 1), isTrue);
    final recus = faux.sessions.first;
    expect(await attendre(() => recus.where((m) => m['type'] == 'ping').length >= 2),
        isTrue,
        reason: 'moins de deux ping reçus : ${recus.map((m) => m['type']).toList()}');
  });

  test('après une coupure, l’app se reconnecte toute seule', () async {
    Rtc.connect('jeton-test');
    expect(await attendre(() => faux.connexions == 1), isTrue);
    await faux.couperTout();
    expect(await attendre(() => Rtc.connected.value == false, ms: 3000), isTrue,
        reason: 'le voyant est resté vert alors que le canal est coupé');
    expect(await attendre(() => faux.connexions >= 2, ms: 8000), isTrue,
        reason: 'pas de reconnexion après la coupure');
  });

  test('un canal muet est abandonné puis rouvert', () async {
    Rtc.connect('jeton-test');
    expect(await attendre(() => faux.connexions == 1), isTrue);
    // On empêche tout message d'arriver : le serveur ne répond plus du tout.
    await faux.couperTout();
    final reconnexions = faux.connexions;
    expect(await attendre(() => faux.connexions > reconnexions, ms: 8000), isTrue,
        reason: 'le canal muet n’a jamais été rouvert');
  });

  test('disconnect() coupe le voyant et arrête le battement', () async {
    Rtc.connect('jeton-test');
    expect(await attendre(() => faux.connexions == 1), isTrue);
    Rtc.disconnect();
    expect(await attendre(() => Rtc.connected.value == false, ms: 2000), isTrue);
    final avant = faux.sessions.first.length;
    await Future.delayed(const Duration(milliseconds: 500));
    expect(faux.sessions.first.length, avant,
        reason: 'des messages sont encore envoyés après la déconnexion');
  });
}
