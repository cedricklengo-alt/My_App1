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
    return SafeArea(
      child: Column(
        children: [
          // Titre + accès rapides : ⭐ Favoris et 📒 Contacts (en haut à droite)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
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
                    message: ok
                        ? 'Prêt à recevoir des appels'
                        : 'Connexion au serveur…',
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
          ),
          const Spacer(),
          Text(number.isEmpty ? ' ' : number,
              style: TextStyle(
                  fontSize: 28,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                  color: MC.ivoire)),
          const SizedBox(height: 6),
          SizedBox(
            height: 20,
            child: Text(tarif,
                style: TextStyle(
                    color: free ? MC.savane : MC.sable,
                    fontWeight: free ? FontWeight.w800 : FontWeight.w400,
                    fontSize: 12.5)),
          ),
          const SizedBox(height: 10),
          // ---- Pavé ----
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: keys
                  .map((k) => Material(
                        color: MC.nuit3,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => k == '⌫' ? _erase() : _press(k),
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
          ),
          const SizedBox(height: 18),
          // ---- Bouton appel ----
          GestureDetector(
            onTap: () {
              final clean = number.replaceAll(RegExp(r'[\s.\-()]'), '');
              if (!RegExp(r'^\+\d{8,15}$').hasMatch(clean)) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('Numéro invalide — format +243…'),
                    backgroundColor: MC.rouge));
                return;
              }
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => CallScreen(to: clean)));
            },
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    colors: [const Color(0xFF3BC684), MC.savane]),
                boxShadow: [
                  BoxShadow(
                      color: MC.savane.withValues(alpha: .4),
                      blurRadius: 24,
                      offset: const Offset(0, 8)),
                ],
              ),
              child:
                  const Icon(Icons.call_rounded, color: Colors.white, size: 30),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
