// Tests du PORTEFEUILLE côté application (écran d'accueil du solde).
//
// Ce que l'utilisateur voit vraiment :
//  • son solde, en gros et au bon format ;
//  • la carte solde est un aplat de sable du thème, pas un dégradé ;
//  • « Recharger » ouvre l'écran de recharge ;
//  • l'alerte de crédit bas n'apparaît que sous 1 $ ;
//  • les promotions du serveur sont affichées.
//
// Aucun réseau : un faux serveur remplace l'API.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mbote/api.dart';
import 'package:mbote/design.dart';
import 'package:mbote/l10n.dart';
import 'package:mbote/screens/home.dart';
import 'package:mbote/screens/topup.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';

/// Faux serveur : uniquement ce que l'écran du portefeuille appelle.
class FakeApi extends Api {
  List promosRows = [];
  int promoAppels = 0;

  /// Résumé renvoyé par `/wallet/summary`. `null` = serveur muet : l'écran ne
  /// doit alors afficher AUCUN chiffre inventé.
  Map? resume;
  Object? erreurResume;
  int resumeAppels = 0;

  @override
  Future<Map> walletSummary() async {
    resumeAppels++;
    if (erreurResume != null) throw erreurResume!;
    return resume ??
        {
          'balance_cents': 1250,
          'currency': 'USD',
          'low_balance': false,
          'threshold_cents': 100,
          'today_cents': 0,
          'month_cents': 0,
          'month_calls_cents': 0,
          'month_sms_cents': 0,
          'month_topup_cents': 0,
          'month_seconds': 0,
          'transactions_count': 0,
        };
  }

  @override
  Future<List> promos() async {
    promoAppels++;
    return promosRows;
  }
}

AppState etat(FakeApi api, {int soldeCents = 1250}) {
  final st = AppState();
  st.token = 'jeton-test';
  st.name = 'Alice Mbote';
  st.phone = '+243810000001';
  st.balanceCents = soldeCents;
  st.ready = true;
  st.api = api;
  return st;
}

