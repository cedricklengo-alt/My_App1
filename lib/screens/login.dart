import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../l10n.dart';
import 'shell.dart';

/// Connexion / inscription par numéro + code OTP (2 étapes sur un écran).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final phoneCtrl = TextEditingController(text: '+243');
  final codeCtrl = TextEditingController();
  final referralCtrl = TextEditingController();
  bool showReferral = false;
  bool otpSent = false;
  bool loading = false;
  String? demoCode;

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? MC.rouge : MC.nuit3,
    ));
  }

  Future<void> _requestOtp() async {
    final st = context.read<AppState>();
    setState(() => loading = true);
    try {
      final r = await st.api.requestOtp(phoneCtrl.text.trim());
      demoCode = r['demo_code'];
      setState(() => otpSent = true);
      _snack(demoCode != null
          ? '📲 Code (mode démo) : $demoCode'
          : '📲 Code envoyé par SMS');
    } catch (e) {
      _snack(friendlyError(e), error: true);
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _verify() async {
    final st = context.read<AppState>();
    setState(() => loading = true);
    try {
      final r = await st.api.verifyOtp(
          phoneCtrl.text.trim(), codeCtrl.text.trim(),
          referralCode: referralCtrl.text.trim());
      st.api.token = r['token'];
      await st.onLoggedIn(r['token'], r['user'], r['balance_cents']);
      if (!mounted) return;
      if (r['is_new'] == true) {
        _snack('🎁 Bienvenue ! 0,50 \$ offerts pour tester.');
      }
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ShellScreen()),
          (_) => false);
    } catch (e) {
      _snack(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connexion')),
      body: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              otpSent ? 'Entre le code reçu 📲' : 'Ton numéro de téléphone',
              style: TextStyle(
                  fontSize: 23, fontWeight: FontWeight.w800, color: MC.ivoire),
            ),
            const SizedBox(height: 8),
            Text(
              otpSent
                  ? 'Un code à 6 chiffres a été envoyé au ${phoneCtrl.text}'
                  : 'On t\'envoie un code par SMS pour vérifier que c\'est bien toi.',
              style: TextStyle(color: MC.sable, fontSize: 14),
            ),
            const SizedBox(height: 26),
            if (!otpSent)
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                style: TextStyle(
                    fontSize: 20, color: MC.ivoire, letterSpacing: 1),
                decoration: const InputDecoration(hintText: '+243 81 234 5678'),
              )
            else ...[
              TextField(
                controller: codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 28, color: MC.ivoire, letterSpacing: 10),
                decoration:
                    const InputDecoration(hintText: '······', counterText: ''),
              ),
              if (demoCode != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Mode démo — code : $demoCode',
                      style:
                          TextStyle(color: MC.savane, fontSize: 12.5)),
                ),
              const SizedBox(height: 12),
              // 🎁 Code parrain (facultatif) — 1 $ offert au 1er appel
              if (!showReferral)
                GestureDetector(
                  onTap: () => setState(() => showReferral = true),
                  child: Text(L10n.t('have_code'),
                      style: TextStyle(
                          color: MC.soleil, fontSize: 13.5)),
                )
              else
                TextField(
                  controller: referralCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(
                      fontSize: 16, color: MC.ivoire, letterSpacing: 2),
                  decoration:
                      const InputDecoration(hintText: 'MBOTE-XXXX'),
                ),
            ],
            const SizedBox(height: 26),
            MboteButton(
              label: otpSent ? 'Vérifier le code' : 'Recevoir mon code',
              loading: loading,
              onTap: otpSent ? _verify : _requestOtp,
            ),
            if (otpSent)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => otpSent = false),
                  child: Text('Changer de numéro',
                      style: TextStyle(color: MC.soleil)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
