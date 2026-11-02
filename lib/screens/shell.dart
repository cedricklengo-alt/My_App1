// lib/screens/shell.dart
// Navigation principale Mbote — Feed · Appels · Messages · ···
//
// INTÉGRATION :
//   Dans main.dart, remplacer le widget racine (souvent un BottomNavigationBar
//   ou un IndexedStack) par : home: const AppShell()
//
// TABS :
//   0  → Accueil (FeedScreen)
//   1  → Appels  (CallsListScreen  — votre écran existant)
//   2  → Messages (ChatsListScreen — votre écran existant)
//   3  → ···     (ouvre le menu MoreMenuSheet)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../state.dart';
import '../tabs.dart';
import '../theme.dart';
import 'chats.dart';
import 'contacts.dart';
import 'feed_screen.dart';
import 'favorites.dart';
import 'history.dart';
import 'home.dart';
import 'keypad.dart';
import 'lokota.dart';
import 'profile.dart';

// ── Remplacez ces imports par les vrais écrans de votre projet ───────────
// import 'calls_list.dart';   // liste des appels récents
// import 'chats_list.dart';   // liste des conversations
// import 'home.dart';         // portefeuille  (HomeScreen)
// import 'profile.dart';      // profil utilisateur
// import 'settings.dart';     // paramètres
// ─────────────────────────────────────────────────────────────────────────

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _tab = 0;

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

// ──────────────────────────────────────────────
// Barre de navigation — 4 onglets
// ──────────────────────────────────────────────

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
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 58,
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

  /// Couleur de la pastille (rouge par défaut pour les manqués).
  final Color badgeColor;

  /// Afficher la pastille même à zéro (utile pour les manqués : « 0 »).
  final bool visibleZero;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge,
    this.badgeColor = const Color(0xFFD94436),
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
                                  color: badgeColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  n > 99 ? '99+' : '$n',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: MC.ivoire,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Menu ··· — Portefeuille · Profil · Paramètres
// ──────────────────────────────────────────────

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
                    fontSize: 13,
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
            style: TextStyle(color: MC.sable, fontSize: 14)),
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
                    color: MC.ivoire, fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(L10n.t('about_text'),
            style: TextStyle(color: MC.sable, fontSize: 13.5, height: 1.4)),
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

              // Mon compte : nom, numéro et solde — sans quitter le menu
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
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
                              fontSize: 15)),
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
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800)),
                          Text(st.phone,
                              style: TextStyle(color: MC.kaki, fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: MC.nuit3,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(fmtMoney(st.balanceCents),
                          style: TextStyle(
                              color: MC.soleil,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: MC.ligne, indent: 20, endIndent: 20),

              _MoreItem(
                icon: Icons.dialpad_rounded,
                iconColor: MC.savane,
                label: L10n.t('nav_keypad'),
                subtitle: L10n.t('more_keypad_sub'),
                onTap: () => _pushBare(context, const KeypadScreen(), L10n.t('nav_keypad')),
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
              _MoreItem(
                icon: Icons.account_balance_wallet_rounded,
                iconColor: MC.savane,
                label: L10n.t('wallet'),
                subtitle: L10n.t('more_wallet_sub'),
                onTap: () =>
                    _pushBare(context, const HomeScreen(), L10n.t('wallet')),
              ),
              _MoreItem(
                icon: Icons.person_rounded,
                iconColor: MC.soleil,
                label: L10n.t('profile'),
                subtitle: L10n.t('more_profile_sub'),
                onTap: () =>
                    _pushBare(context, const ProfileScreen(), L10n.t('profile')),
              ),
              _MoreItem(
                icon: Icons.settings_rounded,
                iconColor: MC.kaki,
                label: L10n.t('settings'),
                subtitle: L10n.t('more_settings_sub'),
                onTap: () => _pushBare(context,
                    const ProfileScreen(startWithSettings: true), L10n.t('settings')),
              ),
              _MoreItem(
                icon: Icons.graphic_eq_rounded,
                iconColor: MC.braise,
                label: L10n.t('lokota_home_title'),
                subtitle: L10n.t('more_lokota_sub'),
                onTap: () => _pushFull(context, const LokotaScreen()),
              ),
              _MoreItem(
                icon: Icons.info_outline_rounded,
                iconColor: MC.kaki,
                label: L10n.t('about'),
                subtitle: L10n.t('more_about_sub'),
                onTap: () => _about(context),
              ),

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
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: MC.kaki,
                          fontSize: 11,
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
