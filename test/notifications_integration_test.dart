// Test d'INTÉGRATION des notifications d'interaction : vraies requêtes HTTP du
// code Dart de l'application (`Api`) vers un vrai serveur `mbote-backend` lancé
// à la volée.
//
// Ce que l'on prouve ici, et que des simulacres ne peuvent pas prouver :
//   1. un j'aime crée UNE notification, et le retrait la supprime ;
//   2. dix allers-retours ne font toujours qu'une notification, un seul auteur ;
//   3. deux auteurs sur la même publication sont regroupés dans une seule ligne
//      (« … ont aimé votre publication »), avec le bon nombre de personnes ;
//   4. un commentaire notifie l'auteur, une réponse notifie l'auteur du
//      commentaire parent — jamais deux fois la même personne ;
//   5. un partage notifie ; un partage anonyme ne notifie personne ;
//   6. l'application sait se positionner sur le commentaire visé (comment_id) ;
//   7. l'analytique d'engagement compte les interactions et classe les
//      publications.
//
// Lancement :  flutter test test/notifications_integration_test.dart
// Variables :  MBOTE_BACKEND_DIR, MBOTE_TEST_PORT (défaut 4805)
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mbote/api.dart';
import 'package:mbote/config.dart';
import 'package:mbote/models/post.dart';
import 'package:mbote/models/social.dart';

class _Compte {
  final Api api;
  final String id;
  final String phone;
  final String name;
  final String? handle;
  _Compte(this.api, this.id, this.phone, this.name, this.handle);
}

