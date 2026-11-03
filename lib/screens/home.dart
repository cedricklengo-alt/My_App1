import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../design.dart';
import '../theme.dart';
import '../l10n.dart';
import 'airtime.dart';
import 'lokota.dart';
import 'packages.dart';
import 'topup.dart';
import 'transfer.dart';

/// Écran d'accueil épuré : solde + actions + promos.
/// (Favoris et contacts : accessibles depuis le Clavier — v1.3)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List promos = [];

  @override
  void initState() {
    super.initState();
    _loadPromos();
  }

  Future<void> _loadPromos() async {
    try {
      final p = await context.read<AppState>().api.promos();
      if (mounted) setState(() => promos = p);
    } catch (_) {/* pas bloquant */}
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return SafeArea(
      child: RefreshIndicator(
        color: MC.soleil,
        onRefresh: () async {
          await st.refresh();
          await _loadPromos();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x3, Sp.x4, Sp.x5),
          children: [
            Text(L10n.t('wallet'),
                style: TextStyle(
                    fontSize: Tx.headline,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                    color: MC.ivoire)),
            const SizedBox(height: 2),
            Text(st.name.isEmpty ? st.phone : st.name,
                style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
            const SizedBox(height: 16),

            // ---- Carte solde ----
            // Identité « Fleuve Congo » : la carte solde est un aplat de
            // sable, comme mes bulles de conversation. Pas d'ombre : un filet.
            Container(
              padding: const EdgeInsets.all(Sp.x5),
              decoration: BoxDecoration(
                color: MC.soleil,
                borderRadius: BorderRadius.circular(Rd.lg),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(L10n.t('my_credit').toUpperCase(),
                            style: TextStyle(
                                fontSize: Tx.caption,
                                letterSpacing: 1.4,
                                fontWeight: FontWeight.w800,
                                color: MC.onAccent)),
                        const SizedBox(height: Sp.x1),
                        Text(fmtMoney(st.balanceCents),
                            style: TextStyle(
                                fontSize: Tx.display,
                                fontWeight: FontWeight.w800,
                                color: MC.onAccent,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                        Text(
                            '≈ ${st.balanceCents ~/ 9} ${L10n.t('min_to_drc')}',
                            style: TextStyle(
                                fontSize: Tx.label,
                                color: MC.onAccent.withValues(alpha: .75))),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const TopupScreen())),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Sp.x4, vertical: Sp.x3),
                      decoration: BoxDecoration(
                        color: MC.onAccent,
                        borderRadius: BorderRadius.circular(Rd.md),
                      ),
                      child: Text(L10n.t('topup'),
                          style: TextStyle(
                              color: MC.soleil,
                              fontSize: Tx.label,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ---- 🗣️ Lokota : notes vocales traduites (pilote) ----
            GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LokotaScreen())),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: MC.nuit2,
                  borderRadius: BorderRadius.circular(Rd.md),
                  border: Border.all(color: MC.ligne),
                ),
                child: Row(
                  children: [
                    const Text('🗣️', style: TextStyle(fontSize: Tx.display)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(L10n.t('lokota_home_title'),
                                  style: TextStyle(
                                      fontSize: Tx.subtitle,
                                      fontWeight: FontWeight.w800,
                                      color: MC.ivoire)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: MC.soleil.withValues(alpha: .16),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: MC.soleil),
                                ),
                                child: Text(L10n.t('lokota_pilot'),
                                    style: TextStyle(
                                        color: MC.soleil,
                                        fontSize: Tx.caption,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(L10n.t('lokota_home_sub'),
                              style: TextStyle(
                                  fontSize: Tx.label,
                                  height: 1.35,
                                  color: MC.kaki)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: MC.soleil),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ---- Transfert + Crédit GSM côte à côte ----
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.send_rounded,
                    color: MC.savane,
                    label: L10n.t('send_credit'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const TransferScreen())),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.phone_android_rounded,
                    color: MC.soleil,
                    label: L10n.t('airtime_title'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AirtimeScreen())),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ---- Forfaits & Pass ----
            GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PackagesScreen())),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: MC.nuit2,
                  borderRadius: BorderRadius.circular(Rd.md),
                  border: Border.all(color: MC.ligne),
                ),
                child: Row(
                  children: [
                    Icon(Icons.card_membership_rounded,
                        color: MC.soleil, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(L10n.t('packages_title'),
                          style: TextStyle(
                              color: MC.ivoire,
                              fontWeight: FontWeight.w700,
                              fontSize: Tx.body)),
                    ),
                    Icon(Icons.chevron_right_rounded, color: MC.kaki),
                  ],
                ),
              ),
            ),

            // ---- ⚠️ Alerte crédit bas ----
            if (st.balanceCents < 100)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: MC.rouge.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(Rd.md),
                  border: Border.all(color: MC.rouge.withValues(alpha: .55)),
                ),
                child: Row(children: [
                  const Text('⚠️ ', style: TextStyle(fontSize: Tx.subtitle)),
                  Expanded(
                    child: Text(L10n.t('low_credit'),
                        style: TextStyle(
                            color: MC.ivoire, fontSize: Tx.label, height: 1.4)),
                  ),
                ]),
              ),

            // ---- 🎉 Bannière Happy Hour ----
            ...promos.map((p) => Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: MC.soleil.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(Rd.md),
                    border: Border.all(color: MC.soleil.withValues(alpha: .55)),
                  ),
                  child: Row(children: [
                    const Text('🎉 ', style: TextStyle(fontSize: Tx.subtitle)),
                    Expanded(
                      child: Text('${p['title']} — ${L10n.t('promo_until')}',
                          style: TextStyle(
                              color: MC.soleil,
                              fontWeight: FontWeight.w700,
                              fontSize: Tx.label)),
                    ),
                  ]),
                )),
          ],
        ),
      ),
    );
  }
}

/// Petite carte d'action (rangée transfert / crédit GSM)
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _ActionCard(
      {required this.icon,
      required this.color,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        // Audit a11y : la carte mesurait 47 px de haut, à un pixel du minimum
        // Material de 48 dp. `minHeight` garantit la cible quelle que soit
        // la taille du texte.
        child: Container(
          constraints: const BoxConstraints(minHeight: Tap.min),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: MC.nuit2,
            borderRadius: BorderRadius.circular(Rd.md),
            border: Border.all(color: MC.ligne),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: MC.ivoire,
                        fontWeight: FontWeight.w700,
                        fontSize: Tx.label,
                        height: 1.25)),
              ),
            ],
          ),
        ),
      );
}
