import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../design.dart';
import '../theme.dart';
import '../widgets/floating_choice.dart';
import '../l10n.dart';
import '../local/local_first.dart';
import '../local/sync_service.dart';
import '../rtc.dart';
import 'call.dart';
import 'contacts.dart';
import 'favorites.dart';
import '../countries.dart';
import '../widgets/country_picker.dart';

/// Clavier de numérotation avec affichage du tarif AVANT l'appel (maquette 02).
/// Touche d'effacement : une sentinelle, jamais un glyphe à l'écran
/// (le clavier affiche une icône Material, lisible par les lecteurs d'écran).
const _effacer = '#erase';

/// Écran clavier autonome (ouverture via le menu « Plus »).
class KeypadScreen extends StatelessWidget {
  const KeypadScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MC.nuit,
      body: SafeArea(child: DialPadPanel()),
    );
  }
}

/// Pavé de numérotation réutilisable : écran clavier complet OU intégré
/// en bas de l'onglet Appels (comme le dialer Tecno Camon 40 Pro).
class DialPadPanel extends StatefulWidget {
  /// false quand intégré dans l'onglet Appels (titre/recents déjà présents).
  final bool showHeader;
  final bool showLocalRecents;
  const DialPadPanel({super.key, this.showHeader = true, this.showLocalRecents = true});
  @override
  State<DialPadPanel> createState() => _DialPadPanelState();
}

class _DialPadPanelState extends State<DialPadPanel> {
  String number = '+243';
  Country country = kDefaultCountry;

  /// Partie nationale du numéro (sans l'indicatif).
  String get _national =>
      number.startsWith(country.dial) ? number.substring(country.dial.length) : number;

  String tarif = '';
  bool free = false; //appel gratuit (MboteCall→MboteCall ou forfait)
  Timer? _debounce;

  void _press(String d) {
    if (!RegExp(r'^\d$').hasMatch(d)) return; // uniquement des chiffres
    if (_national.length >= country.maxDigits) {
      HapticFeedback.mediumImpact(); // nombre déjà complet pour ce pays
      return;
    }
    HapticFeedback.lightImpact(); // retour tactile façon clavier natif
    setState(() => number = country.dial + _national + d);
    _lookupTarif();
  }

