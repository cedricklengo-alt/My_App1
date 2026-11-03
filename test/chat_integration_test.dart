// Test d'INTÉGRATION de l'onglet Discussion : vraies requêtes HTTP depuis le
// code Dart de l'application (`Api`) **et vrai WebSocket** (`Rtc`) vers un vrai
// serveur `mbote-backend` lancé à la volée.
//
// C'est la preuve de bout en bout, avec exactement les appels qu'utilisent les
// écrans « Discussion » et « Conversation » :
//   envoi d'un texte → fil du destinataire → accusé de lecture → réponse en
//   temps réel (WebSocket) → photo téléchargée à l'identique → note vocale
//   traduite écoutée → suppression pour moi / pour tout le monde →
//   pagination → indicateur de saisie.
//
// Lancement :
//   flutter test test/chat_integration_test.dart
// Variables reconnues :
//   MBOTE_BACKEND_DIR=/chemin/vers/mbote-backend   (défaut : ../mbote-backend)
//   MBOTE_CHAT_TEST_PORT=4792
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mbote/api.dart';
import 'package:mbote/config.dart';
import 'package:mbote/rtc.dart';

/// 1×1 PNG transparent : signature valide côté serveur.
const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
    'hKmMIQAAAABJRU5ErkJggg==';

class _User {
  final Api api;
  final String id;
  final String phone;
  final String name;
  _User(this.api, this.id, this.phone, this.name);
}

