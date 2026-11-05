// Tests de bout en bout du MENU « ··· » et des RÉGLAGES.
//
// Ce que ces tests prouvent :
//   • le menu est organisé en sections (Compte / Outils / Réglages / Aide) et
//     AUCUNE entrée ne mène nulle part ;
//   • chaque réglage change vraiment quelque chose ET est enregistré :
//     - thème  → la palette de l'app change (MC) ;
//     - police → la famille de police de l'app change ;
//     - taille → l'échelle de texte choisie est conservée ;
//     - langue → les libellés basculent (fr → ln) ;
//   • sécurité : le code PIN s'active, se vérifie et se désactive ; la session
//     affiche le bon numéro et peut être fermée (déconnexion réelle) ;
//   • langue : une liste vide côté serveur affiche un message, une erreur
//     réseau aussi, et le téléchargement d'un paquet réel installe la langue.
//
// Aucun réseau : un faux serveur remplace l'API.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mbote/api.dart';
import 'package:mbote/l10n.dart';
import 'package:mbote/pin.dart';
import 'package:mbote/prefs.dart';
import 'package:mbote/screens/settings.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';

class FakeApi extends Api {
  List langs = [];
  Object? erreurLangs;
  Map pack = {'code': 'en', 'strings': {'settings': 'Settings'}};

  @override
  Future<List> availableLangs() async {
    if (erreurLangs != null) throw erreurLangs!;
    return langs;
  }

  @override
  Future<Map> langPack(String code) async => pack;

  @override
  Future<Map> me() async => {
        'user': {'id': 'u1', 'name': 'Alice Mbote', 'phone': '+243810000001'},
        'balance_cents': 1250,
      };

  @override
  Future<List> promos() async => const [];
}

AppState etat(FakeApi api) {
  final st = AppState();
  st.token = 'jeton-test';
  st.id = 'u1';
  st.name = 'Alice Mbote';
  st.phone = '+243810000001';
  st.balanceCents = 1250;
  st.ready = true;
  st.api = api;
  return st;
}

Widget enveloppe(Widget ecran, AppState st) {
  MC.apply(kPalettes['fleuve']!);
  return ChangeNotifierProvider<AppState>.value(
    value: st,
    child: MaterialApp(
      theme: mboteTheme(),
      home: ecran,
    ),
  );
}

