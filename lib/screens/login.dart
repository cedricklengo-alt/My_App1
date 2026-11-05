import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sms_autofill/sms_autofill.dart';

import '../api.dart';
import '../countries.dart';
import '../state.dart';
import '../design.dart';
import '../theme.dart';
import '../l10n.dart';
import '../widgets/country_picker.dart';
import '../widgets/otp_field.dart';
import 'shell.dart';

/// Connexion / inscription par numéro + code OTP (2 étapes sur un écran).
///
/// v4.0 — sélecteur de pays complet (recherche instantanée, indicatif injecté),
/// validation intelligente (nombre exact de chiffres du pays, compteur en
/// temps réel, bouton désactivé tant que invalide) et champ OTP à cases
/// séparées (auto-avance, retour arrière, collage, auto-validation).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  Country country = kDefaultCountry;
  final phoneCtrl = TextEditingController(); // numéro NATIONAL (sans indicatif)
  final referralCtrl = TextEditingController();
  final otpKey = GlobalKey<OtpFieldState>();
  bool showReferral = false;
  bool otpSent = false;
  bool loading = false;
  String? demoCode;

  @override
  void initState() {
    super.initState();
    _startAutoFill();
  }

  /// 📱 Détection automatique du code SMS (Android SMS Retriever / iOS Autofill).
  Future<void> _startAutoFill() async {
    try {
      await SmsAutoFill().listenForCode();
      SmsAutoFill().code.listen((c) {
        final m = RegExp(r'(\d{6})').firstMatch(c);
        if (m != null && otpSent && mounted) {
          otpKey.currentState?.fill(m.group(1)!);
          _verify(m.group(1)!); // vérifie sans saisie manuelle
        }
      });
    } catch (_) {/* saisie manuelle en secours */}
  }

  /// Chiffres saisis / attendus pour le pays sélectionné.
  int get digits => phoneCtrl.text.replaceAll(RegExp(r'\D'), '').length;
  bool get phoneValid =>
      digits >= country.minDigits && digits <= country.maxDigits;
  String get fullPhone => '${country.dial}${phoneCtrl.text.replaceAll(RegExp(r'\D'), '')}';

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? MC.rouge : MC.nuit3,
    ));
  }

  Future<void> _pickCountry() async {
    final c = await showCountryPicker(context, current: country);
    if (c != null) {
      HapticFeedback.selectionClick();
      setState(() => country = c);
    }
  }

  Future<void> _requestOtp() async {
    if (!phoneValid) return;
    final st = context.read<AppState>();
    setState(() => loading = true);
    try {
      final r = await st.api.requestOtp(fullPhone);
      demoCode = r['demo_code'];
      setState(() => otpSent = true);
      _snack(demoCode != null
          ? 'Code (mode démo) : $demoCode'
          : 'Code envoyé par SMS');
    } catch (e) {
      _snack(friendlyError(e), error: true);
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _verify([String? autoCode]) async {
    final code = autoCode ?? otpKey.currentState?.code ?? '';
    if (code.length != 6 || loading) return;
    final st = context.read<AppState>();
    setState(() => loading = true);
    try {
      String appVersion = 'unknown';
      try {
        appVersion = (await PackageInfo.fromPlatform()).version;
      } catch (_) {}
      final r = await st.api.verifyOtp(
        fullPhone,
        code,
        referralCode: referralCtrl.text.trim(),
        dialCode: country.dial,
        country: country.iso,
        appVersion: appVersion,
        language: Localizations.localeOf(context).languageCode,
      );
      st.api.token = r['token'];
      await st.onLoggedIn(r['token'], r['user'], r['balance_cents'],
          refreshToken: r['refresh_token']);
      if (!mounted) return;
      if (r['is_new'] == true) {
        _snack('Bienvenue ! 0,50 \$ offerts pour tester.');
      }
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ShellScreen()), (_) => false);
    } catch (e) {
      _snack(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    SmsAutoFill().unregisterListener();
    phoneCtrl.dispose();
    referralCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MC.nuit,
      body: SafeArea(
        child: Stack(
          children: [
            // Halo doré subtil derrière le logo (maquette login premium).
            Positioned(
              top: 30,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      MC.soleil.withValues(alpha: .13),
                      MC.soleil.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 44, 26, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Logo + identité (maquette login premium) ──
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: MC.degrade,
                            boxShadow: [
                              BoxShadow(
                                color: MC.soleil.withValues(alpha: .25),
                                blurRadius: 26,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Icon(Icons.call_rounded,
                              color: MC.onAccent, size: 38),
                        ),
                        const SizedBox(height: 16),
                        Text('MboteCall',
                            style: TextStyle(
                                color: MC.ivoire,
                                fontSize: Tx.title,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.5)),
                        const SizedBox(height: 6),
                        Text(
                          'Appelle et discute gratuitement, partout en RDC',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: MC.kaki, fontSize: Tx.body),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),
                  Text(
                    otpSent ? 'Entre le code reçu' : 'Ton numéro de téléphone',
              style: TextStyle(
                  fontSize: Tx.headline, fontWeight: FontWeight.w800, color: MC.ivoire),
            ),
            const SizedBox(height: 8),
            Text(
              otpSent
                  ? 'Un code à 6 chiffres a été envoyé au $fullPhone'
                  : 'On t\'envoie un code par SMS pour vérifier que c\'est bien toi.',
              style: TextStyle(color: MC.sable, fontSize: Tx.body),
            ),
            const SizedBox(height: 26),
            if (!otpSent) ...[
              // Sélecteur de pays + champ numérique
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.number, // clavier UNIQUEMENT numérique
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly, // bloque tout caractère non numérique
                  LengthLimitingTextInputFormatter(country.maxDigits), // bloque au-delà du max du pays
                ],
                style:
                    TextStyle(fontSize: Tx.title, color: MC.ivoire, letterSpacing: 1),
                decoration: InputDecoration(
                  labelText: L10n.t('label_phone'),
                  hintText: 'Ex. 812345678',
                  filled: true,
                  fillColor: MC.nuit3,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Rd.pill),
                    borderSide: BorderSide(color: MC.ligne),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Rd.pill),
                    borderSide: BorderSide(color: MC.soleil, width: 1.6),
                  ),
                  // Compteur en temps réel : chiffres restants / attendus
                  counterText: '',
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '$digits/${country.expected} chiffres',
                      style: TextStyle(
                        color: phoneValid ? MC.savane : MC.kaki,
                        fontSize: Tx.label,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  prefixIcon: InkWell(
                    onTap: _pickCountry,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(Rd.xs),
                            child: Image.asset(
                              'assets/flags/${country.iso.toLowerCase()}.png',
                              width: 30,
                              height: 21,
                              fit: BoxFit.cover,
                              excludeFromSemantics: true,
                              errorBuilder: (_, __, ___) => Container(
                                width: 30,
                                height: 21,
                                alignment: Alignment.center,
                                color: MC.nuit3,
                                child: Text(country.iso,
                                    style: TextStyle(
                                        color: MC.soleil,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(country.dial,
                              style: TextStyle(
                                  color: MC.ivoire,
                                  fontSize: Tx.bodyLg,
                                  fontWeight: FontWeight.w700)),
                          Icon(Icons.arrow_drop_down_rounded, color: MC.kaki),
                        ],
                      ),
                    ),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              // Signal immédiat : numéro incomplet
              if (digits > 0 && digits < country.minDigits)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 12),
                  child: Text(
                    'Numéro incomplet — ${country.name} attend ${country.expected} chiffres',
                    style: TextStyle(color: MC.soleil, fontSize: Tx.label),
                  ),
                ),
            ] else ...[
              Center(
                child: OtpField(
                  key: otpKey,
                  length: 6,
                  onCompleted: (c) {
                    HapticFeedback.lightImpact();
                    _verify(c); // validation automatique
                  },
                ),
              ),
              if (demoCode != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Center(
                    child: Text('Mode démo — code : $demoCode',
                        style: TextStyle(color: MC.savane, fontSize: Tx.label)),
                  ),
                ),
              const SizedBox(height: 12),
              // Code parrain (facultatif) — 1 $ offert au 1er appel
              if (!showReferral)
                GestureDetector(
                  onTap: () => setState(() => showReferral = true),
                  child: Text(L10n.t('have_code'),
                      style: TextStyle(color: MC.soleil, fontSize: Tx.label)),
                )
              else
                TextField(
                  controller: referralCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(
                      fontSize: Tx.subtitle, color: MC.ivoire, letterSpacing: 2),
                  decoration: InputDecoration(
                      labelText: L10n.t('label_invite'),
                      hintText: 'MBOTE-XXXX'),
                ),
            ],
            const SizedBox(height: 26),
            MboteButton(
              label: otpSent ? 'Vérifier le code' : 'Recevoir mon code',
              loading: loading,
              // Désactivé tant que le numéro n'est pas valide / le code incomplet
              onTap: (!otpSent && !phoneValid) || (otpSent && (otpKey.currentState?.code.length ?? 0) != 6)
                  ? null
                  : () => otpSent ? _verify() : _requestOtp(),
            ),
            if (otpSent)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => otpSent = false),
                  child: Text('Changer de numéro',
                      style: TextStyle(color: MC.soleil)),
                ),
              ),
            const SizedBox(height: 22),
            Center(
              child: Text(
                'En continuant, tu acceptes les conditions d\u2019utilisation',
                textAlign: TextAlign.center,
                style: TextStyle(color: MC.kaki, fontSize: Tx.caption),
              ),
            ),
          ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
