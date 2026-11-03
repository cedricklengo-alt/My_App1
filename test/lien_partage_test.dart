// test/lien_partage_test.dart
// LIEN PARTAGÉ — lecture du lien et ouverture de la publication.
//
// Le partage ne s'arrête pas à l'envoi : celui qui reçoit le lien doit pouvoir
// revenir dans l'application, sur la publication exacte. Ces tests couvrent
// l'analyse du lien et l'ouverture réelle dans le fil.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mbote/liens.dart';
import 'package:mbote/screens/feed_screen.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';

import 'feed_screen_test.dart' show FakeApi;

/// Même montage que les autres tests du fil : la palette puis l'état connecté.
Widget wrap(FakeApi api) {
  MC.apply(kPalettes['kin']!);
  return ChangeNotifierProvider<AppState>.value(
    value: AppState(),
    child: MaterialApp(home: FeedScreen(api: api)),
  );
}

void main() {
  setUp(Liens.reset);
  tearDown(Liens.reset);

  group('Analyse du lien mbote://post/<id>', () {
    test('lien complet', () {
      expect(Liens.idDepuisLien('mbote://post/po_123'), 'po_123');
    });

    test('forme transmise par Android', () {
      expect(Liens.idDepuisLien('post/po_123'), 'po_123');
    });

    test('paramètres et barre finale ignorés', () {
      expect(Liens.idDepuisLien('mbote://post/po_123?from=whatsapp'), 'po_123');
      expect(Liens.idDepuisLien('mbote://post/po_123/'), 'po_123');
    });

    test('un autre schéma est refusé', () {
      expect(Liens.idDepuisLien('https://exemple.cd/p/po_123'), isNull);
      expect(Liens.idDepuisLien(''), isNull);
      expect(Liens.idDepuisLien('mbote://'), isNull);
    });

    test('un lien prévient le fil une seule fois', () {
      var notifs = 0;
      void compter() => notifs++;
      Liens.post.addListener(compter);
      Liens.traiter('mbote://post/po_1');
      Liens.traiter('mbote://post/po_1'); // relivraison du système
      Liens.post.removeListener(compter);
      expect(notifs, 1);
    });
  });

  testWidgets('la publication d\'un lien s\'ouvre par-dessus le fil',
      (tester) async {
    final api = FakeApi()
      ..page1 = [FakeApi.post('p1', texte: 'Depuis le fil')];

    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    // Le lien arrive alors que l'application est déjà ouverte.
    Liens.traiter('mbote://post/p9');
    await tester.pumpAndSettle();

    expect(api.calls, contains('lirePublication(p9)'));
    expect(find.text('Publication partagée'), findsOneWidget);
    expect(find.text('Texte de la publication p9'), findsOneWidget);
  });

  testWidgets('un lien vers une publication privée ne casse rien',
      (tester) async {
    final api = FakeApi()..page1 = [FakeApi.post('p1')];
    api.erreurLecture = 'Publication introuvable';

    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    Liens.traiter('mbote://post/absent');
    await tester.pumpAndSettle();

    expect(find.text('Publication partagée'), findsNothing);
    expect(find.textContaining('indisponible'), findsOneWidget);
  });
}
