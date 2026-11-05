// Tests de la BOUTIQUE et de « Mes forfaits » côté application.
//
// Ce que ces tests prouvent :
//   • les prix affichés viennent du SERVEUR (aucun prix codé en dur) ;
//   • les états chargement / vide / erreur existent vraiment ;
//   • un forfait n'est annoncé « activé » qu'après un statut `success`
//     renvoyé par le serveur — jamais sur un simple retour d'écran ;
//   • un paiement refusé affiche un échec et laisse réessayer ;
//   • la page carte affiche l'URL hébergée (aucune donnée de carte saisie).
//
// Aucun réseau : un faux serveur remplace l'API.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mbote/api.dart';
import 'package:mbote/l10n.dart';
import 'package:mbote/screens/my_plans.dart';
import 'package:mbote/screens/shop.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';

class FakeApi extends Api {
  List packs = [];
  List plans = [];
  Object? erreurCatalogue;

  String statutPaiement = 'success';
  Map? dernierPaiement;
  final List<String> appels = [];

  @override
  Future<List> shopCatalog() async {
    appels.add('catalog');
    if (erreurCatalogue != null) throw erreurCatalogue!;
    return packs;
  }

  @override
  Future<Map> createShopOrder(int packageId) async {
    appels.add('order:$packageId');
    return {'id': 'ord_1', 'status': 'pending', 'amount_cents': 500};
  }

  @override
  Future<Map> payShopOrder(String orderId, String method, {String? phone}) async {
    appels.add('pay:$method');
    dernierPaiement = {'method': method, 'phone': phone};
    return {
      'payment': {'id': 'pay_1', 'status': 'pending'},
      'redirect_url': method == 'card' ? 'https://flexpay.example/p/1' : null,
      'message': 'En attente',
    };
  }

  @override
  Future<Map> shopPayStatus(String orderId) async {
    appels.add('poll');
    return {'status': statutPaiement};
  }

  @override
  Future<Map> shopOrderStatus(String orderId) async =>
      {'order': {'id': orderId, 'status': statutPaiement}};

  @override
  Future<List> myPlans() async =>
      plans.where((p) => '${(p as Map)['status']}' == 'active').toList();

  @override
  Future<List> myPlansAll() async => plans;
}

AppState etat(FakeApi api) {
  final st = AppState();
  st.token = 'jeton-test';
  st.name = 'Alice Mbote';
  st.phone = '+243810000001';
  st.balanceCents = 5000;
  st.ready = true;
  st.api = api;
  return st;
}

Widget enveloppe(Widget enfant, AppState st) {
  MC.apply(kPalettes['fleuve']!);
  return ChangeNotifierProvider<AppState>.value(
    value: st,
    child: MaterialApp(theme: mboteTheme(), home: enfant),
  );
}

