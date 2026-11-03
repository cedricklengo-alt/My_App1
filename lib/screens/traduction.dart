import 'package:flutter/material.dart';

import '../design.dart';
import '../l10n.dart';
import '../theme.dart';
import '../prefs.dart';
import 'lokota.dart';

/// Panneau de traduction des discussions.
///
/// Lokota (traduction des messages et des notes vocales) n'est plus une
/// rubrique du menu : c'est une **option de la Discussion**, réglée ici une
/// fois pour toutes et appliquée à toutes les conversations. Le bouton
/// flottant de l'onglet Discussion ouvre ce panneau, et le bouton du
/// composeur dans une conversation ouvre le même — un seul endroit décide.
Future<void> showTraductionSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: MC.nuit2,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Rd.lg))),
    builder: (_) => const TraductionSheet(),
  );
}

class TraductionSheet extends StatefulWidget {
  const TraductionSheet({super.key});
  @override
  State<TraductionSheet> createState() => _TraductionSheetState();
}

class _TraductionSheetState extends State<TraductionSheet> {
  @override
  Widget build(BuildContext context) {
    final actif = TradPrefs.actif;
    // Material explicite : le panneau reste utilisable monté seul (tests,
    // aperçus) et les puces de langue ont leur surface d'encre.
    return Material(
      color: MC.nuit2,
      child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: MC.nuit3, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.translate_rounded, color: MC.soleil, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(L10n.t('trad_title'),
                        style: TextStyle(
                            color: MC.ivoire,
                            fontSize: Tx.title,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(L10n.t('trad_sheet_sub'),
                  style: TextStyle(
                      color: MC.kaki, fontSize: Tx.label, height: 1.4)),
              const SizedBox(height: 12),

 // ---- Interrupteur global -------------------------------------
              _Carte(
                child: SwitchListTile.adaptive(
                  key: const Key('trad-globale'),
                  value: actif,
                  activeThumbColor: MC.onAccent,
                  activeTrackColor: MC.soleil,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  title: Text(L10n.t('trad_global'),
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.body,
                          fontWeight: FontWeight.w700)),
                  subtitle: Text(L10n.t('trad_global_sub'),
                      style: TextStyle(
                          color: MC.kaki, fontSize: Tx.caption, height: 1.35)),
                  onChanged: (v) async {
                    // Retour immédiat dans le panneau : l'interrupteur, la
                    // ligne d'état et le bouton flottant changent ensemble.
                    // Pas de SnackBar ici : le panneau doit rester utilisable
                    // monté seul (aperçus, tests), sans dépendre d'un Scaffold.
                    await TradPrefs.set(actif: v);
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(height: 10),

 // ---- Langues ------------------------------------------------
              _Titre(L10n.t('trad_my_lang')),
              _Langues(
                prefixe: 'trad-ma',
                choisi: TradPrefs.maLangue,
                onPick: (c) async {
                  await TradPrefs.set(maLangue: c);
 // Si la cible devient la même langue que la source, on garde
 // une traduction utile en repoussant la cible ailleurs.
                  if (TradPrefs.cible == c) {
                    await TradPrefs.set(
                        cible: TradPrefs.codes.firstWhere((x) => x != c));
                  }
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 6),
              _Titre(L10n.t('trad_their_lang')),
              _Langues(
                prefixe: 'trad-vers',
                choisi: TradPrefs.cible,
                onPick: (c) async {
                  await TradPrefs.set(cible: c);
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 10),

 // ---- Notes vocales ------------------------------------------
              _Carte(
                child: SwitchListTile.adaptive(
                  key: const Key('trad-audio'),
                  value: TradPrefs.audio,
                  activeThumbColor: MC.onAccent,
                  activeTrackColor: MC.savane,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  secondary: Icon(Icons.graphic_eq_rounded, color: MC.savane),
                  title: Text(L10n.t('trad_audio'),
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.body,
                          fontWeight: FontWeight.w700)),
                  subtitle: Text(L10n.t('trad_audio_sub'),
                      style: TextStyle(
                          color: MC.kaki, fontSize: Tx.caption, height: 1.35)),
                  onChanged: (v) async {
                    await TradPrefs.set(audio: v);
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(height: 8),

 // ---- Notes vocales traduites (Lokota historique) ------------
              _Carte(
                child: ListTile(
                  key: const Key('trad-lokota'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: Icon(Icons.record_voice_over_rounded,
                      color: MC.soleil),
                  title: Text(L10n.t('trad_voice_notes'),
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.body,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text(L10n.t('trad_voice_notes_sub'),
                      style: TextStyle(
                          color: MC.kaki, fontSize: Tx.caption, height: 1.35)),
                  trailing: Icon(Icons.chevron_right_rounded, color: MC.kaki),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const LokotaScreen()));
                  },
                ),
              ),

              if (actif)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: MC.kaki, size: 15),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(L10n.t('trad_active_note'),
                            style: TextStyle(
                                color: MC.kaki,
                                fontSize: Tx.caption,
                                height: 1.35)),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  key: const Key('trad-fermer'),
                  style: FilledButton.styleFrom(
                    backgroundColor: MC.soleil,
                    foregroundColor: MC.onAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Rd.md)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(L10n.t('trad_done'),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Carte arrondie, même surface que partout dans l'application.
class _Carte extends StatelessWidget {
  final Widget child;
  const _Carte({required this.child});
  @override
  Widget build(BuildContext context) => Material(
        color: MC.nuit3,
        borderRadius: BorderRadius.circular(Rd.md),
        child: child,
      );
}

class _Titre extends StatelessWidget {
  final String texte;
  const _Titre(this.texte);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 2),
        child: Text(texte.toUpperCase(),
            style: TextStyle(
                color: MC.kaki,
                fontSize: Tx.caption,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1)),
      );
}

class _Langues extends StatelessWidget {
  final String prefixe;
  final String choisi;
  final ValueChanged<String> onPick;
  const _Langues({
    required this.prefixe,
    required this.choisi,
    required this.onPick,
  });

  static String _nom(String c) {
    switch (c) {
      case 'ln':
        return L10n.t('lang_ln');
      case 'sw':
        return L10n.t('lang_sw');
      default:
        return L10n.t('lang_fr');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in TradPrefs.codes)
          ChoiceChip(
            key: Key('$prefixe-$c'),
            selected: choisi == c,
            onSelected: (_) => onPick(c),
            label: Text(_nom(c)),
            avatar: Icon(
              choisi == c ? Icons.check_rounded : Icons.language_rounded,
              size: 16,
              color: choisi == c ? MC.onAccent : MC.kaki,
            ),
            labelStyle: TextStyle(
                color: choisie(choisi, c) ? MC.onAccent : MC.sable,
                fontWeight: FontWeight.w700,
                fontSize: Tx.label),
            backgroundColor: MC.nuit3,
            selectedColor: MC.soleil,
            side: BorderSide(color: choisi == c ? MC.soleil : MC.ligne),
            showCheckmark: false,
          ),
      ],
    );
  }

  bool choisie(String choisi, String c) => choisi == c;
}
