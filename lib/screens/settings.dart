import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../design.dart';
import '../l10n.dart';
import '../pin.dart';
import '../prefs.dart';
import '../push.dart';
import '../state.dart';
import '../theme.dart';
import 'home.dart';
import 'my_plans.dart';
import 'profile.dart';
import 'shop.dart';
import 'transactions.dart';

/// ⚙️ RÉGLAGES — le seul endroit où l'on change quelque chose dans l'app.
///
/// Organisation « comme WhatsApp », adaptée à nos écrans :
///
///   • **Compte**      : profil, portefeuille, forfaits, transactions ;
///   • **Réglages**    : apparence (thème, police, taille), langue,
///                       notifications et sonnerie ;
///   • **Confidentialité et sécurité** : code PIN, session ;
///   • **Aide**        : à propos, inviter un ami.
///
/// Chaque ligne mène à un écran RÉEL et chaque réglage est enregistré sur le
/// téléphone (`SharedPreferences`) puis appliqué au démarrage suivant.
/// Aucune ligne « bientôt » : si une fonction n'existe pas, elle n'est pas là.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool pinSet = false;

  @override
  void initState() {
    super.initState();
    Pin.isSet().then((v) {
      if (mounted) setState(() => pinSet = v);
    });
  }

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _relirePin() async {
    final v = await Pin.isSet();
    if (mounted) setState(() => pinSet = v);
  }

  Future<void> _deconnexion() async {
    final st = context.read<AppState>();
    final oui = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.nuit2,
        title: Text(L10n.t('logout'),
            style: TextStyle(
                color: MC.ivoire, fontSize: Tx.subtitle, fontWeight: FontWeight.w800)),
        content: Text(L10n.t('logout_confirm'),
            style: TextStyle(color: MC.sable, fontSize: Tx.body)),
        actions: [
          TextButton(
            key: const Key('settings-logout-cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(L10n.t('cancel_btn'), style: TextStyle(color: MC.kaki)),
          ),
          TextButton(
            key: const Key('settings-logout-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L10n.t('logout'),
                style: TextStyle(color: MC.rouge, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (oui == true) await st.logout();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return Scaffold(
      backgroundColor: MC.nuit,
      appBar: AppBar(
        backgroundColor: MC.nuit2,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: MC.ligne)),
        leading: IconButton(
          key: const Key('settings-back'),
          tooltip: L10n.t('back'),
          icon: Icon(Icons.arrow_back_rounded, color: MC.ivoire),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(L10n.t('settings'),
            style: TextStyle(
                color: MC.ivoire,
                fontSize: Tx.title,
                fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          // ---- Carte du compte ----
          _CarteCompte(state: st, onTap: () => _push(const ProfileScreen())),
          const SizedBox(height: Sp.x2),

          _section(L10n.t('settings_section_account')),
          _Ligne(
            icon: Icons.person_rounded,
            color: MC.soleil,
            titre: L10n.t('profile'),
            sous: st.name.isEmpty ? st.phone : st.name,
            onTap: () => _push(const ProfileScreen()),
          ),
          _Ligne(
            icon: Icons.account_balance_wallet_rounded,
            color: MC.savane,
            titre: L10n.t('wallet'),
            sous: fmtMoney(st.balanceCents),
            onTap: () => _push(const _PortefeuilleEcran()),
          ),
          _Ligne(
            icon: Icons.storefront_rounded,
            color: MC.soleil,
            titre: L10n.t('shop_title'),
            sous: L10n.t('settings_shop_sub'),
            onTap: () => _push(const ShopScreen()),
          ),
          _Ligne(
            icon: Icons.confirmation_number_rounded,
            color: MC.savane,
            titre: L10n.t('shop_my_plans'),
            sous: L10n.t('settings_plans_sub'),
            onTap: () => _push(const MyPlansScreen()),
          ),
          _Ligne(
            icon: Icons.receipt_long_rounded,
            color: MC.terre,
            titre: L10n.t('wallet_transactions'),
            sous: L10n.t('settings_tx_sub'),
            onTap: () => _push(const TransactionsScreen()),
          ),

          _section(L10n.t('settings_section_prefs')),
          _Ligne(
            icon: Icons.palette_rounded,
            color: MC.soleil,
            titre: L10n.t('appearance'),
            sous:
                '${ThemeCtl.themes[ThemeCtl.theme] ?? ''} · ${ThemeCtl.fonts[ThemeCtl.font] ?? ''}',
            onTap: () => _push(const AppearanceScreen()),
          ),
          _Ligne(
            icon: Icons.translate_rounded,
            color: MC.savane,
            titre: L10n.t('language'),
            sous: L10n.langs[L10n.lang] ?? L10n.lang,
            onTap: () => _push(const LanguageScreen()),
          ),
          _Ligne(
            icon: Icons.notifications_active_rounded,
            color: MC.braise,
            titre: L10n.t('settings_notifications'),
            sous: CallPrefs.vibration
                ? L10n.t('settings_notif_on')
                : L10n.t('settings_notif_silent'),
            onTap: () => _push(const NotificationsScreen()),
          ),

          _section(L10n.t('settings_section_privacy')),
          _Ligne(
            icon: Icons.shield_rounded,
            color: pinSet ? MC.savane : MC.kaki,
            titre: L10n.t('settings_security'),
            sous:
                pinSet ? L10n.t('settings_pin_on') : L10n.t('settings_pin_off'),
            key: const Key('settings-security'),
            onTap: () async {
              await _push(const SecurityScreen());
              await _relirePin();
            },
          ),

          _section(L10n.t('settings_section_help')),
          _Ligne(
            icon: Icons.info_outline_rounded,
            color: MC.kaki,
            titre: L10n.t('about'),
            sous: 'MboteCall',
            onTap: () {
              showAboutDialogMbote(context);
            },
          ),
          _Ligne(
            icon: Icons.favorite_rounded,
            color: MC.braise,
            titre: L10n.t('invite'),
            sous: L10n.t('invite_sub'),
            onTap: () => _push(const ProfileScreen()),
          ),
          const SizedBox(height: Sp.x4),
          OutlinedButton.icon(
            key: const Key('settings-logout'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: MC.rouge),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.md)),
            ),
            onPressed: _deconnexion,
            icon: Icon(Icons.logout_rounded, color: MC.rouge, size: 18),
            label: Text(L10n.t('logout'),
                style: TextStyle(color: MC.rouge, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: Sp.x3),
          Center(
            child: Text('MboteCall · v3.6',
                style: TextStyle(color: MC.kaki, fontSize: Tx.caption)),
          ),
        ],
      ),
    );
  }

  Widget _section(String titre) => Padding(
        padding: const EdgeInsets.fromLTRB(4, Sp.x4, 4, Sp.x2),
        child: Text(titre,
            style: TextStyle(
                color: MC.kaki,
                fontSize: Tx.caption,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2)),
      );
}

/// Écran du portefeuille : `HomeScreen` est un corps d'écran (sans Scaffold),
/// on l'enveloppe ici pour avoir une flèche de retour.
class _PortefeuilleEcran extends StatelessWidget {
  const _PortefeuilleEcran();

  @override
  Widget build(BuildContext context) => Scaffold(
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
          title: Text(L10n.t('wallet'),
              style: TextStyle(
                  color: MC.ivoire,
                  fontSize: Tx.title,
                  fontWeight: FontWeight.w800)),
        ),
        body: const HomeScreen(),
      );
}

// ────────────────────────────────────────────────────────────────
// Briques communes
// ────────────────────────────────────────────────────────────────

/// Une ligne de réglage : icône, titre, sous-titre, chevron.
class _Ligne extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String titre;
  final String? sous;
  final VoidCallback? onTap;

  const _Ligne({
    super.key,
    required this.icon,
    required this.color,
    required this.titre,
    this.sous,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: MC.nuit2,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rd.md),
          side: BorderSide(color: MC.ligne),
        ),
        child: ListTile(
          onTap: onTap,
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(Rd.sm),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          title: Text(titre,
              style: TextStyle(
                  color: MC.ivoire,
                  fontSize: Tx.bodyLg,
                  fontWeight: FontWeight.w600)),
          subtitle: (sous == null || sous!.isEmpty)
              ? null
              : Text(sous!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
          trailing: onTap == null
              ? null
              : Icon(Icons.chevron_right_rounded, color: MC.kaki),
        ),
      ),
    );
  }
}

