import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../design.dart';
import '../l10n.dart';
import '../state.dart';
import '../theme.dart';

/// 📋 FICHE D'UN APPEL — tout ce que le serveur sait de cette communication.
///
/// Distinction importante pour l'utilisateur :
///   • **ce qu'il a payé** (`cost_cents`, débit réel de son portefeuille) ;
///   • **ce que l'appel a coûté à l'entreprise** (`provider_cost_cents`, prix
///     fournisseur, souvent connu seulement après consolidation).
///
/// Les actions proposées dépendent du numéro : rappeler, écrire dans
/// l'application, envoyer un SMS, ou masquer l'entrée de l'historique
/// (donnée comptable conservée côté serveur).
class CallDetailSheet extends StatefulWidget {
  final String callId;
  final Map<String, dynamic>? fallback;
  final bool dialable;

  const CallDetailSheet({
    super.key,
    required this.callId,
    this.fallback,
    this.dialable = true,
  });

  @override
  State<CallDetailSheet> createState() => _CallDetailSheetState();
}

class _CallDetailSheetState extends State<CallDetailSheet> {
  Map<String, dynamic>? call;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await context.read<AppState>().api.callDetail(widget.callId);
      final c = Map<String, dynamic>.from(raw);
      if (!mounted) return;
      setState(() {
        call = c.isEmpty ? widget.fallback : c;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = friendlyError(e);
        call = widget.fallback;
        loading = false;
      });
    }
  }

  Future<void> _masquer() async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.nuit2,
        title: Text(L10n.t('history_delete_local'),
            style: TextStyle(color: MC.ivoire, fontSize: Tx.bodyLg)),
        content: Text(
          L10n.t('history_delete_note'),
          style: TextStyle(color: MC.kaki, fontSize: Tx.body, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(L10n.t('chat_cancel'),
                style: TextStyle(color: MC.kaki)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L10n.t('history_delete_local'),
                style: TextStyle(color: MC.braise)),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    try {
      await context.read<AppState>().api.hideCall(widget.callId);
      if (!mounted) return;
      Navigator.pop(context, 'hidden');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  static int _n(dynamic v) => int.tryParse('${v ?? 0}') ?? 0;

  String _heure(int ms) {
    if (ms <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String deux(int v) => v.toString().padLeft(2, '0');
    return '${deux(d.day)}/${deux(d.month)}/${d.year} · ${deux(d.hour)}:${deux(d.minute)}';
  }

  String _duree(int sec) {
    if (sec <= 0) return '—';
    final m = sec ~/ 60;
    final s = sec % 60;
    if (m == 0) return '${s}s';
    return s == 0 ? '${m}min' : '$m min ${deux(s)}s';
  }

  static String deux(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final c = call;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: MC.nuit2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Rd.lg)),
      ),
      child: SafeArea(
        top: false,
        child: loading
            ? const SizedBox(
                height: 160, child: Center(child: Chargement()))
            : SingleChildScrollView(child: _contenu(c)),
      ),
    );
  }

  Widget _contenu(Map<String, dynamic>? c) {
    if (c == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error ?? L10n.t('history_no_detail'),
              style: TextStyle(color: MC.kaki, fontSize: Tx.body)),
          const SizedBox(height: Sp.x3),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L10n.t('close'), style: TextStyle(color: MC.kaki)),
          ),
        ],
      );
    }

    final gsm = '${c['channel'] ?? ''}' == 'gsm';
    final cout = _n(c['cost_cents']);
    final sec = _n(c['billed_sec']);
    final tarif = _n(c['price_per_min_cents']);
    final numero = '${c['phone'] ?? c['callee'] ?? ''}';
    final nom = '${c['name'] ?? c['contact_name'] ?? ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(L10n.t('history_detail'),
                  style: TextStyle(
                      color: MC.ivoire,
                      fontSize: Tx.title,
                      fontWeight: FontWeight.w800)),
            ),
            IconButton(
              tooltip: L10n.t('close'),
              icon: Icon(Icons.close_rounded, color: MC.kaki),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: Sp.x1),
        Text(nom.isEmpty ? numero : nom,
            style: TextStyle(
                color: MC.ivoire,
                fontSize: Tx.bodyLg,
                fontWeight: FontWeight.w700)),
        if (nom.isNotEmpty)
          Text(numero,
              style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
        const SizedBox(height: Sp.x3),
        _ligne(Icons.schedule_rounded, L10n.t('chats_yesterday').isEmpty ? '' : 'Call',
            _heure(_n(c['started_at']))),
        _ligne(Icons.hourglass_bottom_rounded, L10n.t('history_duration'),
            _duree(sec)),
        _ligne(
          gsm ? Icons.phone_in_talk_rounded : Icons.wifi_rounded,
          L10n.t('history_channel'),
          gsm ? L10n.t('history_channel_gsm') : L10n.t('history_channel_internet'),
        ),
        if (gsm)
          _ligne(Icons.local_offer_rounded, L10n.t('history_price_per_min'),
              tarif > 0 ? '${fmtMoney(tarif)}/min' : '—'),
        _ligne(Icons.payments_rounded, L10n.t('history_billed'),
            cout > 0 ? fmtMoney(cout) : L10n.t('history_free')),
        if (c['provider_cost_cents'] != null)
          _ligne(Icons.cloud_rounded, 'Coût fournisseur',
              fmtMoney(_n(c['provider_cost_cents']))),
        if ('${c['hangup_cause'] ?? ''}'.isNotEmpty)
          _ligne(Icons.info_outline_rounded, L10n.t('history_status_ended'),
              '${c['hangup_cause']}'),
        const SizedBox(height: Sp.x4),
        if (widget.dialable) ...[
          MboteButton(
            label: L10n.t('history_recall'),
            onTap: () => Navigator.pop(context, 'call'),
          ),
          const SizedBox(height: Sp.x2),
          Row(
            children: [
              Expanded(
                child: _action(Icons.chat_bubble_rounded,
                    L10n.t('history_message'), () => Navigator.pop(context, 'message')),
              ),
              const SizedBox(width: Sp.x2),
              Expanded(
                child: _action(Icons.sms_rounded, 'SMS',
                    () => Navigator.pop(context, 'sms')),
              ),
            ],
          ),
          const SizedBox(height: Sp.x3),
        ],
        Center(
          child: TextButton.icon(
            onPressed: _masquer,
            icon: Icon(Icons.visibility_off_rounded, color: MC.kaki, size: 18),
            label: Text(L10n.t('history_delete_local'),
                style: TextStyle(color: MC.kaki, fontSize: Tx.body)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.x2),
          child: Text(L10n.t('history_delete_note'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: MC.kaki.withValues(alpha: .8),
                  fontSize: Tx.caption,
                  height: 1.4)),
        ),
      ],
    );
  }

  Widget _ligne(IconData icone, String libelle, String valeur) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 17, color: MC.kaki),
            const SizedBox(width: Sp.x2),
            Expanded(
              child: Text(libelle,
                  style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
            ),
            const SizedBox(width: Sp.x2),
            Flexible(
              child: Text(valeur,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: MC.ivoire,
                      fontSize: Tx.label,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _action(IconData icone, String texte, VoidCallback onTap) => Material(
        color: MC.nuit3,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rd.md),
            side: BorderSide(color: MC.ligne)),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icone, size: 17, color: MC.soleil),
                const SizedBox(width: 7),
                Text(texte,
                    style: TextStyle(
                        color: MC.ivoire,
                        fontSize: Tx.label,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
}
