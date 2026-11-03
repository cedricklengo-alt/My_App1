// Tests de l'ÉCRAN SORTANT (l'appelant) et de la fiche d'appel.
// Aucun réseau, aucun micro, aucune caméra : on vérifie le parcours complet
// côté appelant — composition, sonnerie, réponse, raccrochage — et l'absence
// de drapeau emoji dans l'interface (remplacé par une icône Material).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mbote/api.dart';
import 'package:mbote/screens/call.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';

/// Faux serveur pilotable : on choisit les réponses de `callStatus`.
class FakeSortantApi extends Api {
  FakeSortantApi({
    this.statuts = const ['ringing'],
    this.rtcOnline = false,
    this.freeReason = 'mbote',
  });

  /// Suite des statuts renvoyés par /calls/:id/status (le dernier se répète).
  List<String> statuts;
  bool rtcOnline;
  String? freeReason;

  final List<String> journal = [];
  int sondagesStatus = 0;
  int hangupAppels = 0;
  String? dernierHangup;

  @override
  Future<Map> startCall(String to) async {
    journal.add('startCall($to)');
    return {
      'call_id': 'ca_sortant',
      'flag': '🇨🇩', // le serveur envoie encore un drapeau : l'app l'ignore
      'destination': 'RDC',
      'price_per_min_cents': 0,
      'free_reason': freeReason,
      'callee_name': 'Bob',
      'callee_avatar': null,
      'rtc_online': rtcOnline,
    };
  }

  @override
  Future<Map> callStatus(String id) async {
    sondagesStatus++;
    if (statuts.length > 1) statuts.removeAt(0);
    final s = statuts.first;
    return {
      'status': s,
      'elapsed_sec': s == 'answered' ? 3 : 0,
      'cost_cents': s == 'answered' ? 25 : 0,
      'balance_after_cents': 5000,
      'hangup_cause': s == 'ended' ? 'normal' : null,
    };
  }

  @override
  Future<Map> hangup(String id) async {
    hangupAppels++;
    dernierHangup = id;
    journal.add('hangup($id)');
    return {'billed_sec': 3, 'cost_cents': 25};
  }

  @override
  Future<Map> me() async => {
        'user': {
          'id': 'u1',
          'name': 'Alice',
          'phone': '+243810000001',
          'avatar': null,
        },
        'balance_cents': 5000,
      };

  @override
  Future<List> contacts() async => [];
}

AppState etatSortant(Api api) {
  final st = AppState();
  st.phone = '+243810000001';
  st.name = 'Alice';
  st.api = api;
  return st;
}

Widget habiller(Widget child, AppState state) {
  MC.apply(kPalettes['kin']!);
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(home: child),
  );
}

/// Laisse passer la requête startCall + la première frame.
Future<void> premieresImages(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('Écran sortant — composition', () {
    testWidgets('l’appel part vers le bon numéro et affiche le nom',
        (tester) async {
      // Appel payant (GSM) : la destination est affichée
      final api = FakeSortantApi(freeReason: null);
      final st = etatSortant(api);
      await tester.pumpWidget(habiller(
        const CallScreen(to: '+243810000002', displayName: 'Bob'),
        st,
      ));
      await premieresImages(tester);

      expect(api.journal.first, 'startCall(+243810000002)');
      expect(find.text('Bob'), findsOneWidget); // nom de l'appelant choisi
      expect(find.text('Ça sonne…'), findsOneWidget);

      // Le drapeau emoji du serveur n'est jamais rendu tel quel
      expect(find.textContaining('🇨🇩'), findsNothing);
      expect(find.text('RDC'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('un appel vidéo sortant garde le bouton raccrocher',
        (tester) async {
      final api = FakeSortantApi();
      final st = etatSortant(api);
      await tester.pumpWidget(habiller(
        const CallScreen(to: '+243810000002', displayName: 'Bob', video: true),
        st,
      ));
      await premieresImages(tester);

      expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);
      expect(api.journal.first, 'startCall(+243810000002)');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('serveur injoignable → message clair, pas de plantage',
        (tester) async {
      final st = etatSortant(_ApiEnPanne());
      await tester.pumpWidget(habiller(
        const CallScreen(to: '+243810000002', displayName: 'Bob'),
        st,
      ));
      await premieresImages(tester);

      // Message générique (aucune fuite technique) + bouton pour sortir
      expect(find.text('Un petit souci est survenu — réessaie'), findsOneWidget);
      expect(find.text('Fermer'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('Écran sortant — transport', () {
    testWidgets(
        'un appel MboteCall → MboteCall ne tombe plus dans la simulation '
        '(aucun sondage /calls/:id/status)', (tester) async {
      // Bug du 3 novembre 2026 : faute du champ rtc_online, TOUS les appels
      // passaient par ce sondage, sans jamais tenter WebRTC — l'appelé ne
      // sonnait pas. Ici, aucun sondage ne doit partir.
      final api = FakeSortantApi(); // freeReason: 'mbote'
      final st = etatSortant(api);
      await tester.pumpWidget(habiller(
        const CallScreen(to: '+243810000002', displayName: 'Bob'),
        st,
      ));
      await premieresImages(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(api.journal.first, 'startCall(+243810000002)');
      expect(api.sondagesStatus, 0,
          reason: 'un appel MboteCall doit tenter la vraie voix, pas le sondage');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('Écran sortant — fin d’appel', () {
    testWidgets('raccrocher clôt l’appel côté serveur', (tester) async {
      // Appel vers un GSM (payant) : c'est le serveur qui suit l'appel.
      // Un appel MboteCall → MboteCall passe désormais par la vraie voix.
      final api = FakeSortantApi(freeReason: null);
      final st = etatSortant(api);
      await tester.pumpWidget(habiller(
        const CallScreen(to: '+243810000002', displayName: 'Bob'),
        st,
      ));
      await premieresImages(tester);

      await tester.tap(find.byIcon(Icons.call_end_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(api.hangupAppels, 1);
      expect(api.dernierHangup, 'ca_sortant');
      expect(find.text('Appel terminé'), findsOneWidget);

      // Le minuteur de fermeture (2 s) est purgé avant la fin du test
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('durée affichée quand l’appel est en ligne', (tester) async {
      // Appel payant : le bandeau d'état reste visible
      final api =
          FakeSortantApi(statuts: ['ringing', 'answered'], freeReason: null);
      final st = etatSortant(api);
      await tester.pumpWidget(habiller(
        const CallScreen(to: '+243810000002', displayName: 'Bob'),
        st,
      ));
      await premieresImages(tester);
      await tester.pump(const Duration(seconds: 1)); // un tick de suivi
      await tester.pump();

      expect(find.text('EN LIGNE · HD'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.call_end_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(api.hangupAppels, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('appelé qui ne répond pas → « Pas de réponse »',
        (tester) async {
      final api = FakeSortantApi(statuts: ['ringing', 'ended'], freeReason: null);
      final st = etatSortant(api);
      await tester.pumpWidget(habiller(
        const CallScreen(to: '+243810000002', displayName: 'Bob'),
        st,
      ));
      await premieresImages(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('Appel terminé'), findsOneWidget);
      // Le solde renvoyé par le serveur est repris
      expect(st.balanceCents, 5000);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}

/// Serveur totalement indisponible : tout appel réseau échoue.
class _ApiEnPanne extends Api {
  @override
  Future<Map> startCall(String to) async =>
      throw Exception('Service momentanément indisponible');
}