Widget enveloppe(Widget enfant, AppState st) {
  MC.apply(kPalettes['fleuve']!);
  return ChangeNotifierProvider<AppState>.value(
    value: st,
    child: MaterialApp(theme: mboteTheme(), home: Scaffold(body: enfant)),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.lang = 'fr';
  });

  testWidgets('le solde est affiché en gros, au format monétaire', (t) async {
    await t.pumpWidget(enveloppe(const HomeScreen(), etat(FakeApi())));
    await t.pumpAndSettle();

    expect(find.text(fmtMoney(1250)), findsOneWidget);
    final montant = t.widget<Text>(find.text(fmtMoney(1250)));
    // C'est le plus gros texte de l'écran : le chiffre clé de l'écran.
    expect(montant.style?.fontSize, Tx.display);
    expect(montant.style?.color, MC.onAccent);
    // Chiffres à largeur fixe : le montant ne « danse » pas quand il change.
    expect(montant.style?.fontFeatures,
        const [FontFeature.tabularFigures()]);
  });

  testWidgets('la carte solde est un aplat de sable, sans dégradé ni ombre',
      (t) async {
    await t.pumpWidget(enveloppe(const HomeScreen(), etat(FakeApi())));
    await t.pumpAndSettle();

    // On retrouve le conteneur qui porte le montant et on lit sa décoration.
    final carte = t.widget<Container>(
      find
          .ancestor(
            of: find.text(fmtMoney(1250)),
            matching: find.byType(Container),
          )
          .last,
    );
    final deco = carte.decoration as BoxDecoration;
    expect(deco.color, MC.soleil, reason: 'aplat de sable de la palette');
    expect(deco.gradient, isNull, reason: 'plus de dégradé sur la carte solde');
    expect(deco.boxShadow, isNull, reason: 'identité sans ombre portée');
    expect(deco.borderRadius, BorderRadius.circular(Rd.lg));
  });

  testWidgets('« Recharger » ouvre l’écran de recharge', (t) async {
    await t.pumpWidget(enveloppe(const HomeScreen(), etat(FakeApi())));
    await t.pumpAndSettle();

    expect(find.text(L10n.t('topup')), findsOneWidget);
    await t.tap(find.text(L10n.t('topup')));
    await t.pumpAndSettle();
    expect(find.byType(TopupScreen), findsOneWidget);
  });

  testWidgets(r'l’alerte de crédit bas n’apparaît que sous 1 $', (t) async {
    await t.pumpWidget(
        enveloppe(const HomeScreen(), etat(FakeApi(), soldeCents: 500)));
    await t.pumpAndSettle();
    // Nouveau libellé (identité « Fleuve Congo ») : titre + explication.
    expect(find.text(L10n.t('wallet_low_balance_title')), findsNothing);

    await t.pumpWidget(
        enveloppe(const HomeScreen(), etat(FakeApi(), soldeCents: 40)));
    await t.pumpAndSettle();
    expect(find.text(L10n.t('wallet_low_balance_title')), findsOneWidget);
    expect(find.text(L10n.t('wallet_low_balance_body')), findsOneWidget);
  });

  testWidgets('les promotions du serveur sont affichées', (t) async {
    final api = FakeApi()..promosRows = [
      {'title': 'Happy Hour —50 %'}
    ];
    await t.pumpWidget(enveloppe(const HomeScreen(), etat(api)));
    await t.pumpAndSettle();

    expect(api.promoAppels, 1);
    expect(find.textContaining('Happy Hour'), findsOneWidget);
  });

  testWidgets('titres de section : jamais plus petits que 11 px', (t) async {
    await t.pumpWidget(enveloppe(const HomeScreen(), etat(FakeApi())));
    await t.pumpAndSettle();

    // On balaie tous les textes de l'écran : aucun n'est sous le plancher.
    for (final widget in t.widgetList<Text>(find.byType(Text))) {
      final taille = widget.style?.fontSize;
      if (taille != null) {
        expect(taille, greaterThanOrEqualTo(Tx.minimum),
            reason: 'texte trop petit : « ${widget.data} » à $taille px');
      }
    }
  });

  group('Résumé du portefeuille (données serveur)', () {
    testWidgets('dépenses du jour et du mois affichées telles quelles',
        (t) async {
      final api = FakeApi()
        ..resume = {
          'balance_cents': 1250,
          'currency': 'USD',
          'low_balance': false,
          'today_cents': 320,
          'month_cents': 2400,
          'month_calls_cents': 1500,
          'month_sms_cents': 140,
          'transactions_count': 17,
        };
      await t.pumpWidget(enveloppe(const HomeScreen(), etat(api)));
      await t.pumpAndSettle();

      expect(api.resumeAppels, greaterThanOrEqualTo(1));
      expect(find.text(fmtMoney(320)), findsOneWidget); // aujourd'hui
      expect(find.text(fmtMoney(1500)), findsOneWidget); // appels du mois
      expect(find.text(fmtMoney(140)), findsOneWidget); // SMS du mois
      expect(find.textContaining(fmtMoney(2400)), findsOneWidget); // total mois
    });

    testWidgets('l’alerte de crédit bas suit le drapeau du serveur',
        (t) async {
      final api = FakeApi()
        ..resume = {'balance_cents': 900, 'low_balance': true, 'today_cents': 0};
      await t.pumpWidget(enveloppe(const HomeScreen(), etat(api, soldeCents: 900)));
      await t.pumpAndSettle();

      // 9 $ en poche mais le serveur signale un seuil atteint : on l'écoute.
      expect(find.text(L10n.t('wallet_low_balance_title')), findsOneWidget);
    });

    testWidgets('résumé indisponible : message, aucun chiffre trompeur',
        (t) async {
      final api = FakeApi()..erreurResume = Exception('réseau');
      await t.pumpWidget(enveloppe(const HomeScreen(), etat(api)));
      await t.pumpAndSettle();

      expect(find.text(L10n.t('wallet_summary_unavailable')), findsOneWidget);
      expect(find.text(fmtMoney(0)), findsNothing,
          reason: 'mieux vaut aucun chiffre qu’un zéro faux');
    });

    testWidgets('« Boutique » et « Mes forfaits » sont accessibles',
        (t) async {
      await t.pumpWidget(enveloppe(const HomeScreen(), etat(FakeApi())));
      await t.pumpAndSettle();

      expect(find.text(L10n.t('wallet_shop')), findsOneWidget);
      expect(find.text(L10n.t('wallet_my_plans')), findsOneWidget);
    });
  });
}
