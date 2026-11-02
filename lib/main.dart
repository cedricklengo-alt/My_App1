import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'state.dart';
import 'theme.dart';
import 'l10n.dart';
import 'pin.dart';
import 'prefs.dart';
import 'screens/onboarding.dart';
import 'screens/shell.dart';
import 'screens/incoming_call.dart';
import 'rtc.dart';

/// Clé du navigateur racine : permet d'afficher l'écran d'appel entrant
/// depuis le canal temps réel, hors de tout contexte d'écran.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 🔔 Firebase (appels app fermée) — ne bloque JAMAIS le démarrage
  try {
    await Firebase.initializeApp();
  } catch (_) {/* google-services.json absent : l'app marche sans push */}
  // 📅 Données de langue pour les dates en français (« 7 déc. 2024 · 09h00 »).
  // Sans cet appel, DateFormat('…', 'fr_FR') lève une LocaleDataException.
  try {
    await initializeDateFormatting('fr_FR', null);
  } catch (_) {/* format de repli numérique */}
  await L10n.load(); // 🗣️ langue sauvegardée (+ langues téléchargées)
  await ThemeCtl.load(); // 🎨 thème + police sauvegardés
  await CallPrefs.load(); // 🔔 sonnerie + vibration choisies
  final pinSet = await Pin.isSet(); // 🔐 verrou PIN éventuel
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: MboteApp(locked: pinSet),
    ),
  );
}

class MboteApp extends StatefulWidget {
  final bool locked;
  const MboteApp({super.key, required this.locked});

  @override
  State<MboteApp> createState() => _MboteAppState();
}

class _MboteAppState extends State<MboteApp> with WidgetsBindingObserver {
  late bool locked = widget.locked;
  bool _callShown = false; // évite d'empiler deux écrans d'appel

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 📞 Branche les appels entrants : sans cette ligne, les offres reçues
    // par le canal temps réel n'ont aucun écran où s'afficher.
    Rtc.onOffer = _onOffer;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Rtc.onOffer == _onOffer) Rtc.onOffer = null;
    super.dispose();
  }

  /// 👁️ App au premier plan / en arrière-plan → le serveur en a besoin pour
  /// éviter les notifications en double quand l'écran est déjà ouvert.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Rtc.setForeground(state == AppLifecycleState.resumed);
  }

  /// 📲 Appel entrant reçu par le canal temps réel.
  void _onOffer(Map msg) {
    // 📳 Acquittement immédiat : sans lui le serveur considère le socket
    // comme « fantôme » au bout de 4,5 s, le ferme et bascule sur un push
    // — la sonnerie puis la réponse ne passent plus.
    final callId = msg['call_id'];
    if (callId != null) {
      Rtc.send({'type': 'ringing', 'call_id': callId, 'from': msg['from']});
    }
    if (_callShown) return;
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    _callShown = true;
    nav
        .push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => IncomingCallScreen(offer: msg),
        ))
        .whenComplete(() => _callShown = false);
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    // L'app entière se reconstruit quand la langue, le thème ou la police change
    return ListenableBuilder(
      listenable: Listenable.merge([L10n.version, ThemeCtl.version]),
      builder: (_, __) => MaterialApp(
        title: 'MboteCall',
        navigatorKey: appNavigatorKey,
        // 🇫🇷 Interface en français (sélecteurs de date, copier/coller, etc.)
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        debugShowCheckedModeBanner: false,
        theme: mboteTheme(),
        home: !st.ready
            ? const _Splash()
            : locked
                // 🔐 Déverrouillage avant tout accès à l'app
                ? PinScreen(onSuccess: () => setState(() => locked = false))
                : st.loggedIn
                    ? const ShellScreen()
                    : const OnboardingScreen(),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              decoration:
                  BoxDecoration(gradient: MC.degrade, shape: BoxShape.circle),
              child: Icon(Icons.wb_sunny_rounded, color: MC.onAccent, size: 42),
            ),
            const SizedBox(height: 18),
            Text('MboteCall',
                style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: MC.ivoire)),
          ]),
        ),
      );
}
