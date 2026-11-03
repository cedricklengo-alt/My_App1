import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../design.dart';
import '../l10n.dart';
import '../state.dart';
import '../theme.dart';
import 'my_plans.dart';

/// 🛍️ BOUTIQUE — catalogue, commande, paiement (Mobile Money ou carte Visa).
///
/// Le prix affiché vient du serveur (`shop_packages`), jamais du client. Après
/// le paiement, l'écran interroge le STATUT RÉEL de la commande : un retour
/// d'URL ou un simple « ça a l'air bon » n'active jamais un forfait.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  List<Map> packs = [];
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
      final list = await context.read<AppState>().api.shopCatalog();
      if (!mounted) return;
      setState(() {
        packs = list
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);
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

  /// Regroupement par catégorie : l'ordre du serveur est conservé.
  Map<String, List<Map>> get _parCategorie {
    final out = <String, List<Map>>{};
    for (final p in packs) {
      final cat = '${p['category'] ?? 'credit'}';
      out.putIfAbsent(cat, () => []).add(p);
    }
    return out;
  }

  String _labelCategorie(String cat) => switch (cat) {
        'minutes' => L10n.t('shop_cat_minutes'),
        'sms' => L10n.t('shop_cat_sms'),
        'mixte' => L10n.t('shop_cat_mix'),
        'pro' => L10n.t('shop_cat_pro'),
        _ => L10n.t('shop_cat_credit'),
      };

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
        title: Text(L10n.t('shop_title'),
            style: TextStyle(
                color: MC.ivoire,
                fontWeight: FontWeight.w800,
                fontSize: Tx.title)),
        actions: [
          IconButton(
            tooltip: L10n.t('shop_my_plans'),
            icon: Icon(Icons.confirmation_number_rounded, color: MC.soleil),
            onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const MyPlansScreen()))
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
          Icon(Icons.cloud_off_rounded, color: MC.kaki, size: 48),
          const SizedBox(height: Sp.x3),
          Text(error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: MC.sable, fontSize: Tx.body)),
          const SizedBox(height: Sp.x4),
          Center(
            child: MboteButton(
                label: L10n.t('chat_retry'), onTap: _load),
          ),
        ],
      );
    }
    if (packs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 60),
          Icon(Icons.storefront_rounded, color: MC.kaki, size: 48),
          const SizedBox(height: Sp.x3),
          Text(L10n.t('shop_empty'),
              textAlign: TextAlign.center,
              style: TextStyle(color: MC.kaki, fontSize: Tx.body)),
        ],
      );
    }

    final cats = _parCategorie;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(L10n.t('shop_intro'),
            style: TextStyle(
                color: MC.kaki, fontSize: Tx.label, height: 1.45)),
        const SizedBox(height: Sp.x2),
        for (final entree in cats.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: Sp.x4, bottom: Sp.x2),
            child: Text(_labelCategorie(entree.key),
                style: TextStyle(
                    color: MC.sable,
                    fontSize: Tx.caption,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
          ),
          for (final p in entree.value) _carte(p),
        ],
        const SizedBox(height: Sp.x5),
        Text(L10n.t('shop_payment_note'),
            style: TextStyle(color: MC.kaki, fontSize: Tx.caption, height: 1.45)),
      ],
    );
  }

  Widget _carte(Map p) {
    final prix = (p['price_cents'] is int)
        ? p['price_cents'] as int
        : int.tryParse('${p['price_cents'] ?? 0}') ?? 0;
    final minutes = int.tryParse('${p['minutes'] ?? 0}') ?? 0;
    final sms = int.tryParse('${p['sms_count'] ?? 0}') ?? 0;
    final jours = int.tryParse('${p['days'] ?? 0}') ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x2),
      child: Material(
        color: MC.nuit2,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rd.md),
            side: BorderSide(color: MC.ligne)),
        child: InkWell(
          onTap: () => _ouvrir(p),
          child: Padding(
            padding: const EdgeInsets.all(Sp.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text('${p['name'] ?? ''}',
                          style: TextStyle(
                              color: MC.ivoire,
                              fontSize: Tx.bodyLg,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: Sp.x2),
                    Text(fmtMoney(prix),
                        style: TextStyle(
                            color: MC.soleil,
                            fontSize: Tx.subtitle,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
                if ('${p['description'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('${p['description']}',
                      style: TextStyle(
                          color: MC.kaki, fontSize: Tx.label, height: 1.4)),
                ],
                const SizedBox(height: Sp.x2),
                Wrap(
                  spacing: Sp.x2,
                  runSpacing: Sp.x1,
                  children: [
                    if (minutes > 0) _puce(Icons.call_rounded, '$minutes min'),
                    if (sms > 0) _puce(Icons.sms_rounded, '$sms SMS'),
                    if (minutes == 0 && sms == 0) _puce(Icons.all_inclusive_rounded, L10n.t('shop_unlimited')),
                    if (jours > 0) _puce(Icons.event_rounded, '$jours ${L10n.t('shop_days')}'),
                    if ('${p['prefix'] ?? ''}'.isNotEmpty)
                      _puce(Icons.public_rounded, '+${p['prefix']}'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _puce(IconData icone, String texte) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: MC.nuit3, borderRadius: BorderRadius.circular(Rd.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 13, color: MC.sable),
            const SizedBox(width: 5),
            Text(texte, style: TextStyle(color: MC.sable, fontSize: Tx.caption)),
          ],
        ),
      );

  Future<void> _ouvrir(Map p) async {
    HapticFeedback.selectionClick();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AchatSheet(pack: p),
    );
    if (ok == true) _load();
  }
}

/// Feuille d'achat : récapitulatif → moyen de paiement → attente → résultat.
class _AchatSheet extends StatefulWidget {
  final Map pack;
  const _AchatSheet({required this.pack});

  @override
  State<_AchatSheet> createState() => _AchatSheetState();
}

class _AchatSheetState extends State<_AchatSheet> {
  final _phone = TextEditingController();
  String methode = 'mpesa'; // mpesa | orange | airtel | card
  String etape = 'recap'; // recap | attente | succes | echec
  String? message;
  String? redirectUrl;
  String? orderId;
  Timer? _poll;

  static const _operateurs = <String, String>{
    'mpesa': 'M-Pesa',
    'orange': 'Orange Money',
    'airtel': 'Airtel Money',
  };

  @override
  void initState() {
    super.initState();
    _phone.text = context.read<AppState>().phone;
  }

  @override
  void dispose() {
    _poll?.cancel();
    _phone.dispose();
    super.dispose();
  }

  int get _prix => int.tryParse('${widget.pack['price_cents'] ?? 0}') ?? 0;

  Future<void> _payer() async {
    final api = context.read<AppState>().api;
    FocusScope.of(context).unfocus();
    setState(() {
      etape = 'attente';
      message = L10n.t('shop_creating_order');
    });
    try {
      // 1) La commande fige le prix côté serveur.
      final order = await api.createShopOrder(
          int.tryParse('${widget.pack['id']}') ?? 0);
      orderId = '${order['id']}';
      if (!mounted) return;
      setState(() => message = L10n.t('shop_init_payment'));

      // 2) Paiement : Mobile Money (USSD Push) ou carte (page hébergée).
      final pay = await api.payShopOrder(orderId!, methode,
          phone: methode == 'card' ? null : _phone.text.trim());
      if (!mounted) return;
      redirectUrl = pay['redirect_url'] as String?;
      setState(() => message = '${pay['message'] ?? L10n.t('shop_waiting')}');

      // 3) On interroge le statut RÉEL jusqu'à confirmation ou abandon.
      _poll?.cancel();
      var essais = 0;
      _poll = Timer.periodic(const Duration(seconds: 3), (t) async {
        essais++;
        if (essais > 100) {
          t.cancel();
          if (mounted) {
            setState(() {
              etape = 'echec';
              message = L10n.t('shop_timeout');
            });
          }
          return;
        }
        try {
          final st = await api.shopPayStatus(orderId!);
          final statut = '${st['status']}';
          if (!mounted) return;
          if (statut == 'success') {
            t.cancel();
            final detail = await api.shopOrderStatus(orderId!);
            final plan = detail['order']?['status'];
            setState(() {
              etape = 'succes';
              message = '${plan ?? ''}';
            });
          } else if (statut == 'failed' || statut == 'cancelled') {
            t.cancel();
            setState(() {
              etape = 'echec';
              message = L10n.t('shop_payment_failed');
            });
          }
        } catch (_) {
          /* réseau instable : on réessaie au prochain tour */
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        etape = 'echec';
        message = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bas = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      margin: const EdgeInsets.only(top: 60),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bas),
      decoration: BoxDecoration(
        color: MC.nuit2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Rd.lg)),
      ),
      child: SingleChildScrollView(
        child: switch (etape) {
          'recap' => _recap(),
          'succes' => _resultat(true),
          'echec' => _resultat(false),
          _ => _attente(),
        },
      ),
    );
  }

  Widget _recap() {
    final p = widget.pack;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${p['name'] ?? ''}',
            style: TextStyle(
                color: MC.ivoire,
                fontSize: Tx.title,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(fmtMoney(_prix),
            style: TextStyle(
                color: MC.soleil,
                fontSize: Tx.headline,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: Sp.x3),
        if ('${p['description'] ?? ''}'.isNotEmpty)
          Text('${p['description']}',
              style: TextStyle(color: MC.sable, fontSize: Tx.body, height: 1.45)),
        if ('${p['conditions'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: Sp.x2),
          Text('${p['conditions']}',
              style: TextStyle(color: MC.kaki, fontSize: Tx.label, height: 1.4)),
        ],
        const SizedBox(height: Sp.x4),
        Text(L10n.t('shop_pay_with'),
            style: TextStyle(
                color: MC.kaki,
                fontSize: Tx.caption,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2)),
        const SizedBox(height: Sp.x2),
        for (final op in _operateurs.entries)
          _optionPaiement(op.key, op.value, Icons.phone_android_rounded),
        _optionPaiement('card', L10n.t('shop_card'), Icons.credit_card_rounded),
        if (methode != 'card') ...[
          const SizedBox(height: Sp.x3),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            style: TextStyle(color: MC.ivoire, fontSize: Tx.body),
            decoration: InputDecoration(
              labelText: L10n.t('label_phone'),
              hintText: '+243…',
              hintStyle: TextStyle(color: MC.kaki),
            ),
          ),
          const SizedBox(height: Sp.x1),
          Text(L10n.t('shop_mm_hint'),
              style: TextStyle(color: MC.kaki, fontSize: Tx.caption, height: 1.4)),
        ] else ...[
          const SizedBox(height: Sp.x2),
          Text(L10n.t('shop_card_hint'),
              style: TextStyle(color: MC.kaki, fontSize: Tx.caption, height: 1.4)),
        ],
        const SizedBox(height: Sp.x4),
        MboteButton(label: L10n.t('shop_pay'), onTap: _payer),
        const SizedBox(height: Sp.x2),
        Center(
          child: TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.t('chat_cancel'),
                style: TextStyle(color: MC.kaki, fontSize: Tx.body)),
          ),
        ),
      ],
    );
  }

  Widget _optionPaiement(String cle, String libelle, IconData icone) {
    final actif = methode == cle;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x2),
      child: Material(
        color: actif ? MC.nuit3 : Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rd.md),
          side: BorderSide(color: actif ? MC.soleil : MC.ligne),
        ),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => methode = cle);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icone, color: actif ? MC.soleil : MC.kaki, size: 20),
                const SizedBox(width: Sp.x3),
                Expanded(
                  child: Text(libelle,
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.body,
                          fontWeight: FontWeight.w600)),
                ),
                if (actif) Icon(Icons.check_circle_rounded, color: MC.soleil, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _attente() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Chargement(taille: 20),
              const SizedBox(width: Sp.x3),
              Expanded(
                child: Text(L10n.t('shop_waiting_title'),
                    style: TextStyle(
                        color: MC.ivoire,
                        fontSize: Tx.bodyLg,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: Sp.x3),
          Text(message ?? '',
              style: TextStyle(color: MC.sable, fontSize: Tx.body, height: 1.45)),
          if (redirectUrl != null && redirectUrl!.isNotEmpty) ...[
            const SizedBox(height: Sp.x3),
            SelectableText(redirectUrl!,
                style: TextStyle(color: MC.soleil, fontSize: Tx.label)),
            const SizedBox(height: Sp.x1),
            Text(L10n.t('shop_card_open_hint'),
                style: TextStyle(color: MC.kaki, fontSize: Tx.caption, height: 1.4)),
          ],
          const SizedBox(height: Sp.x4),
          TextButton(
            onPressed: () {
              _poll?.cancel();
              Navigator.pop(context, false);
            },
            child: Text(L10n.t('close'),
                style: TextStyle(color: MC.kaki, fontSize: Tx.body)),
          ),
        ],
      );

  Widget _resultat(bool succes) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(succes ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              color: succes ? MC.savane : MC.braise, size: 40),
          const SizedBox(height: Sp.x2),
          Text(succes ? L10n.t('shop_success') : L10n.t('shop_failed'),
              style: TextStyle(
                  color: MC.ivoire,
                  fontSize: Tx.title,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: Sp.x2),
          Text(message ?? '',
              style: TextStyle(color: MC.sable, fontSize: Tx.body, height: 1.45)),
          const SizedBox(height: Sp.x4),
          MboteButton(
            label: succes ? L10n.t('shop_my_plans') : L10n.t('chat_retry'),
            onTap: () {
              if (succes) {
                Navigator.pop(context, true);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MyPlansScreen()));
              } else {
                setState(() {
                  etape = 'recap';
                  message = null;
                });
              }
            },
          ),
          const SizedBox(height: Sp.x1),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context, succes),
              child: Text(L10n.t('close'),
                  style: TextStyle(color: MC.kaki, fontSize: Tx.body)),
            ),
          ),
        ],
      );
}
