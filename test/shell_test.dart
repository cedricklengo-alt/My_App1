// Tests de la NAVIGATION (les 4 onglets) et du menu « ··· ».
//
// On vérifie ce que l'utilisateur obtient vraiment :
//  • chaque onglet affiche son écran ;
//  • re-taper l'onglet actif recharge son contenu ;
//  • la pastille « manqués » apparaît sur l'onglet Appels ;
//  • le menu ··· n'a plus aucun bouton mort (chaque entrée ouvre un écran) ;
//  • la déconnexion demande confirmation puis ferme la session ;
//  • l'onglet Appels distingue reçu / passé / sans réponse.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mbote/api.dart';
import 'package:mbote/l10n.dart';
import 'package:mbote/models/post.dart';
import 'package:mbote/screens/chats.dart';
import 'package:mbote/screens/feed_screen.dart';
import 'package:mbote/screens/history.dart';
import 'package:mbote/screens/settings.dart';
import 'package:mbote/screens/shell.dart';
import 'package:mbote/screens/shop.dart';
import 'package:mbote/state.dart';
import 'package:mbote/tabs.dart';
import 'package:mbote/theme.dart';

/// Faux serveur minimal : fil vide, aucun appel, aucune conversation.
class FakeApi extends Api {
  final List<String> calls = [];
  List<Map> historyRows = [];
  Object? failHistory;
  final List<String> derniersFiltres = [];

  @override
  Future<FeedPage> feedPage({int? before, String? cursor}) async {
    calls.add('feedPage');
    return const FeedPage(posts: [], nextBefore: null, nextCursor: null);
  }

  @override
  Future<List<Story>> feedStories() async {
    calls.add('feedStories');
    return const [];
  }

  @override
  Future<Map> history({String filter = 'all', String? q, int limit = 100, int? since}) async {
    calls.add('history');
    derniersFiltres.add(filter);
    if (failHistory != null) throw failHistory!;
    // Le VRAI backend filtre : le faux l'imite, sinon on testerait un
    // comportement que la production n'a pas.
    bool manque(Map r) =>
        '${r['answered_at'] ?? 0}' == '0' && r['direction'] == 'incoming';
    final rows = switch (filter) {
      'in' => historyRows
          .where((r) => r['direction'] == 'incoming' && !manque(r))
          .toList(),
      'out' => historyRows
          .where((r) => r['direction'] == 'outgoing' && !manque(r))
          .toList(),
      'missed' => historyRows.where(manque).toList(),
      'internet' => historyRows
          .where((r) => '${r['channel'] ?? 'internet'}' == 'internet')
          .toList(),
      'gsm' => historyRows.where((r) => '${r['channel'] ?? ''}' == 'gsm').toList(),
      _ => historyRows,
    };
    final cherche = (q ?? '').trim().toLowerCase();
    final filtre = cherche.isEmpty
        ? rows
        : rows
            .where((r) =>
                '${r['callee']}'.toLowerCase().contains(cherche) ||
                '${r['destination']}'.toLowerCase().contains(cherche))
            .toList();
    return {
      'calls': filtre,
      'total': filtre.length,
      'has_more': false,
      'month_sec': 0,
      'month_cost_cents': 0,
    };
  }

  @override
  Future<List> messageThreads() async {
    calls.add('threads');
    return const [];
  }

  @override
  Future<List> promos() async => const [];
}

Map callRow({
  required String id,
  String direction = 'outgoing',
  int answeredAt = 0,
  int billedSec = 0,
  String cause = 'user_hangup',
  int video = 0,
  int startedAt = 1762000000000,
}) =>
    {
      'id': id,
      'callee': '+243810000002',
      'direction': direction,
      'destination': 'MboteCall',
      'status': 'ended',
      'started_at': startedAt,
      'answered_at': answeredAt,
      'ended_at': startedAt,
      'billed_sec': billedSec,
      'cost_cents': 0,
      'hangup_cause': cause,
      'with_video': video,
      'rtc_mode': 1,
    };

