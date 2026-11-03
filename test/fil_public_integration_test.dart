// Test d'INTÉGRATION du fil public : vraies requêtes HTTP depuis le code Dart
// de l'application (`Api`) vers un vrai serveur `mbote-backend` lancé à la volée.
//
// Ce que l'on prouve ici, et qui ne pouvait pas l'être avant :
//   1. une publication créée sans préciser d'audience est PUBLIQUE et un autre
//      utilisateur la voit dans son fil (c'était le défaut : personne ne voyait
//      rien sauf l'auteur) ;
//   2. la découverte publique classe et renvoie les publications ;
//   3. « Suivre » remplit un fil d'abonnements ;
//   4. les vues se comptent une fois par lecteur, jamais pour l'auteur ;
//   5. les mots-clés alimentent les tendances et le filtrage ;
//   6. l'auteur peut ouvrir ses anciennes publications à tout le monde.
//
// Lancement :
//   flutter test test/fil_public_integration_test.dart
// Variables reconnues :
//   MBOTE_BACKEND_DIR=/chemin/vers/mbote-backend   (défaut : ../mbote-backend)
//   MBOTE_TEST_PORT=4791
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mbote/api.dart';
import 'package:mbote/config.dart';
import 'package:mbote/models/post.dart';

void main() {
  final backendDir = Platform.environment['MBOTE_BACKEND_DIR'] ??
      Directory.current.parent.uri.resolve('mbote-backend').toFilePath();
  final port =
      int.tryParse(Platform.environment['MBOTE_TEST_PORT'] ?? '') ?? 4791;
  final base = 'http://127.0.0.1:$port/api';

  final hasBackend = Directory(backendDir).existsSync() &&
      File('$backendDir/src/server.js').existsSync();

  if (!hasBackend) {
    test('fil public — intégration', () {},
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
        'JWT_SECRET': 'test-fil-public',
        'DEMO_MODE': 'true',
        'PUSH_DEBUG_FAKE': 'true',
        'DATABASE_URL': '',
        'MBOTE_MESSAGE_STORAGE': '/var/tmp/fil-public-it',
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
    await server?.exitCode
        .timeout(const Duration(seconds: 5), onTimeout: () => -1);
  });

  Future<_Compte> login(String phone, String name) async {
    final api = Api();
    final a = await api.requestOtp(phone);
    final b = await api.verifyOtp(phone, '${a['demo_code']}', name: name);
    api.token = b['token'] as String?;
    return _Compte(api, '${(b['user'] as Map?)?['id']}', phone, name);
  }

  test('le fil public voit les publications de tout le monde', () async {
    final auteur = await login('+2438200$suffix', 'Auteur Public');
    final lecteur = await login('+2438201$suffix', 'Lecteur Public');
    final inconnu = await login('+2438202$suffix', 'Inconnu Public');

    // 1. Aucune audience précisée → PUBLIC (le défaut d'avant était
    //    « contacts », c'est-à-dire invisible pour tout le monde).
    final p = await auteur.api.createPost(
      type: PostType.texte,
      texte: 'Publication sans audience $suffix',
    );
    expect(p.visibilite, PostVisibilite.public,
        reason: 'une publication sans audience explicite doit être publique');

    // 2. Un autre utilisateur la voit dans son fil.
    final filLecteur = await lecteur.api.feedPage();
    expect(filLecteur.posts.any((x) => x.id == p.id), isTrue,
        reason: 'le fil d’un autre utilisateur doit contenir la publication');

    // 3. Elle est aussi dans la découverte.
    final decouverte = await lecteur.api.discoverPage();
    expect(decouverte.posts.any((x) => x.id == p.id), isTrue);

    // 4. La visibilité « contacts » reste, elle, protégée.
    final restreint = await auteur.api.createPost(
      type: PostType.texte,
      texte: 'Pour mes contacts seulement $suffix',
      visibilite: PostVisibilite.contacts,
    );
    final filInconnu = await inconnu.api.feedPage();
    expect(filInconnu.posts.any((x) => x.id == restreint.id), isFalse,
        reason: 'un inconnu ne doit jamais voir une publication « contacts »');
    expect(
        (await inconnu.api.discoverPage())
            .posts
            .any((x) => x.id == restreint.id),
        isFalse,
        reason: 'la découverte ne contient que du public');

    // 5. Mais un contact la voit.
    await lecteur.api.addContact('Auteur Public', auteur.phone);
    final filContact = await lecteur.api.feedPage();
    expect(filContact.posts.any((x) => x.id == restreint.id), isTrue);

    // 6. L'auteur peut ouvrir ses anciennes publications à tout le monde.
    final r = await auteur.api.setAllPostsVisibility(PostVisibilite.public);
    expect(r['publications'], greaterThanOrEqualTo(2));
    expect(
        (await inconnu.api.feedPage())
            .posts
            .any((x) => x.id == restreint.id),
        isTrue,
        reason: 'après ouverture explicite, tout le monde voit la publication');

    // Nettoyage
    for (final id in [p.id, restreint.id]) {
      await auteur.api.deletePost(id);
    }
  });

  test('suivre un auteur remplit le fil des abonnements', () async {
    final auteur = await login('+2438203$suffix', 'Auteur Suivi');
    final lecteur = await login('+2438204$suffix', 'Lecteur Abonné');

    final p = await auteur.api.createPost(
      type: PostType.texte,
      texte: 'À lire par mes abonnés $suffix',
      visibilite: PostVisibilite.communaute,
    );

    // Avant de suivre : rien dans le fil des abonnements.
    expect((await lecteur.api.followingPage()).posts, isEmpty);

    final suivi = await lecteur.api.followAuthor(auteur.id);
    expect(suivi['suivi'], isTrue);
    final apres = await lecteur.api.followingPage();
    expect(apres.posts.any((x) => x.id == p.id), isTrue,
        reason: 'la publication de l’auteur suivi doit apparaître');

    // Le profil public donne de quoi décider de suivre.
    final profil = await lecteur.api.authorProfile(auteur.id);
    final info = Map<String, dynamic>.from(profil['auteur'] as Map);
    expect(info['name'], 'Auteur Suivi');
    expect(info['suivi'], isTrue);

    await lecteur.api.unfollowAuthor(auteur.id);
    expect((await lecteur.api.followingPage()).posts, isEmpty);

    await auteur.api.deletePost(p.id);
  });

  test('les vues se comptent une fois par lecteur, jamais pour l’auteur',
      () async {
    final auteur = await login('+2438205$suffix', 'Auteur Vues');
    final l1 = await login('+2438206$suffix', 'Lecteur 1');
    final l2 = await login('+2438207$suffix', 'Lecteur 2');

    final p = await auteur.api.createPost(
        type: PostType.texte, texte: 'Compteur $suffix');

    final v1 = await l1.api.viewPost(p.id);
    expect(v1['vues'], 1);
    expect(v1['compte'], isTrue);

    final v1bis = await l1.api.viewPost(p.id);
    expect(v1bis['vues'], 1, reason: 'rafraîchir ne doit pas gonfler le chiffre');
    expect(v1bis['compte'], isFalse);

    final v2 = await l2.api.viewPost(p.id);
    expect(v2['vues'], 2);

    final vAuteur = await auteur.api.viewPost(p.id);
    expect(vAuteur['vues'], 2, reason: 'la vue de l’auteur ne compte pas');

    await auteur.api.deletePost(p.id);
  });

  test('les mots-clés alimentent les tendances et le filtrage', () async {
    final auteur = await login('+2438208$suffix', 'Auteur Tags');
    final lecteur = await login('+2438209$suffix', 'Lecteur Tags');

    final p = await auteur.api.createPost(
      type: PostType.texte,
      texte: 'Grand concert #Kinshasa #Rumba $suffix',
    );
    expect(p.tags, containsAll(<String>['kinshasa', 'rumba']));

    final tendances = await lecteur.api.trendingTags();
    expect(tendances.any((t) => '${t['tag']}' == 'kinshasa'), isTrue,
        reason: 'le mot-clé doit apparaître dans les tendances');

    final parTag = await lecteur.api.postsByTag('kinshasa');
    expect(parTag.any((x) => x.id == p.id), isTrue);

    final inconnu = await lecteur.api.postsByTag('motclequinexistepas');
    expect(inconnu, isEmpty);

    await auteur.api.deletePost(p.id);
  });
}

class _Compte {
  final Api api;
  final String id;
  final String phone;
  final String name;
  const _Compte(this.api, this.id, this.phone, this.name);
}
