// HASHTAGS ET MENTIONS — tests de l'application.
//
// Ce que ces tests prouvent, sans réseau :
//   1. la découpe d'un texte est la même que celle du serveur (accents, courriel,
//      lien, ponctuation) ;
//   2. un hashtag et une mention sont réellement cliquables dans une carte ;
//   3. l'éditeur propose des hashtags et des personnes pendant la frappe, et
//      remplace le mot en cours par la proposition choisie ;
//   4. les compteurs restent justes (10 de chaque, la règle du serveur) ;
//   5. la page d'un hashtag affiche ses chiffres et s'abonne ;
//   6. la recherche universelle regroupe par nature (#, @, texte) ;
//   7. la boîte de réception montre les mentions et se marque comme lue.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mbote/api.dart';
import 'package:mbote/models/post.dart';
import 'package:mbote/models/social.dart';
import 'package:mbote/screens/hashtag_screen.dart';
import 'package:mbote/screens/notifications_screen.dart';
import 'package:mbote/screens/recherche_screen.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';
import 'package:mbote/widgets/feed/post_card.dart';
import 'package:mbote/widgets/social/champ_social.dart';
import 'package:mbote/widgets/social/texte_social.dart';

class FakeSocial extends Api {
  final List<String> appels = [];

  List<Post> posts = [];
  List<Hashtag> suggestions = [];
  List<Personne> personnes = [];
  Hashtag? page;
  bool suivi = false;
  List<NotificationSociale> notifs = [];
  ResultatsRecherche? resultats;

  @override
  Future<FeedPage> feedPage({int? before, String? cursor}) async =>
      FeedPage(posts: posts);

  @override
  Future<FeedPage> filPersonnalise({int offset = 0, int limit = 20}) async =>
      FeedPage(posts: offset == 0 ? posts : const []);

  @override
  Future<List<Hashtag>> suggestionsHashtags({String q = '', int limit = 8}) async {
    appels.add('suggestionsHashtags($q)');
    return suggestions.where((h) => q.isEmpty || h.tag.startsWith(q)).toList();
  }

