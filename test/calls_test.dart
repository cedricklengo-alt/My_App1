// Tests des APPELS côté application : appels vidéo, appels de groupe et
// fiche d'appel. Aucun micro, aucune caméra, aucun réseau : on vérifie la
// logique (grille des participants, états, messages) et l'interface.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mbote/api.dart';
import 'package:mbote/group_call.dart';
import 'package:mbote/screens/call.dart';
import 'package:mbote/screens/call_sheet.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';

/// Faux serveur : répond aux points d'entrée utilisés par l'écran d'appel.
class FakeCallApi extends Api {
  final List<String> calls = [];
  bool groupStarted = false;
  int? groupDuration;

  @override
  Future<Map> startCall(String to) async {
    calls.add('startCall($to)');
    return {
      'call_id': 'ca_test',
      'flag': '🇨🇩',
      'destination': 'RDC',
      'price_per_min_cents': 0,
      'free_reason': 'mbote',
      'callee_name': 'Bob',
      'callee_avatar': null,
      'rtc_online': false, // pas de WebRTC en test : mode « sonnerie »
    };
  }

  @override
  Future<Map> callStatus(String id) async => {
        'status': 'ringing',
        'elapsed_sec': 0,
        'cost_cents': 0,
        'balance_after_cents': 0,
      };

  @override
  Future<Map> hangup(String id) async => {'billed_sec': 0, 'cost_cents': 0};

  @override
  Future<Map> startGroupCall(String callId) async {
    groupStarted = true;
    return {'ok': true};
  }

  @override
  Future<Map> endGroupCall(String callId, int durationSec) async {
    groupDuration = durationSec;
    return {'ok': true};
  }
}

AppState callState() {
  final st = AppState();
  st.phone = '+243810000001';
  st.name = 'Alice';
  st.api = FakeCallApi();
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
  group('GroupCallSession — tenue de la grille', () {
    late GroupCallSession s;

    setUp(() {
      s = GroupCallSession(
        callId: 'g1',
        myPhone: '+243810000001',
        myName: 'Alice',
        video: true,
      );
    });

    tearDown(() => s.dispose());

    test('les messages d’une autre salle sont ignorés', () async {
      await s.handle({
        'type': 'group_peer_joined',
        'call_id': 'autre',
        'from': '+243999',
      });
      expect(s.peers, isEmpty);
    });

    test('un participant qui arrive est ajouté avec son nom', () async {
      await s.handle({
        'type': 'group_peer_joined',
        'call_id': 'g1',
        'from': '+243810000002',
        'from_name': 'Bob',
      });
      expect(s.peers.length, 1);
      expect(s.peers['+243810000002']!.name, 'Bob');
      expect(s.peers['+243810000002']!.label, 'Bob');
      expect(s.count, 2); // moi + Bob
    });

    test('moi-même ne devient jamais un participant', () async {
      await s.handle({
        'type': 'group_peer_joined',
        'call_id': 'g1',
        'from': '+243810000001',
      });
      expect(s.peers, isEmpty);
    });

    test('micro coupé et caméra coupée sont reflétés', () async {
      await s.handle({
        'type': 'group_peer_joined',
        'call_id': 'g1',
        'from': '+243810000002',
        'from_name': 'Bob',
      });
      await s.handle({
        'type': 'group_mute',
        'call_id': 'g1',
        'from': '+243810000002',
        'muted': true,
        'video': false,
      });
      final bob = s.peers['+243810000002']!;
      expect(bob.muted, isTrue);
      expect(bob.videoOff, isTrue);
    });

    test('un participant qui part quitte la grille', () async {
      await s.handle({
        'type': 'group_peer_joined',
        'call_id': 'g1',
        'from': '+243810000002',
      });
      await s.handle({
        'type': 'group_peer_left',
        'call_id': 'g1',
        'from': '+243810000002',
      });
      expect(s.peers, isEmpty);
    });

    test('salle pleine → message clair, pas de plantage', () async {
      await s.handle({
        'type': 'group_error',
        'call_id': 'g1',
        'reason': 'room_full',
      });
      expect(s.error, contains('pleine'));
    });

    test('invitation reçue → on rejoint la salle', () async {
      await s.handle({
        'type': 'group_invite',
        'call_id': 'g1',
        'from': '+243810000002',
      });
      expect(s.joined, isTrue);
    });
  });

  group('Écran d’appel individuel', () {
    testWidgets('appel audio : commandes micro / haut-parleur', (tester) async {
      final st = callState();
      await tester.pumpWidget(wrap(
        const CallScreen(to: '+243810000002', displayName: 'Bob'),
        st,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
      expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);
      // Aucune caméra sur un appel audio
      expect(find.byIcon(Icons.videocam_rounded), findsNothing);

      await tester.pumpWidget(const SizedBox()); // libère les minuteurs
      await tester.pump();
    });

    testWidgets('appel vidéo : zone vidéo + commandes caméra', (tester) async {
      final st = callState();
      await tester.pumpWidget(wrap(
        const CallScreen(to: '+243810000002', displayName: 'Bob', video: true),
        st,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // La zone vidéo remplace l'avatar rond
      expect(find.text('En attente de sa caméra…'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_rounded), findsOneWidget); // couper
      expect(find.byIcon(Icons.flip_camera_ios_rounded), findsOneWidget);
      expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);

      // Couper la caméra change l'état et affiche le badge
      await tester.tap(find.byIcon(Icons.videocam_rounded));
      await tester.pump();
      expect(find.text('Caméra coupée'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('un appel vidéo reçu s’ouvre en vidéo', (tester) async {
      final st = callState();
      await tester.pumpWidget(wrap(
        const CallScreen(
          to: '+243810000002',
          displayName: 'Bob',
          // L'appelant a demandé la vidéo : c'est l'offre qui fait foi.
          incomingOffer: {
            'call_id': 'ca_in',
            'from': '+243810000002',
            'from_name': 'Bob',
            'video': true,
            'sdp': {'type': 'offer', 'sdp': 'x'},
          },
        ),
        st,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Connexion vidéo…'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('Fiche d’appel', () {
    testWidgets('propose audio, vidéo et groupe', (tester) async {
      final st = callState();
      await tester.pumpWidget(wrap(
        Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () =>
                  showCallModeSheet(ctx, '+243810000002', name: 'Bob'),
              child: const Text('Appeler'),
            ),
          ),
        ),
        st,
      ));
      await tester.tap(find.text('Appeler'));
      await tester.pumpAndSettle();

      expect(find.text('Appel audio'), findsOneWidget);
      expect(find.text('Appel vidéo'), findsOneWidget);
      expect(find.text('Appel de groupe'), findsOneWidget);
      expect(find.text('Copier le numéro'), findsOneWidget);
    });
  });
}
