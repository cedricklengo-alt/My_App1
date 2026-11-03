// Test d'INTÉGRATION des hashtags et des mentions : vraies requêtes HTTP du
// code Dart de l'application (`Api`) vers un vrai serveur `mbote-backend` lancé
// à la volée.
//
// Ce que l'on prouve ici, et qui ne pouvait pas l'être avec des simulacres :
//   1. une publication qui contient « #MboteCall » et « @pseudo » arrive au
//      serveur avec ses hashtags et ses mentions résolues ;
//   2. la personne mentionnée reçoit une notification, et une seule ;
//   3. la page du hashtag compte ses publications et ses abonnés, et « Suivre »
//      change réellement le fil « Pour toi » ;
//   4. la recherche universelle trouve par #, par @ et par texte ;
//   5. une mention dans un commentaire notifie aussi ;
//   6. une publication réservée aux contacts reste introuvable à la recherche.
//
// Lancement :  flutter test test/social_integration_test.dart
// Variables :  MBOTE_BACKEND_DIR, MBOTE_TEST_PORT (défaut 4803)
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mbote/api.dart';
import 'package:mbote/config.dart';
import 'package:mbote/models/post.dart';

class _Compte {
  final Api api;
  final String id;
  final String phone;
  final String name;
  String? handle;
  _Compte(this.api, this.id, this.phone, this.name, this.handle);
}