  @override
  Future<List<Personne>> suggestionsMentions({String q = '', int limit = 8}) async {
    appels.add('suggestionsMentions($q)');
    return personnes
        .where((p) => q.isEmpty || (p.handle ?? p.name).toLowerCase().startsWith(q))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> pageHashtag(String tag, {String tri = 'recentes'}) async {
    appels.add('pageHashtag($tag,$tri)');
    return {
      'tag': tag,
      'publications': page?.publications ?? 0,
      'abonnes': page?.abonnes ?? 0,
      'suivi': suivi ? 1 : 0,
      'tendance': 1,
      'croissance': 0.5,
      'posts': tri == 'videos'
          ? posts.where((p) => p.type == PostType.clip).map(_json).toList()
          : posts.map(_json).toList(),
    };
  }

  @override
  Future<Hashtag> suivreHashtag(String tag) async {
    appels.add('suivreHashtag($tag)');
    suivi = true;
    return Hashtag(
        tag: tag,
        publications: page?.publications ?? 0,
        abonnes: (page?.abonnes ?? 0) + 1,
        suivi: true);
  }

  @override
  Future<Hashtag> nePlusSuivreHashtag(String tag) async {
    appels.add('nePlusSuivreHashtag($tag)');
    suivi = false;
    return Hashtag(
        tag: tag, publications: page?.publications ?? 0, abonnes: page?.abonnes ?? 0);
  }

  @override
  Future<ResultatsRecherche> rechercher(String q) async {
    appels.add('rechercher($q)');
    return resultats ??
        const ResultatsRecherche(q: '', portee: 'tout');
  }

  @override
  Future<Map<String, dynamic>> notifications({int? before, int limite = 30}) async {
    appels.add('notifications');
    return {
      'notifications': notifs.length,
      'non_lues': notifs.where((n) => !n.lu).length,
    }
      ..remove('notifications')
      ..['notifications'] = [
        for (final n in notifs)
          {
            'id': n.id,
            'type': n.type,
            'post_id': n.postId,
            'source_type': n.sourceType,
            'texte': n.texte,
            'lu': n.lu ? 1 : 0,
            'created_at': n.createdAt.millisecondsSinceEpoch,
            'expediteur': n.expediteur == null
                ? null
                : {'id': n.expediteur!.id, 'name': n.expediteur!.name},
          }
      ];
  }

  @override
  Future<int> notificationsNonLues() async =>
      notifs.where((n) => !n.lu).length;

  @override
  Future<void> marquerNotificationsLues() async {
    appels.add('marquerNotificationsLues');
    notifs = [
      for (final n in notifs)
        NotificationSociale(
          id: n.id,
          type: n.type,
          createdAt: n.createdAt,
          postId: n.postId,
          sourceType: n.sourceType,
          texte: n.texte,
          lu: true,
          expediteur: n.expediteur,
        )
    ];
  }

  /// Forme JSON d'une publication, comme le renvoie le serveur.
  Map<String, dynamic> _json(Post p) => {
        'id': p.id,
        'author_id': p.authorId,
        'author_name': p.authorName,
        'type': p.type == PostType.clip ? 'clip' : 'texte',
        'texte': p.texte,
        'likes': p.likes,
        'comments': p.comments,
        'created_at': p.createdAt.millisecondsSinceEpoch,
        'tags': p.tags,
        'mentions': [
          for (final m in p.mentionsListe)
            {'id': m.id, 'handle': m.handle, 'name': m.name}
        ],
      };
}

Widget wrap(Widget enfant) {
  MC.apply(kPalettes['fleuve']!);
  final st = AppState();
  st.id = 'u1';
  st.api = _apiCourante!;
  return ChangeNotifierProvider<AppState>.value(
    value: st,
    child: MaterialApp(home: enfant),
  );
}

FakeSocial? _apiCourante;

void main() {
  setUp(() {
    _apiCourante = FakeSocial();
  });

  // ── 1. Analyse du texte ──────────────────────────────────────────────────
  group('Découpe d’un texte', () {
    test('hashtags et mentions reconnus', () {
      final s = AnalyseurSocial.decouper('Salut @Cédrick, bienvenue sur #MboteCall et #RDC');
      final tags = s.where((x) => x.estHashtag).map((x) => x.cle).toList();
      final gens = s.where((x) => x.estMention).map((x) => x.cle).toList();
      expect(tags, ['mbotecall', 'rdc']);
      expect(gens, ['cedrick']);
    });

    test('les accents ne changent pas la clé', () {
      final s = AnalyseurSocial.decouper('#Kinshasa #kinshasa');
      expect(s.where((x) => x.estHashtag).map((x) => x.cle), ['kinshasa', 'kinshasa']);
    });

    test('une adresse électronique n’est pas une mention', () {
      final s = AnalyseurSocial.decouper('écris à contact@mbote.cd');
      expect(s.any((x) => x.estMention), isFalse);
    });

    test('un lien reste un lien', () {
      final s = AnalyseurSocial.decouper('voir https://exemple.cd/p/1 #MboteCall');
      expect(s.any((x) => x.type == 'lien'), isTrue);
      expect(s.last.estHashtag, isTrue);
    });

    test('la ponctuation de fin est retirée de la clé', () {
      final s = AnalyseurSocial.decouper('Bravo #MboteCall, merci @cedrick.');
      expect(s.where((x) => x.estHashtag).first.cle, 'mbotecall');
      expect(s.where((x) => x.estMention).first.cle, 'cedrick');
    });

    test('un # collé à un mot n’est pas un hashtag', () {
      final s = AnalyseurSocial.decouper('prix 100# pas un tag');
      expect(s.any((x) => x.estHashtag), isFalse);
    });
  });

  // ── 2. Rendu cliquable ───────────────────────────────────────────────────
  testWidgets('dans une carte, le hashtag ouvre sa page et la mention son profil',
      (tester) async {
    String? tagTouche;
    String? mentionTouchee;

    await tester.pumpWidget(wrap(Scaffold(
      body: PostCard(
        post: Post(
          id: 'p1',
          authorId: 'u2',
          authorName: 'Auteur',
          type: PostType.texte,
          createdAt: DateTime.now(),
          texte: 'Concert à #Kinshasa merci @cedrick',
          mentionsListe: const [
            Mention(id: 'u3', handle: 'cedrick', name: 'Cédrick Lengo')
          ],
        ),
        onHashtag: (t) => tagTouche = t,
        onMention: (m) => mentionTouchee = m,
      ),
    )));
    await tester.pumpAndSettle();

    // Un appui doit viser le MOT, pas la ligne : `tapOnText` place le doigt
    // exactement sur « #Kinshasa », comme le ferait un vrai lecteur.
    await tester.tapOnText(find.textRange.ofSubstring('#Kinshasa'));
    await tester.pumpAndSettle();
    expect(tagTouche, 'kinshasa');

    await tester.tapOnText(find.textRange.ofSubstring('@Cédrick Lengo'));
    await tester.pumpAndSettle();
    expect(mentionTouchee, 'cedrick');
  });

  // ── 3. Éditeur : suggestions et compteurs ────────────────────────────────
  testWidgets('taper # propose les hashtags existants et les insère',
      (tester) async {
    final api = _apiCourante!;
    api.suggestions = const [
      Hashtag(tag: 'mbotecall', publications: 12),
      Hashtag(tag: 'mbote', publications: 3),
    ];
    final champ = TextEditingController();

    await tester.pumpWidget(wrap(Scaffold(
      body: ChampSocial(controller: champ),
    )));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Bienvenue sur #mbo');
    await tester.pumpAndSettle();

    expect(api.appels, contains('suggestionsHashtags(mbo)'));
    expect(find.text('#mbotecall'), findsOneWidget);
    expect(find.text('12 publications'), findsOneWidget);

    await tester.tap(find.text('#mbotecall'));
    await tester.pumpAndSettle();
    expect(champ.text, 'Bienvenue sur #mbotecall ');
    // Compteur : un hashtag sur dix.
    expect(find.text('1/10'), findsOneWidget);
  });

  testWidgets('taper @ propose des personnes, contacts d’abord', (tester) async {
    final api = _apiCourante!;
    api.personnes = const [
      Personne(id: 'u3', name: 'Cédrick Lengo', handle: 'cedricklengo', contact: true),
      Personne(id: 'u4', name: 'Patrick Mbala', handle: 'patrick'),
    ];
    final champ = TextEditingController();

    await tester.pumpWidget(wrap(Scaffold(body: ChampSocial(controller: champ))));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Merci @ced');
    await tester.pumpAndSettle();

    expect(api.appels, contains('suggestionsMentions(ced)'));
    expect(find.text('@cedricklengo'), findsOneWidget);
    expect(find.textContaining('Contact'), findsOneWidget);

    await tester.tap(find.text('@cedricklengo'));
    await tester.pumpAndSettle();
    expect(champ.text, 'Merci @cedricklengo ');
    expect(find.text('1/10'), findsOneWidget);
  });

  testWidgets('les doublons ne comptent qu’une fois', (tester) async {
    final champ = TextEditingController(text: '#MboteCall et #mbotecall et #RDC');
    await tester.pumpWidget(wrap(Scaffold(body: ChampSocial(controller: champ))));
    await tester.pumpAndSettle();

    // Deux hashtags distincts, pas trois.
    expect(find.text('2/10'), findsOneWidget);
  });

  // ── 4. Page d'un hashtag ─────────────────────────────────────────────────
  testWidgets('la page du hashtag affiche ses chiffres et permet de le suivre',
      (tester) async {
    final api = _apiCourante!;
    api.page = const Hashtag(tag: 'mbotecall', publications: 7, abonnes: 4);
    api.posts = [
      Post(
        id: 'p1',
        authorId: 'u2',
        authorName: 'Auteur',
        type: PostType.texte,
        createdAt: DateTime.now(),
        texte: 'Bienvenue sur #MboteCall',
      )
    ];

    await tester.pumpWidget(wrap(const HashtagScreen(tag: 'mbotecall')));
    await tester.pumpAndSettle();

    expect(find.text('#mbotecall'), findsWidgets);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Suivre'), findsOneWidget);

    await tester.tap(find.text('Suivre'));
    await tester.pumpAndSettle();

    expect(api.appels, contains('suivreHashtag(mbotecall)'));
    expect(find.text('Suivi'), findsOneWidget);
  });

  testWidgets('les onglets interrogent le serveur avec le bon tri', (tester) async {
    final api = _apiCourante!;
    api.page = const Hashtag(tag: 'mbotecall', publications: 2);

    await tester.pumpWidget(wrap(const HashtagScreen(tag: 'mbotecall')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vidéos'));
    await tester.pumpAndSettle();
    expect(api.appels, contains('pageHashtag(mbotecall,videos)'));

    await tester.tap(find.text('Populaires'));
    await tester.pumpAndSettle();
    expect(api.appels, contains('pageHashtag(mbotecall,populaires)'));
  });

  // ── 5. Recherche universelle ─────────────────────────────────────────────
  testWidgets('la recherche regroupe hashtags, personnes et publications',
      (tester) async {
    final api = _apiCourante!;
    api.resultats = const ResultatsRecherche(
      q: 'mbote',
      portee: 'tout',
      hashtags: [Hashtag(tag: 'mbotecall', publications: 5)],
      personnes: [Personne(id: 'u3', name: 'Cédrick Lengo', handle: 'cedricklengo')],
      publications: [
        {'id': 'p1', 'texte': 'Bienvenue sur #MboteCall', 'auteur': {'name': 'Auteur'}}
      ],
      total: 3,
    );

    await tester.pumpWidget(wrap(const RechercheScreen(requeteInitiale: 'mbote')));
    await tester.pumpAndSettle();

    expect(api.appels, contains('rechercher(mbote)'));
    expect(find.text('HASHTAGS'), findsOneWidget);
    expect(find.text('PERSONNES'), findsOneWidget);
    expect(find.text('PUBLICATIONS'), findsOneWidget);
    expect(find.text('#mbotecall'), findsOneWidget);
    expect(find.text('@cedricklengo'), findsOneWidget);
  });

  testWidgets('un hashtag trouvé ouvre sa page', (tester) async {
    final api = _apiCourante!;
    api.resultats = const ResultatsRecherche(
      q: '#mbote',
      portee: 'hashtags',
      hashtags: [Hashtag(tag: 'mbotecall', publications: 5)],
      total: 1,
    );
    api.page = const Hashtag(tag: 'mbotecall', publications: 5);

    await tester.pumpWidget(wrap(const RechercheScreen(requeteInitiale: '#mbote')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('#mbotecall'));
    await tester.pumpAndSettle();

    expect(find.byType(HashtagScreen), findsOneWidget);
  });

  // ── 6. Notifications ─────────────────────────────────────────────────────
  testWidgets('les mentions reçues s’affichent et se marquent comme lues',
      (tester) async {
    final api = _apiCourante!;
    api.notifs = [
      NotificationSociale(
        id: 'n1',
        type: 'mention',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        postId: 'p1',
        sourceType: 'post',
        texte: 'Merci beaucoup',
        expediteur: const Personne(id: 'u3', name: 'Cédrick Lengo'),
      ),
    ];

    await tester.pumpWidget(wrap(const NotificationsScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Cédrick Lengo t’a mentionné'), findsOneWidget);
    expect(find.textContaining('Merci beaucoup'), findsOneWidget);
    expect(find.text('Tout lire'), findsOneWidget);

    await tester.tap(find.text('Tout lire'));
    await tester.pumpAndSettle();

    expect(api.appels, contains('marquerNotificationsLues'));
    expect(find.text('Tout lire'), findsNothing);
  });

  testWidgets('aucune notification : le message explique comment en recevoir',
      (tester) async {
    await tester.pumpWidget(wrap(const NotificationsScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Aucune notification'), findsOneWidget);
    expect(find.textContaining('@'), findsWidgets);
  });
}
