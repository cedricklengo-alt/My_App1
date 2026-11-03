// lib/widgets/social/champ_social.dart
// ÉDITEUR SOCIAL — compteurs et suggestions pendant la frappe.
//
// Comportement, aligné sur TikTok, Instagram et X :
//   - je tape « # » → la liste des hashtags existants apparaît sous le champ ;
//   - je tape « @ » → la liste des personnes apparaît, contacts d'abord ;
//   - un appui insère la proposition et referme la liste ;
//   - deux compteurs discrets rappellent combien de hashtags et de mentions
//     seront envoyés (10 au maximum chacun, la règle du serveur).
//
// Aucune animation, aucun Hero : la liste apparaît et disparaît.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api.dart';
import '../../design.dart';
import '../../models/social.dart';
import '../../state.dart';
import '../../theme.dart';
import 'texte_social.dart';

class ChampSocial extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  const ChampSocial({
    super.key,
    required this.controller,
    this.hint = 'Quoi de neuf ?',
    this.maxLines = 4,
    this.onChanged,
    this.autofocus = false,
  });

  @override
  State<ChampSocial> createState() => _ChampSocialState();
}

class _ChampSocialState extends State<ChampSocial> {
  List<Hashtag> _tags = const [];
  List<Personne> _personnes = const [];

  /// Jeton en cours de frappe : « #mbo », « @ced », ou null.
  String? _jeton;
  bool _charge = false;

