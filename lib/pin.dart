import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'state.dart';
import 'design.dart';
import 'theme.dart';
import 'l10n.dart';

/// 🔐 Code PIN local (pur Dart, stocké dans SharedPreferences).
/// Protège l'ouverture de l'app — le solde et les transferts de l'utilisateur.
class Pin {
  static const _key = 'mbote_pin';

  static Future<String?> get() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  static Future<bool> isSet() async => (await get()) != null;

  static Future<void> save(String pin) async =>
      (await SharedPreferences.getInstance()).setString(_key, pin);

  static Future<void> remove() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}

/// Écran de verrouillage : pavé 4 chiffres, style « Soleil de Kin ».
/// - [setup] = true : choisir puis confirmer un nouveau code.
/// - sinon : vérifier le code existant (déverrouillage ou désactivation).
class PinScreen extends StatefulWidget {
  final bool setup;
  final VoidCallback onSuccess;
  const PinScreen({super.key, this.setup = false, required this.onSuccess});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String entered = '';
  String? firstPin; // en mode setup : 1re saisie à confirmer
  bool error = false;

  String get title {
    if (widget.setup) {
      return firstPin == null ? L10n.t('pin_new') : L10n.t('pin_confirm');
    }
    return L10n.t('pin_enter');
  }

  Future<void> _press(String d) async {
    if (entered.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() {
      entered += d;
      error = false;
    });
    if (entered.length < 4) return;

    // 4 chiffres saisis
    if (widget.setup) {
      if (firstPin == null) {
        setState(() {
          firstPin = entered;
          entered = '';
        });
      } else if (entered == firstPin) {
        await Pin.save(entered);
        widget.onSuccess();
      } else {
        setState(() {
          firstPin = null;
          entered = '';
          error = true;
        });
      }
    } else {
      final saved = await Pin.get();
      if (entered == saved) {
        widget.onSuccess();
      } else {
        setState(() {
          entered = '';
          error = true;
        });
      }
    }
  }

  void _erase() {
    if (entered.isEmpty) return;
    setState(() => entered = entered.substring(0, entered.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Container(
              width: 70,
              height: 70,
              decoration:
                  BoxDecoration(gradient: MC.degrade, shape: BoxShape.circle),
              child: Icon(Icons.lock_rounded, color: MC.onAccent, size: 32),
            ),
            const SizedBox(height: 18),
            Text(title,
                style: TextStyle(
                    fontSize: Tx.subtitle,
                    fontWeight: FontWeight.w800,
                    color: MC.ivoire)),
            const SizedBox(height: 8),
            SizedBox(
              height: 18,
              child: error
                  ? Text(L10n.t('pin_wrong'),
                      style: TextStyle(color: MC.rouge, fontSize: Tx.label))
                  : null,
            ),
            const SizedBox(height: 16),
            // ---- 4 points ----
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < entered.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? MC.soleil : Colors.transparent,
                    border: Border.all(
                        color: filled ? MC.soleil : MC.kaki, width: 1.6),
                  ),
                );
              }),
            ),
            const Spacer(),
            // ---- Pavé ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 44),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: keys
                    .map((k) => k.isEmpty
                        ? const SizedBox()
                        : Material(
                            color: MC.nuit3,
                            borderRadius: BorderRadius.circular(Rd.md),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(Rd.md),
                              onTap: () => k == '⌫' ? _erase() : _press(k),
                              child: Center(
                                child: Text(k,
                                    style: TextStyle(
                                        fontSize: Tx.headline,
                                        fontWeight: FontWeight.w600,
                                        color: MC.ivoire)),
                              ),
                            ),
                          ))
                    .toList(),
              ),
            ),
            const Spacer(),
            // 🆘 PIN oublié ? → on reprouve son identité par SMS (comme au 1er jour)
            if (!widget.setup)
              TextButton(
                onPressed: () => _forgotPin(context),
                child: Text(L10n.t('pin_forgot'),
                    style: TextStyle(
                        color: MC.kaki,
                        fontSize: Tx.label,
                        decoration: TextDecoration.underline,
                        decorationColor: MC.kaki)),
              ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }

  Future<void> _forgotPin(BuildContext context) async {
    final ok = await resetPinBySms(context);
    if (ok) widget.onSuccess();
  }
}

/// 🔐 Réinitialisation du PIN par SMS — réutilisable PARTOUT :
/// écran verrouillé (« Code PIN oublié ? ») ET Profil → PIN.
/// L'esprit « pro » : le numéro de téléphone EST l'identité du compte ;
/// celui qui reçoit le SMS est le propriétaire légitime.
/// Renvoie true si le PIN a bien été effacé.
Future<bool> resetPinBySms(BuildContext context) async {
  final st = context.read<AppState>();
  final phone = st.phone;
  if (phone.isEmpty) {
    _pinSnack(
        context,
        friendlyError(ApiException(
            'Pas d\'Internet — vérifie ta connexion 📶', 'offline')),
        err: true);
    return false;
  }

  // Étape 1. Explication claire + consentement
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: MC.nuit2,
      title: Text(L10n.t('pin_forgot'),
          style: TextStyle(color: MC.ivoire, fontSize: Tx.subtitle)),
      content: Text(L10n.t('pin_reset_body').replaceAll('%PHONE%', phone),
          style: TextStyle(color: MC.sable, fontSize: Tx.body, height: 1.5)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text(L10n.t('cancel_btn'), style: TextStyle(color: MC.kaki))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L10n.t('pin_reset_send'),
                style:
                    TextStyle(color: MC.soleil, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;

  // Étape 2. Envoi du code SMS dédié (protocole sécurisé : le code
  // n'est JAMAIS renvoyé à l'app — il arrive par SMS sur la SIM du compte)
  try {
    await st.api.pinResetRequest();
  } catch (e) {
    if (context.mounted) _pinSnack(context, friendlyError(e), err: true);
    return false;
  }
  if (!context.mounted) return false;

  // Étape 3. Saisie du code reçu
  final ctrl = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: MC.nuit2,
      title: Text(L10n.t('pin_reset_enter'),
          style: TextStyle(color: MC.ivoire, fontSize: Tx.subtitle)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(L10n.t('pin_reset_rules'),
                textAlign: TextAlign.center,
                style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
          ),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: TextStyle(color: MC.ivoire, fontSize: Tx.headline, letterSpacing: 8),
            decoration: InputDecoration(
              counterText: '',
              // Libellé persistant : un lecteur d'écran (et l'utilisateur)
              // sait à quoi sert le champ même après la saisie (WCAG 3.3.2).
              labelText: L10n.t('label_pin'),
              hintText: '••••••',
              hintStyle: TextStyle(color: MC.kaki),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text(L10n.t('cancel_btn'), style: TextStyle(color: MC.kaki))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('OK',
                style:
                    TextStyle(color: MC.soleil, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  if (code == null || code.isEmpty || !context.mounted) return false;

  // Étape 4. Vérification serveur (usage unique, 3 essais) → PIN effacé
  try {
    await st.api.pinResetVerify(code);
    await Pin.remove();
    if (context.mounted) {
      _pinSnack(context, L10n.t('pin_reset_done'));
    }
    return true;
  } catch (e) {
    if (context.mounted) _pinSnack(context, friendlyError(e), err: true);
    return false;
  }
}

void _pinSnack(BuildContext context, String msg, {bool err = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: err ? MC.rouge : MC.savane));
}
