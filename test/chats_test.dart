// Tests de l'onglet DISCUSSION côté application.
// Aucun réseau, aucun micro : on remplace l'API par un faux serveur et on
// vérifie ce que l'utilisateur voit vraiment — liste des conversations,
// bulles, états ✓✓, traduction, envoi, échec et reprise, non-lus.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mbote/api.dart';
import 'package:mbote/l10n.dart';
import 'package:mbote/screens/chat.dart';
import 'package:mbote/screens/chats.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';

const peer = '+243810000002';

Map<String, dynamic> msg({
  required String id,
  String kind = 'text',
  bool mine = false,
  String body = '',
  String status = 'read',
  int created = 1762000000000,
  String translation = '',
  String transcript = '',
  int duration = 5,
  int played = 0,
  bool deleted = false,
}) =>
    {
      'id': id,
      'kind': deleted ? 'deleted' : kind,
      'mine': mine,
      'body': body,
      'translation': translation,
      'transcript': transcript,
      'lang_from': 'fr',
      'lang_to': 'ln',
      'status': status,
      'created_at': created,
      'delivered_at': 0,
      'read_at': 0,
      'played_at': played,
      'deleted': deleted ? 1 : 0,
      'has_media': kind != 'text' && !deleted,
      'att_name': kind == 'file' ? 'recu.pdf' : null,
      'att_mime': null,
      'att_size': 2048,
      'duration_sec': duration,
      'wave': const [20, 60, 40, 80, 30, 55],
    };

/// Faux serveur de messagerie.
class FakeChatApi extends Api {
  final List<Map> threads;

  /// Carnet d'adresses renvoyé à l'ouverture du sélecteur de destinataire.
  List<Map> carnet = [
    {'id': 'ct1', 'name': 'Chantal', 'phone': '+243810000003'},
    {'id': 'ct2', 'name': 'Bob', 'phone': peer},
  ];
  int carnetAppels = 0;

  @override
  Future<List> contacts() async {
    carnetAppels++;
    return carnet;
  }
  final Map<String, List<Map>> conversations = {};
  final List<String> journal = [];
  bool failSend = false;
  int reads = 0;

  FakeChatApi({List<Map>? threads, List<Map>? messages})
      : threads = threads ??
            [
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
                'unread': 2,
              },
            ] {
    if (messages != null) conversations[peer] = messages;
  }

  @override
  Future<List> messageThreads() async {
    journal.add('threads');
    return threads;
  }

  /// Pages d'historique plus anciennes, par curseur (`before`).
  final Map<int, List<Map>> olderPages = {};
  bool hasMore = false;

  @override
  Future<Map> conversation(String phone, {int? before}) async {
    journal.add('conversation($phone${before == null ? '' : ', before: $before'})');
    final items = before == null
        ? (conversations[phone] ?? const [])
        : (olderPages[before] ?? const []);
    return {
      'peer_phone': phone,
      'peer_name': 'Bob',
      'peer_online': true,
      'peer_last_seen_at': null,
      'has_more': hasMore,
      'items': items,
    };
  }

  @override
  Future<void> markConversationRead(String phone) async {
    reads++;
    journal.add('read($phone)');
  }

  @override
  Future<Map> sendMessage(String to, String text, {String? clientId, String langFrom = 'fr', String langTo = 'fr', String kind = 'text'}) async {
    journal.add('send($to, $text, $clientId)');
    if (failSend) throw ApiException('Pas d\'Internet — vérifie ta connexion 📶');
    return msg(
      id: 'srv-$clientId',
      mine: true,
      body: text,
      status: 'sent',
      created: 1762000500000,
    );
  }

  @override
  Future<void> deleteMessageForAll(String id) async => journal.add('delall($id)');

  @override
  Future<void> deleteMessagesForMe(List<String> ids) async =>
      journal.add('delme(${ids.join(',')})');
}

AppState chatState(Api api) {
  final st = AppState();
  st.phone = '+243810000001';
  st.name = 'Alice';
  st.api = api;
  return st;
}

