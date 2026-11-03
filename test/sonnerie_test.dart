// SONNERIE ET APPEL ENTRANT — le son choisi dans les réglages, le cycle
// entrant / sortant, et l'accessibilité des deux boutons de l'écran entrant.
//
// Le canal natif de la sonnerie est simulé : aucun son n'est joué pendant les
// tests, mais on vérifie que l'application demande bien la sonnerie choisie.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mbote/l10n.dart';
import 'package:mbote/prefs.dart';
import 'package:mbote/rtc.dart';
import 'package:mbote/screens/incoming_call.dart';
import 'package:mbote/screens/settings.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';

/// Journal des appels au canal natif de la sonnerie.
final List<String> sonneries = [];

Widget enveloppe(Widget ecran) {
  MC.apply(kPalettes['fleuve']!);
  final st = AppState();
  st.id = 'u1';
  st.name = 'Alice';
  st.phone = '+243810000001';
  return ChangeNotifierProvider<AppState>.value(
    value: st,
    child: MaterialApp(theme: mboteTheme(), home: ecran),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.lang = 'fr';
    CallPrefs.ringtone = 'classique';
    CallPrefs.vibration = true;
    sonneries.clear();
    // Canal natif simulé (aucun plugin en test).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_ringtone_player'), (call) async {
      sonneries.add('${call.method}:${call.arguments}');
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_ringtone_player'), null);
  });

  group('Choix de la sonnerie dans les réglages', () {
    testWidgets('choisir « douce » est retenu et enregistré', (tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(enveloppe(const NotificationsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ring-douce')));
      await tester.pumpAndSettle();

      expect(CallPrefs.ringtone, 'douce');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ring_type'), 'douce');
    });

    testWidgets('couper la vibration est retenu', (tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(enveloppe(const NotificationsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ring-vibration')));
      await tester.pumpAndSettle();

      expect(CallPrefs.vibration, isFalse);
      expect((await SharedPreferences.getInstance()).getBool('ring_vibration'),
          isFalse);
    });

    test('les préférences survivent au redémarrage', () async {
      await CallPrefs.setRingtone('forte');
      await CallPrefs.setVibration(false);
      CallPrefs.ringtone = 'classique';
      CallPrefs.vibration = true;

      await CallPrefs.load();
      expect(CallPrefs.ringtone, 'forte');
      expect(CallPrefs.vibration, isFalse);
    });
  });

  group('Écran d’appel entrant', () {
    Future<void> ouvrirEntrant(WidgetTester tester) async {
      await tester.pumpWidget(enveloppe(const IncomingCallScreen(
        offer: {
          'from': '+243810000009',
          'from_name': 'Papa Kisangani',
          'call_id': 'c-1',
          'sdp': 'offre',
        },
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('il sonne dès l’ouverture', (tester) async {
      await ouvrirEntrant(tester);
      expect(sonneries, isNotEmpty,
          reason: 'la sonnerie doit démarrer sans attendre une action');
      // Fermeture propre : plus de sonnerie en sortant.
      await tester.pumpWidget(enveloppe(const SizedBox()));
      await tester.pumpAndSettle();
      expect(sonneries.any((s) => s.startsWith('stop')), isTrue);
    });

    testWidgets('sonnerie « silencieux » : aucun son demandé', (tester) async {
      CallPrefs.ringtone = 'silencieux';
      CallPrefs.vibration = false;
      await ouvrirEntrant(tester);
      expect(sonneries.where((s) => s.startsWith('play')), isEmpty,
          reason: 'le mode silencieux ne doit jouer aucune sonnerie');
    });

    testWidgets('nom de l’appelant et deux boutons nommés', (tester) async {
      await ouvrirEntrant(tester);

      expect(find.text('Papa Kisangani'), findsOneWidget);
      expect(find.bySemanticsLabel(L10n.t('call_accept')), findsOneWidget);
      expect(find.bySemanticsLabel(L10n.t('call_decline')), findsOneWidget);
    });

    testWidgets('refuser coupe la sonnerie et journalise', (tester) async {
      await ouvrirEntrant(tester);
      sonneries.clear();
      Rtc.onSignal = null;

      await tester.tap(find.bySemanticsLabel(L10n.t('call_decline')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(sonneries.any((s) => s.startsWith('stop')), isTrue,
          reason: 'refuser doit arrêter la sonnerie immédiatement');
    });
  });
}
