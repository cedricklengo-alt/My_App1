import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../design.dart';
import '../l10n.dart';
import '../state.dart';
import '../theme.dart';

///TRANSACTIONS — le grand livre du portefeuille, tel que le serveur
/// l'enregistre : montants SIGNÉS (débit < 0, crédit > 0), statut réel
/// (en attente ≠ confirmé) et type métier.
///
/// L'écran ne calcule aucun solde : il affiche les écritures. C'est ce qui
/// garantit qu'un paiement « en attente » n'est jamais présenté comme reçu.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<Map> items = [];
  bool loading = true;
  String? error;
  String type = 'all';
  String statut = 'all';
  int offset = 0;
  bool hasMore = false;
  bool chargementPlus = false;

  /// Valeurs de `transactions.type` réellement écrites par le serveur.
  static const _types = <String, String>{
    'all': 'tx_filter_all',
    'call_debit': 'tx_calls',
    'sms_debit': 'tx_sms',
    'topup': 'tx_topup',
    'package': 'tx_packages',
    'transfer_out': 'tx_transfers',
    'call_reserve': 'wallet_reservation',
    'refund': 'wallet_refund',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool plus = false}) async {
    if (plus) {
      setState(() => chargementPlus = true);
    } else {
      setState(() {
        loading = true;
        error = null;
        offset = 0;
      });
    }
    try {
      final r = await context.read<AppState>().api.walletTransactions(
            type: type,
            status: statut,
            limit: 40,
            offset: plus ? offset : 0,
          );
      if (!mounted) return;
      final page = ((r['transactions'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        items = plus ? [...items, ...page] : page;
        offset = items.length;
        hasMore = r['has_more'] == true;
        loading = false;
        chargementPlus = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = friendlyError(e);
        loading = false;
        chargementPlus = false;
      });
    }
  }

  static int _n(dynamic v) => int.tryParse('${v ?? 0}') ?? 0;

  String _date(int ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String deux(int v) => v.toString().padLeft(2, '0');
    return '${deux(d.day)}/${deux(d.month)}/${d.year} · '
        '${deux(d.hour)}:${deux(d.minute)}';
  }

  IconData _icone(String t) => switch (t) {
        'call_debit' => Icons.call_rounded,
        'sms_debit' => Icons.sms_rounded,
        'topup' => Icons.add_card_rounded,
        'bonus' || 'referral_bonus' => Icons.celebration_rounded,
        'package' || 'package_purchase' => Icons.card_membership_rounded,
        'transfer_out' || 'transfer_in' => Icons.swap_horiz_rounded,
        'refund' || 'sms_refund' => Icons.undo_rounded,
        'call_reserve' => Icons.lock_clock_rounded,
        _ => Icons.receipt_long_rounded,
      };

  String? _libelleType(String t) {
    final cle = _types[t];
    return cle == null ? null : L10n.t(cle);
  }

  @override
  Widget build(BuildContext context) {
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
        title: Text(L10n.t('wallet_transactions'),
            style: TextStyle(
                color: MC.ivoire,
                fontWeight: FontWeight.w800,
                fontSize: Tx.title)),
      ),
      body: Column(
        children: [
          // ---- Filtres ----
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final t in _types.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(L10n.t(t.value)),
                      selected: type == t.key,
                      selectedColor: MC.soleil,
                      backgroundColor: MC.nuit2,
                      side: BorderSide(
                          color: type == t.key ? MC.soleil : MC.ligne),
                      showCheckmark: false,
                      labelStyle: TextStyle(
                          color: type == t.key ? MC.onAccent : MC.sable,
                          fontWeight: FontWeight.w700,
                          fontSize: Tx.label),
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => type = t.key);
                        _load();
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(L10n.t('wallet_pending_only')),
                    selected: statut == 'pending',
                    selectedColor: MC.braise.withValues(alpha: .25),
                    backgroundColor: MC.nuit2,
                    side: BorderSide(
                        color: statut == 'pending' ? MC.braise : MC.ligne),
                    showCheckmark: false,
                    labelStyle: TextStyle(
                        color: statut == 'pending' ? MC.ivoire : MC.sable,
                        fontWeight: FontWeight.w700,
                        fontSize: Tx.label),
                    onSelected: (v) {
                      HapticFeedback.selectionClick();
                      setState(() => statut = v ? 'pending' : 'all');
                      _load();
                    },
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: MC.ligne),
          Expanded(child: _corps()),
        ],
      ),
    );
  }

  Widget _corps() {
    if (loading) return const Center(child: Chargement());
    if (error != null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 40),
          Text(error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: MC.sable, fontSize: Tx.body)),
          const SizedBox(height: Sp.x4),
          Center(child: MboteButton(label: L10n.t('chat_retry'), onTap: _load)),
        ],
      );
    }
    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 50),
          Icon(Icons.receipt_long_rounded, size: 46, color: MC.kaki),
          const SizedBox(height: Sp.x3),
          Text(L10n.t('tx_empty'),
              textAlign: TextAlign.center,
              style: TextStyle(color: MC.kaki, fontSize: Tx.body)),
        ],
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 200 &&
            hasMore &&
            !chargementPlus) {
          _load(plus: true);
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: items.length + (hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: Chargement(taille: 18)),
            );
          }
          return _ligne(items[i]);
        },
      ),
    );
  }

  Widget _ligne(Map t) {
    final montant = _n(t['amount_cents']);
    final credit = montant > 0;
    final enAttente = '${t['status']}' == 'pending';
    final echoue = '${t['status']}' == 'failed';
    final ref = '${t['reference'] ?? t['method'] ?? ''}';
    final typeT = '${t['type'] ?? ''}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: MC.nuit2,
          borderRadius: BorderRadius.circular(Rd.md),
          border: Border.all(color: enAttente ? MC.braise : MC.ligne),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (credit ? MC.savane : MC.terre).withValues(alpha: .14),
                borderRadius: BorderRadius.circular(Rd.sm),
              ),
              child: Icon(_icone(typeT),
                  size: 17, color: credit ? MC.savane : MC.terre),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_libelleType(typeT) ?? typeT,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.body,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (ref.isNotEmpty) ref,
                      _date(_n(t['created_at'])),
                      if (enAttente) L10n.t('wallet_status_pending'),
                      if (echoue) L10n.t('wallet_status_failed'),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: enAttente
                            ? MC.braise
                            : echoue
                                ? MC.kaki
                                : MC.kaki,
                        fontSize: Tx.caption),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${credit ? '+' : '−'}${fmtMoney(montant.abs())}',
              style: TextStyle(
                color: echoue
                    ? MC.kaki.withValues(alpha: .7)
                    : credit
                        ? MC.savane
                        : MC.ivoire,
                fontSize: Tx.body,
                fontWeight: FontWeight.w800,
                decoration: echoue ? TextDecoration.lineThrough : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