void main() {
  final backendDir = Platform.environment['MBOTE_BACKEND_DIR'] ??
      Directory.current.parent.uri.resolve('mbote-backend').toFilePath();
  final port =
      int.tryParse(Platform.environment['MBOTE_CHAT_TEST_PORT'] ?? '') ?? 4792;
  final base = 'http://127.0.0.1:$port/api';

  final hasBackend = Directory(backendDir).existsSync() &&
      File('$backendDir/src/server.js').existsSync();

  if (!hasBackend) {
    test('discussions — intégration', () {},
        skip: 'backend introuvable dans $backendDir');
    return;
  }

  Process? server;
  final suffix = DateTime.now().millisecondsSinceEpoch % 100000;

  setUpAll(() async {
    server = await Process.start(
      'node',
      ['src/server.js'],
      workingDirectory: backendDir,
      environment: {
        'PORT': '$port',
        'JWT_SECRET': 'test-chat-integration',
        'DEMO_MODE': 'true',
        'PUSH_DEBUG_FAKE': 'true',
        'DATABASE_URL': '',
        'PUBLIC_URL': 'http://127.0.0.1:$port',
        'MBOTE_MESSAGE_STORAGE': '/var/tmp/chat-it-storage',
        'MBOTE_LOKOTA_URL': '',
      },
    );
    server!.stdout.drain<void>();
    server!.stderr.drain<void>();

    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        final c = HttpClient();
        final req = await c.getUrl(Uri.parse('$base/health'));
        final res = await req.close();
        await res.drain<void>();
        c.close(force: true);
        if (res.statusCode == 200) break;
      } catch (_) {/* pas encore prêt */}
    }
    Config.apiBase = base;
  });

  tearDownAll(() async {
    Rtc.disconnect();
    Config.reset();
    server?.kill(ProcessSignal.sigkill);
    await server?.exitCode
        .timeout(const Duration(seconds: 5), onTimeout: () => -1);
  });

  Future<_User> login(String phone, String name) async {
    final api = Api();
    final a = await api.requestOtp(phone);
    final b = await api.verifyOtp(phone, '${a['demo_code']}', name: name);
    api.token = b['token'] as String?;
    expect(api.token, isNotNull, reason: 'jeton reçu après vérification OTP');
    final id = '${(b['user'] as Map?)?['id']}';
    expect(id, isNotEmpty);
    return _User(api, id, phone, name);
  }

  /// Attend un évènement WebSocket qui satisfait [test] (max 6 s).
  Future<Map?> waitFor(
    List<Map> boite,
    bool Function(Map m) test, {
    int ms = 6000,
  }) async {
    final fin = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(fin)) {
      for (final m in List<Map>.from(boite)) {
        if (test(m)) {
          boite.remove(m);
          return m;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return null;
  }

  test('parcours complet des discussions entre deux utilisateurs', () async {
    final alice = await login('+2439100$suffix', 'Alice Chat');
    final bob = await login('+2439101$suffix', 'Bob Chat');

    // ── 1. Envoi d'un texte ────────────────────────────────────────────
    final m1 = await alice.api.sendMessage(
      bob.phone,
      'Mbote Bob, tu es là ?',
      clientId: 'it-1$suffix',
    );
    expect(m1['id'], isNotEmpty);
    expect(m1['mine'], isTrue);
    expect(m1['body'], 'Mbote Bob, tu es là ?');

    // Le même client_id renvoyé ne crée pas de doublon (réseau instable).
    final again = await alice.api.sendMessage(bob.phone, 'Mbote Bob, tu es là ?',
        clientId: 'it-1$suffix');
    expect(again['id'], m1['id'], reason: 'envoi idempotent');

    // ── 2. Le destinataire voit le message et le non-lu ────────────────
    final filsBob = await bob.api.messageThreads();
    final fil = filsBob.firstWhere((t) => '${(t as Map)['peer_phone']}' == alice.phone)
        as Map;
    expect(fil['peer_name'], 'Alice Chat');
    expect(fil['last_preview'], 'Mbote Bob, tu es là ?');
    expect(fil['unread'], 1);
    expect(fil['last_mine'], isFalse);

    final convBob = await bob.api.conversation(alice.phone);
    final itemsBob = (convBob['items'] as List).cast<Map>();
    final recu = itemsBob.firstWhere((m) => m['id'] == m1['id']);
    expect(recu['mine'], isFalse);
    expect(recu['kind'], 'text');
    expect(recu['status'], 'done');

    // ── 3. Accusé de lecture : l'expéditeur voit « lu » ────────────────
    await bob.api.markConversationRead(alice.phone);
    final convAlice = await alice.api.conversation(bob.phone);
    final vueParAlice = (convAlice['items'] as List)
        .cast<Map>()
        .firstWhere((m) => m['id'] == m1['id']);
    expect(vueParAlice['status'], 'read');
    expect(vueParAlice['mine'], isTrue);

    // ── 4. Temps réel : la réponse arrive par WebSocket ───────────────
    final boite = <Map>[];
    void onMessage(Map m) => boite.add(m);
    Rtc.addMessageListener(onMessage);
    Rtc.connect(alice.api.token!);
    for (var i = 0; i < 100 && !Rtc.connected.value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(Rtc.connected.value, isTrue, reason: 'canal temps réel ouvert');

    await bob.api.sendMessage(alice.phone, 'Oui, je t’écoute 👂');
    final notif = await waitFor(
        boite, (m) => m['type'] == 'msg' && m['kind'] == 'message');
    expect(notif, isNotNull, reason: 'l’expéditeur reçoit le message en direct');
    expect(notif!['from_phone'], bob.phone);
    expect(notif['from_name'], 'Bob Chat');
    expect(notif['preview'], 'Oui, je t’écoute 👂');

    // ── 5. « écrit… » relayé par le serveur ────────────────────────────
    // Bob ouvre aussi un canal WebSocket : il servira à vérifier l'évènement
    // « supprimé » (le serveur prévient le destinataire, pas l'auteur).
    final boiteBob = <Map>[];
    final wsBob = await WebSocket.connect('${Config.wsUrl}?token=${bob.api.token}');
    wsBob.listen((raw) {
      try {
        boiteBob.add(jsonDecode('$raw') as Map);
      } catch (_) {/* ping */}
    });
    wsBob.add(jsonEncode({'type': 'typing', 'to': alice.phone}));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final saisie = await waitFor(boite, (m) => m['type'] == 'typing');
    expect(saisie, isNotNull, reason: 'indicateur de saisie relayé');
    expect(saisie!['from'], bob.phone);

    // ── 6. Photo : envoyée puis téléchargée à l'identique ─────────────
    final png = base64Decode(_png1x1);
    final photo = await alice.api.sendMessageMedia(
      bob.phone,
      bytes: png,
      kind: 'image',
      mime: 'image/png',
      name: 'kin.png',
      clientId: 'img-1$suffix',
    );
    expect(photo['kind'], 'image');
    expect(photo['has_media'], isTrue);
    expect(photo['att_name'], 'kin.png');

    final filsBob2 = await bob.api.messageThreads();
    final fil2 = filsBob2
        .firstWhere((t) => '${(t as Map)['peer_phone']}' == alice.phone) as Map;
    expect(fil2['last_preview'], 'Photo');

    final dl = await HttpClient()
        .getUrl(Uri.parse(alice.api.messageMediaUrl('${photo['id']}')))
        .then((req) {
      req.headers.set('Authorization', 'Bearer ${bob.api.token}');
      return req.close();
    });
    expect(dl.statusCode, 200);
    final octets = await dl
        .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
    expect(octets, png, reason: 'octets identiques à l’envoi');

    // ── 7. Note vocale traduite, puis « écoutée » ─────────────────────
    boite.clear();
    final note = await alice.api.sendVoiceNote(
      bob.phone,
      bytes: List<int>.filled(3000, 3),
      durationSec: 9,
      langFrom: 'fr',
      langTo: 'ln',
    );
    expect(note['kind'], 'note');
    expect(note['duration_sec'], 9);
    expect(note['lang_from'], 'fr');
    expect(note['lang_to'], 'ln');

    final filsBob3 = await bob.api.messageThreads();
    final fil3 = filsBob3
        .firstWhere((t) => '${(t as Map)['peer_phone']}' == alice.phone) as Map;
    expect(fil3['last_preview'], 'Note vocale');

    await bob.api.markMessagePlayed('${note['id']}');
    final ecoute = await waitFor(boite, (m) => m['kind'] == 'played');
    expect(ecoute, isNotNull, reason: 'l’auteur sait que sa note a été écoutée');
    expect(ecoute!['msg_id'], note['id']);

    // ── 8. Suppression « pour moi » puis « pour tout le monde » ────────
    await bob.api.deleteMessagesForMe([m1['id'] as String]);
    final convBob2 = await bob.api.conversation(alice.phone);
    expect(
      (convBob2['items'] as List).every((m) => (m as Map)['id'] != m1['id']),
      isTrue,
      reason: 'disparaît de mon fil',
    );
    final convAlice2 = await alice.api.conversation(bob.phone);
    expect(
      (convAlice2['items'] as List).any((m) => (m as Map)['id'] == m1['id']),
      isTrue,
      reason: 'reste visible chez l’autre',
    );

    await alice.api.deleteMessageForAll('${note['id']}');
    final efface = await waitFor(boiteBob, (m) => m['kind'] == 'deleted');
    expect(efface, isNotNull, reason: 'le proche est prévenu de la suppression');
    final convBob3 = await bob.api.conversation(alice.phone);
    final noteSupprimee = (convBob3['items'] as List)
        .cast<Map>()
        .firstWhere((m) => m['id'] == note['id']);
    expect(noteSupprimee['kind'], 'deleted');
    expect(noteSupprimee['body'], '');

    // ── 9. Pagination : 50 par page, puis on remonte le temps ──────────
    for (var i = 0; i < 55; i++) {
      await alice.api.sendMessage(bob.phone, 'vague $i',
          clientId: 'w$i-$suffix');
    }
    final page1 = await bob.api.conversation(alice.phone);
    final items1 = (page1['items'] as List).cast<Map>();
    expect(items1.length, 50);
    expect(page1['has_more'], isTrue);
    expect(items1.last['body'], 'vague 54');

    final page2 = await bob.api
        .conversation(alice.phone, before: items1.first['created_at'] as int);
    final items2 = (page2['items'] as List).cast<Map>();
    expect(items2, isNotEmpty);
    expect(
      items2.any((m) => items1.any((x) => x['id'] == m['id'])),
      isFalse,
      reason: 'aucun doublon entre les pages',
    );

    await wsBob.close();
    Rtc.removeMessageListener(onMessage);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
