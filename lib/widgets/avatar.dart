import 'package:flutter/material.dart';

import '../design.dart';
import '../theme.dart';

///L'avatar de l'application — **carré arrondi**, jamais un cercle.
///
/// Identité « Fleuve Congo » : les photos et les initiales vivent dans un
/// carré à coins arrondis (12 px), cerclé d'un filet de 1 px. Ce widget existe
/// pour qu'aucun écran n'assemble son avatar à la main (cercle, dégradé,
/// initiales) :
/// changer l'avatar de toute l'application se fait ici.
///
/// ```dart
/// MboteAvatar(name: 'Maman')
/// MboteAvatar(name: 'Maman', image: MemoryImage(octets), size: 88)
/// MboteAvatar(name: 'Maman', accent: true) // fond dégradé signature
/// ```
class MboteAvatar extends StatelessWidget {
  /// Nom complet : les initiales sont calculées automatiquement.
  final String name;

  /// Photo de profil (réseau, mémoire, fichier). Sinon : initiales.
  final ImageProvider? image;

  /// Côté du carré, en pixels.
  final double size;

  /// Fond dégradé (accent → accent2) : sert à mettre en avant un fil non lu.
  final bool accent;

  const MboteAvatar({
    super.key,
    required this.name,
    this.image,
    this.size = Densite.avatar,
    this.accent = false,
  });

  /// Taille de la police adaptée au carré, toujours dans l'échelle.
  double get _tailleTexte {
    if (size >= 56) return Tx.headline;
    if (size >= 40) return Tx.subtitle;
    if (size >= 30) return Tx.body;
    return Tx.label;
  }

  /// « Maman » → « M », « Papa Joseph » → « PJ ».
  String get _initiales {
    final mots = name.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty);
    if (mots.isEmpty) return '?';
    if (mots.length == 1) return mots.first.characters.first.toUpperCase();
    return (mots.first.characters.first + mots.elementAt(1).characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Rd.avatar),
        color: accent ? null : MC.nuit3,
        gradient: accent ? MC.degrade : null,
        border: Border.all(color: accent ? MC.soleil : MC.ligne),
      ),
      child: image != null
          ? Image(image: image!, fit: BoxFit.cover, width: size, height: size)
          : Text(
              _initiales,
              style: TextStyle(
                color: accent ? MC.onAccent : MC.sable,
                fontSize: _tailleTexte,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}
