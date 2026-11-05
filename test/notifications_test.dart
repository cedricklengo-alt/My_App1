// NOTIFICATIONS D'INTERACTION — tests de l'application.
//
// Ce que ces tests prouvent, sans réseau :
//   1. un message de groupe (« Patrick, Junior et 16 autres personnes… ») est
//      repris tel quel, et le repli local couvre chaque type ;
//   2. les sections Aujourd'hui / Cette semaine / Plus anciennes sont justes,
//      y compris aux frontières (minuit, sept jours) ;
//   3. l'écran affiche les trois sections, la pastille des non-lues et le
//      nombre de personnes concernées ;
//   4. toucher une notification l'ouvre sur la publication ET sur le
//      commentaire visé ;
//   5. le contrôleur du badge se rafraîchit, décrémente et se met en pause ;
//   6. l'écran de statistiques affiche les chiffres et le classement.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mbote/api.dart';
import 'package:mbote/models/social.dart';
import 'package:mbote/screens/engagement_screen.dart';
import 'package:mbote/screens/notifications_screen.dart';
import 'package:mbote/state.dart';
import 'package:mbote/state/notifs.dart';
import 'package:mbote/theme.dart';

class FakeNotifs extends Api {
  FakeNotifs();

  List<NotificationSociale> notifs = [];
  int nonLues = 0;
  final List<String> appels = [];
  Map<String, dynamic> engagement = const {};

  @override
  Future<Map<String, dynamic>> notifications({int? before, int limite = 30}) async {
    appels.add('notifications($limite)');
    return {
      'notifications': [
        for (final n in notifs)
          {
            'id': n.id,
            'type': n.type,
            'post_id': n.postId,
            'comment_id': n.commentId,
            'source_type': n.sourceType,
            'texte': n.texte,
            'lu': n.lu ? 1 : 0,
            'created_at': n.createdAt.millisecondsSinceEpoch,
            'nb_acteurs': n.nbActeurs,
            'message': n.message,
            'acteurs': [
              for (final a in n.acteurs) {'id': a.id, 'name': a.name},
            ],
            'expediteur': n.expediteur == null
                ? null
                : {'id': n.expediteur!.id, 'name': n.expediteur!.name},
          },
      ],
      'non_lues': notifs.where((n) => !n.lu).length,
      'next': null,
    };
  }

  @override
  Future<int> notificationsNonLues() async {
    appels.add('count');
    return notifs.where((n) => !n.lu).length;
  }

  @override
  Future<void> marquerNotificationLue(String id) async {
    appels.add('lue($id)');
    notifs = [
      for (final n in notifs)
        if (n.id == id) n.copyWith(lu: true) else n,
    ];
  }

  @override
  Future<void> marquerNotificationsLues() async {
    appels.add('toutLire');
    notifs = [for (final n in notifs) n.copyWith(lu: true)];
  }

  @override
  Future<Map<String, dynamic>> analytiqueEngagement() async {
    appels.add('analytique');
    return engagement;
  }
}

Widget wrap(Widget enfant, Api api) {
  MC.apply(kPalettes['fleuve']!);
  final st = AppState();
  st.id = 'u1';
  st.api = api;
  return ChangeNotifierProvider<AppState>.value(
    value: st,
    child: MaterialApp(home: enfant),
  );
}

NotificationSociale notif({
  String id = 'n1',
  String type = 'post_like',
  DateTime? quand,
  String? postId = 'p1',
  String? commentId,
  String message = '',
  String texte = '',
  int nbActeurs = 1,
  List<Personne> acteurs = const [],
  Personne? expediteur,
  bool lu = false,
}) =>
    NotificationSociale(
      id: id,
      type: type,
      createdAt: quand ?? DateTime.now().subtract(const Duration(minutes: 3)),
      postId: postId,
      commentId: commentId,
      message: message,
      texte: texte,
      nbActeurs: nbActeurs,
      acteurs: acteurs,
      lu: lu,
      expediteur: expediteur ?? const Personne(id: 'u2', name: 'Patrick Ilunga'),
    );

