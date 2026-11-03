// lib/screens/shell.dart
// Navigation principale Mbote — Accueil · Appels · Discussion · ···
//
// INTÉGRATION :
//   Dans main.dart, remplacer le widget racine (souvent un BottomNavigationBar
//   ou un IndexedStack) par : home: const AppShell()
//
// TABS :
//   0  → Accueil (FeedScreen)
//   1  → Appels  (CallsListScreen  — votre écran existant)
//   2  → Discussion (ChatsListScreen — liste des conversations)
//   3  → ···     (ouvre le menu MoreMenuSheet)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../liens.dart';
import '../state.dart';
import '../tabs.dart';
import '../design.dart';
import '../theme.dart';
import 'chats.dart';
import 'contacts.dart';
import 'feed_screen.dart';
import 'favorites.dart';
import 'history.dart';
import 'home.dart';
import 'keypad.dart';
import 'my_plans.dart';
import 'profile.dart';
import 'settings.dart';
import 'shop.dart';
import 'transactions.dart';

// Remplacez ces imports par les vrais écrans de votre projet ──────────
// import 'calls_list.dart';   // liste des appels récents
// import 'chats_list.dart';   // liste des conversations
// import 'home.dart';         // portefeuille  (HomeScreen)
// import 'profile.dart';      // profil utilisateur
// import 'settings.dart';     // paramètres
//──────────────────────────────────────────────────────────────────────

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Une publication ouverte depuis un lien partagé s'affiche dans le fil.
    Liens.post.addListener(_surLien);
  }

  @override
  void dispose() {
    Liens.post.removeListener(_surLien);
    super.dispose();
  }

  void _surLien() {
    if (Liens.post.value == null || !mounted) return;
    if (_tab != 0) setState(() => _tab = 0);
  }

  // Les pages permanentes (IndexedStack) : elles restent vivantes, donc les
  // appels entrants et les messages arrivent même sur un autre onglet.
  final List<Widget> _pages = const [
    FeedScreen(),
    HistoryScreen(),
    ChatsScreen(),
  ];

  void _onTabTap(int index) {
    if (index == 3) {
      // Onglet ••• : ouvre le menu, ne change pas _tab
      HapticFeedback.selectionClick();
      _showMoreMenu();
      return;
    }
    if (index == _tab) {
      // Re-tap sur l'onglet actif → on recharge son contenu (comme WhatsApp).
      HapticFeedback.selectionClick();
      Tabs.refresh(index);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _tab = index);
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _MoreMenuSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MC.nuit,
      body: IndexedStack(
        index: _tab,
        children: _pages,
      ),
      bottomNavigationBar: _BottomBar(
        currentIndex: _tab,
        onTap: _onTabTap,
      ),
    );
  }
}