  void _erase() {
    if (_national.isEmpty) return;
    setState(() => number = country.dial + _national.substring(0, _national.length - 1));
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
    const keys = ['1','2','3','4','5','6','7','8','9','*','0', _effacer];
    // Lettres des touches façon téléphone classique (2=ABC… 9=WXYZ)
    const lettres = {
      '2': 'ABC', '3': 'DEF', '4': 'GHI', '5': 'JKL',
      '6': 'MNO', '7': 'PQRS', '8': 'TUV', '9': 'WXYZ', '0': '+',
    };

    //Le clavier s'adapte : sur un petit téléphone il défile au lieu de
    // déborder (l'ancienne version fixe débordait de 372 px en 800×600).
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.showHeader) ...[
                    _header(),
                    const SizedBox(height: 12),
                  ],
                      const SizedBox(height: 10),
                      // Champ numéro sobre et CENTRÉ : chiffres seuls (+243 implicite)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 7),
                          decoration: BoxDecoration(
                            color: MC.nuit3,
                            borderRadius: BorderRadius.circular(Rd.pill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_national.isEmpty ? 'Numéro' : _national,
                                  style: TextStyle(
                                      fontSize: Tx.bodyLg + 2,
                                      letterSpacing: 1.2,
                                      fontWeight: FontWeight.w600,
                                      color: _national.isEmpty ? MC.kaki : MC.ivoire)),
                              const SizedBox(width: 8),
                              Text(
                                  '${_national.length}/${country.expected}',
                                  style: TextStyle(
                                      color: _national.length >= country.minDigits
                                          ? MC.savane
                                          : MC.kaki,
                                      fontSize: Tx.caption,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 18,
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
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.55,
                        children: keys
                            .map((k) => _Key(
                                  label: k,
                                  lettres: lettres[k] ?? '',
                                  erase: k == _effacer,
                                  onTap: () =>
                                      k == _effacer ? _erase() : _press(k),
                                  onLongPress: k == _effacer
                                      ? () {
                                          setState(() => number = country.dial);
                                          _lookupTarif();
                                        }
                                      : null,
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 14),
                      // ---- Pilule d'appel à deux modes (idée Tecno Camon) ----
                      // 1 = Mbote ↔ Mbote (VoIP, gratuit) · 2 = Mbote ↔ GSM
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Semantics(
                            button: true,
                            label: 'Appel Mbote vers Mbote — gratuit via Internet',
                            child: Container(
                              decoration: BoxDecoration(
                                color: MC.savane,
                                borderRadius: BorderRadius.circular(Rd.pill),
                                boxShadow: [
                                  BoxShadow(
                                      color: MC.savane.withValues(alpha: .35),
                                      blurRadius: 16,
                                      offset: const Offset(0, 5)),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _modeAppel(
                                      icone: Icons.wifi_calling_3_rounded,
                                      tooltip:
                                          'Mbote ↔ Mbote — gratuit via Internet (HD, chiffré)',
                                      onTap: () => _callMode(false)),
                                  Container(
                                      width: 1,
                                      height: 24,
                                      color: MC.onAccent.withValues(alpha: .25)),
                                  _modeAppel(
                                      icone: Icons.cell_tower_rounded,
                                      tooltip:
                                          'Mbote ↔ GSM — réseau mobile, crédit requis si applicable',
                                      onTap: () => _callMode(true)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          _callButton(
                            icon: Icons.videocam_rounded,
                            size: 46,
                            gradient: false,
                            tooltip: L10n.t('chat_call_video'),
                            video: true,
                          ),
                          const SizedBox(width: 10),
                          // 🕐 Appeler plus tard : persisté localement, envoyé
                          // au serveur dès le retour d'Internet (file de synchro).
                          FloatingChoice(
                            icon: Icons.schedule_rounded,
                            color: MC.kaki,
                            label: 'Appeler plus tard',
                            size: 46,
                            outlined: true,
                            onTap: _scheduleLater,
                          ),
                        ],
                      ),

                      // 📒 Récents — lus dans la base LOCALE : visibles même
                      // hors connexion (ils viennent de l'historique d'appels).
                      if (number == '+243') ...[
                        const SizedBox(height: 14),
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: LocalFirst(api: context.read<AppState>().api)
                              .recentNumbers(limit: 5),
                          builder: (context, snap) {
                            final rows = snap.data ?? const [];
                            if (rows.isEmpty) return const SizedBox.shrink();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Récents',
                                    style: TextStyle(
                                        color: MC.kaki,
                                        fontSize: Tx.caption,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1)),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final r in rows)
                                      Semantics(
                                        button: true,
                                        label:
                                            'Composer ${r['phone']}',
                                        child: InkWell(
                                          onTap: () {
                                            setState(() {
                                              number = '${r['phone']}';
                                            });
                                            _lookupTarif();
                                          },
                                          borderRadius:
                                              BorderRadius.circular(Rd.lg),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: MC.nuit3,
                                              borderRadius:
                                                  BorderRadius.circular(Rd.lg),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.history_rounded,
                                                    size: 14, color: MC.soleil),
                                                const SizedBox(width: 6),
                                                Text(
                                                  (r['name'] as String).isNotEmpty
                                                      ? '${r['name']}'
                                                      : '${r['phone']}',
                                                  style: TextStyle(
                                                      color: MC.ivoire,
                                                      fontSize: Tx.label),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 10),
                    ],
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
                    fontSize: Tx.display,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.6,
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

  /// 🕐 « Appeler plus tard » : choisit une heure, enregistre l'intention
  /// dans la file de synchro locale → le serveur rappellera à l'heure dite
  /// dès que la connexion reviendra.
  Future<void> _scheduleLater() async {
    final clean = number.replaceAll(RegExp(r'[\s.\-()]'), '');
    if (!RegExp(r'^\+\d{8,15}$').hasMatch(clean)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L10n.t('keypad_invalid')),
          backgroundColor: MC.rouge));
      return;
    }
    final now = DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: now.hour + 1, minute: 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: MC.soleil,
            surface: MC.nuit2,
            onSurface: MC.ivoire,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    var at = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
    if (at.isBefore(now.add(const Duration(minutes: 1)))) {
      at = at.add(const Duration(days: 1));
    }
    try {
      await LocalFirst(api: context.read<AppState>().api)
          .scheduleCallLater(clean, at: at);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Rappel enregistré pour ${picked.hour}h${picked.minute.toString().padLeft(2, '0')} — envoyé dès la reconnexion'),
          backgroundColor: MC.nuit3,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e)), backgroundColor: MC.rouge));
      }
    }
  }

  /// Moitié de la pilule d'appel : une icône Material porte le mode
  /// (wifi_calling_3 = Mbote↔Mbote · cell_tower = Mbote↔GSM).
  /// Le libellé n'est JAMAIS affiché : tooltip + Semantics uniquement.
  Widget _modeAppel(
      {required IconData icone,
      required String tooltip,
      required VoidCallback onTap}) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Icon(icone, color: MC.onAccent, size: 26),
        ),
      ),
    );
  }

  /// Lance l'appel selon le mode choisi (gsm=true → Mbote↔GSM).
  void _callMode(bool gsm) {
    final clean = number.replaceAll(RegExp(r'[\s.\-()]'), '');
    if (!RegExp(r'^\+\d{8,15}$').hasMatch(clean)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L10n.t('keypad_invalid')),
          backgroundColor: MC.rouge));
      return;
    }
    // Le serveur décide du tarif (gratuit Mbote↔Mbote ou GSM payant) ;
    // le mode 2 force la passarelle GSM classique.
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CallScreen(to: clean, video: false, forceGsm: gsm)));
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

/// Touche de clavier premium : grande, arrondie, scale animé au toucher.
class _Key extends StatefulWidget {
  final String label;
  final String lettres;
  final bool erase;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _Key(
      {required this.label,
      this.lettres = '',
      required this.erase,
      required this.onTap,
      this.onLongPress});
  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  double _scale = 1.0;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.erase ? L10n.t('keypad_erase') : widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _scale = .90),
        onTapUp: (_) => setState(() => _scale = 1.0),
        onTapCancel: () => setState(() => _scale = 1.0),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 90),
          child: Container(
            decoration: BoxDecoration(
              color: MC.nuit3,
              borderRadius: BorderRadius.circular(Rd.lg),
              boxShadow: const [
                BoxShadow(
                    color: Surcouche.ombre,
                    blurRadius: 8,
                    offset: Offset(0, 3)),
              ],
            ),
            child: Center(
              child: widget.erase
                  ? Icon(Icons.backspace_outlined,
                      size: Tx.bodyLg, color: MC.ivoire)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.label,
                            style: TextStyle(
                                fontSize: Tx.headline,
                                fontWeight: FontWeight.w600,
                                color: MC.ivoire,
                                height: 1)),
                        if (widget.lettres.isNotEmpty)
                          Text(widget.lettres,
                              style: TextStyle(
                                  fontSize: 9,
                                  color: MC.kaki,
                                  letterSpacing: 1,
                                  height: 1.1)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