void main() {
  // ── 1. Modèle ────────────────────────────────────────────────────────────
  group('Modèle de notification', () {
    test('le message du serveur est repris tel quel (regroupement)', () {
      final n = notif(
        type: 'post_like',
        nbActeurs: 18,
        message: 'Patrick, Junior et 16 autres personnes ont aimé votre publication',
      );
      expect(n.resume, contains('16 autres personnes'));
      expect(n.estGroupee, isTrue);
      expect(n.nature, 'J’aime');
    });

    test('le repli local couvre chaque type', () {
      expect(notif(type: 'post_like').resume, contains('a aimé votre publication'));
      expect(notif(type: 'comment').resume, contains('a commenté votre publication'));
      expect(notif(type: 'comment_reply').resume,
          contains('a répondu à votre commentaire'));
      expect(notif(type: 'share').resume, contains('a partagé votre publication'));
      expect(notif(type: 'mention').resume, contains('mentionné'));
    });

    test('une mention dans un commentaire le dit', () {
      final n = NotificationSociale(
        id: 'n9',
        type: 'mention',
        sourceType: 'comment',
        createdAt: DateTime.now(),
        expediteur: const Personne(id: 'u3', name: 'Alice'),
      );
      expect(n.resume, contains('commentaire'));
    });

    test('une notification sans publication n’ouvre rien', () {
      expect(notif(type: 'follow', postId: null).aUnePublication, isFalse);
      expect(notif().aUnePublication, isTrue);
    });

    test('la lecture est dérivée du JSON (0/1 et vrai/faux)', () {
      expect(
          NotificationSociale.fromJson({'id': 'a', 'type': 'post_like', 'lu': 1}).lu,
          isTrue);
      expect(
          NotificationSociale.fromJson({'id': 'b', 'type': 'post_like', 'lu': 0}).lu,
          isFalse);
      final g = NotificationSociale.fromJson({
        'id': 'c',
        'type': 'post_like',
        'nb_acteurs': 3,
        'acteurs': [
          {'id': 'u1', 'name': 'A'},
          {'id': 'u2', 'name': 'B'},
        ],
      });
      expect(g.nbActeurs, 3);
      expect(g.acteurs.length, 2);
    });
  });

  // ── 2. Sections ──────────────────────────────────────────────────────────
  group('Sections du centre', () {
    final maintenant = DateTime(2026, 11, 3, 14, 30);

    test('aujourd’hui commence à minuit', () {
      expect(trancheDe(DateTime(2026, 11, 3, 0, 0), maintenant: maintenant),
          TrancheNotifs.aujourdhui);
      expect(trancheDe(DateTime(2026, 11, 2, 23, 59), maintenant: maintenant),
          TrancheNotifs.semaine);
    });

    test('cette semaine couvre sept jours', () {
      expect(trancheDe(DateTime(2026, 10, 28), maintenant: maintenant),
          TrancheNotifs.semaine);
      expect(trancheDe(DateTime(2026, 10, 20), maintenant: maintenant),
          TrancheNotifs.anciennes);
    });

    test('le temps écoulé est en français', () {
      expect(quandNotif(maintenant.subtract(const Duration(seconds: 20)),
          maintenant: maintenant), 'à l’instant');
      expect(quandNotif(maintenant.subtract(const Duration(minutes: 5)),
          maintenant: maintenant), 'il y a 5 min');
      expect(quandNotif(maintenant.subtract(const Duration(hours: 3)),
          maintenant: maintenant), 'il y a 3 h');
      expect(quandNotif(maintenant.subtract(const Duration(days: 1)),
          maintenant: maintenant), 'hier');
      expect(quandNotif(maintenant.subtract(const Duration(days: 3)),
          maintenant: maintenant), 'il y a 3 jours');
    });
  });

  // ── 3. Écran ─────────────────────────────────────────────────────────────
  group('Centre de notifications', () {
    testWidgets('trois sections, pastille et regroupement', (tester) async {
      final api = FakeNotifs()
        ..notifs = [
          notif(
            id: 'n1',
            type: 'post_like',
            nbActeurs: 18,
            message:
                'Patrick, Junior et 16 autres personnes ont aimé votre publication',
            acteurs: const [
              Personne(id: 'u2', name: 'Patrick Ilunga'),
              Personne(id: 'u3', name: 'Junior Kasongo'),
            ],
          ),
          notif(
            id: 'n2',
            type: 'comment',
            quand: DateTime.now().subtract(const Duration(days: 2)),
            message: 'Aline Mbala a commenté votre publication',
            texte: 'Superbe photo du fleuve',
          ),
          notif(
            id: 'n3',
            type: 'share',
            quand: DateTime.now().subtract(const Duration(days: 30)),
            message: 'Junior Kasongo a partagé votre publication',
          ),
        ];

      await tester.pumpWidget(wrap(const NotificationsScreen(), api));
      await tester.pumpAndSettle();

      expect(find.text('AUJOURD’HUI'), findsOneWidget);
      expect(find.text('CETTE SEMAINE'), findsOneWidget);
      expect(find.text('PLUS ANCIENNES'), findsOneWidget);
      expect(find.textContaining('16 autres personnes'), findsOneWidget);
      expect(find.textContaining('Superbe photo'), findsOneWidget);
      expect(find.text('18 personnes'), findsOneWidget);
      expect(find.text('Tout lire'), findsOneWidget);
    });

    testWidgets('toucher une notification ouvre la publication et le commentaire',
        (tester) async {
      final api = FakeNotifs()
        ..notifs = [
          notif(
            id: 'n1',
            type: 'comment_reply',
            commentId: 'cm42',
            message: 'Aline Mbala a répondu à votre commentaire',
            texte: 'Merci Patrick !',
          ),
        ];

      String? postId;
      String? commentaireId;
      await tester.pumpWidget(wrap(
        NotificationsScreen(
          onOuvrirPublication: (id, {String? commentId}) {
            postId = id;
            commentaireId = commentId;
          },
        ),
        api,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('a répondu à votre commentaire'));
      await tester.pumpAndSettle();

      expect(postId, 'p1');
      expect(commentaireId, 'cm42');
      expect(api.appels, contains('lue(n1)'));
    });

    testWidgets('« Tout lire » vide la pastille', (tester) async {
      final api = FakeNotifs()..notifs = [notif(id: 'n1'), notif(id: 'n2')];

      await tester.pumpWidget(wrap(const NotificationsScreen(), api));
      await tester.pumpAndSettle();
      expect(find.text('Tout lire'), findsOneWidget);

      await tester.tap(find.text('Tout lire'));
      await tester.pumpAndSettle();

      expect(api.appels, contains('toutLire'));
      expect(find.text('Tout lire'), findsNothing);
    });

    testWidgets('sans notification, le message explique ce qui arrivera',
        (tester) async {
      await tester.pumpWidget(wrap(const NotificationsScreen(), FakeNotifs()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Aucune notification'), findsOneWidget);
      expect(find.textContaining('partages'), findsWidgets);
    });
  });

  // ── 4. Contrôleur du badge ───────────────────────────────────────────────
  group('Badge temps réel', () {
    testWidgets('le compteur suit le serveur et décrémente à la lecture',
        (tester) async {
      final api = FakeNotifs()
        ..notifs = [notif(id: 'n1'), notif(id: 'n2'), notif(id: 'n3')];
      final ctl = NotifsCtl(api);
      addTearDown(ctl.dispose);

      ctl.demarrer();
      await ctl.rafraichirBadge();
      expect(ctl.nonLues, 3);

      await ctl.charger();
      expect(ctl.items.length, 3);

      await ctl.marquerLue(ctl.items.first);
      expect(ctl.nonLues, 2);

      await ctl.toutLire();
      expect(ctl.nonLues, 0);
      expect(api.appels, contains('toutLire'));

      // Le minuteur périodique doit être arrêté avant la fin du test : c'est
      // exactement ce que fait la mise en arrière-plan de l'application.
      ctl.arreter();
    });

    testWidgets('un serveur injoignable ne casse pas la pastille', (tester) async {
      final api = _ApiMuette();
      final ctl = NotifsCtl(api);
      addTearDown(ctl.dispose);

      await ctl.rafraichirBadge();
      await ctl.charger();
      expect(ctl.nonLues, 0);
      expect(ctl.items, isEmpty);
      expect(ctl.erreur, isNotNull);
    });

    testWidgets('les données arrivent de la première page', (tester) async {
      final api = FakeNotifs()..notifs = [notif(id: 'n1')];
      final ctl = NotifsCtl(api);
      addTearDown(ctl.dispose);

      await ctl.charger();
      expect(ctl.charge, isFalse);
      expect(ctl.aPlus, isFalse);
      expect(api.appels.first, startsWith('notifications'));
    });
  });

  // ── 5. Statistiques ──────────────────────────────────────────────────────
  group('Mes statistiques', () {
    testWidgets('chiffres, taux et classement', (tester) async {
      final api = FakeNotifs()
        ..engagement = {
          'mentions': {'recues': 4},
          'engagement': {
            'publications': 2,
            'likes': 12,
            'commentaires': 5,
            'partages': 3,
            'vues': 100,
            'interactions': 20,
            'taux': 20.0,
            'taux_base': 'vues',
            'likes_par_publication': 6.0,
            'notifications': 9,
            'top': [
              {
                'id': 'p1',
                'texte': 'Le fleuve monte ce matin',
                'likes': 10,
                'commentaires': 4,
                'partages': 3,
                'score': 27,
              },
            ],
          },
        };

      await tester.pumpWidget(wrap(EngagementScreen(api: api), api));
      await tester.pumpAndSettle();

      expect(find.text('12'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.textContaining('20.0 % des vues'), findsOneWidget);
      expect(find.textContaining('Le fleuve monte'), findsOneWidget);
      expect(find.textContaining('10 j’aime'), findsOneWidget);
    });
  });
}

class _ApiMuette extends Api {
  @override
  Future<int> notificationsNonLues() async => throw Exception('hors ligne');

  @override
  Future<Map<String, dynamic>> notifications({int? before, int limite = 30}) async =>
      throw Exception('hors ligne');
}
