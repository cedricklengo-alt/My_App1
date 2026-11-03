import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../design.dart';
import '../theme.dart';
import '../widgets/floating_choice.dart';
import '../l10n.dart';
import '../rtc.dart';
import 'call.dart';
import 'contacts.dart';
import 'favorites.dart';

/// Clavier de numérotation avec affichage du tarif AVANT l'appel (maquette 02).
/// Touche d'effacement : une sentinelle, jamais un glyphe à l'écran
/// (le clavier affiche une icône Material, lisible par les lecteurs d'écran).
const _effacer = '#erase';

class KeypadScreen extends StatefulWidget {
  const KeypadScreen({super.key});
  @override
  State<KeypadScreen> createState() => _KeypadScreenState();
}

class _KeypadScreenState extends State<KeypadScreen> {
  String number = '+243';
  String tarif = '';
  bool free = false; //appel gratuit (MboteCall→MboteCall ou forfait)
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

  @override
  void dispose() {
    // Sans cette annulation, un appui suivi d'un retour arrière immédiat
    // laissait un minuteur vivant appeler setState sur un écran détruit.
    _debounce?.cancel();
    super.dispose();
  }

  void _lookupTarif() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
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
            //gratuit : app-à-app ou forfait
            tarif = r['free_reason'] == 'package'
                ? '${r['destination']} · ${L10n.t('free_call')} — ${L10n.t('free_package')}'
                : '${r['destination']} · ${L10n.t('free_call')}';
          } else {
            tarif =
                '${r['destination']} · ${(r['price_per_min_cents'] / 100).toStringAsFixed(2)} \$/min · ≈ ${r['max_minutes']} min possibles';
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
    const keys = ['1','2','3','4','5','6','7','8','9','+','0', _effacer];

    //Le clavier s'adapte : sur un petit téléphone il défile au lieu de
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
                              fontSize: Tx.headline,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w600,
                              color: MC.ivoire)),
                      SizedBox(
                        height: 22,
                        child: tarif.isEmpty
                            ? null
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Destination (plus de drapeau emoji : icône)
                                  Icon(Icons.public_rounded,
                                      size: 14,
                                      color: free ? MC.savane : MC.sable),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(tarif,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: free ? MC.savane : MC.sable,
                                            fontWeight: free
                                                ? FontWeight.w800
                                                : FontWeight.w400,
                                            fontSize: Tx.label)),
                                  ),
                                ],
                              ),
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
                                  borderRadius: BorderRadius.circular(Rd.md),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(Rd.md),
                                    onTap: () =>
                                        k == _effacer ? _erase() : _press(k),
                                    onLongPress: k == _effacer
                                        ? () {
                                            setState(() => number = '');
                                            _lookupTarif();
                                          }
                                        : null,
                                    child: Center(
                                      child: k == _effacer
                                          ? Icon(Icons.backspace_outlined,
                                              size: Tx.headline,
                                              color: MC.ivoire,
                                              semanticLabel:
                                                  L10n.t('keypad_erase'))
                                          : Text(k,
                                          style: TextStyle(
                                              fontSize: Tx.headline,
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
                    fontSize: Tx.headline,
                    fontWeight: FontWeight.w800,
                    color: MC.ivoire)),
          ),
          //Voyant temps réel : vert = prêt pour la vraie voix
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
  ///
  /// Même vocabulaire que la fiche d'appel : bouton flottant, icône seule,
  /// couleur porteuse de sens (vert = voix, sable = vidéo).
  Widget _callButton({
    required IconData icon,
    required double size,
    required bool gradient,
    required String tooltip,
    required bool video,
  }) {
    return FloatingChoice(
      icon: icon,
      color: gradient ? MC.savane : MC.soleil,
      label: tooltip,
      size: size,
      outlined: !gradient,
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
    );
  }
}
