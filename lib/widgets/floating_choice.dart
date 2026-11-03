import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design.dart';
import '../theme.dart';

/// 🔵 Bouton **flottant à icône seule** — le geste de choix de l'application.
///
/// Principe d'interface (UI) : un aplat de couleur, une icône Material
/// explicite, un léger relief qui le détache du fond — rien d'autre.
/// Principe d'expérience (UX) :
///  • **aucun texte visible** : l'icône parle d'elle-même (téléphone, caméra,
///    groupe) et la couleur renforce le sens (vert = voix, sable = vidéo,
///    corail = groupe) ;
///  • l'explication reste accessible : `tooltip` au survol / appui long et
///    `Semantics.label` pour les lecteurs d'écran — donc rien n'est perdu
///    pour un utilisateur malvoyant ou novice ;
///  • retour tactile (`HapticFeedback.selectionClick`) et animation de
///    pression (l'échelle tombe à 0,93) : le doigt sent que ça répond ;
///  • cible de 68 px, très au-dessus du minimum de 48 px.
class FloatingChoice extends StatefulWidget {
  /// Icône Material du choix (`Icons.call_rounded`, etc.).
  final IconData icon;

  /// Aplat du bouton. L'icône est toujours dessinée en `MC.nuit` : les trois
  /// couleurs de l'identité dépassent 5:1 avec ce fond (vérifié par les tests).
  final Color color;

  /// Nom du choix — **jamais affiché**, lu par les lecteurs d'écran et le
  /// survol. Exemple : « Appel audio ».
  final String label;

  /// Détail lu par les lecteurs d'écran (« Voix sur Internet, gratuit… »).
  final String? hint;

  final VoidCallback onTap;

  /// Côté du bouton. 68 px par défaut, 56 px pour une action secondaire.
  final double size;

  /// Version discrète : contour et icône de couleur, sans aplat plein.
  final bool outlined;

  /// État « choisi » : anneau autour du bouton (sélection dans une liste).
  final bool selected;

  const FloatingChoice({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.hint,
    this.size = 68,
    this.outlined = false,
    this.selected = false,
  });

  @override
  State<FloatingChoice> createState() => _FloatingChoiceState();
}

class _FloatingChoiceState extends State<FloatingChoice> {
  bool _presse = false;

  @override
  Widget build(BuildContext context) {
    final rayon = BorderRadius.circular(widget.size * 0.32);
    final fond = widget.outlined ? MC.nuit2 : widget.color;
    final teinte = widget.outlined ? widget.color : MC.nuit;

    return Semantics(
      button: true,
      label: widget.label,
      hint: widget.hint,
      child: Tooltip(
        message: widget.hint == null ? widget.label : '${widget.label} · ${widget.hint}',
        waitDuration: const Duration(milliseconds: 400),
        child: AnimatedScale(
          scale: _presse ? .93 : 1,
          duration: Motion.rapide,
          curve: Curves.easeOut,
          child: Container(
            // Le relief est ce qui rend le bouton « flottant » : une ombre
            // teintée de sa propre couleur, jamais du noir.
            decoration: BoxDecoration(
              borderRadius: rayon,
              boxShadow: widget.outlined
                  ? null
                  : [
                      BoxShadow(
                        color: widget.color.withValues(alpha: .34),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
              border: widget.selected
                  ? Border.all(color: MC.ivoire, width: 2)
                  : null,
            ),
            child: Material(
              color: fond,
              borderRadius: rayon,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: rayon,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onTap();
                },
                onTapDown: (_) => setState(() => _presse = true),
                onTapCancel: () => setState(() => _presse = false),
                onTapUp: (_) => setState(() => _presse = false),
                child: SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: Icon(
                    widget.icon,
                    color: teinte,
                    size: widget.size * 0.42,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rangée de boutons flottants, espacés et centrés — l'alignement est
/// volontairement identique partout (choix du type d'appel, audio/vidéo…).
class FloatingChoiceRow extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  const FloatingChoiceRow({
    super.key,
    required this.children,
    this.gap = Sp.x5,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          children[i],
        ],
      ],
    );
  }
}
