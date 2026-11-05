// lib/widgets/social/texte_social.dart
// TEXTE SOCIAL — hashtags et mentions cliquables, partout.
//
// Le même widget sert dans le fil, les commentaires, les statuts et la
// recherche : une seule façon de reconnaître « #MboteCall » et « @cedrick »,
// donc un seul comportement à corriger le jour où la règle change.
//
// Couleurs (identité MboteCall) :
//   #hashtag → couleur primaire du thème (accent)
//   @mention → couleur secondaire du thème (accent2)
// Un appui donne un retour tactile discret, pas d'animation : Hero = 0.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../../design.dart';

/// Segment reconnu dans un texte.
class SegmentSocial {
  final String type; // texte | hashtag | mention | lien
  final String valeur;
  final String cle; // clé du hashtag, identifiant de la personne

  const SegmentSocial(this.type, this.valeur, [this.cle = '']);

  bool get estHashtag => type == 'hashtag';
  bool get estMention => type == 'mention';
}

/// Découpe un texte en segments. Même règle que le serveur :
///  - `#mot` : 2 à 30 caractères, lettres (accents compris), chiffres, `_` ;
///  - `@mot` : 2 à 40 caractères, lettres, chiffres, `.`, `_`, `-` ;
///  - ni l'un ni l'autre s'ils sont collés à un mot (courriel, code couleur).
class AnalyseurSocial {
  static final RegExp _motif = RegExp(
    r'(?<![\p{L}\p{N}_.])#[^#@\s#]{2,30}'
    r'|'
    r'(?<![\p{L}\p{N}_.])@[^#@\s@]{2,40}'
    r'|'
    r'https?://[^\s]+',
    unicode: true,
  );

  static List<SegmentSocial> decouper(String texte) {
    if (texte.isEmpty) return const [SegmentSocial('texte', '')];
    final segments = <SegmentSocial>[];
    var dernier = 0;

    for (final m in _motif.allMatches(texte)) {
      if (m.start > dernier) {
        segments.add(SegmentSocial('texte', texte.substring(dernier, m.start)));
      }
      final brut = m.group(0)!;
      if (brut.startsWith('#')) {
        final nom = brut.substring(1).replaceAll(RegExp(r'[.,;:!?)]+$'), '');
        final cle = _cle(nom);
        segments.add(cle == null
            ? SegmentSocial('texte', brut)
            : SegmentSocial('hashtag', brut, cle));
      } else if (brut.startsWith('@')) {
        final nom = brut.substring(1).replaceAll(RegExp(r'[.,;:!?)]+$'), '');
        final cle = _handle(nom);
        segments.add(cle == null
            ? SegmentSocial('texte', brut)
            : SegmentSocial('mention', brut, cle));
      } else {
        segments.add(SegmentSocial('lien', brut));
      }
      dernier = m.start + brut.length;
    }
    if (dernier < texte.length) {
      segments.add(SegmentSocial('texte', texte.substring(dernier)));
    }
    return segments;
  }

  /// Clé de comparaison d'un hashtag (sans accent, minuscules).
  static String? _cle(String nom) {
    final s = retirerAccents(nom).replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return s.length >= 2 ? s : null;
  }

  /// Identifiant public d'une mention.
  static String? _handle(String nom) {
    final s = retirerAccents(nom).replaceAll(RegExp(r'[^a-z0-9._-]'), '');
    return s.length >= 2 ? s : null;
  }

  /// Retire les accents : « Cédrick » et « Cedrick » désignent la même personne.
  static String retirerAccents(String v) {
    const avec = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
    const sans = 'aaaaaaceeeeiiiinooooouuuuyyoea';
    final b = StringBuffer();
    for (final rune in v.toLowerCase().runes) {
      final c = String.fromCharCode(rune);
      final i = avec.indexOf(c);
      b.write(i >= 0 ? sans[i] : c);
    }
    return b.toString();
  }
}

