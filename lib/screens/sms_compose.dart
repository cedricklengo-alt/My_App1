import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../design.dart';
import '../l10n.dart';
import '../state.dart';
import '../theme.dart';

/// ✉️ COMPOSITION D'UN SMS vers le réseau GSM.
///
/// Avant l'envoi, l'écran demande un DEVIS au serveur :
///   • destination couverte ou non (`NO_RATE`) ;
///   • prix exact (`sms_price_cents`) ou couverture par un forfait ;
///   • fournisseur prêt (`provider_ready`).
///
/// Il n'affiche jamais « c'est gratuit » sans preuve, et n'envoie rien si le
/// devis dit que l'envoi n'est pas possible. Un `client_id` aléatoire rend
/// l'envoi idempotent : un double appui ne produit pas deux SMS payants.
class SmsComposeScreen extends StatefulWidget {
  final String phone;
  const SmsComposeScreen({super.key, required this.phone});

  @override
  State<SmsComposeScreen> createState() => _SmsComposeScreenState();
}

class _SmsComposeScreenState extends State<SmsComposeScreen> {
  final _texte = TextEditingController();
  Map? devis;
  bool chargementDevis = true;
  bool envoi = false;
  String? erreur;

  /// Identifiant d'idempotence : stable pour cette rédaction.
  final String _clientId =
      'sms_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  @override
  void initState() {
    super.initState();
    _devis();
  }

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  Future<void> _devis() async {
    setState(() => chargementDevis = true);
    try {
      final d = await context.read<AppState>().api.smsQuote(widget.phone);
      if (!mounted) return;
      setState(() {
        devis = d;
        chargementDevis = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        erreur = friendlyError(e);
        chargementDevis = false;
      });
    }
  }

  Future<void> _envoyer() async {
    final texte = _texte.text.trim();
    if (texte.isEmpty) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    setState(() {
      envoi = true;
      erreur = null;
    });
    try {
      await context
          .read<AppState>()
          .api
          .sendSms(widget.phone, texte, clientId: _clientId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t('sms_sent'))),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        envoi = false;
        erreur = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prix = devis == null
        ? null
        : int.tryParse('${devis!['sms_price_cents'] ?? ''}');
    final couvert = devis?['covered_by_plan'] == true;
    final possible = devis?['can_send'] == true;
    final fournisseur = devis?['provider_ready'] == true;

    return Scaffold(
      backgroundColor: MC.nuit,
      appBar: AppBar(
        backgroundColor: MC.nuit2,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: MC.ligne)),
        leading: IconButton(
          tooltip: L10n.t('back'),
          icon: Icon(Icons.arrow_back_rounded, color: MC.ivoire),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(L10n.t('sms_title'),
            style: TextStyle(
                color: MC.ivoire,
                fontWeight: FontWeight.w800,
                fontSize: Tx.title)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Text(widget.phone,
              style: TextStyle(
                  color: MC.soleil,
                  fontSize: Tx.subtitle,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: Sp.x4),
          TextField(
            controller: _texte,
            maxLines: 5,
            maxLength: 320,
            autofocus: true,
            style: TextStyle(color: MC.ivoire, fontSize: Tx.body),
            decoration: InputDecoration(
              labelText: L10n.t('sms_hint'),
              alignLabelWithHint: true,
              hintStyle: TextStyle(color: MC.kaki),
              filled: true,
              fillColor: MC.nuit2,
              counterStyle: TextStyle(color: MC.kaki, fontSize: Tx.caption),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Rd.md),
                borderSide: BorderSide(color: MC.ligne),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Rd.md),
                borderSide: BorderSide(color: MC.ligne),
              ),
            ),
          ),
          const SizedBox(height: Sp.x2),
          if (chargementDevis)
            Row(children: [
              const Chargement(taille: 16),
              const SizedBox(width: Sp.x2),
              Text(L10n.t('loading'),
                  style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
            ])
          else if (devis != null)
            Container(
              padding: const EdgeInsets.all(Sp.x3),
              decoration: BoxDecoration(
                color: MC.nuit2,
                borderRadius: BorderRadius.circular(Rd.md),
                border: Border.all(color: MC.ligne),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                          couvert
                              ? Icons.check_circle_rounded
                              : Icons.payments_rounded,
                          size: 16,
                          color: couvert ? MC.savane : MC.soleil),
                      const SizedBox(width: Sp.x2),
                      Expanded(
                        child: Text(
                          couvert
                              ? L10n.t('sms_covered')
                              : prix == null
                                  ? L10n.t('sms_rate_missing')
                                  : '${L10n.t('sms_price')} : ${fmtMoney(prix)}',
                          style: TextStyle(
                              color: couvert ? MC.savane : MC.sable,
                              fontSize: Tx.label,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                  if (!fournisseur) ...[
                    const SizedBox(height: 6),
                    Text(L10n.t('sms_not_configured'),
                        style: TextStyle(
                            color: MC.braise, fontSize: Tx.caption, height: 1.4)),
                  ],
                  if ('${devis!['destination'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('${devis!['flag'] ?? ''} ${devis!['destination']}',
                        style:
                            TextStyle(color: MC.kaki, fontSize: Tx.caption)),
                  ],
                ],
              ),
            ),
          if (erreur != null) ...[
            const SizedBox(height: Sp.x2),
            Text(erreur!,
                style: TextStyle(
                    color: MC.braise, fontSize: Tx.label, height: 1.4)),
          ],
          const SizedBox(height: Sp.x4),
          MboteButton(
            label: L10n.t('sms_send'),
            loading: envoi,
            onTap: (possible && fournisseur && !envoi) ? _envoyer : null,
          ),
        ],
      ),
    );
  }
}
