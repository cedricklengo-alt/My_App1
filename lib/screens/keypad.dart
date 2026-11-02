import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../theme.dart';
import '../l10n.dart';
import '../rtc.dart';
import 'call.dart';
import 'contacts.dart';
import 'favorites.dart';

/// Clavier de numérotation avec affichage du tarif AVANT l'appel (maquette 02).
class KeypadScreen extends StatefulWidget {
  const KeypadScreen({super.key});
  @override
  State<KeypadScreen> createState() => _KeypadScreenState();
}

class _KeypadScreenState extends State<KeypadScreen> {
  String number = '+243';
  String tarif = '';
  bool free = false; // 💚 appel gratuit (MboteCall→MboteCall ou forfait)
  Timer? _debounce;

  void _press(String d) {
    HapticFeedback.lightImpact(); // retour tactile façon clavier natif
    setState(() => number += d);
    _lookupTarif();
  }

  void _erase() {
    if (number.isEmpty) return;
    setState(() => number = number.substring(0, number.length - 1));
    _lookupTarif();
  }

  void _lookupTarif() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (number.length < 8) {
        setState(() {
          tarif = '';
          free = false;
        });
        return;
      }
      try {
        final r = await context.read<AppState>().api.rateLookup(number);
        if (!mounted) return;
        final isFree = r['price_per_min_cents'] == 0;
        setState(() {
          free = isFree;
          if (isFree) {
            // 💚 gratuit : app-à-app ou forfait
            tarif = r['free_reason'] == 'package'
                ? '${r['flag']} ${r['destination']} · ${L10n.t('free_call')} — ${L10n.t('free_package')}'
                : '${r['flag']} ${r['destination']} · ${L10n.t('free_call')}';
          } else {
            tarif =
                '${r['flag']} ${r['destination']} · ${(r['price_per_min_cents'] / 100).toStringAsFixed(2)} \$/min · ≈ ${r['max_minutes']} min possibles';
          }
        });
      } catch (_) {
        if (mounted) {
          setState(() {
            tarif = '';
            free = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '0', '⌫'];

    // 📐 Le clavier s'adapte : sur un petit téléphone il défile au lieu de
    // déborder (l'ancienne version fixe débordait de 372 px en 800×600).
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _header(),
                      const SizedBox(height: 12),
                      // Le numéro composé
                      Text(number.isEmpty ? ' ' : number,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 28,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w600,
                              color: MC.ivoire)),
                      SizedBox(
                        height: 22,
                        child: Text(tarif,
                            style: TextStyle(
                                color: free ? MC.savane : MC.sable,
                                fontWeight:
                                    free ? FontWeight.w800 : FontWeight.w400,
                                fontSize: 12.5)),
                      ),
                      const SizedBox(height: 8),
                      // ---- Pavé ----
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.75,
                        children: keys
                            .map((k) => Material(
                                  color: MC.nuit3,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () =>
                                        k == '⌫' ? _erase() : _press(k),
                                    onLongPress: k == '⌫'
                                        ? () {
                                            setState(() => number = '');
                                            _lookupTarif();
                                          }
                                        : null,
                                    child: Center(
                                      child: Text(k,
                                          style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w600,
                                              color: MC.ivoire)),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 18),
                      // ---- Appel audio · appel vidéo (côte à côte) ----
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _callButton(
                            icon: Icons.call_rounded,
                            size: 68,
                            gradient: true,
                            tooltip: L10n.t('chat_call_audio'),
                            video: false,
                          ),
                          const SizedBox(width: 22),
                          _callButton(
                            icon: Icons.videocam_rounded,
                            size: 56,
                            gradient: false,
                            tooltip: L10n.t('chat_call_video'),
                            video: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// En-tête : titre, voyant temps réel, favoris et contacts.
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(L10n.t('nav_keypad'),
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: MC.ivoire)),
          ),
          // 🟢 Voyant temps réel : vert = prêt pour la vraie voix
          ValueListenableBuilder<bool>(
            valueListenable: Rtc.connected,
            builder: (_, ok, __) => Tooltip(
              message: ok ? L10n.t('keypad_ready') : L10n.t('keypad_connecting'),
              child: Icon(Icons.circle,
                  size: 10, color: ok ? MC.savane : MC.kaki),
            ),
          ),
          IconButton(
            tooltip: L10n.t('favorites'),
            icon: Icon(Icons.star_rounded, color: MC.soleil, size: 26),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FavoritesScreen())),
          ),
          IconButton(
            tooltip: L10n.t('contacts_title'),
            icon: Icon(Icons.contacts_rounded, color: MC.sable, size: 23),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ContactsScreen())),
          ),
        ],
      ),
    );
  }

  /// Bouton d'appel (audio ou vidéo) — refuse un numéro invalide.
  Widget _callButton({
    required IconData icon,
    required double size,
    required bool gradient,
    required String tooltip,
    required bool video,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          final clean = number.replaceAll(RegExp(r'[\s.\-()]'), '');
          if (!RegExp(r'^\+\d{8,15}$').hasMatch(clean)) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(L10n.t('keypad_invalid')),
                backgroundColor: MC.rouge));
            return;
          }
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => CallScreen(to: clean, video: video)));
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: gradient
                ? LinearGradient(
                    colors: [const Color(0xFF3BC684), MC.savane])
                : null,
            color: gradient ? null : MC.nuit3,
            border: gradient
                ? null
                : Border.all(color: MC.soleil.withValues(alpha: .5)),
            boxShadow: gradient
                ? [
                    BoxShadow(
                        color: MC.savane.withValues(alpha: .4),
                        blurRadius: 24,
                        offset: const Offset(0, 8)),
                  ]
                : null,
          ),
          child: Icon(icon,
              color: gradient ? Colors.white : MC.soleil,
              size: gradient ? 30 : 24),
        ),
      ),
    );
  }
}
