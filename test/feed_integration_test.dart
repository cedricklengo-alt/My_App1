// Test d'INTÉGRATION du fil : vraies requêtes HTTP depuis le code Dart de
// l'application (`Api`) vers un vrai serveur `mbote-backend` lancé à la volée.
//
// C'est la preuve de bout en bout : inscription par OTP, contacts, publication,
// lecture du fil, j'aime, commentaire, pagination par curseur, statuts et envoi
// de fichier — avec les mêmes appels que ceux utilisés par l'écran Accueil.
//
// Lancement :
//   flutter test test/feed_integration_test.dart
// Variables reconnues :
//   MBOTE_BACKEND_DIR=/chemin/vers/mbote-backend   (défaut : ../mbote-backend)
//   MBOTE_TEST_PORT=4790
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mbote/api.dart';
import 'package:mbote/config.dart';
import 'package:mbote/models/post.dart';

/// 1×1 PNG transparent, écrit sur disque pour tester l'envoi de fichier.
const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
    'hKmMIQAAAABJRU5ErkJggg==';

void main() {
  final backendDir = Platform.environment['MBOTE_BACKEND_DIR'] ??
      Directory.current.parent.uri.resolve('mbote-backend').toFilePath();
  final port =
      int.tryParse(Platform.environment['MBOTE_TEST_PORT'] ?? '') ?? 4790;
  final base = 'http://127.0.0.1:$port/api';

  final hasBackend = Directory(backendDir).existsSync() &&
      File('$backendDir/src/server.js').existsSync();

  if (!hasBackend) {
    // Sur une machine sans le dépôt backend, on n'échoue pas : on le dit.
    test('fil — intégration', () {},
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
        'JWT_SECRET': 'test-integration',
        'DEMO_MODE': 'true',
        'PUSH_DEBUG_FAKE': 'true',
        'DATABASE_URL': '',
        'MBOTE_MESSAGE_STORAGE': '/var/tmp/feed-it-storage',
        // Sans cela, le `.env` du dépôt fait pointer les URL d'images vers la
        // production et le fichier envoyé localement est introuvable.
        'PUBLIC_URL': 'http://127.0.0.1:$port',
      },
    );
    server!.stdout.drain<void>();
    server!.stderr.drain<void>();

    // Attente du démarrage (max 30 s).
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
    Config.reset();
    server?.kill(ProcessSignal.sigkill);
    await server?.exitCode
        .timeout(const Duration(seconds: 5), onTimeout: () => -1);
  });

  /// Connexion complète par OTP de démonstration.
  Future<_User> login(String phone, String name) async {
    final api = Api();
    final a = await api.requestOtp(phone);
    final code = '${a['demo_code']}';
    final b = await api.verifyOtp(phone, code, name: name);
    api.token = b['token'] as String?;
    expect(api.token, isNotNull, reason: 'jeton reçu après vérification OTP');
    final id = '${(b['user'] as Map?)?['id']}';
    expect(id, isNotEmpty);
    return _User(api, id, phone);
  }

  test('parcours complet du fil entre deux utilisateurs', () async {
    final alicePhone = '+2439000$suffix';
    final bobPhone = '+2439001$suffix';

    final alice = await login(alicePhone, 'Alice IT');
    final bob = await login(bobPhone, 'Bob IT');

    // 1. Bob est dans les contacts d'Alice → son numéro doit apparaître.
    await alice.api.addContact('Bob IT', bobPhone);

    // 2. Bob publie un texte visible par ses contacts.
    final post = await bob.api.createPost(
      type: PostType.texte,
      texte: 'Salut les amis $suffix',
      visibilite: PostVisibilite.contacts,
      ville: 'Kinshasa',
    );
    expect(post.id, isNotEmpty);
    expect(post.texte, 'Salut les amis $suffix');

    // 3. Alice lit le fil : le post y est, avec le numéro (il est contact).
    final page = await alice.api.feedPage();
    expect(page.posts, isNotEmpty, reason: 'le fil ne doit pas être vide');
    final vu = page.posts.firstWhere((p) => p.id == post.id);
    expect(vu.authorName, 'Bob IT');
    expect(vu.texte, 'Salut les amis $suffix');
    expect(vu.authorPhone, bobPhone, reason: 'contact → numéro fourni');
    expect(vu.canCall, isTrue, reason: '→ bouton « Appeler » affiché');
    expect(vu.ville, 'Kinshasa');
    expect(vu.likes, 0);
    expect(vu.liked, isFalse);

    // 4. J'aime / je retire.
    final like = await alice.api.likePost(post.id);
    expect(like['liked'], isTrue);
    expect(like['likes'], 1);
    final feed2 = await alice.api.feedPage();
    expect(feed2.posts.firstWhere((p) => p.id == post.id).liked, isTrue);
    final unlike = await alice.api.likePost(post.id);
    expect(unlike['liked'], isFalse);
    expect(unlike['likes'], 0);

    // 5. Commentaire : écrit puis relu.
    await alice.api.addComment(post.id, 'Bien reçu, frère !');
    final comments = await alice.api.postComments(post.id);
    expect(comments.length, 1);
    expect(comments.first['texte'], 'Bien reçu, frère !');
    final feed3 = await alice.api.feedPage();
    expect(feed3.posts.firstWhere((p) => p.id == post.id).comments, 1);

    // 6. Un inconnu (non contact) ne voit ni le post « contacts », ni le numéro.
    final stranger = await login('+2439002$suffix', 'Chantal IT');
    final vueStranger = await stranger.api.feedPage();
    expect(vueStranger.posts.any((p) => p.id == post.id), isFalse,
        reason: 'visibilité « contacts » respectée');

    // Post public : visible par tous, mais sans numéro.
    final pub = await bob.api.createPost(
      type: PostType.texte,
      texte: 'Annonce publique $suffix',
      visibilite: PostVisibilite.public,
    );
    final vuePublique = await stranger.api.feedPage();
    final trouve = vuePublique.posts.firstWhere((p) => p.id == pub.id);
    expect(trouve.authorPhone, isNull, reason: 'inconnu → numéro masqué');
    expect(trouve.canCall, isFalse);

    // 7. Pagination par curseur : plus de 20 publications → page suivante.
    for (var i = 0; i < 22; i++) {
      await bob.api.createPost(
        type: PostType.texte,
        texte: 'Série $suffix #$i',
        visibilite: PostVisibilite.public,
      );
    }
    final p1 = await alice.api.feedPage();
    expect(p1.posts.length, 20);
    expect(p1.hasMore, isTrue, reason: 'il reste des publications');
    expect(p1.nextCursor, isNotNull);

    final p2 =
        await alice.api.feedPage(before: p1.nextBefore, cursor: p1.nextCursor);
    expect(p2.posts, isNotEmpty);
    final ids1 = p1.posts.map((p) => p.id).toSet();
    expect(p2.posts.every((p) => !ids1.contains(p.id)), isTrue,
        reason: 'aucun doublon entre les pages');

    // 8. Statuts : publication, lecture, marquage « vu ».
    await alice.api.postStory(texte: 'Mon statut $suffix');
    final stories = await bob.api.feedStories();
    final mienne = stories.firstWhere((s) => s.userId == alice.id,
        orElse: () => throw StateError('statut d’Alice absent'));
    expect(mienne.texte, 'Mon statut $suffix');
    expect(mienne.seen, isFalse);
    await bob.api.markStorySeen(mienne.id);
    final apres = await bob.api.feedStories();
    expect(apres.firstWhere((s) => s.id == mienne.id).seen, isTrue);

    // 9. Envoi de fichier (photo) : le type MIME doit être accepté.
    final tmp = File('${Directory.systemTemp.path}/mbote-it-$suffix.png')
      ..writeAsBytesSync(base64Decode(_png1x1));
    addTearDown(() => tmp.existsSync() ? tmp.deleteSync() : null);
    final url = await alice.api.uploadMedia(tmp.path);
    expect(url, contains('/uploads/'));
    expect(url, startsWith('http://127.0.0.1:$port/'),
        reason: 'URL renvoyée par le serveur local');
    final c = HttpClient();
    final res = await (await c.getUrl(Uri.parse(url))).close();
    await res.drain<void>();
    c.close(force: true);
    expect(res.statusCode, 200, reason: 'le fichier envoyé est servi : $url');

    // 10. Événement : date, lieu et mots-clés font l'aller-retour.
    final ev = await bob.api.createPost(
      type: PostType.event,
      texte: 'Concert de rumba',
      eventTitle: 'Fikin $suffix',
      eventDate: DateTime(2026, 12, 31, 20, 30),
      eventLieu: 'Palais du Peuple',
      eventTags: const ['musique', 'kin'],
      visibilite: PostVisibilite.public,
    );
    expect(ev.eventTitle, 'Fikin $suffix');
    expect(ev.eventLieu, 'Palais du Peuple');
    expect(ev.eventTags, containsAll(['musique', 'kin']));
    expect(ev.eventDate, isNotNull);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

class _User {
  final Api api;
  final String id;
  final String phone;
  _User(this.api, this.id, this.phone);
}