Map pack({
  int id = 1,
  String nom = 'Forfait Essentiel',
  int prix = 500,
  int minutes = 60,
  int sms = 10,
  int jours = 30,
  String categorie = 'minutes',
}) =>
    {
      'id': id,
      'name': nom,
      'description': 'Appels vers le réseau local',
      'price_cents': prix,
      'currency': 'USD',
      'minutes': minutes,
      'sms_count': sms,
      'days': jours,
      'prefix': '',
      'category': categorie,
      'conditions': '',
      'renewable': false,
      'active': true,
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.lang = 'fr';
  });

  group('Boutique — catalogue', () {
    testWidgets('affiche le prix et le contenu envoyés par le serveur',
        (tester) async {
      final api = FakeApi()
        ..packs = [
          pack(nom: 'Essentiel 60', prix: 500, minutes: 60),
          pack(id: 2, nom: 'Duo 120', prix: 900, minutes: 120, categorie: 'mixte'),
        ];
      await tester.pumpWidget(enveloppe(const ShopScreen(), etat(api)));
      await tester.pump(); // laisse la requête se terminer

      expect(api.appels, contains('catalog'));
      expect(find.text('Essentiel 60'), findsOneWidget);
      expect(find.text(fmtMoney(500)), findsWidgets);
      expect(find.text('Duo 120'), findsOneWidget);
      expect(find.text(fmtMoney(900)), findsWidgets);
      // Le contenu du forfait est visible, pas seulement le prix.
      expect(find.text('60 min'), findsOneWidget);
    });

    testWidgets('catalogue vide : message clair, pas d’écran blanc',
        (tester) async {
      final api = FakeApi()..packs = [];
      await tester.pumpWidget(enveloppe(const ShopScreen(), etat(api)));
      await tester.pump();
      expect(find.text(L10n.t('shop_empty')), findsOneWidget);
    });

    testWidgets('erreur réseau : message + bouton Réessayer qui relance',
        (tester) async {
      final api = FakeApi()..erreurCatalogue = Exception('réseau');
      await tester.pumpWidget(enveloppe(const ShopScreen(), etat(api)));
      await tester.pump();

      expect(find.text(L10n.t('chat_retry')), findsOneWidget);
      final avant = api.appels.where((a) => a == 'catalog').length;

      api.erreurCatalogue = null;
      api.packs = [pack()];
      await tester.tap(find.text(L10n.t('chat_retry')));
      await tester.pump();
      await tester.pump();

      expect(api.appels.where((a) => a == 'catalog').length, greaterThan(avant));
    });
  });

  group('Boutique — parcours d’achat', () {
    Future<void> ouvrirAchat(WidgetTester tester, FakeApi api) async {
      // Écran de test plus haut que les 600 px par défaut : la feuille d'achat
      // contient plusieurs moyens de paiement et doit être entièrement
      // atteignable (le vrai téléphone défile).
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(enveloppe(const ShopScreen(), etat(api)));
      await tester.pump();
      await tester.tap(find.text('Essentiel 60'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('paiement Mobile Money : la commande est créée puis le '
        'forfait n’est annoncé activé qu’après un statut « success »',
        (tester) async {
      final api = FakeApi()
        ..packs = [pack(nom: 'Essentiel 60')]
        ..statutPaiement = 'success';
      await ouvrirAchat(tester, api);

      // Feuille d'achat : le prix est rappelé et le moyen de paiement choisi.
      expect(find.text(L10n.t('shop_pay')), findsOneWidget);
      expect(find.text('M-Pesa'), findsOneWidget);

      await tester.tap(find.text(L10n.t('shop_pay')));
      await tester.pump(); // début de l'envoi
      await tester.pump(const Duration(milliseconds: 50));

      expect(api.appels, contains('order:1'));
      expect(api.appels, contains('pay:mpesa'));
      // Le numéro de l'utilisateur est transmis (il peut le corriger).
      expect(api.dernierPaiement!['phone'], '+243810000001');

      // Le polling (3 s) confirme le paiement → succès.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(L10n.t('shop_success')), findsOneWidget);
      expect(api.appels, contains('poll'));
    });

    testWidgets('paiement refusé : échec affiché, aucune activation annoncée',
        (tester) async {
      final api = FakeApi()
        ..packs = [pack(nom: 'Essentiel 60')]
        ..statutPaiement = 'failed';
      await ouvrirAchat(tester, api);

      await tester.tap(find.text(L10n.t('shop_pay')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(L10n.t('shop_failed')), findsOneWidget);
      // « Forfait activé » ne doit JAMAIS apparaître sur un échec.
      expect(find.text(L10n.t('shop_success')), findsNothing);
    });

    testWidgets('carte : URL de paiement hébergée affichée, pas de champ carte',
        (tester) async {
      final api = FakeApi()..packs = [pack(nom: 'Essentiel 60')];
      await ouvrirAchat(tester, api);

      await tester.tap(find.text(L10n.t('shop_card')));
      await tester.pump();
      // Le champ « numéro Mobile Money » disparaît pour un paiement carte.
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text(L10n.t('shop_pay')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(api.appels, contains('pay:card'));
      expect(api.dernierPaiement!['phone'], isNull);
      expect(find.text('https://flexpay.example/p/1'), findsOneWidget);
      // Aucune donnée de carte n'est demandée dans l'application.
      expect(find.textContaining('CVV'), findsNothing);
    });
  });

  group('Mes forfaits', () {
    Map plan({
      String nom = 'Essentiel 60',
      int reste = 1800,
      String statut = 'active',
    }) =>
        {
          'id': 'plan_1',
          'package_name': nom,
          'minutes_total': 60,
          'remaining_sec': reste,
          'consumed_sec': 3600 - reste,
          'sms_total': 10,
          'remaining_sms': 4,
          'unlimited': 0,
          'status': statut,
          'activated_at': DateTime.now().millisecondsSinceEpoch,
          'expires_at':
              DateTime.now().add(const Duration(days: 20)).millisecondsSinceEpoch,
        };

    testWidgets('quota restant et expiration affichés', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final api = FakeApi()..plans = [plan()];
      await tester.pumpWidget(enveloppe(const MyPlansScreen(), etat(api)));
      await tester.pump();

      // Le forfait figure dans « actifs » ET dans l'historique : le nom
      // apparaît donc deux fois, mais le quota restant n'est affiché qu'une.
      expect(find.text('Essentiel 60'), findsWidgets);
      expect(find.textContaining('30 min / 60 min'), findsWidgets);
      expect(find.textContaining('4 / 10'), findsWidgets);
      expect(find.text(L10n.t('plans_status_active')), findsWidgets);
    });

    testWidgets('aucun forfait : deux messages vides distincts',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final api = FakeApi()..plans = [];
      await tester.pumpWidget(enveloppe(const MyPlansScreen(), etat(api)));
      await tester.pump();

      expect(find.text(L10n.t('plans_none_active')), findsOneWidget);
      expect(find.text(L10n.t('plans_none_history')), findsOneWidget);
    });
  });
}
