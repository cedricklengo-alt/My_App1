import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../design.dart';
import '../theme.dart';
import '../l10n.dart';
import 'airtime.dart';
import 'lokota.dart';
import 'my_plans.dart';
import 'packages.dart';
import 'shop.dart';
import 'topup.dart';
import 'transactions.dart';
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

  /// 📊 Résumé financier calculé par le SERVEUR (`/wallet/summary`).
  /// Aucun chiffre n'est estimé ici : si le résumé n'arrive pas, on n'affiche
  /// simplement pas le bloc (plutôt qu'un « 0 » trompeur).
  Map? resume;
  String? resumeErreur;

  @override
  void initState() {
    super.initState();
    _loadPromos();
    _loadResume();
  }

  Future<void> _loadPromos() async {
    try {
      final p = await context.read<AppState>().api.promos();
      if (mounted) setState(() => promos = p);
    } catch (_) {/* pas bloquant */}
  }

  Future<void> _loadResume() async {
    try {
      final r = await context.read<AppState>().api.walletSummary();
      if (!mounted) return;
      setState(() {
        resume = r;
        resumeErreur = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => resumeErreur = friendlyError(e));
    }
  }

  static int _n(dynamic v) => int.tryParse('${v ?? 0}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return SafeArea(
      child: RefreshIndicator(
        color: MC.soleil,
        onRefresh: () async {
          await st.refresh();
          await _loadPromos();
          await _loadResume();
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

            // ---- 📊 Activité réelle du portefeuille ----
            if (resume != null) ...[
              Container(
                padding: const EdgeInsets.all(Sp.x4),
                decoration: BoxDecoration(
                  color: MC.nuit2,
                  borderRadius: BorderRadius.circular(Rd.md),
                  border: Border.all(color: MC.ligne),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _stat(
                            L10n.t('wallet_today'),
                            fmtMoney(_n(resume!['today_cents'])),
                            MC.soleil,
                          ),
                        ),
                        Container(width: 1, height: 34, color: MC.ligne),
                        Expanded(
                          child: _stat(
                            L10n.t('wallet_calls_spend'),
                            fmtMoney(_n(resume!['month_calls_cents'])),
                            MC.savane,
                          ),
                        ),
                        Container(width: 1, height: 34, color: MC.ligne),
                        Expanded(
                          child: _stat(
                            L10n.t('wallet_sms_spend'),
                            fmtMoney(_n(resume!['month_sms_cents'])),
                            MC.terre,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Sp.x3),
                    Divider(color: MC.ligne, height: 1),
                    const SizedBox(height: Sp.x2),
                    Row(
                      children: [
                        Icon(Icons.calendar_month_rounded,
                            size: 15, color: MC.kaki),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${L10n.t('wallet_month')} : ${fmtMoney(_n(resume!['month_cents']))}',
                            style: TextStyle(
                                color: MC.kaki, fontSize: Tx.caption),
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: const Size(0, Tap.min)),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const TransactionsScreen()))
                              .then((_) => _loadResume()),
                          child: Text(L10n.t('wallet_transactions'),
                              style: TextStyle(
                                  color: MC.soleil,
                                  fontSize: Tx.caption,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ] else if (resumeErreur != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: MC.nuit2,
                  borderRadius: BorderRadius.circular(Rd.md),
                  border: Border.all(color: MC.ligne),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded, size: 15, color: MC.kaki),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(L10n.t('wallet_summary_unavailable'),
                        style: TextStyle(color: MC.kaki, fontSize: Tx.caption)),
                  ),
                  TextButton(
                    onPressed: _loadResume,
                    child: Text(L10n.t('chat_retry'),
                        style: TextStyle(color: MC.soleil, fontSize: Tx.caption)),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
            ],

            // ---- ⚠️ Alerte crédit bas ----
            if (resume?['low_balance'] == true || st.balanceCents < 100)
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(L10n.t('wallet_low_balance_title'),
                            style: TextStyle(
                                color: MC.ivoire,
                                fontSize: Tx.label,
                                fontWeight: FontWeight.w800)),
                        Text(L10n.t('wallet_low_balance_body'),
                            style: TextStyle(
                                color: MC.sable,
                                fontSize: Tx.caption,
                                height: 1.4)),
                      ],
                    ),
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

            // ---- 🛍️ Boutique (FlexPay) + Mes forfaits ----
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.storefront_rounded,
                    color: MC.soleil,
                    label: L10n.t('wallet_shop'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ShopScreen())).then((_) {
                      _loadResume();
                      st.refresh();
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.confirmation_number_rounded,
                    color: MC.savane,
                    label: L10n.t('wallet_my_plans'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const MyPlansScreen())),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ---- Forfaits & Pass (ancien catalogue interne) ----
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

          ],
        ),
      ),
    );
  }
}

/// Chiffre + libellé (bloc « activité du portefeuille »).
Widget _stat(String libelle, String valeur, Color couleur) => Column(
      children: [
        Text(valeur,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: couleur,
                fontSize: Tx.bodyLg,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(height: 3),
        Text(libelle,
            textAlign: TextAlign.center,
            style: TextStyle(color: MC.kaki, fontSize: Tx.caption)),
      ],
    );

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
