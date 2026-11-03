// Tests d'interface de l'onglet Accueil : chargement, erreur + réessai,
// j'aime, état vide, pagination, publication.
//
// L'API est remplacée par un faux serveur (`FakeApi`) : aucun réseau.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mbote/api.dart';
import 'package:mbote/models/post.dart';
import 'package:mbote/screens/feed_screen.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';
import 'package:mbote/widgets/feed/media_view.dart';
import 'package:mbote/widgets/feed/post_card.dart';

/// Faux backend : programmable, et il enregistre les appels reçus.
class FakeApi extends Api {
  List<Post> page1 = [];
  List<Post> page2 = [];
  Object? failWith; // si non nul, feedPage lève cette erreur
  bool failLike = false;
  bool deleteFails = false;

  final List<String> calls = [];
  int feedPageCalls = 0;

  /// État « j'aime » persistant, comme le ferait un vrai serveur.
  final Map<String, ({int likes, bool liked})> likeState = {};

  ({int likes, bool liked}) _likeOf(Post p) => likeState.putIfAbsent(
        p.id,
        () => (likes: p.likes, liked: p.liked),
      );

  static Post post(
    String id, {
    String texte = 'Bonjour',
    String? phone = '+243810000001',
    int likes = 0,
    bool liked = false,
    int comments = 0,
  }) =>
      Post(
        id: id,
        authorId: 'u_$id',
        authorName: 'Auteur $id',
        authorPhone: phone,
        type: PostType.texte,
        createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
        texte: texte,
        likes: likes,
        liked: liked,
        comments: comments,
      );

  @override
  Future<FeedPage> feedPage({int? before, String? cursor}) async {
    calls.add('feedPage($cursor)');
    feedPageCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (failWith != null) throw failWith!;
    if (cursor == null) {
      return FeedPage(
        posts: page1,
        nextBefore: page2.isEmpty ? null : 123,
        nextCursor: page2.isEmpty ? null : 'c1',
      );
    }
    return FeedPage(posts: page2);
  }

  @override
  Future<List<Story>> feedStories() async {
    calls.add('feedStories');
    return const [];
  }

  @override
  Future<void> deletePost(String id) async {
    calls.add('deletePost($id)');
    if (deleteFails) throw ApiException('Suppression refusée', 'forbidden');
    page1 = page1.where((p) => p.id != id).toList();
  }

  @override
  Future<void> deleteStory(String id) async {
    calls.add('deleteStory($id)');
  }

  @override
  Future<Map> likePost(String id) async {
    calls.add('likePost($id)');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (failLike) throw ApiException('Serveur indisponible', 'down');
    final p = [...page1, ...page2].firstWhere((e) => e.id == id);
    final cur = _likeOf(p);
    final liked = !cur.liked;
    final likes = liked ? cur.likes + 1 : cur.likes - 1;
    likeState[id] = (likes: likes, liked: liked); // le serveur retient l'état
    return {'liked': liked, 'likes': likes};
  }

  @override
  Future<List<Map>> postComments(String id) async {
    calls.add('postComments($id)');
    return [
      {'id': 'c1', 'author_name': 'Bob', 'texte': 'Bien vu !'},
    ];
  }

  @override
  Future<Map> addComment(String id, String texte) async {
    calls.add('addComment($id,$texte)');
    return {'id': 'c2', 'author_name': 'Moi', 'texte': texte};
  }

  @override
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
    PostVisibilite visibilite = PostVisibilite.contacts,
    PostOrigine origine = PostOrigine.rdc,
    PostDuree duree = PostDuree.permanent,
  }) async {
    calls.add('createPost(${postTypeToApi(type)},$texte)');
    return post('nouveau', texte: texte ?? '', phone: '+243810000001');
  }
}

/// État connecté minimal : FeedScreen a besoin de mon identifiant pour
/// distinguer « mes » publications des autres.
AppState loggedState([String? id]) {
  final st = AppState();
  st.id = id;
  return st;
}

Widget wrap(FeedScreen screen, AppState state) {
  // On applique la palette claire par défaut pour éviter les couleurs
  // héritées d'un test précédent.
  MC.apply(kPalettes['kin']!);
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(home: screen),
  );
}

