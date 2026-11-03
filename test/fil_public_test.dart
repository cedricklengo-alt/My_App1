// Tests du FIL PUBLIC côté interface : les trois lectures (Pour toi,
// Abonnements, Tendances), le rappel d'audience, le bouton « Suivre », les
// mots-clés et la visibilité par défaut du formulaire de publication.
//
// Aucun réseau : l'API est remplacée par un faux serveur.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mbote/api.dart';
import 'package:mbote/models/post.dart';
import 'package:mbote/screens/feed_screen.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';
import 'package:mbote/widgets/feed/post_card.dart';

class FakeApi extends Api {
  List<Post> fil = [];
  List<Post> abonnements = [];
  List<Post> tendancesDecouverte = [];

  final List<String> calls = [];

  static Post post(
    String id, {
    String texte = 'Bonjour',
    String authorId = 'u_autre',
    String authorName = 'Auteur',
    PostVisibilite visibilite = PostVisibilite.public,
    bool aMoi = false,
    bool suivi = false,
    List<String> tags = const [],
    int vues = 0,
    String? partageUrl,
    int partages = 0,
  }) =>
      Post(
        id: id,
        authorId: authorId,
        authorName: authorName,
        type: PostType.texte,
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        texte: texte,
        visibilite: visibilite,
        aMoi: aMoi,
        suivi: suivi,
        tags: tags,
        vues: vues,
        partageUrl: partageUrl,
        partages: partages,
      );

  @override
  Future<FeedPage> feedPage({int? before, String? cursor}) async {
    calls.add('feedPage');
    return FeedPage(posts: fil);
  }

  @override
  Future<FeedPage> followingPage({int? before, String? cursor}) async {
    calls.add('followingPage');
    return FeedPage(posts: abonnements);
  }

  @override
  Future<FeedPage> discoverPage({
    String sort = 'tendances',
    String? tag,
    String? ville,
    int? offset,
  }) async {
    calls.add('discoverPage($sort,${tag ?? '-'})');
    return FeedPage(posts: tendancesDecouverte);
  }

  @override
  Future<List<Story>> feedStories() async => const [];

  @override
  Future<Map> viewPost(String id) async {
    calls.add('viewPost($id)');
    // Le serveur renvoie le compteur à jour : le faux serveur fait pareil.
    final p = fil.firstWhere((e) => e.id == id, orElse: () => fil.first);
    return {'vues': p.vues, 'compte': true};
  }

  @override
  Future<Map> followAuthor(String auteurId) async {
    calls.add('follow($auteurId)');
    return {'suivi': true, 'abonnes': 1};
  }

  @override
  Future<Map> unfollowAuthor(String auteurId) async {
    calls.add('unfollow($auteurId)');
    return {'suivi': false, 'abonnes': 0};
  }

  int partages = 0;

  @override
  Future<Map> markShared(String id) async {
    calls.add('markShared($id)');
    partages += 1;
    return {'partages': partages, 'share_url': 'https://exemple.cd/p/$id'};
  }

  @override
  Future<Map> setAllPostsVisibility(PostVisibilite v) async {
    calls.add('setAllPostsVisibility(${postVisibiliteToApi(v)})');
    return {'visibilite': postVisibiliteToApi(v), 'publications': 3};
  }
}

Widget wrap(FeedScreen screen) {
  MC.apply(kPalettes['kin']!);
  final st = AppState();
  st.id = 'u_moi';
  return ChangeNotifierProvider<AppState>.value(
    value: st,
    child: MaterialApp(home: screen),
  );
}