/// Bandeau du compte : avatar, nom, numéro, solde.
class _CarteCompte extends StatelessWidget {
  final AppState state;
  final VoidCallback onTap;
  const _CarteCompte({required this.state, required this.onTap});

  static String _initiales(String nom) {
    final propre = nom.trim();
    if (propre.isEmpty) return '?';
    final parts = propre.split(RegExp(r'\s+'));
    final a = String.fromCharCodes(parts.first.runes.take(1));
    if (parts.length == 1) return a.toUpperCase();
    final b = String.fromCharCodes(parts.last.runes.take(1));
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MC.nuit2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rd.lg),
        side: BorderSide(color: MC.ligne),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Sp.x4),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: MC.degrade,
                  borderRadius: BorderRadius.circular(Rd.avatar),
                ),
                child: Text(_initiales(state.name),
                    style: TextStyle(
                        color: MC.onAccent,
                        fontSize: Tx.bodyLg,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: Sp.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.name.isEmpty ? state.phone : state.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: MC.ivoire,
                            fontSize: Tx.bodyLg,
                            fontWeight: FontWeight.w800)),
                    Text(state.phone,
                        style:
                            TextStyle(color: MC.kaki, fontSize: Tx.label)),
                  ],
                ),
              ),
              const SizedBox(width: Sp.x2),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: MC.nuit3,
                    borderRadius: BorderRadius.circular(Rd.md)),
                child: Text(fmtMoney(state.balanceCents),
                    style: TextStyle(
                        color: MC.soleil,
                        fontSize: Tx.label,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// 🎨 Apparence — thème, police, taille du texte
// ────────────────────────────────────────────────────────────────

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  double echelle = ThemeCtl.textScale;

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
        title: Text(L10n.t('appearance'),
            style: TextStyle(
                color: MC.ivoire,
                fontSize: Tx.title,
                fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _titre(L10n.t('theme_label')),
          for (final e in ThemeCtl.themes.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Choix(
                key: Key('theme-${e.key}'),
                titre: e.value,
                selectionne: ThemeCtl.theme == e.key,
                pastille: LinearGradient(
                  colors: [
                    kPalettes[e.key]!.accent,
                    kPalettes[e.key]!.accent2,
                  ],
                ),
                onTap: () async {
                  HapticFeedback.selectionClick();
                  await ThemeCtl.setTheme(e.key);
                  if (mounted) setState(() {});
                },
              ),
            ),

          _titre(L10n.t('font_label')),
          for (final e in ThemeCtl.fonts.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Choix(
                key: Key('font-${e.key}'),
                titre: e.value,
                selectionne: ThemeCtl.font == e.key,
                police: switch (e.key) {
                  'serif' => 'serif',
                  'condensed' => 'sans-serif-condensed',
                  'mono' => 'monospace',
                  _ => null,
                },
                onTap: () async {
                  HapticFeedback.selectionClick();
                  await ThemeCtl.setFont(e.key);
                  if (mounted) setState(() {});
                },
              ),
            ),

          _titre(L10n.t('text_size')),
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
                    Text('A', style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
                    Expanded(
                      child: Slider(
                        key: const Key('text-size-slider'),
                        value: echelle,
                        min: ThemeCtl.echelleMin,
                        max: ThemeCtl.echelleMax,
                        divisions:
                            ((ThemeCtl.echelleMax - ThemeCtl.echelleMin) / .05)
                                .round(),
                        activeColor: MC.soleil,
                        inactiveColor: MC.nuit3,
                        label: '${(echelle * 100).round()} %',
                        onChanged: (v) => setState(() => echelle = v),
                        onChangeEnd: (v) async {
                          final retenu = await ThemeCtl.setTextScale(v);
                          if (mounted) setState(() => echelle = retenu);
                        },
                      ),
                    ),
                    Text('A',
                        style: TextStyle(color: MC.kaki, fontSize: Tx.subtitle)),
                  ],
                ),
                Text('${(echelle * 100).round()} %',
                    style: TextStyle(
                        color: MC.soleil,
                        fontSize: Tx.bodyLg,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: Sp.x2),
                // Aperçu réel : le texte grossit sous les yeux.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Sp.x3),
                  decoration: BoxDecoration(
                    color: MC.nuit3,
                    borderRadius: BorderRadius.circular(Rd.sm),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(L10n.t('text_size_preview_title'),
                          style: TextStyle(
                              color: MC.ivoire,
                              fontSize: Tx.bodyLg,
                              fontWeight: FontWeight.w800)),
                      Text(L10n.t('text_size_preview_body'),
                          style: TextStyle(
                              color: MC.sable, fontSize: Tx.body, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.x3),
          Center(
            child: TextButton(
              key: const Key('text-size-reset'),
              onPressed: () async {
                final v = await ThemeCtl.resetTextScale();
                if (mounted) setState(() => echelle = v);
              },
              child: Text(L10n.t('text_size_reset'),
                  style: TextStyle(color: MC.kaki, fontSize: Tx.body)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _titre(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, Sp.x3, 4, Sp.x2),
        child: Text(t,
            style: TextStyle(
                color: MC.kaki,
                fontSize: Tx.caption,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2)),
      );
}

/// Ligne de choix (thème, police) avec pastille et coche.
class _Choix extends StatelessWidget {
  final String titre;
  final bool selectionne;
  final LinearGradient? pastille;
  final String? police;
  final VoidCallback onTap;

  const _Choix({
    super.key,
    required this.titre,
    required this.selectionne,
    required this.onTap,
    this.pastille,
    this.police,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selectionne ? MC.nuit3 : MC.nuit2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rd.md),
        side: BorderSide(color: selectionne ? MC.soleil : MC.ligne),
      ),
      child: ListTile(
        onTap: onTap,
        leading: pastille == null
            ? Icon(Icons.font_download_rounded, color: MC.kaki, size: 20)
            : Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: pastille,
                  border: Border.all(color: MC.ligne, width: 2),
                ),
              ),
        title: Text(titre,
            style: TextStyle(
                color: MC.ivoire,
                fontSize: Tx.bodyLg,
                fontWeight: FontWeight.w600,
                fontFamily: police)),
        trailing: selectionne
            ? Icon(Icons.check_circle_rounded, color: MC.soleil, size: 20)
            : null,
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// 🗣️ Langue — 3 langues intégrées + téléchargement depuis le serveur
// ────────────────────────────────────────────────────────────────

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  bool chargement = false;
  String? erreur;
  List disponibles = [];
  bool aCharge = false;

  Future<void> _chargerDisponibles() async {
    setState(() {
      chargement = true;
      erreur = null;
    });
    try {
      final l = await context.read<AppState>().api.availableLangs();
      if (!mounted) return;
      setState(() {
        disponibles = l.where((x) => !L10n.langs.containsKey(x['code'])).toList();
        chargement = false;
        aCharge = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        erreur = friendlyError(e);
        chargement = false;
      });
    }
  }

  Future<void> _installer(Map l) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        SnackBar(content: Text(L10n.t('downloading')), duration: const Duration(seconds: 1)));
    try {
      final pack = await context.read<AppState>().api.langPack(l['code']);
      final strings = Map<String, String>.from(
          (pack['strings'] as Map?) ?? const {});
      if (strings.isEmpty) throw ApiException(L10n.t('lang_empty_pack'));
      await L10n.install('${l['code']}', '${l['name']}', strings);
      if (!mounted) return;
      setState(() => disponibles.remove(l));
      messenger.showSnackBar(
          SnackBar(content: Text(L10n.t('downloaded')), backgroundColor: MC.savane));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: MC.rouge));
    }
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
        title: Text(L10n.t('language'),
            style: TextStyle(
                color: MC.ivoire,
                fontSize: Tx.title,
                fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          for (final e in L10n.langs.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Choix(
                key: Key('lang-${e.key}'),
                titre: e.value,
                selectionne: L10n.lang == e.key,
                onTap: () async {
                  HapticFeedback.selectionClick();
                  await L10n.setLang(e.key);
                  if (mounted) setState(() {});
                },
              ),
            ),
          const SizedBox(height: Sp.x3),
          Divider(color: MC.ligne, height: 1),
          const SizedBox(height: Sp.x3),
          if (!aCharge)
            MboteButton(
                key: const Key('lang-more'),
                label: L10n.t('lang_more'),
                loading: chargement,
                onTap: _chargerDisponibles),
          if (erreur != null) ...[
            const SizedBox(height: Sp.x2),
            Text(erreur!,
                textAlign: TextAlign.center,
                style: TextStyle(color: MC.braise, fontSize: Tx.label)),
            const SizedBox(height: Sp.x1),
            Center(
              child: TextButton(
                onPressed: _chargerDisponibles,
                child: Text(L10n.t('chat_retry'),
                    style: TextStyle(color: MC.soleil, fontSize: Tx.body)),
              ),
            ),
          ],
          if (aCharge && disponibles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.x3),
              child: Text(L10n.t('lang_all_installed'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
            ),
          for (final l in disponibles)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Ligne(
                icon: Icons.download_rounded,
                color: MC.savane,
                titre: '${l['name'] ?? l['code']}',
                sous: L10n.t('lang_download_hint'),
                onTap: () => _installer(Map<String, dynamic>.from(l as Map)),
              ),
            ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// 🔔 Notifications et sonnerie
// ────────────────────────────────────────────────────────────────

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final FlutterRingtonePlayer _player = FlutterRingtonePlayer();
  bool _relance = false;

  @override
  void dispose() {
    _player.stop();
    super.dispose();
  }

  /// Fait écouter 2,5 s la sonnerie choisie : on sait ce qu'on choisit.
  void _ecouter(String cle) {
    _player.stop();
    switch (cle) {
      case 'douce':
        _player.play(
            android: AndroidSounds.notification,
            ios: IosSounds.triTone,
            looping: false,
            volume: .9);
      case 'forte':
        _player.playAlarm(looping: false, volume: 1);
      case 'silencieux':
        return;
      default:
        _player.playRingtone(looping: false, volume: 1);
    }
    Timer(const Duration(milliseconds: 2500), _player.stop);
  }

  @override
  Widget build(BuildContext context) {
    const options = [
      ('classique', Icons.ring_volume_rounded, 'ring_classic'),
      ('douce', Icons.music_note_rounded, 'ring_soft'),
      ('forte', Icons.campaign_rounded, 'ring_loud'),
      ('silencieux', Icons.notifications_off_rounded, 'ring_silent'),
    ];

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
        title: Text(L10n.t('settings_notifications'),
            style: TextStyle(
                color: MC.ivoire,
                fontSize: Tx.title,
                fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Text(L10n.t('ring_hint'),
              style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
          const SizedBox(height: Sp.x3),
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Choix(
                key: Key('ring-${o.$1}'),
                titre: L10n.t(o.$3),
                selectionne: CallPrefs.ringtone == o.$1,
                onTap: () async {
                  HapticFeedback.selectionClick();
                  await CallPrefs.setRingtone(o.$1);
                  _ecouter(o.$1);
                  if (mounted) setState(() {});
                },
              ),
            ),
          const SizedBox(height: Sp.x2),
          Material(
            color: MC.nuit2,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Rd.md),
              side: BorderSide(color: MC.ligne),
            ),
            child: SwitchListTile(
              key: const Key('ring-vibration'),
              value: CallPrefs.vibration,
              activeThumbColor: MC.soleil,
              secondary: Icon(Icons.vibration_rounded,
                  color: CallPrefs.vibration ? MC.soleil : MC.kaki),
              title: Text(L10n.t('vibration'),
                  style: TextStyle(
                      color: MC.ivoire,
                      fontSize: Tx.bodyLg,
                      fontWeight: FontWeight.w600)),
              subtitle: Text(L10n.t('settings_vibration_sub'),
                  style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
              onChanged: (v) async {
                await CallPrefs.setVibration(v);
                if (v) HapticFeedback.vibrate();
                if (mounted) setState(() {});
              },
            ),
          ),
          const SizedBox(height: Sp.x4),
          Text(L10n.t('settings_push_title'),
              style: TextStyle(
                  color: MC.kaki,
                  fontSize: Tx.caption,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
          const SizedBox(height: Sp.x2),
          Container(
            padding: const EdgeInsets.all(Sp.x4),
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
                    Icon(Icons.phone_in_talk_rounded, color: MC.savane, size: 18),
                    const SizedBox(width: Sp.x2),
                    Expanded(
                      child: Text(L10n.t('settings_push_body'),
                          style: TextStyle(
                              color: MC.sable,
                              fontSize: Tx.label,
                              height: 1.45)),
                    ),
                  ],
                ),
                const SizedBox(height: Sp.x3),
                MboteButton(
                  key: const Key('push-reactivate'),
                  label: L10n.t('settings_push_action'),
                  loading: _relance,
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    final api = context.read<AppState>().api;
                    final messenger = ScaffoldMessenger.of(context);
                    setState(() => _relance = true);
                    await Push.register(api, force: true);
                    if (!mounted) return;
                    setState(() => _relance = false);
                    messenger.showSnackBar(SnackBar(
                        content: Text(L10n.t('settings_push_sent')),
                        backgroundColor: MC.savane));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// 🔐 Confidentialité et sécurité — code PIN + session
// ────────────────────────────────────────────────────────────────

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool pinSet = false;

  @override
  void initState() {
    super.initState();
    Pin.isSet().then((v) {
      if (mounted) setState(() => pinSet = v);
    });
  }

  Future<void> _activer() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PinScreen(
          setup: true,
          onSuccess: () {
            Navigator.pop(context);
          },
        ),
      ),
    );
    final v = await Pin.isSet();
    if (mounted) setState(() => pinSet = v);
  }

  Future<void> _verifierPuis(Future<void> Function() action) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PinScreen(
          onSuccess: () {
            Navigator.pop(context);
          },
        ),
      ),
    );
    await action();
    final v = await Pin.isSet();
    if (mounted) setState(() => pinSet = v);
  }

  Future<void> _desactiver() async {
    await _verifierPuis(() async {
      await Pin.remove();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L10n.t('pin_removed')), backgroundColor: MC.nuit3));
    });
  }

  Future<void> _changer() async {
    await _verifierPuis(() async {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PinScreen(setup: true, onSuccess: () => Navigator.pop(context)),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L10n.t('pin_saved')), backgroundColor: MC.savane));
    });
  }

  Future<void> _oublie() async {
    final ok = await resetPinBySms(context);
    if (ok && mounted) setState(() => pinSet = false);
  }

  Future<void> _deconnexion() async {
    final st = context.read<AppState>();
    final oui = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.nuit2,
        title: Text(L10n.t('settings_session_title'),
            style: TextStyle(
                color: MC.ivoire,
                fontSize: Tx.subtitle,
                fontWeight: FontWeight.w800)),
        content: Text(L10n.t('logout_confirm'),
            style: TextStyle(color: MC.sable, fontSize: Tx.body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(L10n.t('cancel_btn'), style: TextStyle(color: MC.kaki)),
          ),
          TextButton(
            key: const Key('security-logout-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L10n.t('logout'),
                style: TextStyle(color: MC.rouge, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (oui == true) await st.logout();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
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
        title: Text(L10n.t('settings_security'),
            style: TextStyle(
                color: MC.ivoire,
                fontSize: Tx.title,
                fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          // Code PIN
          Container(
            padding: const EdgeInsets.all(Sp.x4),
            decoration: BoxDecoration(
              color: MC.nuit2,
              borderRadius: BorderRadius.circular(Rd.md),
              border: Border.all(color: pinSet ? MC.savane : MC.ligne),
            ),
            child: Row(
              children: [
                Icon(pinSet ? Icons.lock_rounded : Icons.lock_open_rounded,
                    color: pinSet ? MC.savane : MC.kaki, size: 22),
                const SizedBox(width: Sp.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(L10n.t('pin_title'),
                          style: TextStyle(
                              color: MC.ivoire,
                              fontSize: Tx.bodyLg,
                              fontWeight: FontWeight.w700)),
                      Text(
                          pinSet
                              ? L10n.t('settings_pin_on')
                              : L10n.t('settings_pin_off'),
                          style: TextStyle(
                              color: pinSet ? MC.savane : MC.kaki,
                              fontSize: Tx.label)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.x3),
          if (!pinSet)
            MboteButton(
                key: const Key('pin-activate'),
                label: L10n.t('pin_set'),
                onTap: _activer)
          else ...[
            _Ligne(
              key: const Key('pin-change'),
              icon: Icons.sync_rounded,
              color: MC.soleil,
              titre: L10n.t('pin_change'),
              onTap: _changer,
            ),
            _Ligne(
              key: const Key('pin-forgot'),
              icon: Icons.sms_rounded,
              color: MC.soleil,
              titre: L10n.t('pin_forgot'),
              sous: 'SMS → ${st.phone}',
              onTap: _oublie,
            ),
            _Ligne(
              key: const Key('pin-off'),
              icon: Icons.lock_open_rounded,
              color: MC.rouge,
              titre: L10n.t('pin_off'),
              onTap: _desactiver,
            ),
          ],
          const SizedBox(height: Sp.x4),
          Text(L10n.t('settings_session_title'),
              style: TextStyle(
                  color: MC.kaki,
                  fontSize: Tx.caption,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
          const SizedBox(height: Sp.x2),
          Container(
            padding: const EdgeInsets.all(Sp.x4),
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
                    Icon(Icons.smartphone_rounded, color: MC.savane, size: 18),
                    const SizedBox(width: Sp.x2),
                    Expanded(
                      child: Text(
                          '${L10n.t('settings_session_device')} · ${st.phone}',
                          style: TextStyle(
                              color: MC.ivoire,
                              fontSize: Tx.body,
                              fontWeight: FontWeight.w600)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: MC.savane.withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(Rd.pill)),
                      child: Text(L10n.t('settings_session_active'),
                          style: TextStyle(
                              color: MC.savane,
                              fontSize: Tx.caption,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: Sp.x2),
                Text(L10n.t('settings_session_body'),
                    style: TextStyle(
                        color: MC.kaki, fontSize: Tx.caption, height: 1.45)),
                const SizedBox(height: Sp.x3),
                OutlinedButton.icon(
                  key: const Key('security-logout'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: MC.rouge),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Rd.md)),
                  ),
                  onPressed: _deconnexion,
                  icon: Icon(Icons.logout_rounded, color: MC.rouge, size: 17),
                  label: Text(L10n.t('settings_session_close'),
                      style: TextStyle(
                          color: MC.rouge, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.x4),
          Text(L10n.t('settings_privacy_note'),
              style: TextStyle(color: MC.kaki, fontSize: Tx.caption, height: 1.5)),
        ],
      ),
    );
  }
}

/// ℹ️ À propos — un seul endroit, réutilisé par le menu et les réglages.
void showAboutDialogMbote(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: MC.nuit2,
      title: Row(children: [
        Icon(Icons.chat_bubble_rounded, color: MC.soleil, size: 22),
        const SizedBox(width: 10),
        Text('MboteCall', style: TextStyle(color: MC.ivoire)),
      ]),
      content: Text(L10n.t('about_text'),
          style: TextStyle(color: MC.sable, fontSize: Tx.label, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('OK', style: TextStyle(color: MC.soleil)),
        ),
      ],
    ),
  );
}