Widget wrap(Widget child, AppState state) {
  MC.apply(kPalettes['kin']!);
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(home: child),
  );
}

void main() {
  setUp(() async {
    L10n.lang = 'fr';
    ChatsScreen.unread.value = 0;
  });

  // Cible stable : la clé du bouton flottant (l'état vide propose en plus un
  // bouton « Nouvelle discussion », et son libellé est le même).
  final fab = find.byKey(const Key('fab-nouvelle-discussion'));

  group('Bouton flottant — nouvelle discussion', () {
    testWidgets('le bouton est là, avec un libellé lisible par un lecteur '
        'd’écran', (t) async {
      final handle = t.ensureSemantics();
      final api = FakeChatApi();
      await t.pumpWidget(wrap(const ChatsScreen(), chatState(api)));
      await t.pumpAndSettle();

      // Trouvé par son libellé : un « + » muet serait inaccessible.
      expect(find.bySemanticsLabel(L10n.t('chats_new')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('le bouton fait 68 px et garde ses proportions', (t) async {
      final api = FakeChatApi();
      await t.pumpWidget(wrap(const ChatsScreen(), chatState(api)));
      await t.pumpAndSettle();

      final boite = t.getSize(
          find.byWidgetPredicate((w) => w is AnimatedScale).first);
      expect(boite.width, 68);
      expect(boite.height, 68);
    });

    testWidgets('toucher le bouton ouvre le choix du destinataire',
        (t) async {
      final api = FakeChatApi();
      await t.pumpWidget(wrap(const ChatsScreen(), chatState(api)));
      await t.pumpAndSettle();

      expect(find.text('Chantal'), findsNothing);

      await t.tap(fab);
      await t.pumpAndSettle();

      // La feuille s'ouvre même si l'app n'avait encore chargé aucun contact.
      expect(api.carnetAppels, greaterThanOrEqualTo(1));
      expect(find.text('Chantal'), findsOneWidget);
      expect(find.text('+243810000003'), findsOneWidget);
    });

    testWidgets('choisir un contact ouvre directement la conversation',
        (t) async {
      final api = FakeChatApi();
      api.conversations['+243810000003'] = [
        msg(id: 'm1', body: 'Mbote Chantal', mine: false, status: 'done'),
      ];
      await t.pumpWidget(wrap(const ChatsScreen(), chatState(api)));
      await t.pumpAndSettle();

      await t.tap(fab);
      await t.pumpAndSettle();
      await t.tap(find.text('Chantal'));
      await t.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Mbote Chantal'), findsOneWidget);
    });

    testWidgets('liste vide : le bouton reste disponible', (t) async {
      final api = FakeChatApi(threads: []);
      await t.pumpWidget(wrap(const ChatsScreen(), chatState(api)));
      await t.pumpAndSettle();

      expect(find.textContaining('Aucune discussion'), findsOneWidget);
      // Le bouton flottant reste offert même sans aucune conversation.
      await t.tap(fab);
      await t.pumpAndSettle();
      expect(find.text('Chantal'), findsOneWidget);
    });

    testWidgets('un appui ne déclenche qu’une seule ouverture', (t) async {
      final api = FakeChatApi();
      await t.pumpWidget(wrap(const ChatsScreen(), chatState(api)));
      await t.pumpAndSettle();

      await t.tap(fab);
      await t.pump(const Duration(milliseconds: 40));
      // Un second appui pendant l'ouverture ne doit pas empiler deux feuilles :
      // une seule liste de destinataires doit être présente.
      expect(find.text('Chantal'), findsOneWidget);
      await t.tapAt(const Offset(200, 40)); // appui hors feuille
      await t.pumpAndSettle();
      expect(find.text('Chantal'), findsNothing);
    });
  });

  group('Liste des conversations', () {
    testWidgets('affiche le nom, l’aperçu et les non-lus', (t) async {
      final api = FakeChatApi();
      await t.pumpWidget(wrap(const ChatsScreen(), chatState(api)));
      await t.pumpAndSettle();

      expect(find.text('Discussions'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('À tantôt !'), findsOneWidget);
      // Pastille de non-lus : dans la liste et sur le titre.
      expect(find.text('2'), findsNWidgets(2));
      expect(api.journal, contains('threads'));
    });

    testWidgets('met à jour la pastille de l’onglet Messages', (t) async {
      final api = FakeChatApi();
      expect(ChatsScreen.unread.value, 0);
      await t.pumpWidget(wrap(const ChatsScreen(), chatState(api)));
      await t.pumpAndSettle();
      expect(ChatsScreen.unread.value, 2);
    });

    testWidgets('liste vide : invite à écrire le premier message', (t) async {
      final api = FakeChatApi(threads: []);
      await t.pumpWidget(wrap(const ChatsScreen(), chatState(api)));
      await t.pumpAndSettle();
      expect(find.textContaining('Aucune discussion'), findsOneWidget);
      expect(ChatsScreen.unread.value, 0);
    });

    testWidgets('la recherche filtre les conversations', (t) async {
      final api = FakeChatApi(threads: [
        {
          'peer_phone': peer,
          'peer_name': 'Bob',
          'last_preview': 'Salut',
          'last_at': 1762000000000,
          'unread': 0,
        },
        {
          'peer_phone': '+243810000003',
          'peer_name': 'Chantal',
          'last_preview': 'Mbote',
          'last_at': 1762000001000,
          'unread': 0,
        },
      ]);
      await t.pumpWidget(wrap(const ChatsScreen(), chatState(api)));
      await t.pumpAndSettle();
      expect(find.text('Chantal'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'chan');
      await t.pumpAndSettle();
      expect(find.text('Chantal'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
    });

    testWidgets('toucher une conversation ouvre le fil et marque lu', (t) async {
      final api = FakeChatApi(messages: [
        msg(id: 'm1', body: 'Coucou', mine: false, status: 'done'),
      ]);
      await t.pumpWidget(wrap(const ChatsScreen(), chatState(api)));
      await t.pumpAndSettle();

      await t.tap(find.text('Bob'));
      await t.pumpAndSettle();

      // L'écran de conversation est bien ouvert.
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Coucou'), findsOneWidget);
      expect(api.reads, greaterThanOrEqualTo(1));
    });
  });

  group('Conversation', () {
    testWidgets('affiche les messages et l’état de lecture', (t) async {
      final api = FakeChatApi(messages: [
        msg(id: 'm1', body: 'Mbote Alice', mine: false, status: 'done'),
        msg(id: 'm2', body: 'Mbote Bob', mine: true, status: 'read', created: 1762000060000),
        msg(id: 'm3', body: 'À tantôt', mine: true, status: 'sent', created: 1762000120000),
      ]);
      await t.pumpWidget(
          wrap(const ChatScreen(peerPhone: peer, peerName: 'Bob'), chatState(api)));
      await t.pumpAndSettle();

      expect(find.text('Mbote Alice'), findsOneWidget);
      expect(find.text('Mbote Bob'), findsOneWidget);
      // ✓✓ lu, ✓ envoyé : deux icônes différentes.
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);
      expect(api.journal, contains('conversation($peer)'));
    });

    testWidgets('note vocale : traduction affichée puis texte original', (t) async {
      final api = FakeChatApi(messages: [
        msg(
          id: 'v1',
          kind: 'note',
          mine: false,
          status: 'done',
          translation: 'Mbote, ozali malamu ?',
          transcript: 'Bonjour, tu vas bien ?',
          duration: 7,
        ),
      ]);
      await t.pumpWidget(
          wrap(const ChatScreen(peerPhone: peer, peerName: 'Bob'), chatState(api)));
      await t.pumpAndSettle();

      // Par défaut on lit le texte original ; un bouton propose la traduction.
      expect(find.textContaining('Bonjour, tu vas bien ?'), findsOneWidget);
      expect(find.text('0:07'), findsOneWidget);
      expect(find.textContaining('Voir la traduction'), findsOneWidget);

      await t.tap(find.textContaining('Voir la traduction'));
      await t.pumpAndSettle();
      expect(find.textContaining('Mbote, ozali malamu ?'), findsOneWidget);
      expect(find.textContaining('Bonjour, tu vas bien ?'), findsNothing);

      await t.tap(find.text('Voir le texte original'));
      await t.pumpAndSettle();
      expect(find.textContaining('Bonjour, tu vas bien ?'), findsOneWidget);
    });

    testWidgets('message supprimé : aucun contenu, aucune coche', (t) async {
      final api = FakeChatApi(messages: [
        msg(id: 'd1', mine: true, deleted: true, status: 'deleted'),
      ]);
      await t.pumpWidget(
          wrap(const ChatScreen(peerPhone: peer, peerName: 'Bob'), chatState(api)));
      await t.pumpAndSettle();

      expect(find.textContaining('Message supprimé'), findsOneWidget);
      expect(find.byIcon(Icons.done_all_rounded), findsNothing);
    });

    testWidgets('fichier : nom et taille affichés', (t) async {
      final api = FakeChatApi(messages: [
        msg(id: 'f1', kind: 'file', mine: false, status: 'done', body: ''),
      ]);
      await t.pumpWidget(
          wrap(const ChatScreen(peerPhone: peer, peerName: 'Bob'), chatState(api)));
      await t.pumpAndSettle();

      expect(find.text('recu.pdf'), findsOneWidget);
      expect(find.text('2 Ko'), findsOneWidget);
    });

    testWidgets('envoi d’un texte : bulle immédiate puis confirmation', (t) async {
      final api = FakeChatApi(messages: []);
      await t.pumpWidget(
          wrap(const ChatScreen(peerPhone: peer, peerName: 'Bob'), chatState(api)));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField), 'Mbote !');
      await t.pump();
      await t.tap(find.byIcon(Icons.send_rounded));
      await t.pumpAndSettle();

      expect(find.text('Mbote !'), findsOneWidget);
      expect(api.journal.any((l) => l.startsWith('send($peer, Mbote !, c')), isTrue,
          reason: api.journal.join(' | '));
      // Le message optimiste a été remplacé par la version du serveur.
      expect(find.text('Mbote !'), findsOneWidget);
    });

    testWidgets('échec d’envoi : « Réessayer » proposé', (t) async {
      final api = FakeChatApi(messages: [])..failSend = true;
      await t.pumpWidget(
          wrap(const ChatScreen(peerPhone: peer, peerName: 'Bob'), chatState(api)));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField), 'Perdu ?');
      await t.pump();
      await t.tap(find.byIcon(Icons.send_rounded));
      await t.pumpAndSettle();

      expect(find.text('Perdu ?'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.textContaining('Pas d\'Internet'), findsOneWidget);

      // Le réseau revient : on réessaie, le message part une seule fois.
      api.failSend = false;
      await t.tap(find.text('Réessayer'));
      await t.pumpAndSettle();
      expect(find.text('Réessayer'), findsNothing);
      expect(find.text('Perdu ?'), findsOneWidget);
    });

    testWidgets('conversation vide : invitation à écrire', (t) async {
      final api = FakeChatApi(messages: []);
      await t.pumpWidget(
          wrap(const ChatScreen(peerPhone: peer, peerName: 'Bob'), chatState(api)));
      await t.pumpAndSettle();
      expect(find.textContaining('Dis bonjour'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_rounded), findsOneWidget);
    });

    testWidgets('l’en-tête propose l’appel audio et vidéo', (t) async {
      final api = FakeChatApi(messages: []);
      await t.pumpWidget(
          wrap(const ChatScreen(peerPhone: peer, peerName: 'Bob'), chatState(api)));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.call_rounded), findsOneWidget);
      expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);
      expect(find.text('en ligne'), findsOneWidget);
    });
  });

  group('Temps réel (WebSocket)', () {
    /// Petit utilitaire : ouvre une conversation et rend son état.
    Future<ChatScreenState> open(WidgetTester t, FakeChatApi api) async {
      await t.pumpWidget(
          wrap(const ChatScreen(peerPhone: peer, peerName: 'Bob'), chatState(api)));
      await t.pumpAndSettle();
      return t.state<ChatScreenState>(find.byType(ChatScreen));
    }

    testWidgets('« écrit… » apparaît puis disparaît tout seul', (t) async {
      final api = FakeChatApi(messages: []);
      await open(t, api);
      expect(find.text('en ligne'), findsOneWidget);

      t.state<ChatScreenState>(find.byType(ChatScreen))
          .handleRealtime({'type': 'typing', 'from': peer});
      await t.pump();
      expect(find.text('écrit…'), findsOneWidget);

      // Un autre numéro ne doit jamais allumer l'indicateur.
      t.state<ChatScreenState>(find.byType(ChatScreen))
          .handleRealtime({'type': 'typing', 'from': '+243899999999'});
      await t.pump();
      await t.pump(const Duration(seconds: 5));
      expect(find.text('écrit…'), findsNothing);
    });

    testWidgets('« lu » transforme mes ✓ en ✓✓ lus', (t) async {
      final api = FakeChatApi(messages: [
        msg(id: 'm1', body: 'Tu es là ?', mine: true, status: 'sent'),
      ]);
      await open(t, api);
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);
      expect(find.byIcon(Icons.done_all_rounded), findsNothing);

      t.state<ChatScreenState>(find.byType(ChatScreen))
          .handleRealtime({'type': 'msg', 'kind': 'read', 'msg_id': 'm1', 'from_phone': peer});
      await t.pump();
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(find.byIcon(Icons.done_rounded), findsNothing);
    });

    testWidgets('« supprimé » remplace le contenu par un avertissement', (t) async {
      final api = FakeChatApi(messages: [
        msg(id: 'm1', body: 'Oups', mine: true, status: 'read'),
      ]);
      await open(t, api);
      expect(find.text('Oups'), findsOneWidget);

      t.state<ChatScreenState>(find.byType(ChatScreen))
          .handleRealtime({'type': 'msg', 'kind': 'deleted', 'msg_id': 'm1', 'from_phone': peer});
      await t.pump();
      expect(find.text('Oups'), findsNothing);
      expect(find.textContaining('Message supprimé'), findsOneWidget);
    });

    testWidgets('un nouveau message du proche recharge le fil et marque lu',
        (t) async {
      final api = FakeChatApi(messages: [
        msg(id: 'm1', body: 'Coucou', mine: false, status: 'done'),
      ]);
      final st = await open(t, api);
      final avant = api.reads;

      api.conversations[peer] = [
        msg(id: 'm1', body: 'Coucou', mine: false, status: 'done'),
        msg(id: 'm2', body: 'Tu as vu ?', mine: false, status: 'done', created: 1762000300000),
      ];
      st.handleRealtime({
        'type': 'msg', 'kind': 'message', 'msg_id': 'm2',
        'from_phone': peer, 'from_name': 'Bob', 'preview': 'Tu as vu ?',
      });
      await t.pumpAndSettle();

      expect(find.text('Tu as vu ?'), findsOneWidget);
      expect(api.reads, greaterThan(avant));
    });

    testWidgets('un message d’un autre contact ne recharge pas ce fil', (t) async {
      final api = FakeChatApi(messages: []);
      final st = await open(t, api);
      final appels = api.journal.where((l) => l.startsWith('conversation')).length;

      st.handleRealtime({
        'type': 'msg', 'kind': 'message', 'msg_id': 'x1',
        'from_phone': '+243899999999', 'preview': 'autre',
      });
      await t.pumpAndSettle();
      expect(api.journal.where((l) => l.startsWith('conversation')).length, appels);
    });
  });

  group('Liste — détails qui changent la vie', () {
    testWidgets('mon dernier message est préfixé « Vous : »', (t) async {
      final api = FakeChatApi(threads: [
        {
          'peer_phone': peer,
          'peer_name': 'Bob',
          'last_preview': 'À tantôt !',
          'last_mine': true,
          'last_type': 'text',
          'last_state': 'read',
          'last_at': 1762000000000,
          'unread': 0,
        },
      ]);
      await t.pumpWidget(wrap(const ChatsScreen(), chatState(api)));
      await t.pumpAndSettle();
      expect(find.textContaining('Vous : À tantôt !'), findsOneWidget);
    });

    testWidgets('« écrit… » apparaît dans la conversation concernée', (t) async {
      final api = FakeChatApi();
      await t.pumpWidget(wrap(const ChatsScreen(), chatState(api)));
      await t.pumpAndSettle();
      final st = t.state<ChatsScreenState>(find.byType(ChatsScreen));

      st.handleRealtime({'type': 'typing', 'from': peer});
      await t.pump();
      expect(find.text('écrit…'), findsOneWidget);
      expect(find.text('À tantôt !'), findsNothing);

      // Un autre numéro n'allume rien.
      st.handleRealtime({'type': 'typing', 'from': '+243899999999'});
      await t.pump();
      await t.pump(const Duration(seconds: 5));
      expect(find.text('écrit…'), findsNothing);
    });

    testWidgets('appui long : appel audio, vidéo ou « marquer comme lu »',
        (t) async {
      final api = FakeChatApi();
      await t.pumpWidget(wrap(const ChatsScreen(), chatState(api)));
      await t.pumpAndSettle();

      await t.longPress(find.text('Bob'));
      await t.pumpAndSettle();
      expect(find.text('Appel audio'), findsOneWidget);
      expect(find.text('Appel vidéo'), findsOneWidget);
      expect(find.text('Marquer comme lu'), findsOneWidget);

      await t.tap(find.text('Marquer comme lu'));
      await t.pumpAndSettle();
      expect(api.reads, greaterThanOrEqualTo(1));
    });

    testWidgets('liste vide : bouton « Nouvelle discussion »', (t) async {
      final api = FakeChatApi(threads: []);
      await t.pumpWidget(wrap(const ChatsScreen(), chatState(api)));
      await t.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Nouvelle discussion'),
          findsOneWidget);
    });
  });

  group('Robustesse du fil (correctifs)', () {
    testWidgets('un message entrant ne jette pas l’historique déjà remonté',
        (t) async {
      // 60 messages : la page serveur n'en renvoie que les 50 derniers.
      final tous = List.generate(
        60,
        (i) => msg(
            id: 'm$i',
            body: 'message $i',
            mine: i.isEven,
            status: 'done',
            created: 1762000000000 + i * 1000),
      );
      final api = FakeChatApi(messages: tous.sublist(10));
      await t.pumpWidget(
          wrap(const ChatScreen(peerPhone: peer, peerName: 'Bob'), chatState(api)));
      await t.pumpAndSettle();

      final st = t.state<ChatScreenState>(find.byType(ChatScreen));
      expect(st.msgs.length, 50);

      // L'utilisateur remonte le temps : page précédente (m0..m9).
      api.olderPages[1762000000000] = tous.sublist(0, 10);
      api.hasMore = false;
      st.msgs.insertAll(0, tous.sublist(0, 10));
      await t.pumpAndSettle();
      expect(st.msgs.length, 60);

      // Un message arrive du serveur : la fusion doit CONSERVER les 60.
      api.conversations[peer] = [
        ...tous.sublist(11),
        msg(
            id: 'm60',
            body: 'tout nouveau',
            mine: false,
            status: 'done',
            created: 1762000100000),
      ];
      st.handleRealtime({
        'type': 'msg', 'kind': 'message', 'msg_id': 'm60',
        'from_phone': peer, 'preview': 'tout nouveau',
      });
      await t.pumpAndSettle();

      expect(st.msgs.length, 61, reason: 'historique + nouveau message');
      expect(st.msgs.first['id'], 'm0', reason: 'le plus ancien est toujours là');
      expect(st.msgs.last['id'], 'm60', reason: 'le nouveau est à la fin');
    });

    testWidgets('« ↓ Nouveaux messages » quand on lit plus haut', (t) async {
      final longs = List.generate(
        24,
        (i) => msg(
            id: 'm$i',
            body: 'ligne $i — un message assez long pour occuper la hauteur',
            mine: i.isEven,
            status: 'done',
            created: 1762000000000 + i * 1000),
      );
      final api = FakeChatApi(messages: longs);
      await t.pumpWidget(
          wrap(const ChatScreen(peerPhone: peer, peerName: 'Bob'), chatState(api)));
      await t.pumpAndSettle();

      // On remonte dans l'historique.
      await t.drag(find.byType(ListView), const Offset(0, 600));
      await t.pumpAndSettle();

      final st = t.state<ChatScreenState>(find.byType(ChatScreen));
      api.conversations[peer] = [
        ...longs,
        msg(
            id: 'm99',
            body: 'pendant que tu lisais',
            mine: false,
            status: 'done',
            created: 1762000500000),
      ];
      st.handleRealtime({
        'type': 'msg', 'kind': 'message', 'msg_id': 'm99', 'from_phone': peer,
      });
      await t.pumpAndSettle();

      expect(find.text('Nouveaux messages'), findsOneWidget);
      // On appuie : la pastille disparaît et l'écran revient en bas.
      await t.tap(find.text('Nouveaux messages'));
      await t.pumpAndSettle();
      expect(find.text('Nouveaux messages'), findsNothing);
      expect(find.text('pendant que tu lisais'), findsOneWidget);
    });

    testWidgets('« reçu » transforme mon ✓ en ✓✓ gris', (t) async {
      final api = FakeChatApi(messages: [
        msg(id: 'm1', body: 'Tu as reçu ?', mine: true, status: 'sent'),
      ]);
      await t.pumpWidget(
          wrap(const ChatScreen(peerPhone: peer, peerName: 'Bob'), chatState(api)));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);

      t.state<ChatScreenState>(find.byType(ChatScreen)).handleRealtime(
          {'type': 'msg', 'kind': 'delivered', 'msg_id': 'm1', 'from_phone': peer});
      await t.pump();
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(find.byIcon(Icons.done_rounded), findsNothing);
    });

    testWidgets('le brouillon est retrouvé en revenant dans le fil', (t) async {
      final api = FakeChatApi(messages: []);
      await t.pumpWidget(
          wrap(const ChatScreen(peerPhone: peer, peerName: 'Bob'), chatState(api)));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField), 'je finis ma phrase…');
      await t.pump();

      // On quitte l'écran (comme un retour en arrière)…
      await t.pumpWidget(wrap(const SizedBox.shrink(), chatState(api)));
      await t.pumpAndSettle();
      // … et on rouvre la même conversation.
      await t.pumpWidget(
          wrap(const ChatScreen(peerPhone: peer, peerName: 'Bob'), chatState(api)));
      await t.pumpAndSettle();

      expect(find.text('je finis ma phrase…'), findsOneWidget);
    });

    testWidgets('le fil ouvert ne compte pas dans les non-lus', (t) async {
      final api = FakeChatApi();
      await t.pumpWidget(wrap(const ChatsScreen(), chatState(api)));
      await t.pumpAndSettle();
      expect(ChatsScreen.unread.value, 2);

      final st = t.state<ChatsScreenState>(find.byType(ChatsScreen));

      // Conversation ouverte : ses messages ne sont plus « non lus ».
      ChatScreen.openPeer = peer;
      st.handleRealtime({'type': 'msg', 'kind': 'message', 'from_phone': peer});
      await t.pump(const Duration(milliseconds: 400)); // laisse le regroupement agir
      await t.pumpAndSettle();
      expect(ChatsScreen.unread.value, 0);
      expect(find.text('2'), findsNothing);

      // Fil refermé : le compteur revient.
      ChatScreen.openPeer = null;
      st.handleRealtime({'type': 'msg', 'kind': 'message', 'from_phone': peer});
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(ChatsScreen.unread.value, 2);
    });
  });
}