void main() {
  /// Le presse-papiers est un canal de plateforme : en test, il faut fournir
  /// une réponse, sinon l'action « copier » reste bloquée sans effet.
  void simulerPressePapiers(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
  }

  testWidgets('les trois lectures du fil sont proposées', (tester) async {
    final api = FakeApi()..fil = [FakeApi.post('p1', texte: 'Salut Kin')];
    await tester.pumpWidget(wrap(FeedScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Pour toi'), findsOneWidget);
    expect(find.text('Abonnements'), findsOneWidget);
    expect(find.text('Tendances'), findsOneWidget);
    expect(api.calls, contains('feedPage'));
  });

  testWidgets('« Abonnements » interroge le fil des auteurs suivis',
      (tester) async {
    final api = FakeApi()
      ..fil = [FakeApi.post('p1', texte: 'Du fil principal')]
      ..abonnements = [FakeApi.post('p2', texte: 'De quelqu’un que je suis')];

    await tester.pumpWidget(wrap(FeedScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Du fil principal'), findsOneWidget);

    await tester.tap(find.text('Abonnements'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('followingPage'));
    expect(find.text('De quelqu’un que je suis'), findsOneWidget);
    expect(find.text('Du fil principal'), findsNothing);
  });

  testWidgets('« Tendances » interroge la découverte publique', (tester) async {
    final api = FakeApi()
      ..fil = [FakeApi.post('p1', texte: 'Du fil')]
      ..tendancesDecouverte = [FakeApi.post('p2', texte: 'Ce qui marche aujourd’hui')];

    await tester.pumpWidget(wrap(FeedScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tendances'));
    await tester.pumpAndSettle();

    expect(api.calls.any((c) => c.startsWith('discoverPage')), isTrue,
        reason: 'la découverte doit être appelée');
    expect(find.text('Ce qui marche aujourd’hui'), findsOneWidget);
  });

  testWidgets('une publication limitée à mes contacts est signalée et peut '
      'être ouverte à tous', (tester) async {
    final api = FakeApi()
      ..fil = [
        FakeApi.post('p1',
            texte: 'Vieille publication',
            authorId: 'u_moi',
            aMoi: true,
            visibilite: PostVisibilite.contacts),
      ];

    await tester.pumpWidget(wrap(FeedScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.textContaining('limitées à tes contacts'), findsOneWidget);

    await tester.tap(find.text('Rendre mes publications visibles par tous'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('setAllPostsVisibility(public)'));
  });

  testWidgets('aucun rappel quand tout est déjà public', (tester) async {
    final api = FakeApi()
      ..fil = [
        FakeApi.post('p1', texte: 'Déjà public', authorId: 'u_moi', aMoi: true),
      ];

    await tester.pumpWidget(wrap(FeedScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.textContaining('limitées à tes contacts'), findsNothing);
  });

  testWidgets('bouton « Suivre » sur la publication d’un autre auteur',
      (tester) async {
    final api = FakeApi()
      ..fil = [FakeApi.post('p1', authorId: 'u_bob', authorName: 'Bob')];

    await tester.pumpWidget(wrap(FeedScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Suivre'), findsOneWidget);
    await tester.tap(find.text('Suivre'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('follow(u_bob)'));
    // Une fois suivi, la mention devient « Suivi ».
    expect(find.text('Suivi'), findsOneWidget);
  });

  testWidgets('pas de bouton « Suivre » sur ma propre publication',
      (tester) async {
    final api = FakeApi()
      ..fil = [FakeApi.post('p1', authorId: 'u_moi', aMoi: true)];

    await tester.pumpWidget(wrap(FeedScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Suivre'), findsNothing);
  });

  testWidgets('les mots-clés sont affichés et ouvrent la découverte filtrée',
      (tester) async {
    final api = FakeApi()
      ..fil = [FakeApi.post('p1', texte: 'Concert', tags: ['kinshasa'])]
      ..tendancesDecouverte = [FakeApi.post('p2', texte: 'Autre concert')];

    await tester.pumpWidget(wrap(FeedScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('#kinshasa'), findsOneWidget);
    await tester.tap(find.text('#kinshasa'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('discoverPage(tendances,kinshasa)'));
  });

  testWidgets('le compteur de vues est affiché quand il existe',
      (tester) async {
    final api = FakeApi()..fil = [FakeApi.post('p1', vues: 42)];
    await tester.pumpWidget(wrap(FeedScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('42'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });

  testWidgets('le formulaire de publication propose « Tout le monde » '
      'par défaut', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(wrap(FeedScreen(api: api)));
    await tester.pumpAndSettle();

    // Ouvre la feuille de création : le bouton flottant porte le libellé
    // d'accessibilité « Publier » (l'icône + est utilisée ailleurs).
    await tester.tap(find.bySemanticsLabel('Publier'));
    await tester.pumpAndSettle();

    // Le texte d'explication correspond au choix public.
    expect(
        find.textContaining('Tout le monde verra cette publication'),
        findsOneWidget);
    // Et le sélecteur affiche bien « Tout le monde ».
    expect(find.text('Tout le monde'), findsOneWidget);
  });

  testWidgets('le partage propose « copier le lien » et « envoyer ailleurs »',
      (tester) async {
    final api = FakeApi()
      ..fil = [
        FakeApi.post('p1',
            texte: 'Concert ce soir',
            partageUrl: 'https://exemple.cd/p/p1'),
      ];

    await tester.pumpWidget(wrap(FeedScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.share_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Partager cette publication'), findsOneWidget);
    expect(find.text('Copier le lien'), findsOneWidget);
    expect(find.text('Partager vers une autre application'), findsOneWidget);
    // Le lien est montré en clair.
    expect(find.text('https://exemple.cd/p/p1'), findsOneWidget);
  });

  testWidgets('copier le lien compte le partage côté serveur', (tester) async {
    simulerPressePapiers(tester);
    final api = FakeApi()
      ..fil = [
        FakeApi.post('p1', texte: 'À partager', partageUrl: 'https://exemple.cd/p/p1'),
      ];

    await tester.pumpWidget(wrap(FeedScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.share_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copier le lien'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('markShared(p1)'));
    expect(find.textContaining('Lien copié'), findsOneWidget);
  });

  testWidgets('le lien est reconstruit si le serveur n’en fournit pas',
      (tester) async {
    final api = FakeApi()..fil = [FakeApi.post('p2')];
    await tester.pumpWidget(wrap(FeedScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.share_rounded));
    await tester.pumpAndSettle();

    // Un lien reste proposé : l'utilisateur n'est jamais laissé sans action.
    expect(find.textContaining('/p/p2'), findsWidgets);
  });

  testWidgets('le compteur de partages est affiché', (tester) async {
    final api = FakeApi()..fil = [FakeApi.post('p1', partages: 7)];
    await tester.pumpWidget(wrap(FeedScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('la pastille d’audience n’apparaît que sur mes publications',
      
      (tester) async {
    final api = FakeApi()
      ..fil = [
        FakeApi.post('p1', authorId: 'u_moi', aMoi: true),
        FakeApi.post('p2', authorId: 'u_bob'),
      ];
    await tester.pumpWidget(wrap(FeedScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Tout le monde'), findsOneWidget);
    expect(find.byType(PostCard), findsNWidgets(2));
  });
}
