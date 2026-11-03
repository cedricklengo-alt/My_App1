import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../design.dart';
import '../theme.dart';

/// Recharge du compte — Mobile Money en premier (maquette 04).
class TopupScreen extends StatefulWidget {
  const TopupScreen({super.key});
  @override
  State<TopupScreen> createState() => _TopupScreenState();
}

class _TopupScreenState extends State<TopupScreen> {
  int amountCents = 500;
  String method = 'mpesa';
  bool loading = false;

  static const amounts = [200, 500, 1000, 2000];
  static const methods = [
    ('mpesa', 'M-Pesa', 'Vodacom', Marques.mpesa),
    ('orange', 'Orange Money', 'Orange', Marques.orangeMoney),
    ('airtel', 'Airtel Money', 'Airtel', Marques.airtelMoney),
    ('card', 'Carte bancaire', 'Visa · Mastercard', Marques.carteBancaire),
  ];

  Future<void> _pay() async {
    final st = context.read<AppState>();
    setState(() => loading = true);
    try {
      // 1. Initier la recharge → le backend envoie le USSD Push
      final init = await st.api.topup(amountCents, method);
      if (!mounted) return;

      // 2. Attendre que le client confirme avec son PIN (polling 2 s)
      final result = await _waitForConfirmation(
          init['payment_id'] as String, init['message'] as String? ?? '');
      if (!mounted) return;

      if (result == null) return; // annulé par l'utilisateur

      if (result['status'] == 'success') {
        st.setBalance(result['balance_cents']);
        final bonus = (result['bonus_cents'] ?? 0) as int;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(bonus > 0
              ? '✓ Recharge réussie ! ${fmtMoney(result['credited_cents'])} crédités (dont ${fmtMoney(bonus)} de bonus 🎁)'
              : '✓ Recharge réussie ! ${fmtMoney(result['credited_cents'])} crédités'),
          backgroundColor: MC.savane,
        ));
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['status'] == 'failed'
              ? 'Paiement refusé ou annulé — votre solde n\'a pas été débité'
              : 'Paiement non confirmé à temps — réessayez'),
          backgroundColor: MC.rouge,
        ));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: MC.rouge));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Affiche la feuille « Confirmez sur votre téléphone » et interroge le
  /// backend toutes les 2 s jusqu'à success/failed (2 min max).
  /// Renvoie null si l'utilisateur ferme la feuille.
  Future<Map?> _waitForConfirmation(String paymentId, String message) async {
    final st = context.read<AppState>();
    return showModalBottomSheet<Map>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: MC.nuit2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Rd.lg))),
      builder: (sheetCtx) {
        Timer? timer;
        int ticks = 0;
        bool done = false;
        timer = Timer.periodic(const Duration(seconds: 2), (_) async {
          if (done) return;
          ticks++;
          try {
            final r = await st.api.topupStatus(paymentId);
            if (done) return;
            if (r['status'] != 'pending' || ticks >= 60) {
              done = true;
              timer?.cancel();
              if (sheetCtx.mounted) Navigator.pop(sheetCtx, r);
            }
          } catch (_) {/* on retentera au prochain tick */}
        });
        return PopScope(
          onPopInvokedWithResult: (_, __) => timer?.cancel(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                    width: 46,
                    height: 46,
                    child: CircularProgressIndicator(
                        color: MC.soleil, strokeWidth: 3)),
                const SizedBox(height: 20),
                Text('Confirmez sur votre téléphone 📲',
                    style: TextStyle(
                        color: MC.ivoire,
                        fontSize: Tx.subtitle,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(
                  message.isNotEmpty
                      ? message
                      : 'Une demande de paiement vient d\'être envoyée. Tapez votre code PIN Mobile Money pour valider.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: MC.sable, fontSize: Tx.label, height: 1.5),
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: () {
                    timer?.cancel();
                    Navigator.pop(sheetCtx, null);
                  },
                  child: Text('Annuler', style: TextStyle(color: MC.kaki)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recharger 💰')),
      body: ListView(
        padding: const EdgeInsets.all(Sp.x4),
        children: [
          Text('MONTANT',
              style: TextStyle(
                  color: MC.kaki,
                  fontSize: Tx.label,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: amounts
                .map((a) => ChoiceChip(
                      label: Text(fmtMoney(a).replaceAll(',00', '')),
                      selected: amountCents == a,
                      onSelected: (_) => setState(() => amountCents = a),
                      selectedColor: MC.soleil,
                      backgroundColor: MC.nuit2,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                          color: amountCents == a ? MC.onAccent : MC.sable,
                          fontWeight: FontWeight.w700,
                          fontSize: Tx.body),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Rd.sm),
                          side: BorderSide(
                              color: amountCents == a ? MC.soleil : MC.ligne)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          Text('🎁 +10% offerts dès 10 \$',
              style: TextStyle(color: MC.savane, fontSize: Tx.label)),
          const SizedBox(height: 24),
          Text('MOYEN DE PAIEMENT',
              style: TextStyle(
                  color: MC.kaki,
                  fontSize: Tx.label,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
          const SizedBox(height: 10),
          ...methods.map((m) {
            final selected = method == m.$1;
            return GestureDetector(
              onTap: () => setState(() => method = m.$1),
              child: Container(
                margin: const EdgeInsets.only(bottom: Sp.x2),
                padding:
                    const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: Sp.x3),
                decoration: BoxDecoration(
                  color: selected ? MC.halo : MC.nuit2,
                  borderRadius: BorderRadius.circular(Rd.md),
                  border: Border.all(
                      color: selected ? MC.soleil : MC.ligne,
                      width: selected ? 1.5 : 1),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: m.$4,
                          borderRadius: BorderRadius.circular(Rd.sm)),
                      child: Text(m.$2[0],
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: Tx.bodyLg,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.$2,
                              style: TextStyle(
                                  color: MC.ivoire,
                                  fontWeight: FontWeight.w700,
                                  fontSize: Tx.body)),
                          Text(m.$3,
                              style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
                        ],
                      ),
                    ),
                    Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: selected ? MC.soleil : MC.kaki,
                        size: 20),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 18),
          MboteButton(
            label:
                'Payer ${fmtMoney(amountCents).replaceAll(',00', '')} avec ${methods.firstWhere((m) => m.$1 == method).$2}',
            loading: loading,
            onTap: _pay,
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
                'Vous recevrez une demande de confirmation sur votre téléphone (code PIN)',
                textAlign: TextAlign.center,
                style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
          ),
        ],
      ),
    );
  }
}
