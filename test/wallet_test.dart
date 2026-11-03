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
    expect(find.text(L10n.t('low_credit')), findsNothing);

    await t.pumpWidget(
        enveloppe(const HomeScreen(), etat(FakeApi(), soldeCents: 40)));
    await t.pumpAndSettle();
    expect(find.text(L10n.t('low_credit')), findsOneWidget);
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
}
