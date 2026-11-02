import 'package:flutter/material.dart';
import '../theme.dart';
import 'login.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [MC.halo, MC.nuit],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, .8],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              children: [
                const Spacer(),
                // Soleil couchant
                Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    gradient: MC.degrade,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: MC.soleil.withOpacity(.3),
                          blurRadius: 80,
                          spreadRadius: 18),
                    ],
                  ),
                  child: Icon(Icons.call_rounded,
                      size: 64, color: MC.onAccent),
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'Appelle le pays,\ncomme si tu y '),
                      TextSpan(
                          text: 'étais.',
                          style: TextStyle(color: MC.soleil)),
                    ]),
                    style: TextStyle(
                        fontSize: 30,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        color: MC.ivoire),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Des appels nets et pas chers vers tous les GSM d'Afrique — même si ton correspondant n'a pas Internet ni l'application.",
                    style: TextStyle(color: MC.sable, fontSize: 14.5),
                  ),
                ),
                const SizedBox(height: 28),
                MboteButton(
                  label: "Commencer · c'est gratuit",
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LoginScreen())),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