/// Texte avec hashtags et mentions cliquables.
class TexteSocial extends StatefulWidget {
  final String texte;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? couleur;
  final int? maxLines;
  final TextAlign textAlign;
  final double height;

  /// Appui sur « #hashtag » (clé sans dièse).
  final ValueChanged<String>? onHashtag;

  /// Appui sur « @mention » (identifiant sans arobase).
  final ValueChanged<String>? onMention;

  /// Appui sur un lien.
  final ValueChanged<String>? onLien;

  /// Nom affiché d'une mention, quand on le connaît déjà (via `post.mentions`).
  final Map<String, String>? nomsMentions;

  const TexteSocial(
    this.texte, {
    super.key,
    this.fontSize = Tx.body,
    this.fontWeight = FontWeight.w400,
    this.couleur,
    this.maxLines,
    this.textAlign = TextAlign.start,
    this.height = 1.4,
    this.onHashtag,
    this.onMention,
    this.onLien,
    this.nomsMentions,
  });

  @override
  State<TexteSocial> createState() => _TexteSocialState();
}

class _TexteSocialState extends State<TexteSocial> {
  final List<TapGestureRecognizer> _gestes = [];

  @override
  void dispose() {
    _nettoyer();
    super.dispose();
  }

  void _nettoyer() {
    for (final g in _gestes) {
      g.dispose();
    }
    _gestes.clear();
  }

  @override
  Widget build(BuildContext context) {
    // Les gestes sont reconstruits à chaque rendu : les libérer évite une fuite
    // silencieuse quand une carte sort du défilement.
    _nettoyer();

    final base = widget.couleur ?? MC.ivoire;
    final segments = AnalyseurSocial.decouper(widget.texte);
    final spans = <InlineSpan>[];

    for (final s in segments) {
      if (s.estHashtag && widget.onHashtag != null) {
        final g = TapGestureRecognizer()
          ..onTap = () {
            HapticFeedback.selectionClick();
            widget.onHashtag!(s.cle);
          };
        _gestes.add(g);
        spans.add(TextSpan(
          text: _affiche(s.valeur),
          recognizer: g,
          style: TextStyle(
            color: MC.soleil,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none,
          ),
        ));
      } else if (s.estMention && widget.onMention != null) {
        final g = TapGestureRecognizer()
          ..onTap = () {
            HapticFeedback.selectionClick();
            widget.onMention!(s.cle);
          };
        _gestes.add(g);
        spans.add(TextSpan(
          text: _affiche(s.valeur),
          recognizer: g,
          style: TextStyle(
            color: MC.braise,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none,
          ),
        ));
      } else if (s.type == 'lien' && widget.onLien != null) {
        final g = TapGestureRecognizer()
          ..onTap = () {
            HapticFeedback.selectionClick();
            widget.onLien!(s.valeur);
          };
        _gestes.add(g);
        spans.add(TextSpan(
          text: s.valeur,
          recognizer: g,
          style: TextStyle(color: MC.braise, decoration: TextDecoration.underline),
        ));
      } else {
        spans.add(TextSpan(text: s.valeur, style: TextStyle(color: base)));
      }
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: widget.maxLines,
      overflow: widget.maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
      textAlign: widget.textAlign,
      style: TextStyle(
        color: base,
        fontSize: widget.fontSize,
        fontWeight: widget.fontWeight,
        height: widget.height,
      ),
    );
  }

  /// Les mentions gardent l'écriture tapée, sauf si l'on connaît le nom
  /// affiché : « @cedricklengo » devient « @Cédrick Lengo ».
  String _affiche(String valeur) {
    if (valeur.startsWith('@') && widget.nomsMentions != null) {
      final nom = widget.nomsMentions![valeur.substring(1).toLowerCase()];
      if (nom != null && nom.trim().isNotEmpty) return '@$nom';
    }
    return valeur;
  }
}
