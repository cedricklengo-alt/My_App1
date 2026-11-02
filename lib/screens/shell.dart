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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'feed_screen.dart';

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

  // Les pages permanentes (IndexedStack)
  final List<Widget> _pages = const [
    FeedScreen(),
    _CallsPlaceholder(), // ← remplacer par CallsListScreen()
    _MessagesPlaceholder(), // ← remplacer par ChatsListScreen()
  ];

  void _onTabTap(int index) {
    if (index == 3) {
      // Onglet ••• : ouvre le menu, ne change pas _tab
      HapticFeedback.selectionClick();
      _showMoreMenu();
      return;
    }
    if (index == _tab) {
      // Tap sur l'onglet actif → scroll to top (optionnel)
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
                label: 'Accueil',
                active: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.call_rounded,
                label: 'Appels',
                active: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              _NavItem(
                icon: Icons.chat_bubble_rounded,
                label: 'Messages',
                active: currentIndex == 2,
                onTap: () => onTap(2),
              ),
              _NavItem(
                icon: Icons.more_horiz_rounded,
                label: '···',
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

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
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
              Icon(icon, size: 22, color: color),
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

class _MoreMenuSheet extends StatelessWidget {
  const _MoreMenuSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MC.nuit2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
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

            // Titre
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Mon compte',
                  style: TextStyle(
                    color: MC.sable,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),

            // Items du menu
            _MoreItem(
              icon: Icons.account_balance_wallet_rounded,
              iconColor: MC.savane,
              label: 'Portefeuille',
              subtitle: 'Solde, recharger, transférer',
              onTap: () {
                Navigator.pop(context);
                // TODO : Navigator.push vers HomeScreen (home.dart)
                // Navigator.push(context,
                //   MaterialPageRoute(builder: (_) => const HomeScreen()));
              },
            ),

            _MoreItem(
              icon: Icons.person_rounded,
              iconColor: MC.soleil,
              label: 'Profil',
              subtitle: 'Photo, nom, biographie',
              onTap: () {
                Navigator.pop(context);
                // TODO : Navigator.push vers ProfileScreen
                // Navigator.push(context,
                //   MaterialPageRoute(builder: (_) => const ProfileScreen()));
              },
            ),

            _MoreItem(
              icon: Icons.settings_rounded,
              iconColor: MC.kaki,
              label: 'Paramètres',
              subtitle: 'Confidentialité, notifications, langue',
              onTap: () {
                Navigator.pop(context);
                // TODO : Navigator.push vers SettingsScreen
                // Navigator.push(context,
                //   MaterialPageRoute(builder: (_) => const SettingsScreen()));
              },
            ),

            const SizedBox(height: 8),
            Divider(height: 1, color: MC.ligne, indent: 20, endIndent: 20),

            // Déconnexion
            _MoreItem(
              icon: Icons.logout_rounded,
              iconColor: MC.rouge,
              label: 'Se déconnecter',
              onTap: () {
                Navigator.pop(context);
                // TODO : déconnexion AppState
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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

// ──────────────────────────────────────────────
// Placeholders temporaires
// (à remplacer par les vrais écrans)
// ──────────────────────────────────────────────

class _CallsPlaceholder extends StatelessWidget {
  const _CallsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MC.nuit,
      body: Center(
        child: Text(
          '📞  Appels\n\n→ Remplacer par CallsListScreen()',
          style: TextStyle(color: MC.kaki, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _MessagesPlaceholder extends StatelessWidget {
  const _MessagesPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MC.nuit,
      body: Center(
        child: Text(
          '💬  Messages\n\n→ Remplacer par ChatsListScreen()',
          style: TextStyle(color: MC.kaki, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