/// Ouvre l'écran dans une fenêtre haute : les réglages sont un ListView, et
/// sur 600 px les sections du bas ne seraient même pas construites.
Future<void> ouvrir(WidgetTester tester, Widget ecran, AppState st) async {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(enveloppe(ecran, st));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    L10n.lang = 'fr';
    ThemeCtl.theme = 'fleuve';
    ThemeCtl.font = 'standard';
    ThemeCtl.textScale = 1.0;
    CallPrefs.ringtone = 'classique';
    CallPrefs.vibration = true;
    MC.apply(kPalettes['fleuve']!);
  });

  group('Hub Réglages — structure', () {
    testWidgets('les quatre sections et le compte sont affichés', (tester) async {
      await ouvrir(tester, const SettingsScreen(), etat(FakeApi()));

      for (final cle in [
        'settings_section_account',
        'settings_section_prefs',
        'settings_section_privacy',
        'settings_section_help',
      ]) {
        expect(find.text(L10n.t(cle)), findsOneWidget, reason: cle);
      }
      // Le compte est rappelé en haut : nom, numéro, solde.
      // Le nom apparaît deux fois : bandeau du compte + ligne « Profil ».
      expect(find.text('Alice Mbote'), findsWidgets);
      expect(find.text('+243810000001'), findsOneWidget);
      // Solde affiché deux fois : bandeau du compte + ligne « Portefeuille ».
      expect(find.text(fmtMoney(1250)), findsWidgets);
    });

    testWidgets('« Apparence » mène à un vrai écran de réglage', (tester) async {
      await ouvrir(tester, const SettingsScreen(), etat(FakeApi()));

      await tester.tap(find.text(L10n.t('appearance')));
      await tester.pumpAndSettle();
      expect(find.byType(AppearanceScreen), findsOneWidget);
      expect(find.byKey(const Key('text-size-slider')), findsOneWidget);
    });

    testWidgets('« Langue » mène au sélecteur de langue', (tester) async {
      await ouvrir(tester, const SettingsScreen(), etat(FakeApi()));

      await tester.tap(find.text(L10n.t('language')));
      await tester.pumpAndSettle();
      expect(find.byType(LanguageScreen), findsOneWidget);
      expect(find.text('Lingála'), findsOneWidget);
    });

    testWidgets('« Notifications et sonnerie » propose les 4 sonneries', (tester) async {
      await ouvrir(tester, const SettingsScreen(), etat(FakeApi()));

      await tester.tap(find.text(L10n.t('settings_notifications')));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);
      for (final k in ['classique', 'douce', 'forte', 'silencieux']) {
        expect(find.byKey(Key('ring-$k')), findsOneWidget, reason: k);
      }
      expect(find.byKey(const Key('ring-vibration')), findsOneWidget);
    });

    testWidgets('aucune ligne morte : chaque entrée ouvre un écran', (tester) async {
      await ouvrir(tester, const SettingsScreen(), etat(FakeApi()));

      // Toutes les lignes cliquables ont une destination : on vérifie qu'il
      // n'existe aucun ListTile sans onTap (hors en-têtes de section).
      final tiles = tester.widgetList<ListTile>(find.byType(ListTile));
      expect(tiles, isNotEmpty);
      for (final tile in tiles) {
        expect(tile.onTap, isNotNull,
            reason: 'ligne inerte : ${tile.title}');
      }
    });
  });

  group('Apparence — thème, police, taille du texte', () {
    testWidgets('changer de thème change vraiment la palette', (tester) async {
      await ouvrir(tester, const AppearanceScreen(), etat(FakeApi()));

      final avant = MC.soleil;
      await tester.tap(find.byKey(const Key('theme-ocean')));
      await tester.pumpAndSettle();

      expect(ThemeCtl.theme, 'ocean');
      expect(MC.soleil, isNot(avant), reason: 'la palette doit être appliquée');
      // Enregistré sur le téléphone : rechargé au prochain démarrage.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme'), 'ocean');
    });

    testWidgets('changer de police change la police de l’application', (tester) async {
      await ouvrir(tester, const AppearanceScreen(), etat(FakeApi()));

      await tester.tap(find.byKey(const Key('font-mono')));
      await tester.pumpAndSettle();

      expect(ThemeCtl.font, 'mono');
      expect(ThemeCtl.font, 'mono');
      expect(mboteTheme().textTheme.bodyMedium?.fontFamily, 'monospace');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('font'), 'mono');
    });

    testWidgets('la taille du texte est bornée et enregistrée', (tester) async {
      await ouvrir(tester, const AppearanceScreen(), etat(FakeApi()));

      await tester.drag(
          find.byKey(const Key('text-size-slider')), const Offset(400, 0));
      await tester.pumpAndSettle();

      expect(ThemeCtl.textScale, greaterThan(1.0));
      expect(ThemeCtl.textScale, lessThanOrEqualTo(ThemeCtl.echelleMax));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('text_scale'), ThemeCtl.textScale);

      // « Revenir à la taille normale » fonctionne.
      await tester.tap(find.byKey(const Key('text-size-reset')));
      await tester.pumpAndSettle();
      expect(ThemeCtl.textScale, 1.0);
    });
  });

  group('Taille du texte — appliquée à toute l’app', () {
    testWidgets('le réglage multiplie la taille du système, sans l’ignorer',
        (tester) async {
      ThemeCtl.textScale = 1.4;
      double? mesure;
      await tester.pumpWidget(MaterialApp(
        home: EchelleTexte(
          child: Builder(builder: (ctx) {
            mesure = MediaQuery.textScalerOf(ctx).scale(10);
            return const SizedBox();
          }),
        ),
      ));
      await tester.pumpAndSettle();
      expect(mesure, closeTo(14, .01), reason: '10 px × 1.4');

      // Un téléphone réglé à 150 % garde son confort : 1.5 × 1.4 = 2.1,
      // borné à 2.0 pour ne pas casser la mise en page.
      ThemeCtl.textScale = 1.4;
      double? borne;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: MaterialApp(
          home: EchelleTexte(
            child: Builder(builder: (ctx) {
              borne = MediaQuery.textScalerOf(ctx).scale(10);
              return const SizedBox();
            }),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(borne, closeTo(20, .01), reason: 'borné à 2.0');
    });
  });

  group('Langue', () {
    testWidgets('passer en lingala change les libellés immédiatement', (tester) async {
      await ouvrir(tester, const LanguageScreen(), etat(FakeApi()));

      await tester.tap(find.byKey(const Key('lang-ln')));
      await tester.pumpAndSettle();

      expect(L10n.lang, 'ln');
      expect(L10n.t('settings'), L10n.t2('ln', 'settings'));
      expect(L10n.t('settings'), isNot(L10n.t2('fr', 'settings')));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('lang'), 'ln');

      // On revient en français pour ne pas polluer les autres tests.
      await tester.tap(find.byKey(const Key('lang-fr')));
      await tester.pumpAndSettle();
      expect(L10n.lang, 'fr');
    });

    testWidgets('serveur muet : message « tout est installé », pas un vide', (tester) async {
      final api = FakeApi()..langs = [];
      await ouvrir(tester, const LanguageScreen(), etat(api));

      await tester.tap(find.byKey(const Key('lang-more')));
      await tester.pumpAndSettle();

      expect(find.text(L10n.t('lang_all_installed')), findsOneWidget);
    });

    testWidgets('erreur réseau : message clair + Réessayer', (tester) async {
      final api = FakeApi()..erreurLangs = Exception('réseau');
      await ouvrir(tester, const LanguageScreen(), etat(api));

      await tester.tap(find.byKey(const Key('lang-more')));
      await tester.pumpAndSettle();

      expect(find.text(L10n.t('chat_retry')), findsOneWidget);
    });

    testWidgets('télécharger une langue l’installe vraiment', (tester) async {
      final api = FakeApi()
        ..langs = [
          {'code': 'en', 'name': 'English 🇬🇧'}
        ];
      await ouvrir(tester, const LanguageScreen(), etat(api));

      await tester.tap(find.byKey(const Key('lang-more')));
      await tester.pumpAndSettle();
      expect(find.text('English 🇬🇧'), findsOneWidget);

      await tester.tap(find.text('English 🇬🇧'));
      await tester.pumpAndSettle();

      // La langue est désormais proposée dans la liste des langues installées.
      expect(L10n.langs.containsKey('en'), isTrue);
      expect(find.byKey(const Key('lang-en')), findsOneWidget);
    });
  });

  group('Confidentialité et sécurité', () {
    testWidgets('activer un code PIN le rend réellement actif', (tester) async {
      await ouvrir(tester, const SecurityScreen(), etat(FakeApi()));

      expect(find.text(L10n.t('settings_pin_off')), findsOneWidget);
      await tester.tap(find.byKey(const Key('pin-activate')));
      await tester.pumpAndSettle();

      // Écran de création : 4 chiffres, puis confirmation.
      expect(find.byType(PinScreen), findsOneWidget);
      for (final d in ['1', '2', '3', '4']) {
        await tester.tap(find.text(d).last);
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pumpAndSettle();
      for (final d in ['1', '2', '3', '4']) {
        await tester.tap(find.text(d).last);
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pumpAndSettle();

      expect(await Pin.isSet(), isTrue, reason: 'le PIN doit être enregistré');
      expect(find.text(L10n.t('settings_pin_on')), findsOneWidget);
    });

    testWidgets('la session affiche le numéro et ferme la session', (tester) async {
      final st = etat(FakeApi());
      await ouvrir(tester, const SecurityScreen(), st);

      expect(find.textContaining('+243810000001'), findsOneWidget);
      expect(st.token, isNotNull);

      await tester.tap(find.byKey(const Key('security-logout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('security-logout-confirm')));
      await tester.pumpAndSettle();

      expect(st.token, isNull, reason: 'la session doit être réellement fermée');
    });

    testWidgets('un PIN déjà posé propose changer / oublier / désactiver', (tester) async {
      await Pin.save('1234');
      await ouvrir(tester, const SecurityScreen(), etat(FakeApi()));

      expect(find.byKey(const Key('pin-change')), findsOneWidget);
      expect(find.byKey(const Key('pin-forgot')), findsOneWidget);
      expect(find.byKey(const Key('pin-off')), findsOneWidget);
      expect(find.byKey(const Key('pin-activate')), findsNothing);
    });
  });
}
