// Tests de l'écran SMS vers le réseau GSM.
//
// Ce que ces tests prouvent :
//   • l'écran demande un DEVIS au serveur avant tout envoi ;
//   • un tarif manquant (`can_send: false`) désactive le bouton : rien ne
//     part, rien n'est débité ;
//   • un fournisseur non configuré est signalé explicitement ;
//   • la couverture par un forfait est annoncée comme telle ;
//   • un identifiant d'idempotence accompagne l'envoi (pas de double SMS).
//
// Aucun réseau : un faux serveur remplace l'API.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mbote/api.dart';
import 'package:mbote/l10n.dart';
import 'package:mbote/screens/sms_compose.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';

class FakeApi extends Api {
  Map devis = {};
  Object? erreurDevis;
  Object? erreurEnvoi;
  String? dernierClientId;
  String? dernierTexte;
  int envois = 0;

  @override
  Future<Map> smsQuote(String phone) async {
    if (erreurDevis != null) throw erreurDevis!;
    return devis;
  }

  @override
  Future<Map> sendSms(String phone, String text, {String? clientId}) async {
    if (erreurEnvoi != null) throw erreurEnvoi!;
    envois++;
    dernierClientId = clientId;
    dernierTexte = text;
    return {'message': {'id': 'sms_1', 'status': 'queued'}, 'duplicate': false};
  }
}

AppState etat(FakeApi api) {
  final st = AppState();
  st.token = 'jeton-test';
  st.phone = '+243810000001';
  st.balanceCents = 2000;
  st.ready = true;
  st.api = api;
  return st;
}

Widget enveloppe(AppState st) {
  MC.apply(kPalettes['fleuve']!);
  return ChangeNotifierProvider<AppState>.value(
    value: st,
    child: MaterialApp(
      theme: mboteTheme(),
      home: const SmsComposeScreen(phone: '+243810000009'),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.lang = 'fr';
  });

  testWidgets('affiche le prix du SMS renvoyé par le serveur', (tester) async {
    final api = FakeApi()
      ..devis = {
        'to': '+243810000009',
        'destination': 'Congo (RDC)',
        'flag': '🇨🇩',
        'sms_price_cents': 7,
        'covered_by_plan': false,
        'can_send': true,
        'provider_ready': true,
      };
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    expect(find.textContaining('${L10n.t('sms_price')} : ${fmtMoney(7)}'),
        findsOneWidget);
  });

  testWidgets('tarif manquant : le bouton reste désactivé et rien ne part',
      (tester) async {
    final api = FakeApi()
      ..devis = {
        'to': '+243810000009',
        'destination': 'Inconnu',
        'sms_price_cents': null,
        'covered_by_plan': false,
        'can_send': false,
        'reason': 'SMS_RATE_MISSING',
        'provider_ready': true,
      };
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    expect(find.text(L10n.t('sms_rate_missing')), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Test');
    await tester.pump();
    await tester.tap(find.text(L10n.t('sms_send')));
    await tester.pump();

    expect(api.envois, 0, reason: 'aucun SMS ne doit partir sans tarif');
  });

  testWidgets('fournisseur non configuré : signalé, envoi bloqué',
      (tester) async {
    final api = FakeApi()
      ..devis = {
        'to': '+243810000009',
        'sms_price_cents': 7,
        'covered_by_plan': false,
        'can_send': true,
        'provider_ready': false,
      };
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    expect(find.text(L10n.t('sms_not_configured')), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Test');
    await tester.pump();
    await tester.tap(find.text(L10n.t('sms_send')));
    await tester.pump();

    expect(api.envois, 0);
  });

  testWidgets('forfait SMS : annoncé comme couvert, sans prix affiché',
      (tester) async {
    final api = FakeApi()
      ..devis = {
        'to': '+243810000009',
        'sms_price_cents': 7,
        'covered_by_plan': true,
        'plan_id': 'plan_1',
        'can_send': true,
        'provider_ready': true,
      };
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    expect(find.text(L10n.t('sms_covered')), findsOneWidget);
    expect(find.textContaining('${L10n.t('sms_price')} :'), findsNothing);
  });

  testWidgets('envoi : texte transmis et identifiant d’idempotence présent',
      (tester) async {
    final api = FakeApi()
      ..devis = {
        'to': '+243810000009',
        'sms_price_cents': 7,
        'covered_by_plan': false,
        'can_send': true,
        'provider_ready': true,
      };
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Mbote na yo');
    await tester.pump();
    await tester.tap(find.text(L10n.t('sms_send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.envois, 1);
    expect(api.dernierTexte, 'Mbote na yo');
    expect(api.dernierClientId, isNotNull);
    expect(api.dernierClientId, isNotEmpty);
  });

  testWidgets('devis impossible (numéro invalide) : erreur affichée',
      (tester) async {
    final api = FakeApi()
      ..erreurDevis = ApiException('Numéro invalide (format +243…)')
      ;
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    expect(find.textContaining('invalide'), findsOneWidget);
  });
}
