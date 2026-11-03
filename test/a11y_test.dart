// AUDIT D'ACCESSIBILITÉ — les règles internationales, exécutées sur l'app.
//
// On utilise les **guides officiels de Flutter** (`meetsGuideline`), qui
// traduisent des normes en contrôles automatiques :
//
//  • `androidTapTargetGuideline`  → Material : cible tactile ≥ 48 × 48 dp
//  • `iOSTapTargetGuideline`      → Apple HIG : cible ≥ 44 × 44 pt
//  • `labeledTapTargetGuideline`  → WCAG 2.2 · 4.1.2 : tout élément cliquable
//                                   doit avoir un nom accessible
//  • `textContrastGuideline`      → WCAG 2.2 · 1.4.3 : texte ≥ 4,5:1
//                                   (3:1 pour le grand texte)
//
// Les écrans sont alimentés par un faux serveur : aucun réseau, aucun micro.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mbote/api.dart';
import 'package:mbote/design.dart';
import 'package:mbote/l10n.dart';
import 'package:mbote/models/post.dart';
import 'package:mbote/screens/call_sheet.dart';
import 'package:mbote/screens/chats.dart';
import 'package:mbote/screens/feed_screen.dart';
import 'package:mbote/screens/history.dart';
import 'package:mbote/screens/home.dart';
import 'package:mbote/screens/keypad.dart';
import 'package:mbote/screens/login.dart';
import 'package:mbote/screens/packages.dart';
import 'package:mbote/screens/profile.dart';
import 'package:mbote/screens/shell.dart';
import 'package:mbote/screens/topup.dart';
import 'package:mbote/state.dart';
import 'package:mbote/tabs.dart';
import 'package:mbote/theme.dart';

/// Faux serveur : le minimum pour peupler chaque écran.
class FakeApi extends Api {
  @override
  Future<List> promos() async => [
        {'title': 'Happy Hour —50 %'}
      ];

  @override
  Future<List> packages() async => const [];

  @override
  Future<List> myPackages() async => const [];

  @override
  Future<Map> wallet() async => {'balance_cents': 1250, 'month_sec': 0};

  @override
  Future<List> messageThreads() async => [
        {
          'peer_phone': '+243810000002',
          'peer_name': 'Maman',
          'last_preview': 'Mbote, na kezia na ndako',
          'last_at': 1762000000000,
          'last_mine': false,
          'last_type': 'text',
          'last_state': 'read',
          'unread': 2,
          'online': true,
        },
        {
          'peer_phone': '+243810000003',
          'peer_name': 'Papa Joseph',
          'last_preview': 'Photo · 1 image',
          'last_at': 1761990000000,
          'last_mine': true,
          'last_type': 'image',
          'last_state': 'read',
          'unread': 0,
          'online': false,
        },
      ];

  @override
  Future<FeedPage> feedPage({int? before, String? cursor}) async =>
      const FeedPage(posts: [], nextBefore: null, nextCursor: null);

  @override
  Future<List<Story>> feedStories() async => const [];
}

AppState etat(FakeApi api) {
  final st = AppState();
  st.token = 'jeton-test';
  st.name = 'Alice Mbote';
  st.phone = '+243810000001';
  st.balanceCents = 1250;
  st.ready = true;
  st.api = api;
  return st;
}

Widget enveloppe(Widget enfant, AppState st, {double echelle = 1.0}) {
  MC.apply(kPalettes['fleuve']!);
  return ChangeNotifierProvider<AppState>.value(
    value: st,
    child: MaterialApp(
      theme: mboteTheme(),
      // WCAG 2.2 · 1.4.4 : le texte doit pouvoir grossir jusqu'à 200 %
      // sans perte de contenu ni chevauchement. `echelle` simule le réglage
      // « Taille de police » d'Android / « Texte plus grand » d'iOS.
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx)
            .copyWith(textScaler: TextScaler.linear(echelle)),
        child: child!,
      ),
      home: enfant,
    ),
  );
}

