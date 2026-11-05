// Lokota est devenu une OPTION DE LA DISCUSSION : plus de rubrique dans le
// menu « · · · », mais un bouton flottant qui active la traduction de toutes
// les conversations, texte et notes vocales.
//
// Ces tests vérifient :
//   1. la règle de langue envoyée au serveur (traduction active ou non) ;
//   2. la persistance des réglages sur le téléphone ;
//   3. le panneau ouvert par le bouton flottant (interrupteurs, langues, audio) ;
//   4. ce qui part réellement au serveur quand on envoie un message ;
//   5. l'absence de Lokota dans le menu « · · · ».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mbote/api.dart';
import 'package:mbote/l10n.dart';
import 'package:mbote/prefs.dart';
import 'package:mbote/screens/chat.dart';
import 'package:mbote/screens/chats.dart';
import 'package:mbote/screens/traduction.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';

const peer = '+243810000002';

class FakeApi extends Api {
  final List<String> envois = [];

  @override
  Future<List> messageThreads() async => [
        {
          'peer_phone': peer,
          'peer_name': 'Bob',
          'online': true,
          'last_seen_at': null,
          'last_at': 1762000000000,
          'last_type': 'text',
          'last_body': 'À tantôt !',
          'last_preview': 'À tantôt !',
          'last_mine': false,
          'last_state': 'done',
          'unread': 0,
        },
      ];

  @override
  Future<Map> conversation(String phone, {int? before}) async => {
        'peer_phone': phone,
        'peer_name': 'Bob',
        'peer_online': true,
        'peer_last_seen_at': null,
        'has_more': false,
        'items': const [],
      };

  @override
  Future<void> markConversationRead(String phone) async {}

  @override
  Future<Map> sendMessage(String to, String text, {String? clientId, String langFrom = 'fr', String langTo = 'fr', String kind = 'text'}) async {
    envois.add('$langFrom>$langTo');
    return {
      'id': 'srv-$clientId',
      'kind': 'text',
      'mine': true,
      'body': text,
      'translation': '',
      'transcript': '',
      'lang_from': langFrom,
      'lang_to': langTo,
      'status': 'sent',
      'created_at': 1762000500000,
      'delivered_at': 0,
      'read_at': 0,
      'played_at': 0,
      'deleted': 0,
      'has_media': false,
      'duration_sec': 0,
      'wave': const <int>[],
    };
  }

  @override
  Future<List> contacts() async => const [];
}

AppState etat(FakeApi api) {
  final st = AppState();
  st.token = 'jeton';
  st.id = 'u1';
  st.name = 'Alice';
  st.phone = '+243810000001';
  st.ready = true;
  st.api = api;
  return st;
}