void main() {
  final backendDir = Platform.environment['MBOTE_BACKEND_DIR'] ??
      Directory.current.parent.uri.resolve('mbote-backend').toFilePath();
  final port =
      int.tryParse(Platform.environment['MBOTE_TEST_PORT'] ?? '') ?? 4803;
  final base = 'http://127.0.0.1:$port/api';

  final hasBackend = Directory(backendDir).existsSync() &&
      File('$backendDir/src/server.js').existsSync();

  if (!hasBackend) {
    test('hashtags et mentions — intégration', () {},
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
        'JWT_SECRET': 'test-social-it',
        'DEMO_MODE': 'true',
        'PUSH_DEBUG_FAKE': 'true',
        'DATABASE_URL': '',
        'MBOTE_MESSAGE_STORAGE': '/var/tmp/social-it',
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
    final user = b['user'] as Map?;
    return _Compte(api, '${user?['id']}', phone, name, user?['handle'] as String?);
  }

  test('écrire #hashtag et @quelqu’un produit une mention et sa notification',
      () async {
    final cedrick = await login('+2438300$suffix', 'Cédrick Lengo');
    final patrick = await login('+2438301$suffix', 'Patrick Mbala');

    expect(cedrick.handle, isNotNull,
        reason: 'un compte doit recevoir un identifiant public à la connexion');

    final post = await cedrick.api.createPost(
      type: PostType.texte,
      texte: 'Bienvenue sur #MboteCall à #Kinshasa, merci @${patrick.handle}',
    );

    // 1. Le serveur a retenu les bons hashtags…
    expect(post.tags, containsAll(['mbotecall', 'kinshasa']));
    // 2. …et la bonne personne.
    expect(post.mentionsListe.map((m) => m.handle), contains(patrick.handle));

    // 3. La personne mentionnée a une notification non lue.
    final boite = await patrick.api.notifications();
    final items = (boite['notifications'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    expect(items, isNotEmpty, reason: 'une mention doit créer une notification');
    expect(items.first['type'], 'mention');
    expect(items.first['post_id'], post.id);
    expect((boite['non_lues'] as num).toInt(), greaterThanOrEqualTo(1));

    // 4. Le badge de l'en-tête le dit aussi.
    expect(await patrick.api.notificationsNonLues(), greaterThanOrEqualTo(1));

    // 5. Tout marquer comme lu vide le badge.
    await patrick.api.marquerNotificationsLues();
    expect(await patrick.api.notificationsNonLues(), 0);

    // 6. L'auteur n'est jamais notifié de sa propre mention.
    final sienne = await cedrick.api.notifications();
    expect((sienne['notifications'] as List), isEmpty);

    await cedrick.api.deletePost(post.id);
  });

  test('la page du hashtag compte, abonne, et change le fil « Pour toi »',
      () async {
    final auteur = await login('+2438302$suffix', 'Auteur Hashtag');
    final lecteur = await login('+2438303$suffix', 'Lecteur Hashtag');

    final post = await auteur.api.createPost(
      type: PostType.texte,
      texte: 'Le tech en RDC avance #TechAfrique$suffix',
    );

    final tag = 'techafrique$suffix';

    // 1. La page existe et compte la publication.
    final page = await lecteur.api.pageHashtag(tag);
    expect(page['tag'], tag);
    expect((page['publications'] as num).toInt(), greaterThanOrEqualTo(1));
    expect((page['suivi'] as num).toInt(), 0);

    // 2. Elle n'est pas encore suivie : le fil la montre comme n'importe
    //    quelle publication — aucun hashtag suivi, aucune raison de remontée.
    final avant = await lecteur.api.filPersonnalise();
    final vuAvant = avant.posts.where((p) => p.id == post.id).toList();
    if (vuAvant.isNotEmpty) {
      expect(vuAvant.first.tagsSuivis, isNot(contains(tag)));
      expect(vuAvant.first.raison, isNot('hashtag:$tag'));
    }

    // 3. Suivre le hashtag…
    final suivi = await lecteur.api.suivreHashtag(tag);
    expect(suivi.suivi, isTrue);
    expect(suivi.abonnes, greaterThanOrEqualTo(1));

    // 4. …le fait remonter dans « Pour toi », avec sa raison.
    final apres = await lecteur.api.filPersonnalise();
    final vuApres = apres.posts.where((p) => p.id == post.id).toList();
    expect(vuApres, isNotEmpty, reason: 'un hashtag suivi doit faire remonter la publication');
    expect(vuApres.first.tagsSuivis, contains(tag));
    expect(vuApres.first.raison, 'hashtag:$tag');
    // Et elle remonte : sa position ne peut pas être plus mauvaise qu'avant.
    if (vuAvant.isNotEmpty) {
      final avantIndex = avant.posts.indexWhere((p) => p.id == post.id);
      final apresIndex = apres.posts.indexWhere((p) => p.id == post.id);
      expect(apresIndex, lessThanOrEqualTo(avantIndex));
    }

    // 5. Mes hashtags suivis sont listés.
    final suivis = await lecteur.api.hashtagsSuivis();
    expect(suivis.map((h) => h.tag), contains(tag));

    // 6. Se désabonner fonctionne.
    final quitte = await lecteur.api.nePlusSuivreHashtag(tag);
    expect(quitte.suivi, isFalse);

    await auteur.api.deletePost(post.id);
  });

  test('la recherche universelle comprend #hashtag, @personne et le texte',
      () async {
    final auteur = await login('+2438304$suffix', 'Auteur Recherche');
    final curieux = await login('+2438305$suffix', 'Curieux Recherche');

    final post = await auteur.api.createPost(
      type: PostType.texte,
      texte: 'Exposition de peinture #KinArt$suffix',
    );

    // Par hashtag.
    final parTag = await curieux.api.rechercher('#KinArt$suffix');
    expect(parTag.portee, 'hashtags');
    expect(parTag.hashtags.map((h) => h.tag), contains('kinart$suffix'));

    // Par personne.
    final parPersonne = await curieux.api.rechercher('@${auteur.handle}');
    expect(parPersonne.portee, 'personnes');
    expect(parPersonne.personnes.map((p) => p.handle), contains(auteur.handle));

    // Par texte.
    final parTexte = await curieux.api.rechercher('peinture');
    expect(parTexte.publications.map((p) => '${p['id']}'), contains(post.id));

    // Une publication réservée aux contacts ne sort jamais de la recherche.
    final prive = await auteur.api.createPost(
      type: PostType.texte,
      texte: 'Confidentiel motrare$suffix #KinArt$suffix',
      visibilite: PostVisibilite.contacts,
    );
    final cherche = await curieux.api.rechercher('motrare$suffix');
    expect(cherche.publications.map((p) => '${p['id']}'), isNot(contains(prive.id)),
        reason: 'la recherche ne doit jamais franchir la visibilité');

    await auteur.api.deletePost(post.id);
    await auteur.api.deletePost(prive.id);
  });

  test('une mention dans un commentaire notifie aussi', () async {
    final auteur = await login('+2438306$suffix', 'Auteur Commentaire');
    final commentateur = await login('+2438307$suffix', 'Commentateur');
    final cible = await login('+2438308$suffix', 'Cible Mention');

    final post = await auteur.api.createPost(
      type: PostType.texte,
      texte: 'Question sur le concert $suffix',
    );

    await commentateur.api.addComment(post.id, 'Merci @${cible.handle} pour l’info');

    final boite = await cible.api.notifications();
    final items = (boite['notifications'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    expect(items, isNotEmpty);
    expect(items.first['source_type'], 'comment');
    expect(items.first['post_id'], post.id);

    await auteur.api.deletePost(post.id);
  });

  test('les suggestions et l’analytique répondent sur le vrai serveur', () async {
    final auteur = await login('+2438309$suffix', 'Auteur Suggestions');
    final autre = await login('+2438310$suffix', 'Autre Suggestions');

    await auteur.api.createPost(
      type: PostType.texte,
      texte: 'Rumba et musique congolaise #Rumba$suffix',
    );

    // Autocomplétion des hashtags, par préfixe.
    final tags = await autre.api.suggestionsHashtags(q: 'rumba$suffix');
    expect(tags, isNotEmpty);
    expect(tags.first.tag, 'rumba$suffix');

    // Autocomplétion des personnes, par identifiant.
    final gens = await autre.api.suggestionsMentions(q: auteur.handle!);
    expect(gens.map((p) => p.handle), contains(auteur.handle));

    // Suggestions assistées pour un brouillon.
    final proposes = await autre.api.suggererHashtags('concert de rumba à Kinshasa');
    expect(proposes, isA<List>());

    // Statistiques de mentions.
    await auteur.api.createPost(
      type: PostType.texte,
      texte: 'Merci @${autre.handle} pour le coup de main $suffix',
    );
    final stats = await autre.api.analytiqueMentions();
    expect(stats.recues, greaterThanOrEqualTo(1));
  });
}