void main() {
  testWidgets('affiche le fil renvoyé par le serveur', (tester) async {
    final api = FakeApi()
      ..page1 = [
        FakeApi.post('p1', texte: 'Makemba ya sika'),
        FakeApi.post('p2', texte: 'Nouveau mix rumba', likes: 12, liked: true),
      ];

    await tester.pumpWidget(wrap(FeedScreen(api: api), AppState()));
    await tester.pump(); // déclenche initState → futur
    // Pendant le premier chargement : squelette de cartes, pas de roue qui tourne.
    expect(find.byKey(const Key('feed-skeleton')), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Makemba ya sika'), findsOneWidget);
    expect(find.text('Nouveau mix rumba'), findsOneWidget);
    expect(find.byType(PostCard), findsNWidgets(2));
    expect(api.calls, contains('feedPage(null)'));
    expect(api.calls, contains('feedStories'));
  });

  testWidgets('erreur réseau → message clair + bouton Réessayer',
      (tester) async {
    final api = FakeApi()
      ..failWith = ApiException("Pas d'Internet — vérifie ta connexion 📶");

    await tester.pumpWidget(wrap(FeedScreen(api: api), AppState()));
    await tester.pumpAndSettle();

    expect(
        find.text("Pas d'Internet — vérifie ta connexion 📶"), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);

    // Le réseau revient : le bouton relance et le fil s'affiche.
    api.failWith = null;
    api.page1 = [FakeApi.post('p1', texte: 'De retour')];
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();

    expect(find.text('De retour'), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
  });

  testWidgets('j’aime : compteur optimiste puis état du serveur',
      (tester) async {
    final api = FakeApi()..page1 = [FakeApi.post('p1', likes: 4)];

    await tester.pumpWidget(wrap(FeedScreen(api: api), AppState()));
    await tester.pumpAndSettle();

    expect(find.text('4'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pump(); // mise à jour optimiste
    expect(find.text('5'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    await tester.pumpAndSettle();
    expect(api.calls, contains('likePost(p1)'));
    expect(find.text('5'), findsOneWidget);

    // Second appui : on retire le like.
    await tester.tap(find.byIcon(Icons.favorite_rounded));
    await tester.pumpAndSettle();
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('échec du like → retour à l’état précédent', (tester) async {
    final api = FakeApi()
      ..page1 = [FakeApi.post('p1', likes: 4)]
      ..failLike = true;

    await tester.pumpWidget(wrap(FeedScreen(api: api), AppState()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();

    expect(find.text('4'), findsOneWidget); // compteur rétabli
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
  });

  testWidgets('fil vide → invitation à publier', (tester) async {
    final api = FakeApi();

    await tester.pumpWidget(wrap(FeedScreen(api: api), AppState()));
    await tester.pumpAndSettle();

    expect(find.text('Le fil est encore vide par ici.'), findsOneWidget);
    expect(find.text('Publier quelque chose'), findsOneWidget);
  });

  testWidgets('pagination : la page suivante s’ajoute au défilement',
      (tester) async {
    final api = FakeApi()
      ..page1 = List.generate(8, (i) => FakeApi.post('a$i', texte: 'Post A$i'))
      ..page2 = List.generate(4, (i) => FakeApi.post('b$i', texte: 'Post B$i'));

    await tester.pumpWidget(wrap(FeedScreen(api: api), AppState()));
    await tester.pumpAndSettle();
    expect(find.text('Post A0'), findsOneWidget);

    // On défile jusqu'en bas → déclenche le chargement de la page 2.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(api.feedPageCalls, greaterThanOrEqualTo(2));
    expect(api.calls.any((c) => c.contains('c1')), isTrue);
    expect(api.calls, contains('feedPage(null)'));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(find.text('Post B3'), findsOneWidget);
  });

  testWidgets('publication d’un texte : le post apparaît en tête',
      (tester) async {
    final api = FakeApi()..page1 = [FakeApi.post('p1', texte: 'Ancien')];

    await tester.pumpWidget(wrap(FeedScreen(api: api), AppState()));
    await tester.pumpAndSettle();

    // Ouvre la feuille de publication via le bouton flottant
    // (« Mon statut » porte aussi un « + », d'où le ciblage par libellé).
    await tester.tap(find.bySemanticsLabel('Publier').first);
    await tester.pumpAndSettle();

    expect(find.text('Publier'), findsWidgets);
    await tester.enterText(find.byType(TextField).first, 'Mon premier post');
    await tester.pumpAndSettle();

    // Valide avec le bouton de la feuille (le dernier « Publier »).
    await tester.tap(find.widgetWithText(FilledButton, 'Publier'));
    await tester.pumpAndSettle();

    expect(
        api.calls
            .any((c) => c.startsWith('createPost(texte,Mon premier post)')),
        isTrue);
    expect(find.text('Mon premier post'), findsOneWidget);
  });

  testWidgets('commentaires : ouverture, lecture et envoi', (tester) async {
    final api = FakeApi()..page1 = [FakeApi.post('p1')];

    await tester.pumpWidget(wrap(FeedScreen(api: api), AppState()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await tester.pumpAndSettle();

    expect(api.calls, contains('postComments(p1)'));
    expect(find.text('Bien vu !'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Super !');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(api.calls, contains('addComment(p1,Super !)'));
    expect(find.text('Super !'), findsWidgets);
  });

  testWidgets('ma publication : pas de bouton Appeler, mais « Supprimer »',
      (tester) async {
    final api = FakeApi()
      ..page1 = [
        FakeApi.post('p1', texte: 'Mon post'), // auteur = u_p1
        FakeApi.post('p2', texte: 'Post de Bob'), // auteur = u_p2
      ];
    // id de l'auteur des posts factices = 'u_p1'
    final state = loggedState('u_p1');

    await tester.pumpWidget(wrap(FeedScreen(api: api), state));
    await tester.pumpAndSettle();

    // Une seule pastille « Appeler » : celle du post de Bob.
    expect(find.text('Appeler'), findsOneWidget);
    expect(find.byIcon(Icons.call_rounded), findsOneWidget);

    // Le menu du post de Bob ne propose pas de suppression…
    await tester.tap(find.byIcon(Icons.more_vert_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('Supprimer'), findsNothing);
    await tester.tapAt(const Offset(10, 10)); // referme le menu
    await tester.pumpAndSettle();

    // …celui de mon post, oui.
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Supprimer'), findsOneWidget);
  });

  testWidgets('suppression : confirmation puis disparition immédiate',
      (tester) async {
    final api = FakeApi()..page1 = [FakeApi.post('p1', texte: 'À jeter')];
    await tester.pumpWidget(wrap(FeedScreen(api: api), loggedState('u_p1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();

    // Boîte de confirmation
    expect(find.text('Supprimer la publication ?'), findsOneWidget);

    // Annuler ne supprime rien
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.text('À jeter'), findsOneWidget);
    expect(api.calls.where((c) => c.startsWith('deletePost')), isEmpty);

    // Confirmer supprime et met l'interface à jour tout de suite
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer').last);
    await tester.pumpAndSettle();

    expect(api.calls, contains('deletePost(p1)'));
    expect(find.text('À jeter'), findsNothing);
    expect(find.text('Le fil est encore vide par ici.'), findsOneWidget);
  });

  testWidgets('suppression refusée par le serveur → le post revient',
      (tester) async {
    final api = FakeApi()
      ..page1 = [FakeApi.post('p1', texte: 'Résistant')]
      ..deleteFails = true;
    await tester.pumpWidget(wrap(FeedScreen(api: api), loggedState('u_p1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer').last);
    await tester.pumpAndSettle();

    expect(find.text('Résistant'), findsOneWidget); // ↩️ remis en place
  });

  testWidgets('publication vidéo : lecteur présent, pas de plantage',
      (tester) async {
    final api = FakeApi()
      ..page1 = [
        Post(
          id: 'v1',
          authorId: 'u_v1',
          authorName: 'Bob',
          type: PostType.clip,
          createdAt: DateTime.now(),
          mediaUrl: 'http://127.0.0.1:9/video.mp4',
          clipDureeSeconds: 42,
        ),
      ];
    await tester.pumpWidget(wrap(FeedScreen(api: api), AppState()));
    await tester.pumpAndSettle();

    expect(find.byType(MboteVideo), findsOneWidget);
    expect(find.text('Appuyer pour lire la vidéo'), findsOneWidget);
    expect(find.text('0:42'), findsOneWidget); // durée affichée
    expect(tester.takeException(), isNull);
  });
}