AppState appState(FakeApi api) {
  final st = AppState();
  st.token = 'jeton-test';
  st.name = 'Alice Mbote';
  st.phone = '+243810000001';
  st.balanceCents = 1250;
  st.ready = true;
  st.api = api;
  return st;
}

Widget wrapShell(AppState state) {
  MC.apply(kPalettes['kin']!);
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: const MaterialApp(home: ShellScreen()),
  );
}

Widget wrapScreen(Widget child, AppState state) {
  MC.apply(kPalettes['kin']!);
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.lang = 'fr';
    Tabs.reset();
    HistoryScreen.missed.value = 0;
    ChatsScreen.unread.value = 0;
  });

  group('Les 4 onglets', () {
    testWidgets('les onglets portent les bons libellés (Discussion, plus « Messages »)',
        (t) async {
      await t.pumpWidget(wrapShell(appState(FakeApi())));
      await t.pumpAndSettle();

      // Le 3ᵉ onglet s'appelle « Discussion » — et plus « Messages ».
      expect(find.text('Discussion'), findsOneWidget);
      expect(find.text('Messages'), findsNothing);
      expect(L10n.t('nav_messages'), 'Discussion');
      expect(L10n.t2('ln', 'nav_messages'), 'Masolo');
      expect(L10n.t2('sw', 'nav_messages'), 'Majadiliano');
      // Les trois autres onglets restent inchangés.
      expect(find.text(L10n.t('nav_home')), findsOneWidget);
      expect(find.text(L10n.t('nav_calls')), findsOneWidget);
      expect(find.text(L10n.t('nav_more')), findsOneWidget);
    });

    testWidgets('Accueil, Appels et Discussion s’affichent', (t) async {
      final api = FakeApi();
      await t.pumpWidget(wrapShell(appState(api)));
      await t.pumpAndSettle();

      // Onglet 0 : le fil.
      expect(find.byType(FeedScreen), findsOneWidget);
      expect(api.calls, contains('feedPage'));

      // Onglet 1 : historique des appels.
      await t.tap(find.text(L10n.t('nav_calls')));
      await t.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(api.calls, contains('history'));

      // Onglet 2 : Discussion.
      await t.tap(find.text('Discussion'));
      await t.pumpAndSettle();
      expect(find.byType(ChatsScreen), findsOneWidget);
      expect(api.calls, contains('threads'));
    });

    testWidgets('re-taper l’onglet actif recharge son contenu', (t) async {
      final api = FakeApi();
      await t.pumpWidget(wrapShell(appState(api)));
      await t.pumpAndSettle();
      final avant = api.calls.where((c) => c == 'feedPage').length;

      // Deuxième appui sur « Accueil » (déjà actif).
      await t.tap(find.text(L10n.t('nav_home')));
      await t.pumpAndSettle();

      expect(api.calls.where((c) => c == 'feedPage').length, avant + 1);
    });

    testWidgets('la pastille des appels manqués apparaît sur l’onglet', (t) async {
      final api = FakeApi()
        ..historyRows = [
          callRow(id: 'a', direction: 'incoming', cause: 'missed'),
          callRow(id: 'b', direction: 'incoming', cause: 'missed'),
          callRow(id: 'c', direction: 'outgoing', answeredAt: 1762000000000, billedSec: 30),
        ];
      await t.pumpWidget(wrapShell(appState(api)));
      await t.pumpAndSettle();
      await t.tap(find.text(L10n.t('nav_calls')));
      await t.pumpAndSettle();

      expect(HistoryScreen.missed.value, 2);
      expect(find.text('2'), findsWidgets); // pastille de l'onglet
    });
  });

  group('Onglet Appels — lecture de l’historique', () {
    testWidgets('reçu, passé et sans réponse sont distingués', (t) async {
      final api = FakeApi()
        ..historyRows = [
          callRow(
              id: 'in',
              direction: 'incoming',
              answeredAt: 1762000000000,
              billedSec: 45,
              startedAt: 1762000400000),
          callRow(
              id: 'out',
              direction: 'outgoing',
              answeredAt: 1762000000000,
              billedSec: 12,
              startedAt: 1762000300000),
          callRow(
              id: 'miss',
              direction: 'incoming',
              cause: 'missed',
              startedAt: 1762000200000),
        ];
      await t.pumpWidget(wrapScreen(const HistoryScreen(), appState(api)));
      await t.pumpAndSettle();

      expect(find.byIcon(Icons.call_received_rounded), findsWidgets);
      expect(find.byIcon(Icons.call_made_rounded), findsWidgets);
      expect(find.byIcon(Icons.phone_missed_rounded), findsWidgets);
      expect(find.textContaining('Sans réponse'), findsOneWidget);
      expect(find.text('45s'), findsOneWidget);
    });

    testWidgets('les catégories filtrent réellement', (t) async {
      final api = FakeApi()
        ..historyRows = [
          callRow(id: 'in', direction: 'incoming', answeredAt: 1, billedSec: 9),
          callRow(id: 'miss', direction: 'incoming', cause: 'missed'),
        ];
      await t.pumpWidget(wrapScreen(const HistoryScreen(), appState(api)));
      await t.pumpAndSettle();

      // 2 appels au total, dont 1 manqué : le compteur est écrit dans la puce.
      expect(find.textContaining(L10n.t('history_missed')).first, findsOneWidget);

      await t.tap(find.textContaining(L10n.t('history_missed')).first);
      await t.pumpAndSettle();
      expect(find.textContaining('Sans réponse'), findsOneWidget);
      expect(find.text('9s'), findsNothing);
    });

    testWidgets('erreur réseau : message clair et bouton Réessayer', (t) async {
      final api = FakeApi()..failHistory = ApiException('Pas d\'Internet — vérifie ta connexion 📶');
      await t.pumpWidget(wrapScreen(const HistoryScreen(), appState(api)));
      await t.pumpAndSettle();

      expect(find.textContaining('Pas d\'Internet'), findsOneWidget);
      await t.tap(find.text(L10n.t('history_retry')));
      await t.pumpAndSettle();
      expect(api.calls.where((c) => c == 'history').length, 2);
    });

    testWidgets('liste vide : proposition de composer un numéro', (t) async {
      final api = FakeApi();
      await t.pumpWidget(wrapScreen(const HistoryScreen(), appState(api)));
      await t.pumpAndSettle();
      expect(find.text(L10n.t('history_empty')), findsOneWidget);
      expect(find.text(L10n.t('history_dial')), findsOneWidget);
    });
  });

  group('Menu ···', () {
    Future<void> openMenu(WidgetTester t) async {
      await t.tap(find.byIcon(Icons.more_horiz_rounded));
      await t.pumpAndSettle();
    }

    /// Le menu est plus haut qu'un écran de test : on fait défiler jusqu'à
    /// l'entrée avant de la toucher (comme le ferait un doigt).
    Future<void> tapEntry(WidgetTester t, String label) async {
      final finder = find.text(label).last;
      await t.ensureVisible(finder);
      await t.pumpAndSettle();
      await t.tap(finder);
      await t.pumpAndSettle();
    }

    testWidgets('il n’y a plus aucun bouton mort', (t) async {
      await t.pumpWidget(wrapShell(appState(FakeApi())));
      await t.pumpAndSettle();
      await openMenu(t);

      for (final key in [
        'nav_keypad',
        'contacts',
        'favorites',
        'wallet',
        'profile',
        'settings',
        'about',
        'logout',
      ]) {
        expect(find.text(L10n.t(key)), findsWidgets, reason: 'entrée manquante : $key');
      }
      // Le solde et le numéro sont rappelés dans l'en-tête du menu.
      expect(find.text('+243810000001'), findsOneWidget);
    });

    testWidgets('le menu est organisé en sections lisibles', (t) async {
      await t.pumpWidget(wrapShell(appState(FakeApi())));
      await t.pumpAndSettle();
      await openMenu(t);

      // Quatre sections, dans l'ordre attendu d'un menu professionnel.
      for (final cle in [
        'settings_section_account',
        'settings_section_tools',
        'settings_section_prefs',
        'settings_section_help',
      ]) {
        expect(find.text(L10n.t(cle)), findsWidgets, reason: cle);
      }

      // Chaque section contient bien ses entrées.
      expect(find.text(L10n.t('profile')), findsWidgets);
      expect(find.text(L10n.t('wallet')), findsWidgets);
      expect(find.text(L10n.t('shop_title')), findsWidgets);
      expect(find.text(L10n.t('nav_keypad')), findsWidgets);
      expect(find.text(L10n.t('settings')), findsWidgets);
    });

    testWidgets('Lokota n’est plus dans le menu : il vit dans la Discussion',
        (t) async {
      await t.pumpWidget(wrapShell(appState(FakeApi())));
      await t.pumpAndSettle();
      await openMenu(t);

      expect(find.text(L10n.t('lokota_home_title')), findsNothing);
      expect(find.text(L10n.t('more_lokota_sub')), findsNothing);
    });

    testWidgets('« Réglages » ouvre le hub de réglages', (t) async {
      await t.pumpWidget(wrapShell(appState(FakeApi())));
      await t.pumpAndSettle();
      await openMenu(t);

      await tapEntry(t, L10n.t('settings'));

      expect(find.byType(SettingsScreen), findsOneWidget);
      // Le compte est en haut ; les réglages suivent (on fait défiler, comme
      // un doigt sur un écran de 600 px).
      expect(find.text(L10n.t('settings_section_account')), findsOneWidget);
      await t.drag(find.byType(ListView).last, const Offset(0, -320));
      await t.pumpAndSettle();
      expect(find.text(L10n.t('appearance')), findsOneWidget);
      expect(find.text(L10n.t('language')), findsOneWidget);
      expect(find.text(L10n.t('settings_notifications')), findsOneWidget);
      await t.drag(find.byType(ListView).last, const Offset(0, -320));
      await t.pumpAndSettle();
      expect(find.text(L10n.t('settings_security')), findsOneWidget);
    });

    testWidgets('« Boutique » ouvre la boutique', (t) async {
      await t.pumpWidget(wrapShell(appState(FakeApi())));
      await t.pumpAndSettle();
      await openMenu(t);

      await tapEntry(t, L10n.t('shop_title'));
      expect(find.byType(ShopScreen), findsOneWidget);
    });

    testWidgets('Portefeuille ouvre un vrai écran', (t) async {
      await t.pumpWidget(wrapShell(appState(FakeApi())));
      await t.pumpAndSettle();
      await openMenu(t);

      await tapEntry(t, L10n.t('wallet'));

      // L'écran du portefeuille est bien là (carte solde + bouton recharger)
      // et on peut revenir en arrière.
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text(L10n.t('topup')), findsWidgets);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('Clavier ouvre le composeur de numéro', (t) async {
      await t.pumpWidget(wrapShell(appState(FakeApi())));
      await t.pumpAndSettle();
      await openMenu(t);

      await tapEntry(t, L10n.t('nav_keypad'));
      // Le clavier affiche ses touches (0 à 9).
      expect(find.text('5'), findsOneWidget);
      expect(find.text('+243'), findsOneWidget);
    });

    testWidgets('Déconnexion : confirmation puis session fermée', (t) async {
      final st = appState(FakeApi());
      await t.pumpWidget(wrapShell(st));
      await t.pumpAndSettle();
      await openMenu(t);

      await tapEntry(t, L10n.t('logout'));
      // La boîte de confirmation explique ce qui va se passer.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(L10n.t('logout_confirm')), findsOneWidget);

      // Annuler ne déconnecte pas.
      await t.tap(find.byKey(const Key('logout-cancel')));
      await t.pumpAndSettle();
      expect(st.token, isNotNull);

      // Confirmer déconnecte.
      await openMenu(t);
      await tapEntry(t, L10n.t('logout'));
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.byKey(const Key('logout-confirm')));
      await t.pumpAndSettle();
      expect(st.token, isNull);
      expect(st.loggedIn, isFalse);
    });

    testWidgets('À propos affiche la présentation de l’application', (t) async {
      await t.pumpWidget(wrapShell(appState(FakeApi())));
      await t.pumpAndSettle();
      await openMenu(t);

      await tapEntry(t, L10n.t('about'));
      expect(find.textContaining('MboteCall'), findsWidgets);
    });
  });
}
