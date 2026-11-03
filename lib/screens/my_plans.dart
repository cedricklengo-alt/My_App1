import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../design.dart';
import '../l10n.dart';
import '../state.dart';
import '../theme.dart';
import 'shop.dart';

/// 🎫 MES FORFAITS — ce que l'utilisateur a acheté et ce qu'il lui reste.
///
/// Deux sections :
///   • **Actifs** : quota restant (minutes/SMS), date d'expiration ;
///   • **Historique** : épuisés, expirés, annulés — jamais supprimés.
///
/// Les chiffres proviennent de `user_plans` côté serveur : l'app ne calcule
/// aucun quota elle-même et ne peut donc pas « inventer » du crédit.
class MyPlansScreen extends StatefulWidget {
  const MyPlansScreen({super.key});

  @override
  State<MyPlansScreen> createState() => _MyPlansScreenState();
}

class _MyPlansScreenState extends State<MyPlansScreen> {
  List<Map> actifs = [];
  List<Map> historique = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = context.read<AppState>().api;
      final a = await api.myPlans();
      final h = await api.myPlansAll();
      if (!mounted) return;
      setState(() {
        actifs = a.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        historique = h.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = friendlyError(e);
      });
    }
  }

  static int _n(dynamic v) => int.tryParse('${v ?? 0}') ?? 0;

  String _date(int ms) {
    if (ms <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
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
        title: Text(L10n.t('shop_my_plans'),
            style: TextStyle(
                color: MC.ivoire,
                fontWeight: FontWeight.w800,
                fontSize: Tx.title)),
        actions: [
          IconButton(
            tooltip: L10n.t('shop_title'),
            icon: Icon(Icons.add_shopping_cart_rounded, color: MC.soleil),
            onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ShopScreen()))
                .then((_) => _load()),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: MC.soleil,
        onRefresh: _load,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (loading) return const Center(child: Chargement());
    if (error != null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 60),
          Text(error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: MC.sable, fontSize: Tx.body)),
          const SizedBox(height: Sp.x4),
          Center(
              child: MboteButton(label: L10n.t('chat_retry'), onTap: _load)),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _titre(L10n.t('plans_active')),
        if (actifs.isEmpty)
          _vide(L10n.t('plans_none_active'))
        else
          for (final p in actifs) _carte(p, actif: true),
        const SizedBox(height: Sp.x5),
        _titre(L10n.t('plans_history')),
        if (historique.isEmpty)
          _vide(L10n.t('plans_none_history'))
        else
          for (final p in historique) _carte(p, actif: false),
      ],
    );
  }

  Widget _titre(String t) => Padding(
        padding: const EdgeInsets.only(bottom: Sp.x2),
        child: Text(t,
            style: TextStyle(
                color: MC.sable,
                fontSize: Tx.caption,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2)),
      );

  Widget _vide(String t) => Padding(
        padding: const EdgeInsets.only(bottom: Sp.x3),
        child: Text(t,
            style: TextStyle(color: MC.kaki, fontSize: Tx.body, height: 1.4)),
      );

  Widget _carte(Map p, {required bool actif}) {
    final total = _n(p['minutes_total']) * 60;
    final reste = _n(p['remaining_sec']);
    final smsTotal = _n(p['sms_total']);
    final smsReste = _n(p['remaining_sms']);
    final illimite = _n(p['unlimited']) == 1;
    final expire = _date(_n(p['expires_at']));
    final statut = '${p['status'] ?? (actif ? 'active' : '')}';

    final ratio = (!illimite && total > 0) ? (reste / total).clamp(0.0, 1.0) : 1.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x2),
      child: Container(
        padding: const EdgeInsets.all(Sp.x4),
        decoration: BoxDecoration(
          color: MC.nuit2,
          borderRadius: BorderRadius.circular(Rd.md),
          border: Border.all(color: actif ? MC.savane : MC.ligne),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${p['package_name'] ?? p['name'] ?? ''}',
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.bodyLg,
                          fontWeight: FontWeight.w800)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: actif ? MC.savane.withValues(alpha: .18) : MC.nuit3,
                    borderRadius: BorderRadius.circular(Rd.pill),
                  ),
                  child: Text(_libelleStatut(statut, actif),
                      style: TextStyle(
                          color: actif ? MC.savane : MC.kaki,
                          fontSize: Tx.caption,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: Sp.x2),
            if (illimite)
              Text(L10n.t('plans_unlimited'),
                  style: TextStyle(color: MC.sable, fontSize: Tx.body))
            else if (total > 0) ...[
              Text(
                  '${L10n.t('plans_remaining')} : '
                  '${(reste / 60).floor()} min / ${(total / 60).floor()} min',
                  style: TextStyle(color: MC.sable, fontSize: Tx.body)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(Rd.pill),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor: MC.nuit3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      ratio > .25 ? MC.savane : MC.braise),
                ),
              ),
            ],
            if (smsTotal > 0) ...[
              const SizedBox(height: 6),
              Text(
                  '${L10n.t('plans_sms_remaining')} : $smsReste / $smsTotal',
                  style: TextStyle(color: MC.sable, fontSize: Tx.body)),
            ],
            const SizedBox(height: Sp.x2),
            Text('${L10n.t('plans_expires')} : $expire',
                style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
          ],
        ),
      ),
    );
  }

  String _libelleStatut(String statut, bool actif) => switch (statut) {
        'active' => L10n.t('plans_status_active'),
        'exhausted' => L10n.t('plans_status_exhausted'),
        'expired' => L10n.t('plans_status_expired'),
        'suspended' => L10n.t('plans_status_suspended'),
        _ => actif ? L10n.t('plans_status_active') : statut,
      };
}