/// Les quatre guides, appliqués d'un coup.
Future<void> verifierNormes(WidgetTester t, String ecran) async {
  final handle = t.ensureSemantics();
  await expectLater(t, meetsGuideline(androidTapTargetGuideline),
      reason: '$ecran — cible tactile Android ≥ 48 dp');
  await expectLater(t, meetsGuideline(iOSTapTargetGuideline),
      reason: '$ecran — cible tactile Apple ≥ 44 pt');
  await expectLater(t, meetsGuideline(labeledTapTargetGuideline),
      reason: '$ecran — nom accessible (WCAG 4.1.2)');
  await expectLater(t, meetsGuideline(textContrastGuideline),
      reason: '$ecran — contraste du texte (WCAG 1.4.3)');
  handle.dispose();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.lang = 'fr';
    ChatsScreen.unread.value = 0;
  });

  testWidgets('Portefeuille respecte les normes', (t) async {
    await t.pumpWidget(enveloppe(const HomeScreen(), etat(FakeApi())));
    await t.pumpAndSettle();
    await verifierNormes(t, 'Portefeuille');
  });

  testWidgets('Discussions respecte les normes', (t) async {
    await t.pumpWidget(
        enveloppe(const Scaffold(body: ChatsScreen()), etat(FakeApi())));
    await t.pumpAndSettle();
    await verifierNormes(t, 'Discussions');
  });

  testWidgets('Accueil (fil) respecte les normes', (t) async {
    await t.pumpWidget(
        enveloppe(const Scaffold(body: FeedScreen()), etat(FakeApi())));
    await t.pumpAndSettle();
    await verifierNormes(t, 'Accueil');
  });

  testWidgets('Appels (historique) respecte les normes', (t) async {
    await t.pumpWidget(
        enveloppe(const Scaffold(body: HistoryScreen()), etat(FakeApi())));
    await t.pumpAndSettle();
    await verifierNormes(t, 'Appels');
  });

  testWidgets('Clavier respecte les normes', (t) async {
    await t.pumpWidget(
        enveloppe(const Scaffold(body: KeypadScreen()), etat(FakeApi())));
    await t.pumpAndSettle();
    await verifierNormes(t, 'Clavier');
  });

  testWidgets('Recharge respecte les normes', (t) async {
    await t.pumpWidget(enveloppe(const TopupScreen(), etat(FakeApi())));
    await t.pumpAndSettle();
    await verifierNormes(t, 'Recharge');
  });

  testWidgets('Navigation complète (4 onglets) respecte les normes',
      (t) async {
    Tabs.reset();
    await t.pumpWidget(enveloppe(const ShellScreen(), etat(FakeApi())));
    await t.pumpAndSettle();
    await verifierNormes(t, 'Navigation');
  });

  testWidgets('Profil respecte les normes', (t) async {
    await t.pumpWidget(
        enveloppe(const Scaffold(body: ProfileScreen()), etat(FakeApi())));
    await t.pumpAndSettle();
    await verifierNormes(t, 'Profil');
  });

  testWidgets('Forfaits respecte les normes', (t) async {
    await t.pumpWidget(enveloppe(const PackagesScreen(), etat(FakeApi())));
    await t.pumpAndSettle();
    await verifierNormes(t, 'Forfaits');
  });

  testWidgets('Connexion respecte les normes', (t) async {
    await t.pumpWidget(enveloppe(const LoginScreen(), etat(FakeApi())));
    await t.pumpAndSettle();
    await verifierNormes(t, 'Connexion');
  });

  // ── Texte agrandi : le vrai test « grand caractère » ────────────────────
  // Un débordement (bandeau jaune/noir en debug) lève une exception et fait
  // échouer le test : c'est exactement ce qu'on veut détecter.
  for (final echelle in <double>[1.5, 2.0]) {
    final pct = '${(echelle * 100).round()} %';

    testWidgets('Portefeuille tient à $pct', (t) async {
      await t.pumpWidget(
          enveloppe(const HomeScreen(), etat(FakeApi()), echelle: echelle));
      await t.pumpAndSettle();
    });

    testWidgets('Discussions tient à $pct', (t) async {
      await t.pumpWidget(enveloppe(
          const Scaffold(body: ChatsScreen()), etat(FakeApi()),
          echelle: echelle));
      await t.pumpAndSettle();
    });

    testWidgets('Accueil (fil) tient à $pct', (t) async {
      await t.pumpWidget(enveloppe(
          const Scaffold(body: FeedScreen()), etat(FakeApi()),
          echelle: echelle));
      await t.pumpAndSettle();
    });

    testWidgets('Appels (historique) tient à $pct', (t) async {
      await t.pumpWidget(enveloppe(
          const Scaffold(body: HistoryScreen()), etat(FakeApi()),
          echelle: echelle));
      await t.pumpAndSettle();
    });

    testWidgets('Profil tient à $pct', (t) async {
      await t.pumpWidget(enveloppe(
          const Scaffold(body: ProfileScreen()), etat(FakeApi()),
          echelle: echelle));
      await t.pumpAndSettle();
    });

    testWidgets('Navigation tient à $pct', (t) async {
      Tabs.reset();
      await t.pumpWidget(
          enveloppe(const ShellScreen(), etat(FakeApi()), echelle: echelle));
      await t.pumpAndSettle();
    });
  }

  testWidgets('le chargement est annoncé aux lecteurs d’écran', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(
        enveloppe(const Center(child: Chargement()), etat(FakeApi())));
    // WCAG 4.1.3 : l'attente n'est pas un silence.
    expect(find.bySemanticsLabel(L10n.t('loading')), findsOneWidget);
    h.dispose();
  });

  testWidgets('Fiche d’appel respecte les normes', (t) async {
    await t.pumpWidget(enveloppe(
      Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                showCallModeSheet(ctx, '+243810000002', name: 'Maman');
              },
              child: const Text('Appeler'),
            ),
          ),
        ),
      ),
      etat(FakeApi()),
    ));
    await t.tap(find.text('Appeler'));
    await t.pumpAndSettle();
    await verifierNormes(t, 'Fiche d’appel');
  });
}