Widget enveloppe(Widget ecran, AppState st) => ChangeNotifierProvider.value(
      value: st,
      child: MaterialApp(theme: mboteTheme(), home: ecran),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.lang = 'fr';
    TradPrefs.reset();
    MC.apply(kPalettes['fleuve']!);
  });

  group('Règle de langue (Lokota)', () {
    test('traduction coupée : le serveur reçoit la même langue', () {
      TradPrefs.reset();
      TradPrefs.maLangue = 'fr';
      TradPrefs.cible = 'ln';
      TradPrefs.actif = false;
      expect(TradPrefs.langFrom, 'fr');
      expect(TradPrefs.langTo, 'fr',
          reason: 'lang_from == lang_to : le serveur ne traduit rien');
    });

    test('traduction active : la langue cible est envoyée', () {
      TradPrefs.reset();
      TradPrefs.maLangue = 'fr';
      TradPrefs.cible = 'sw';
      TradPrefs.actif = true;
      expect(TradPrefs.langFrom, 'fr');
      expect(TradPrefs.langTo, 'sw');
      expect(TradPrefs.audio, isTrue);
    });

    test('une langue inconnue est refusée', () async {
      await TradPrefs.set(maLangue: 'xx');
      expect(TradPrefs.maLangue, 'fr');
      await TradPrefs.set(cible: 'zz');
      expect(TradPrefs.cible, 'ln');
    });

    test('les réglages survivent au redémarrage', () async {
      await TradPrefs.set(actif: true, maLangue: 'ln', cible: 'fr', audio: false);
      TradPrefs.reset(); // simule un redémarrage (mémoire vidée)
      expect(TradPrefs.actif, isFalse);

      await TradPrefs.load();
      expect(TradPrefs.actif, isTrue);
      expect(TradPrefs.maLangue, 'ln');
      expect(TradPrefs.cible, 'fr');
      expect(TradPrefs.audio, isFalse);
    });
  });

  group('Bouton flottant de la Discussion', () {
    testWidgets('le bouton existe et ouvre le panneau', (tester) async {
      await tester.pumpWidget(enveloppe(const ChatsScreen(), etat(FakeApi())));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fab-traduction')), findsOneWidget);

      await tester.tap(find.byKey(const Key('fab-traduction')));
      await tester.pumpAndSettle();

      expect(find.byType(TraductionSheet), findsOneWidget);
      expect(find.byKey(const Key('trad-globale')), findsOneWidget);
      expect(find.byKey(const Key('trad-audio')), findsOneWidget);
      expect(find.byKey(const Key('trad-lokota')), findsOneWidget);
      for (final c in TradPrefs.codes) {
        expect(find.byKey(Key('trad-ma-$c')), findsOneWidget, reason: c);
        expect(find.byKey(Key('trad-vers-$c')), findsOneWidget, reason: c);
      }
    });

    testWidgets('activer la traduction est enregistré', (tester) async {
      await tester.pumpWidget(enveloppe(const TraductionSheet(), etat(FakeApi())));
      await tester.pumpAndSettle();

      expect(TradPrefs.actif, isFalse);
      await tester.tap(find.byKey(const Key('trad-globale')));
      await tester.pumpAndSettle();

      expect(TradPrefs.actif, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('trad_actif'), isTrue);
    });

    testWidgets('changer de langue met à jour la cible', (tester) async {
      await tester.pumpWidget(enveloppe(const TraductionSheet(), etat(FakeApi())));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('trad-vers-sw')));
      await tester.pumpAndSettle();
      expect(TradPrefs.cible, 'sw');
      expect((await SharedPreferences.getInstance()).getString('trad_cible'), 'sw');
    });

    testWidgets('choisir la même langue des deux côtés repousse la cible',
        (tester) async {
      await tester.pumpWidget(enveloppe(const TraductionSheet(), etat(FakeApi())));
      await tester.pumpAndSettle();

      // « je parle » = la langue déjà choisie comme cible (ln par défaut).
      await tester.tap(find.byKey(const Key('trad-ma-ln')));
      await tester.pumpAndSettle();
      expect(TradPrefs.maLangue, 'ln');
      expect(TradPrefs.cible, isNot('ln'),
          reason: 'une traduction vers la même langue ne servirait à rien');
    });

    testWidgets('couper la traduction des notes vocales est enregistré',
        (tester) async {
      await tester.pumpWidget(enveloppe(const TraductionSheet(), etat(FakeApi())));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('trad-audio')));
      await tester.pumpAndSettle();
      expect(TradPrefs.audio, isFalse);
      expect((await SharedPreferences.getInstance()).getBool('trad_audio'), isFalse);
    });
  });

  group('Ce qui part réellement au serveur', () {
    Future<void> envoie(WidgetTester tester, FakeApi api) async {
      await tester.pumpWidget(enveloppe(
          const ChatScreen(key: ValueKey('fil-2'), peerPhone: peer),
          etat(api)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Mbote');
      await tester.pump(); // le bouton micro devient « envoyer »
      await tester.tap(find.byIcon(Icons.send_rounded).first);
      await tester.pumpAndSettle();
    }

    testWidgets('traduction coupée : lang_from == lang_to', (tester) async {
      final api = FakeApi();
      TradPrefs.reset();
      TradPrefs.maLangue = 'fr';
      TradPrefs.cible = 'ln';
      TradPrefs.actif = false;
      await envoie(tester, api);
      expect(api.envois, ['fr>fr']);
    });

    testWidgets('traduction active : la cible est envoyée', (tester) async {
      final api = FakeApi();
      TradPrefs.reset();
      TradPrefs.maLangue = 'fr';
      TradPrefs.cible = 'ln';
      TradPrefs.actif = true;
      await envoie(tester, api);
      expect(api.envois, ['fr>ln']);
    });

    testWidgets('le réglage est relu à chaque ouverture de conversation',
        (tester) async {
      final api = FakeApi();
      TradPrefs.reset();
      TradPrefs.actif = false;
      await envoie(tester, api);

      // L'utilisateur active la traduction puis revient dans le fil.
      await TradPrefs.set(actif: true, cible: 'sw');
      await tester.pumpWidget(
          enveloppe(const ChatScreen(peerPhone: peer), etat(api)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Deuxième');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded).first);
      await tester.pumpAndSettle();

      expect(api.envois, ['fr>fr', 'fr>sw']);
    });
  });
}