void main() {
  final backendDir = Platform.environment['MBOTE_BACKEND_DIR'] ??
      Directory.current.parent.uri.resolve('mbote-backend').toFilePath();
  final port =
      int.tryParse(Platform.environment['MBOTE_TEST_PORT'] ?? '') ?? 4805;
  final base = 'http://127.0.0.1:$port/api';

  final hasBackend = Directory(backendDir).existsSync() &&
      File('$backendDir/src/server.js').existsSync();

  if (!hasBackend) {
    test('notifications — intégration', () {},
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
        'JWT_SECRET': 'test-notifs-it',
        'DEMO_MODE': 'true',
        'PUSH_DEBUG_FAKE': 'true',
        'DATABASE_URL': '',
        'MBOTE_MESSAGE_STORAGE': '/var/tmp/notifs-it',
        'PUBLIC_URL': 'http://127.0.0.1:$port',
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
    Config.reset();
    server?.kill(ProcessSignal.sigkill);
    await server?.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
  });

  Future<_Compte> login(String phone, String name) async {
    final api = Api();
    final a = await api.requestOtp(phone);
    final b = await api.verifyOtp(phone, '${a['demo_code']}', name: name);
    api.token = b['token'] as String?;
    final user = b['user'] as Map?;
    return _Compte(api, '${user?['id']}', phone, name, user?['handle'] as String?);
  }

  Future<List<NotificationSociale>> boiteDe(_Compte c) async {
    final r = await c.api.notifications(limite: 50);
    return ((r['notifications'] as List?) ?? const [])
        .map((e) => NotificationSociale.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  test('j’aime : une notification, le retrait l’efface, le regroupement tient',
      () async {
    final aline = await login('+2438400$suffix', 'Aline Mbala');
    final patrick = await login('+2438401$suffix', 'Patrick Ilunga');
    final junior = await login('+2438402$suffix', 'Junior Kasongo');

    final post = await aline.api.createPost(
      type: PostType.texte,
      texte: 'Le fleuve monte ce matin à Kinshasa',
    );

    // 1. Un j'aime → une notification.
    await patrick.api.likePost(post.id);
    var boite = await boiteDe(aline);
    var likes = boite.where((n) => n.type == 'post_like').toList();
    expect(likes.length, 1);
    expect(likes.first.postId, post.id);
    expect(likes.first.lu, isFalse);
    expect(likes.first.resume, contains('a aimé votre publication'));
    expect(await aline.api.notificationsNonLues(), greaterThanOrEqualTo(1));

    // 2. Le retrait l'efface : pas de « X a aimé » fantôme.
    await patrick.api.likePost(post.id);
    boite = await boiteDe(aline);
    expect(boite.where((n) => n.type == 'post_like'), isEmpty);

    // 3. Dix allers-retours → une seule ligne, un seul auteur.
    for (var i = 0; i < 10; i++) {
      await patrick.api.likePost(post.id);
      if (i < 9) await patrick.api.likePost(post.id);
    }
    boite = await boiteDe(aline);
    likes = boite.where((n) => n.type == 'post_like').toList();
    expect(likes.length, 1);
    expect(likes.first.nbActeurs, 1);

    // 4. Un deuxième auteur rejoint la même ligne.
    await junior.api.likePost(post.id);
    boite = await boiteDe(aline);
    likes = boite.where((n) => n.type == 'post_like').toList();
    expect(likes.length, 1, reason: 'les j’aime se regroupent sur une ligne');
    expect(likes.first.nbActeurs, 2);
    expect(likes.first.resume, contains('ont aimé'));
    expect(likes.first.acteurs.length, 2);

    // 5. L'auteur ne se notifie jamais lui-même.
    await aline.api.likePost(post.id);
    boite = await boiteDe(aline);
    expect(
        boite.where((n) => n.type == 'post_like').first.nbActeurs, 2,
        reason: 'un auteur qui aime sa publication ne s’ajoute pas');
    await aline.api.likePost(post.id);
  });

  test('commentaire et réponse notifient les bonnes personnes, une seule fois',
      () async {
    final aline = await login('+2438410$suffix', 'Aline Mbala');
    final patrick = await login('+2438411$suffix', 'Patrick Ilunga');

    final post = await aline.api.createPost(
      type: PostType.texte,
      texte: 'Photo du fleuve au lever du jour',
    );

    final commentaire =
        await patrick.api.addComment(post.id, 'Superbe, merci du partage !');

    var boiteAline = await boiteDe(aline);
    final commentaires = boiteAline.where((n) => n.type == 'comment').toList();
    expect(commentaires.length, 1);
    expect(commentaires.first.resume, contains('a commenté votre publication'));
    expect(commentaires.first.commentId, commentaire['id'],
        reason: 'l’application doit pouvoir se positionner sur ce commentaire');
    expect(commentaires.first.texte, contains('Superbe'));

    // Réponse d'Aline au commentaire de Patrick.
    final reponse = await aline.api
        .addComment(post.id, 'Merci Patrick !', parentId: '${commentaire['id']}');
    expect('${reponse['parent_id']}', '${commentaire['id']}');

    final boitePatrick = await boiteDe(patrick);
    final reponses =
        boitePatrick.where((n) => n.type == 'comment_reply').toList();
    expect(reponses.length, 1);
    expect(reponses.first.resume, contains('a répondu à votre commentaire'));
    expect(reponses.first.commentId, '${reponse['id']}');

    // Aline n'est pas notifiée de sa propre réponse.
    boiteAline = await boiteDe(aline);
    expect(
        boiteAline.where((n) => n.commentId == '${reponse['id']}'), isEmpty);

    // La liste des commentaires expose la réponse.
    final liste = await aline.api.postComments(post.id);
    final enfants =
        liste.where((c) => '${c['parent_id']}' == '${commentaire['id']}');
    expect(enfants.length, 1);
  });

  test('partage : l’auteur est notifié, un visiteur anonyme ne l’est pas',
      () async {
    final aline = await login('+2438420$suffix', 'Aline Mbala');
    final junior = await login('+2438421$suffix', 'Junior Kasongo');

    final post = await aline.api.createPost(
      type: PostType.texte,
      texte: 'Kinshasa by night',
    );

    final partage = await junior.api.markShared(post.id);
    expect((partage['partages'] as num).toInt(), greaterThanOrEqualTo(1));

    var boite = await boiteDe(aline);
    final partages = boite.where((n) => n.type == 'share').toList();
    expect(partages.length, 1);
    expect(partages.first.resume, contains('a partagé votre publication'));

    // Un anonyme (sans jeton) partage : le compteur monte, la boîte ne bouge pas.
    final avant = partages.first.nbActeurs;
    await Api().markShared(post.id);
    boite = await boiteDe(aline);
    expect(boite.where((n) => n.type == 'share').first.nbActeurs, avant);
  });

  test('badge, lecture unitaire et analytique d’engagement', () async {
    final aline = await login('+2438430$suffix', 'Aline Mbala');
    final patrick = await login('+2438431$suffix', 'Patrick Ilunga');

    final post = await aline.api.createPost(
      type: PostType.texte,
      texte: 'Mokili mobimba #Kinshasa',
    );
    await patrick.api.likePost(post.id);
    await patrick.api.addComment(post.id, 'Bien vu');
    await patrick.api.markShared(post.id);

    final n = await aline.api.notificationsNonLues();
    expect(n, greaterThanOrEqualTo(3));

    final boite = await boiteDe(aline);
    await aline.api.marquerNotificationLue(boite.first.id);
    expect(await aline.api.notificationsNonLues(), n - 1);

    await aline.api.marquerNotificationsLues();
    expect(await aline.api.notificationsNonLues(), 0);

    final stats = await aline.api.analytiqueEngagement();
    final e = Map<String, dynamic>.from(stats['engagement'] as Map);
    expect((e['likes'] as num).toInt(), greaterThanOrEqualTo(1));
    expect((e['commentaires'] as num).toInt(), greaterThanOrEqualTo(1));
    expect((e['partages'] as num).toInt(), greaterThanOrEqualTo(1));
    expect(e['taux'], isNotNull);
    final top = (e['top'] as List).cast<Map>();
    expect(top, isNotEmpty);
    expect('${top.first['id']}', post.id,
        reason: 'la publication la plus engageante est en tête');
  });
}
