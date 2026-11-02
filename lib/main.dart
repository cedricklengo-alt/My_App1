import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state.dart';
import 'theme.dart';
import 'l10n.dart';
import 'pin.dart';
import 'prefs.dart';
import 'screens/onboarding.dart';
import 'screens/shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 🔔 Firebase (appels app fermée) — ne bloque JAMAIS le démarrage
  try {
    await Firebase.initializeApp();
  } catch (_) {/* google-services.json absent : l'app marche sans push */}
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

class _MboteAppState extends State<MboteApp> {
  late bool locked = widget.locked;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    // L'app entière se reconstruit quand la langue, le thème ou la police change
    return ListenableBuilder(
      listenable: Listenable.merge([L10n.version, ThemeCtl.version]),
      builder: (_, __) => MaterialApp(
        title: 'MboteCall',
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
