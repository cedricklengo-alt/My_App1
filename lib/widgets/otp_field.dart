import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design.dart';
import '../theme.dart';

/// Champ OTP professionnel : [ 1 ] [ 2 ] [ 3 ] [ 4 ] [ 5 ] [ 6 ]
///
/// - nombre de cases configurable [length]
/// - passage automatique au champ suivant
/// - retour automatique à l'effacement
/// - collage complet du code pris en charge
/// - animation légère à chaque saisie
/// - [onCompleted] quand toutes les cases sont remplies
class OtpField extends StatefulWidget {
  final int length;
  final void Function(String code) onCompleted;
  const OtpField({super.key, this.length = 6, required this.onCompleted});

  @override
  State<OtpField> createState() => OtpFieldState();
}

class OtpFieldState extends State<OtpField> {
  late final List<TextEditingController> ctrls;
  late final List<FocusNode> nodes;
  late final List<bool> filled;

  @override
  void initState() {
    super.initState();
    ctrls = List.generate(widget.length, (_) => TextEditingController());
    nodes = List.generate(widget.length, (_) => FocusNode());
    filled = List.filled(widget.length, false);
    // iOS Autofill OTP : le clavier propose le code reçu automatiquement.
    nodes.first.requestFocus();
  }

  @override
  void dispose() {
    for (final c in ctrls) c.dispose();
    for (final n in nodes) n.dispose();
    super.dispose();
  }

  String get code => ctrls.map((c) => c.text).join();

  void _onChanged(int i, String v) {
    // Collage complet : on répartit les chiffres sur toutes les cases.
    if (v.length > 1) {
      final digits = v.replaceAll(RegExp(r'\D'), '');
      for (int k = 0; k < widget.length; k++) {
        ctrls[k].text = k < digits.length ? digits[k] : '';
      }
      final next = digits.length >= widget.length
          ? widget.length - 1
          : digits.length;
      nodes[next].requestFocus();
      _checkComplete();
      setState(() {});
      return;
    }
    final digit = v.replaceAll(RegExp(r'\D'), '');
    ctrls[i].text = digit;
    setState(() => filled[i] = digit.isNotEmpty);
    if (digit.isNotEmpty && i < widget.length - 1) {
      nodes[i + 1].requestFocus(); // avance automatique
    } else if (digit.isNotEmpty) {
      nodes[i].unfocus();
    }
    _checkComplete();
  }

  void _onKey(int i, RawKeyEvent e) {
    if (e is RawKeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.backspace &&
        ctrls[i].text.isEmpty &&
        i > 0) {
      nodes[i - 1].requestFocus(); // retour automatique
    }
  }

  void _checkComplete() {
    if (ctrls.every((c) => c.text.isNotEmpty)) {
      widget.onCompleted(code);
    }
  }

  /// Remplit les cases d'un coup (SMS Retriever / Autofill automatique).
  void fill(String c) {
    final digits = c.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    setState(() {
      for (int k = 0; k < widget.length; k++) {
        ctrls[k].text = k < digits.length ? digits[k] : '';
        filled[k] = k < digits.length;
      }
    });
    _checkComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.length, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: RawKeyboardListener(
            focusNode: FocusNode(),
            onKey: (e) => _onKey(i, e),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              width: 46,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: filled[i] ? MC.soleil.withValues(alpha: .14) : MC.nuit3,
                borderRadius: BorderRadius.circular(Rd.md),
                border: Border.all(
                  color: filled[i] ? MC.soleil : MC.ligne,
                  width: filled[i] ? 2 : 1,
                ),
              ),
              child: TextField(
                controller: ctrls[i],
                focusNode: nodes[i],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                autofillHints: i == 0 ? const [AutofillHints.oneTimeCode] : null,
                style: TextStyle(
                    color: MC.ivoire,
                    fontSize: Tx.subtitle,
                    fontWeight: FontWeight.w800),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(1),
                ],
                onChanged: (v) => _onChanged(i, v),
              ),
            ),
          ),
        );
      }),
    );
  }
}
