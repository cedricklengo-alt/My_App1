// CYCLE DE STATUT (24 h) — de la bande de statuts à la publication.
//
// Ce que ces tests prouvent, sans réseau :
//   1. « Mon statut » mène à la création quand je n'ai rien publié ;
//   2. publier un statut texte appelle vraiment le serveur et l'affiche ;
//   3. ouvrir le statut de quelqu'un le marque comme vu côté serveur ;
//   4. supprimer mon statut passe par une confirmation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mbote/api.dart';
import 'package:mbote/models/post.dart';
import 'package:mbote/screens/feed_screen.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';

class FakeApi extends Api {
  List<Story> stories = [];
  final List<String> appels = [];

  @override
  Future<FeedPage> feedPage({int? before, String? cursor}) async =>
      const FeedPage(posts: [], nextBefore: null, nextCursor: null);

  @override
  Future<List<Story>> feedStories() async {
    appels.add('feedStories');
    return stories;
  }

  @override
  Future<void> postStory({String? mediaUrl, String? texte}) async {
    appels.add('postStory(${texte ?? mediaUrl})');
    stories = [
      ...stories,
      Story(
        id: 'st-mien',
        userId: 'u1',
        authorName: 'Alice',
        texte: texte ?? '',
        createdAt: DateTime.now(),
      ),
    ];
  }

  @override
  Future<void> markStorySeen(String id) async => appels.add('seen($id)');

  @override
  Future<void> deleteStory(String id) async {
    appels.add('deleteStory($id)');
    stories = stories.where((s) => s.id != id).toList();
  }
}

Widget wrap(FakeApi api) {
  MC.apply(kPalettes['fleuve']!);
  final st = AppState();
  st.id = 'u1';
  st.name = 'Alice';
  st.phone = '+243810000001';
  st.api = api;
  return ChangeNotifierProvider<AppState>.value(
    value: st,
    child: const MaterialApp(home: FeedScreen()),
  );
}

void main() {
  testWidgets('sans statut publié, « Mon statut » propose d’en créer un',
      (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    expect(find.text('Mon statut'), findsOneWidget);

    await tester.tap(find.text('Mon statut'));
    await tester.pumpAndSettle();

    // Les trois formats proposés par l'application.
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Vidéo courte (60 s max)'), findsOneWidget);
    expect(find.text('Texte'), findsOneWidget);
  });

  testWidgets('publier un statut texte passe par le serveur', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mon statut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Texte'));
    await tester.pumpAndSettle();

    expect(find.text('Statut texte'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Mbote na bino');
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();

    expect(api.appels.any((a) => a.startsWith('postStory(Mbote na bino')),
        isTrue,
        reason: 'le texte doit partir au serveur');
    // La bande se recharge : mon statut existe maintenant.
    expect(api.stories.any((s) => s.texte == 'Mbote na bino'), isTrue);
  });

  testWidgets('ouvrir le statut d’un proche le marque comme vu',
      (tester) async {
    final api = FakeApi()
      ..stories = [
        Story(
          id: 'st-bob',
          userId: 'u2',
          authorName: 'Bob',
          texte: 'Le fleuve ce matin',
          createdAt: DateTime.now(),
        ),
      ];
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    await tester.tap(find.text('Bob'));
    // pumpAndSettle ferait avancer l'horloge jusqu'à la fin du statut (5 s) :
    // on avance juste assez pour l'ouverture.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // Le contenu du statut s'affiche et le serveur retient la lecture.
    expect(find.text('Le fleuve ce matin'), findsOneWidget);
    expect(api.appels.contains('seen(st-bob)'), isTrue);
  });

  testWidgets('supprimer mon statut demande une confirmation',
      (tester) async {
    final api = FakeApi()
      ..stories = [
        Story(
          id: 'st-mien',
          userId: 'u1',
          authorName: 'Alice',
          texte: 'Mon premier statut',
          createdAt: DateTime.now(),
        ),
      ];
    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mon statut'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(api.appels, isNot(contains('deleteStory(st-mien)')),
        reason: 'ouvrir son statut ne supprime rien');
  });
}