//───────────────────────────────────────────
// Barre de navigation — 4 onglets
//───────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;

  const _BottomBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MC.nuit2,
        border: Border(top: BorderSide(color: MC.ligne, width: 1)),
        boxShadow: const [
          BoxShadow(
            color: Surcouche.ombre,
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          // Barre de navigation : 56 dp au repos, mais elle GRANDIT avec la
          // taille de police du système. Hauteur figée + texte à 200 % =
          // libellé rogné (WCAG 2.2 · 1.4.4), constaté par l'audit.
          height: Tap.confort +
              (MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0) -
                  1.0) *
                  (Tx.label * 1.6),
          child: Row(
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: L10n.t('nav_home'),
                active: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.call_rounded,
                label: L10n.t('nav_calls'),
                active: currentIndex == 1,
                badge: HistoryScreen.missed,
                badgeColor: MC.rouge,
                visibleZero: false,
                onTap: () => onTap(1),
              ),
              _NavItem(
                icon: Icons.chat_bubble_rounded,
                label: L10n.t('nav_messages'),
                active: currentIndex == 2,
                badge: ChatsScreen.unread,
                onTap: () => onTap(2),
              ),
              _NavItem(
                icon: Icons.more_horiz_rounded,
                label: L10n.t('nav_more'),
                active: false, // jamais "actif" visuellement
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  /// Nombre à afficher en pastille (0 = rien, sauf `visibleZero`).
  final ValueListenable<int>? badge;

  /// Couleur de la pastille (`null` = rouge du thème actif, `MC.rouge`).
  final Color? badgeColor;

  /// Afficher la pastille même à zéro (utile pour les manqués : « 0 »).
  final bool visibleZero;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge,
    this.badgeColor,
    this.visibleZero = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? MC.soleil : MC.kaki;
    return Expanded(
      child: Semantics(
        label: label,
        button: true,
        selected: active,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Pastille active
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: active ? 36 : 0,
                height: 3,
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  gradient: active ? MC.degrade : null,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 22, color: color),
                  if (badge != null)
                    Positioned(
                      right: -8,
                      top: -4,
                      child: ValueListenableBuilder<int>(
                        valueListenable: badge!,
                        builder: (_, n, __) => n <= 0 && !visibleZero
                            ? const SizedBox.shrink()
                            : Container(
                                constraints: const BoxConstraints(minWidth: 15),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: badgeColor ?? MC.rouge,
                                  borderRadius: BorderRadius.circular(Rd.sm),
                                ),
                                child: Text(
                                  n > 99 ? '99+' : '$n',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: MC.ivoire,
                                    fontSize: Tx.caption,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              // `FittedBox` : à 11 px le libellé swahili « Majadiliano »
              // dépasse la largeur d'un onglet sur un écran de 320 px.
              // Il rétrécit alors tout seul, au lieu de déborder.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: color,
                      fontSize: Tx.caption,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//───────────────────────────────────────────
// Menu ··· — Portefeuille · Profil · Paramètres
//───────────────────────────────────────────

/// Menu « ··· » : tout ce qui n'a pas sa place dans la barre du bas.
///
/// Chaque entrée ouvre un écran **réel** — plus aucun bouton mort.
class _MoreMenuSheet extends StatelessWidget {
  const _MoreMenuSheet();

  /// Ouvre un écran qui n'a pas son propre Scaffold (Accueil, Profil, Clavier).
  static void _pushBare(BuildContext context, Widget child, String title) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: MC.nuit,
          // Ces écrans affichent déjà leur propre titre : la barre ne sert
          // qu'à revenir en arrière (et au lecteur d'écran).
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: MC.ivoire),
            title: Text(title,
                style: TextStyle(
                    color: MC.kaki,
                    fontSize: Tx.label,
                    fontWeight: FontWeight.w700)),
          ),
          body: child,
        ),
      ),
    );
  }

  /// Ouvre un écran complet (il a déjà son Scaffold et sa barre de titre).
  static void _pushFull(BuildContext context, Widget child) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => child));
  }

  Future<void> _logout(BuildContext context) async {
    final st = context.read<AppState>();
    // On ferme d'abord le menu : la boîte de dialogue s'affiche au-dessus de
    // l'onglet, pas au-dessus d'une feuille qui va disparaître.
    final nav = Navigator.of(context);
    nav.pop();
    final yes = await showDialog<bool>(
      context: nav.context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.nuit2,
        title: Text(L10n.t('logout'),
            style: TextStyle(color: MC.ivoire, fontWeight: FontWeight.w800)),
        content: Text(L10n.t('logout_confirm'),
            style: TextStyle(color: MC.sable, fontSize: Tx.body)),
        actions: [
          TextButton(
            key: const Key('logout-cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(L10n.t('cancel_btn'),
                style: TextStyle(color: MC.kaki)),
          ),
          TextButton(
            key: const Key('logout-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L10n.t('logout'),
                style: TextStyle(
                    color: MC.rouge, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (yes == true) await st.logout();
  }

  void _about(BuildContext context) {
    final nav = Navigator.of(context);
    nav.pop();
    showDialog(
      context: nav.context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.nuit2,
        title: Row(
          children: [
            Icon(Icons.wb_sunny_rounded, color: MC.soleil),
            const SizedBox(width: 8),
            Text(L10n.t('about'),
                style: TextStyle(
                    color: MC.ivoire, fontSize: Tx.subtitle, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(L10n.t('about_text'),
            style: TextStyle(color: MC.sable, fontSize: Tx.label, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.t('chat_ok'),
                style: TextStyle(color: MC.soleil, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return Container(
      decoration: BoxDecoration(
        color: MC.nuit2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Poignée
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: MC.nuit3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

 // Mon compte : nom, numéro et solde, sans quitter le menu─
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Material(
                  color: MC.nuit3,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Rd.md),
                    side: BorderSide(color: MC.ligne),
                  ),
                  child: InkWell(
                    onTap: () =>
                        _pushBare(context, const ProfileScreen(), L10n.t('profile')),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: MC.degrade,
                            ),
                            child: Text(_initials(st.name),
                                style: TextStyle(
                                    color: MC.onAccent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: Tx.bodyLg)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    st.name.trim().isEmpty
                                        ? L10n.t('nav_profile')
                                        : st.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: MC.ivoire,
                                        fontSize: Tx.bodyLg,
                                        fontWeight: FontWeight.w800)),
                                Text(st.phone,
                                    style: TextStyle(
                                        color: MC.kaki, fontSize: Tx.label)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: MC.nuit2,
                              borderRadius: BorderRadius.circular(Rd.md),
                            ),
                            child: Text(fmtMoney(st.balanceCents),
                                style: TextStyle(
                                    color: MC.soleil,
                                    fontSize: Tx.label,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

 // COMPTE─
              _SectionTitre(L10n.t('settings_section_account')),
              _MoreItem(
                icon: Icons.person_rounded,
                iconColor: MC.soleil,
                label: L10n.t('profile'),
                subtitle: L10n.t('more_account_sub'),
                onTap: () =>
                    _pushBare(context, const ProfileScreen(), L10n.t('profile')),
              ),
              _MoreItem(
                icon: Icons.account_balance_wallet_rounded,
                iconColor: MC.savane,
                label: L10n.t('wallet'),
                subtitle: L10n.t('more_wallet_sub'),
                onTap: () =>
                    _pushBare(context, const HomeScreen(), L10n.t('wallet')),
              ),
              _MoreItem(
                icon: Icons.storefront_rounded,
                iconColor: MC.soleil,
                label: L10n.t('shop_title'),
                subtitle: L10n.t('more_shop_sub'),
                onTap: () => _pushFull(context, const ShopScreen()),
              ),
              _MoreItem(
                icon: Icons.confirmation_number_rounded,
                iconColor: MC.savane,
                label: L10n.t('shop_my_plans'),
                subtitle: L10n.t('more_plans_sub'),
                onTap: () => _pushFull(context, const MyPlansScreen()),
              ),
              _MoreItem(
                icon: Icons.receipt_long_rounded,
                iconColor: MC.terre,
                label: L10n.t('wallet_transactions'),
                subtitle: L10n.t('more_tx_sub'),
                onTap: () => _pushFull(context, const TransactionsScreen()),
              ),

 // OUTILS─
              _SectionTitre(L10n.t('settings_section_tools')),
              _MoreItem(
                icon: Icons.dialpad_rounded,
                iconColor: MC.savane,
                label: L10n.t('nav_keypad'),
                subtitle: L10n.t('more_keypad_sub'),
                onTap: () =>
                    _pushBare(context, const KeypadScreen(), L10n.t('nav_keypad')),
              ),
              _MoreItem(
                icon: Icons.contacts_rounded,
                iconColor: MC.soleil,
                label: L10n.t('contacts'),
                subtitle: L10n.t('more_contacts_sub'),
                onTap: () => _pushFull(context, const ContactsScreen()),
              ),
              _MoreItem(
                icon: Icons.star_rounded,
                iconColor: MC.terre,
                label: L10n.t('favorites'),
                subtitle: L10n.t('more_favorites_sub'),
                onTap: () => _pushFull(context, const FavoritesScreen()),
              ),

 // RÉGLAGES─
              _SectionTitre(L10n.t('settings_section_prefs')),
              _MoreItem(
                icon: Icons.settings_rounded,
                iconColor: MC.soleil,
                label: L10n.t('settings'),
                subtitle: L10n.t('more_settings_sub2'),
                onTap: () => _pushFull(context, const SettingsScreen()),
              ),

 // AIDE─
              _SectionTitre(L10n.t('settings_section_help')),
              _MoreItem(
                icon: Icons.info_outline_rounded,
                iconColor: MC.kaki,
                label: L10n.t('about'),
                subtitle: L10n.t('more_about_sub'),
                onTap: () => _about(context),
              ),

              const SizedBox(height: 6),
              Divider(height: 1, color: MC.ligne, indent: 20, endIndent: 20),
              _MoreItem(
                icon: Icons.logout_rounded,
                iconColor: MC.rouge,
                label: L10n.t('logout'),
                subtitle: null,
                onTap: () => _logout(context),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return '?';
    final parts = clean.split(RegExp(r'\s+'));
    final first = String.fromCharCodes(parts.first.runes.take(1));
    if (parts.length == 1) return first.toUpperCase();
    final last = String.fromCharCodes(parts.last.runes.take(1));
    return (first + last).toUpperCase();
  }
}

class _MoreItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _MoreItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        splashColor: iconColor.withValues(alpha: .08),
        highlightColor: iconColor.withValues(alpha: .04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              // Icône dans un cercle
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconColor.withValues(alpha: .12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: MC.ivoire,
                        fontSize: Tx.bodyLg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: MC.kaki,
                          fontSize: Tx.caption,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: MC.kaki,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Petit titre de section dans le menu (« COMPTE », « OUTILS »…).
class _SectionTitre extends StatelessWidget {
  final String texte;
  const _SectionTitre(this.texte);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(texte,
              style: TextStyle(
                  color: MC.kaki,
                  fontSize: Tx.caption,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3)),
        ),
      );
}
