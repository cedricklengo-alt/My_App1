import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../design.dart';
import '../theme.dart';
import '../l10n.dart';

///Forfaits & Pass : mes forfaits actifs + catalogue à acheter.
class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});
  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  List catalog = [];
  List mine = [];
  bool loading = true;
  int? buying;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    try {
      final results = await Future.wait([api.packages(), api.myPackages()]);
      if (!mounted) return;
      setState(() {
        catalog = results[0];
        mine = results[1];
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _buy(Map p) async {
    final st = context.read<AppState>();
    setState(() => buying = p['id']);
    try {
      await st.api.buyPackage(p['id']);
      await st.refresh();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L10n.t('bought_ok')), backgroundColor: MC.savane));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: MC.rouge));
    }
    if (mounted) setState(() => buying = null);
  }

  String _expiry(dynamic iso) {
    try {
      final d = DateTime.parse(iso.toString()).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t('packages_title'))),
      body: loading
          ? const Center(child: Chargement())
          : RefreshIndicator(
              color: MC.soleil,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x4, Sp.x6),
                children: [
                  Text(L10n.t('packages_sub'),
                      style: TextStyle(
                          color: MC.sable, fontSize: Tx.label, height: 1.5)),
                  const SizedBox(height: 18),

                  // ---- Mes forfaits actifs ----
                  if (mine.isNotEmpty) ...[
                    Text(L10n.t('my_packages'),
                        style: TextStyle(
                            color: MC.kaki,
                            fontSize: Tx.label,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    ...mine.map((p) => Container(
                          margin: const EdgeInsets.only(bottom: Sp.x2),
                          padding: const EdgeInsets.all(Sp.x4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Rd.md),
                            border: Border.all(
                                color: MC.savane.withValues(alpha: .55)),
                            color: MC.savane.withValues(alpha: .08),
                          ),
                          child: Row(children: [
                            Icon(Icons.inventory_2_rounded, size: Tx.headline, color: MC.soleil),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p['name'],
                                      style: TextStyle(
                                          color: MC.ivoire,
                                          fontWeight: FontWeight.w800,
                                          fontSize: Tx.bodyLg)),
                                  const SizedBox(height: 2),
                                  Text(
                                      '${L10n.t('expires')} ${_expiry(p['expires_at'])}',
                                      style: TextStyle(
                                          color: MC.kaki, fontSize: Tx.label)),
                                ],
                              ),
                            ),
                            Text(
                                p['unlimited'] == 1 || p['unlimited'] == true
                                    ? '∞ ${L10n.t('unlimited')}'
                                    : '${(p['remaining_sec'] / 60).floor()} min\n${L10n.t('remaining')}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    color: MC.savane,
                                    fontWeight: FontWeight.w800,
                                    fontSize: Tx.label,
                                    height: 1.3)),
                          ]),
                        )),
                    const SizedBox(height: 18),
                  ],

                  // ---- Catalogue ----
                  Text(L10n.t('catalog'),
                      style: TextStyle(
                          color: MC.kaki, fontSize: Tx.label, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  ...catalog.map((p) {
                    final unlimited = p['minutes'] == 0;
                    final affordable =
                        st.balanceCents >= (p['price_cents'] as int);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: MC.nuit2,
                        borderRadius: BorderRadius.circular(Rd.lg),
                        border: Border.all(
                            color: unlimited
                                ? MC.soleil.withValues(alpha: .55)
                                : MC.ligne),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(p['name'],
                                  style: TextStyle(
                                      color: MC.ivoire,
                                      fontWeight: FontWeight.w800,
                                      fontSize: Tx.subtitle)),
                            ),
                            Text(fmtMoney(p['price_cents']),
                                style: TextStyle(
                                    color: MC.soleil,
                                    fontWeight: FontWeight.w800,
                                    fontSize: Tx.subtitle)),
                          ]),
                          const SizedBox(height: 6),
                          Text(
                            '${unlimited ? '∞ ${L10n.t('unlimited')}' : '${p['minutes']} min'} · ${p['days']} jours · ${(p['prefix'] ?? '').toString().isEmpty ? '' : '+${p['prefix']}…'}',
                            style: TextStyle(color: MC.kaki, fontSize: Tx.label),
                          ),
                          const SizedBox(height: 12),
                          MboteButton(
                            label: affordable
                                ? L10n.t('buy')
                                : '${L10n.t('buy')} (solde insuffisant)',
                            loading: buying == p['id'],
                            onTap: affordable && buying == null
                                ? () => _buy(p)
                                : null,
                          ),
                        ],
                      ),
                    );
                  }),
                  if (catalog.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text('Aucun forfait disponible pour le moment',
                            style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