  Api get _api => context.read<AppState>().api;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_surTexte);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_surTexte);
    super.dispose();
  }

  void _surTexte() {
    widget.onChanged?.call(widget.controller.text);
    final jeton = _jetonCourant();
    if (jeton == null) {
      if (_tags.isNotEmpty || _personnes.isNotEmpty || _jeton != null) {
        setState(() {
          _jeton = null;
          _tags = const [];
          _personnes = const [];
        });
      }
      return;
    }
    if (jeton == _jeton && _charge) return;
    setState(() => _jeton = jeton);
    _chercher(jeton);
  }

  /// Le mot en cours de frappe, s'il commence par # ou @.
  String? _jetonCourant() {
    final texte = widget.controller.text;
    var debut = texte.length;
    while (debut > 0 && !RegExp(r'\s').hasMatch(texte[debut - 1])) {
      debut--;
    }
    final mot = texte.substring(debut);
    if (!mot.startsWith('#') && !mot.startsWith('@')) return null;
    if (mot.length > 25) return null;
    return mot;
  }

  Future<void> _chercher(String jeton) async {
    final requete = jeton.substring(1);
    try {
      if (jeton.startsWith('#')) {
        final tags = await _api.suggestionsHashtags(q: requete);
        if (!mounted || _jeton != jeton) return;
        setState(() {
          _tags = tags;
          _personnes = const [];
          _charge = true;
        });
      } else {
        final gens = await _api.suggestionsMentions(q: requete);
        if (!mounted || _jeton != jeton) return;
        setState(() {
          _personnes = gens;
          _tags = const [];
          _charge = true;
        });
      }
    } catch (_) {
      // Pas de réseau : pas de suggestions. Le texte reste utilisable.
      if (!mounted) return;
      setState(() {
        _tags = const [];
        _personnes = const [];
      });
    }
  }

  /// Remplace le jeton en cours par la proposition choisie.
  void _inserer(String valeur) {
    final texte = widget.controller.text;
    var debut = texte.length;
    while (debut > 0 && !RegExp(r'\s').hasMatch(texte[debut - 1])) {
      debut--;
    }
    final nouveau = '${texte.substring(0, debut)}$valeur ';
    widget.controller.value = TextEditingValue(
      text: nouveau,
      selection: TextSelection.collapsed(offset: nouveau.length),
    );
    HapticFeedback.selectionClick();
    setState(() {
      _jeton = null;
      _tags = const [];
      _personnes = const [];
      _charge = false;
    });
  }

  /// Nombre de hashtags et de mentions déjà écrits (règle du serveur : 10).
  (int, int) get _compteurs {
    final segments = AnalyseurSocial.decouper(widget.controller.text);
    final tags = <String>{};
    final gens = <String>{};
    for (final s in segments) {
      if (s.estHashtag) tags.add(s.cle);
      if (s.estMention) gens.add(s.cle);
    }
    return (tags.length, gens.length);
  }

  @override
  Widget build(BuildContext context) {
    final (nbTags, nbMentions) = _compteurs;
    final suggestions = _tags.isNotEmpty || _personnes.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          autofocus: widget.autofocus,
          maxLines: widget.maxLines,
          minLines: 3,
          style: TextStyle(color: MC.ivoire, fontSize: Tx.body, height: 1.4),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(color: MC.kaki, fontSize: Tx.body),
            filled: true,
            fillColor: MC.nuit3,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Rd.md),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),

        // Compteurs : discrets, ils n'apparaissent que si l'on écrit vraiment
        // des hashtags ou des mentions.
        if (nbTags > 0 || nbMentions > 0) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              if (nbTags > 0)
                _Compteur(
                  icone: Icons.tag_rounded,
                  texte: '$nbTags/10',
                  couleur: MC.soleil,
                  trop: nbTags > 10,
                ),
              if (nbTags > 0 && nbMentions > 0) const SizedBox(width: 12),
              if (nbMentions > 0)
                _Compteur(
                  icone: Icons.alternate_email_rounded,
                  texte: '$nbMentions/10',
                  couleur: MC.braise,
                  trop: nbMentions > 10,
                ),
            ],
          ),
        ],

        // Suggestions temps réel.
        if (suggestions) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: MC.nuit3,
              borderRadius: BorderRadius.circular(Rd.md),
              border: Border.all(color: MC.ligne),
            ),
            child: Column(
              children: [
                if (_tags.isNotEmpty)
                  for (final t in _tags.take(5))
                    _LigneSuggestion(
                      icone: Icons.tag_rounded,
                      couleur: MC.soleil,
                      titre: t.libelle,
                      detail: t.suivi ? 'Suivi · ${t.volume}' : t.volume,
                      onTap: () => _inserer(t.libelle),
                    ),
                if (_personnes.isNotEmpty)
                  for (final p in _personnes.take(5))
                    _LigneSuggestion(
                      icone: Icons.alternate_email_rounded,
                      couleur: MC.braise,
                      titre: p.mention,
                      detail: [
                        if (p.name.isNotEmpty) p.name,
                        if (p.contact) 'Contact',
                        if (p.suivi) 'Suivi',
                      ].join(' · '),
                      avatar: p.avatar,
                      onTap: () => _inserer(p.mention),
                    ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Compteur extends StatelessWidget {
  final IconData icone;
  final String texte;
  final Color couleur;
  final bool trop;

  const _Compteur({
    required this.icone,
    required this.texte,
    required this.couleur,
    this.trop = false,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$texte éléments',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 13, color: trop ? MC.rouge : couleur),
            const SizedBox(width: 3),
            Text(texte,
                style: TextStyle(
                  color: trop ? MC.rouge : MC.kaki,
                  fontSize: Tx.caption,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      );
}

class _LigneSuggestion extends StatelessWidget {
  final IconData icone;
  final Color couleur;
  final String titre;
  final String detail;
  final String? avatar;
  final VoidCallback onTap;

  const _LigneSuggestion({
    required this.icone,
    required this.couleur,
    required this.titre,
    required this.detail,
    required this.onTap,
    this.avatar,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: titre,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              if (avatar != null && avatar!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(avatar!,
                      width: 24,
                      height: 24,
                      fit: BoxFit.cover,
                      // Décoratif : le nom est déjà lu juste à côté.
                      excludeFromSemantics: true,
                      errorBuilder: (_, __, ___) =>
                          Icon(Icons.person_rounded, size: 18, color: couleur)),
                )
              else
                Icon(icone, size: 17, color: couleur),
              const SizedBox(width: 9),
              Expanded(
                child: Text(titre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: MC.ivoire,
                        fontSize: Tx.label,
                        fontWeight: FontWeight.w700)),
              ),
              if (detail.isNotEmpty)
                Flexible(
                  child: Text(detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(color: MC.kaki, fontSize: Tx.caption)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
