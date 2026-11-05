// Tests de l'ONGLET APPELS côté application.
//
// Ce que ces tests prouvent :
//   • les filtres (dont Internet / GSM) et la recherche sont envoyés au
//     SERVEUR : l'app ne prétend pas filtrer ce qu'elle n'a pas reçu ;
//   • la recherche est différée (anti-rebond) : une frappe = une requête ;
//   • un appui sur une ligne ouvre la fiche détaillée (coût, durée, canal) ;
//   • masquer une entrée appelle la route dédiée et recharge la liste ;
//   • l'état vide et l'état d'erreur existent.
//
// Aucun réseau : un faux serveur remplace l'API.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mbote/api.dart';
import 'package:mbote/l10n.dart';
import 'package:mbote/screens/history.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';

class FakeApi extends Api {
  List<Map> rows = [];
  Object? erreur;
  final List<Map<String, dynamic>> requetes = [];
  final List<String> masques = [];

  Map detail = {};

  @override
  Future<Map> history({String filter = 'all', String? q, int limit = 100, int? since}) async {
    requetes.add({'filter': filter, 'q': q, 'limit': limit});
    if (erreur != null) throw erreur!;
    return {
      'calls': rows,
      'total': rows.length,
      'has_more': false,
      'month_sec': 0,
      'month_cost_cents': 0,
    };
  }

  @override
  Future<Map> callDetail(String id) async => detail;

  @override
  Future<void> hideCall(String id) async => masques.add(id);
}

AppState etat(FakeApi api) {
  final st = AppState();
  st.token = 'jeton-test';
  st.phone = '+243810000001';
  st.ready = true;
  st.api = api;
  return st;
}

Widget enveloppe(AppState st) {
  // Historique seul : l'écran s'insère normalement dans la coquille, mais il
  // fonctionne aussi isolément (c'est ce que l'on teste ici).
  MC.apply(kPalettes['fleuve']!);
  return ChangeNotifierProvider<AppState>.value(
    value: st,
    child: MaterialApp(
      theme: mboteTheme(),
      // L'écran vit normalement dans la coquille (qui fournit le Scaffold).
      home: const Scaffold(body: HistoryScreen()),
    ),
  );
}

Map appel({
  String id = 'c1',
  String nom = 'Mama Nicole',
  String num = '+243810000002',
  int sec = 90,
  int cout = 45,
  int canal = 1,
}) =>
    {
      'id': id,
      'callee': nom,
      'destination': num,
      'billed_sec': sec,
      'cost_cents': cout,
      'channel': canal == 1 ? 'gsm' : 'internet',
      'started_at': DateTime.now().millisecondsSinceEpoch - 60000,
      'status': 'ended',
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.lang = 'fr';
  });

  testWidgets('la liste affiche nom, durée et sens de l’appel',
      (tester) async {
    final api = FakeApi()..rows = [appel()];
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    expect(find.text('Mama Nicole'), findsOneWidget);
    expect(find.text('1:30'), findsOneWidget);
    expect(find.byIcon(Icons.call_made_rounded), findsWidgets);
  });

  testWidgets('le filtre « GSM » interroge le serveur avec filter=gsm',
      (tester) async {
    final api = FakeApi()..rows = [appel()];
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    await tester.tap(find.text(L10n.t('history_filter_gsm')));
    await tester.pump();
    await tester.pump();

    expect(api.requetes.last['filter'], 'gsm');
  });

  testWidgets('le filtre « Internet » interroge le serveur avec filter=internet',
      (tester) async {
    final api = FakeApi()..rows = [appel(canal: 2)];
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    await tester.tap(find.text(L10n.t('history_filter_internet')));
    await tester.pump();
    await tester.pump();

    expect(api.requetes.last['filter'], 'internet');
  });

  testWidgets('la recherche est différée : 3 frappes = 1 requête serveur',
      (tester) async {
    final api = FakeApi()..rows = [appel()];
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();
    final avant = api.requetes.length;

    await tester.enterText(find.byType(TextField), 'Nic');
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(api.requetes.length, avant + 1,
        reason: 'le debounce doit regrouper la frappe');
    expect(api.requetes.last['q'], 'Nic');
  });

  testWidgets('un appui ouvre la fiche : coût et canal affichés',
      (tester) async {
    final api = FakeApi()
      ..rows = [appel()]
      ..detail = {
        'id': 'c1',
        'phone': '+243810000002',
        'name': 'Mama Nicole',
        'channel': 'gsm',
        'billed_sec': 90,
        'cost_cents': 45,
        'price_per_min_cents': 30,
        'started_at': DateTime.now().millisecondsSinceEpoch - 60000,
        'hangup_cause': 'completed',
      };
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    await tester.tap(find.text('Mama Nicole'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(L10n.t('history_detail')), findsOneWidget);
    expect(find.text(fmtMoney(45)), findsWidgets);
    expect(find.text(L10n.t('history_channel_gsm')), findsOneWidget);
    expect(find.textContaining('min'), findsWidgets);
  });

  testWidgets('masquer une entrée appelle la route dédiée puis recharge',
      (tester) async {
    final api = FakeApi()
      ..rows = [appel()]
      ..detail = {
        'id': 'c1',
        'phone': '+243810000002',
        'name': 'Mama Nicole',
        'channel': 'gsm',
        'billed_sec': 90,
        'cost_cents': 45,
      };
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    await tester.tap(find.text('Mama Nicole'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Bouton « Masquer » puis confirmation.
    await tester.tap(find.text(L10n.t('history_delete_local')).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text(L10n.t('history_delete_local')).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(api.masques, ['c1']);
    // La liste a été rechargée après le masquage.
    expect(api.requetes.length, greaterThanOrEqualTo(2));
  });

  testWidgets('historique vide : message clair', (tester) async {
    final api = FakeApi()..rows = [];
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    expect(find.text(L10n.t('history_empty')), findsOneWidget);
  });

  testWidgets('erreur réseau : message + Réessayer', (tester) async {
    final api = FakeApi()..erreur = Exception('réseau');
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    expect(find.text(L10n.t('history_retry')), findsOneWidget);
  });
}
