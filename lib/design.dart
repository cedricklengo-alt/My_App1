import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'l10n.dart';

//────────────────────────────────────────────────────────────────────┐
// SYSTÈME DE DESIGN MBOTE — les « règles du jeu » visuelles
//────────────────────────────────────────────────────────────────────┘
//
// Historiquement, chaque écran choisissait ses tailles de texte, ses
// arrondis et ses marges « à la main » : ~30 tailles de police différentes,
// des libellés tombés à 9 px (illisibles), 7 couples de couleurs sous le
// seuil de contraste WCAG AA. Ce fichier centralise les décisions pour
// qu'elles soient **vérifiables par des tests** (`test/design_test.dart`).
//
// Trois règles, courtes :
//   1. **Lisibilité** — aucun texte sous [Tx.caption] (11 px) ; tout texte
//      courant atteint un contraste ≥ 4.5:1 (AA), les éléments purement
//      décoratifs ≥ 3:1.
//   2. **Rythme** — une échelle typographique fermée ([Tx]) et une échelle
//      d'espacement en multiples de 4 ([Sp]). On ne réinvente pas 12,5 px.
//   3. **Cohérence** — des rayons ([Rd]), des durées d'animation ([Motion])
//      et des cibles tactiles ([Tap]) nommés, pas des nombres magiques.

///Échelle typographique — 7 marches, du plus petit au plus grand.
///
/// Une seule taille par « rôle ». Si un écran a besoin d'une taille qui n'est
/// pas ici, c'est le rôle qui manque : en ajouter un, pas un nombre.
class Tx {
  Tx._();

  /// 11 px — le **plancher absolu** : badges, horodatages, mentions légères.
  static const double caption = 11;

  /// 12 px — étiquettes de boutons compacts, onglets, puces.
  static const double label = 12;

  /// 14 px — texte courant des listes et des champs (défaut du corps).
  static const double body = 14;

  /// 15 px — texte courant confortable (messages, paragraphes).
  static const double bodyLg = 15;

  /// 17 px — sous-titres, titres de section de carte.
  static const double subtitle = 17;

  /// 21 px — titres d'écran (AppBar) et en-têtes de section.
  static const double title = 21;

  /// 26 px — chiffres clés (solde, durée d'appel), titres de héros.
  static const double headline = 26;

  /// 34 px — très gros chiffres (compte à rebours, montant plein écran).
  static const double display = 34;

  /// Tailles autorisées, triées — sert de référence aux tests.
  static const List<double> echelle = [
    caption,
    label,
    body,
    bodyLg,
    subtitle,
    title,
    headline,
    display,
  ];

  /// Taille minimale autorisée pour **tout** texte affiché.
  static const double minimum = caption;
}

///Espacement — multiples de 4 px, alignés sur une grille de 8.
class Sp {
  Sp._();
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;

  /// Marge horizontale standard d'un écran.
  static const double ecran = x4;

  /// Espace entre deux blocs distincts.
  static const double bloc = x3;

  /// Espace entre deux éléments d'un même bloc.
  static const double element = x2;
}

///Rayons — 4 crans, pour que tous les coins se ressemblent.
///
/// Identité « Fleuve Congo » : bords **nets**. Les cartes et les champs sont
/// peu arrondis (12), les avatars sont des carrés arrondis et non des cercles.
class Rd {
  Rd._();
  static const double xs = 4; // puces, mini-badges
  static const double sm = 8; // champs compacts, vignettes
  static const double md = 12; // cartes, boutons, champs (défaut)
  static const double lg = 20; // feuilles (bottom sheets), grandes cartes
  static const double avatar = 12; // avatars : carrés arrondis
  static const double pill = 999; // pastilles de compteur, filtres
}

///Mesures de densité (identité compacte : plus de contenu à l'écran).
class Densite {
  Densite._();
  static const double ligneListe = 64; // une conversation dans la liste
  static const double avatar = 44;
  static const double avatarPetit = 30;
  static const double barre = 56; // barre d'onglets / de saisie
  static const double separateur = 1;
}

/// Durées d'animation — trois vitesses, pas plus.
class Motion {
  Motion._();
  static const Duration rapide = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration lent = Duration(milliseconds: 320);
}

///Cibles tactiles — Material recommande 48 dp de côté minimum.
class Tap {
  Tap._();
  static const double min = 48;
  static const double confort = 56;
}

///Couleurs **hors palettes**, centralisées ici pour rester traçables.
///
/// Les quatre palettes de `theme.dart` décrivent l'identité de l'app ; les
/// couleurs ci-dessous sont des exceptions assumées (marques tierces, types
/// de contenu). Elles ne doivent **pas** être écrites en dur dans un écran :
/// sinon un changement de thème laisse des taches incohérentes.

/// Couleurs officielles des moyens de paiement (marques : on ne les
/// « harmonise » pas, on les respecte).
class Marques {
  Marques._();
  static const Color mpesa = Color(0xFFE2231A);
  static const Color orangeMoney = Color(0xFFFF7900);
  static const Color airtelMoney = Color(0xFFD6001C);
  static const Color carteBancaire = Color(0xFF1A3C8B);
}

/// Couleurs sémantiques de contenu (badges, états, accents fonctionnels).
class Semantique {
  Semantique._();

  /// Étiquette « CLIP » sur une vidéo courte.
  static const Color clip = Color(0xFFE8674F);

  /// Étiquette « ÉVÉN. » et filets d'un événement.
  static const Color evenement = Color(0xFF9C6DFF);

  /// Vert du bouton d'appel (dégradé du clavier téléphonique).
  static const Color appelClair = Color(0xFF3BC684);

  /// Coche « lu » dans la liste des discussions.
  static const Color lu = Color(0xFF53BDEB);

  /// Coche « lu » posée **sur une bulle claire** (fond ambre) : version
  /// sombre, sinon l'icône disparaît.
  static const Color luSurBulle = Color(0xFF1B6FA8);

  /// Rouge du bouton « raccrocher ». Plus profond que `MC.rouge` pour que
  /// l'icône **blanche** (convention universelle) atteigne 4.5:1 : sur le
  /// rouge d'erreur #EE6459 elle tombait à 3.18:1.
  static const Color raccrocher = Color(0xFFC63A32);
}

/// Surcouches neutres (ombres, voiles) — jamais des couleurs de marque.
class Surcouche {
  Surcouche._();
  static const Color ombre = Color(0x33000000);
}

///Contraste WCAG 2.1 — luminance relative d'une couleur opaque.
///
/// La formule est celle de la recommandation (sRGB linéarisé). On ignore le
/// canal alpha : les couleurs de la palette sont opaques par construction.
double luminanceRelative(Color c) {
  double canal(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
}

/// Rapport de contraste entre deux couleurs, entre 1:1 et 21:1.
///
/// `contrastRatio(a, b) >= 4.5` = lisible en texte courant (AA).
/// `>= 3.0` = suffisant pour une icône, une bordure ou un aplat décoratif.
double contrastRatio(Color a, Color b) {
  final la = luminanceRelative(a);
  final lb = luminanceRelative(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

//────────────────────────────────────────────────────────────────────┐
// ACCESSIBILITÉ — annoncer l'attente
//────────────────────────────────────────────────────────────────────┘

/// Indicateur de chargement **annoté**.
///
/// Un `CircularProgressIndicator` posé seul est invisible pour un lecteur
/// d'écran (WCAG 4.1.3 « messages de statut »). `Chargement` l'enveloppe dans
/// une région vivante qui annonce « Chargement… » dès son apparition, et
/// masque le cercle lui-même (purement décoratif).
///
/// ```dart
/// const Center(child: Chargement())
/// ```
class Chargement extends StatelessWidget {
  const Chargement({
    super.key,
    this.taille = 24,
    this.couleur,
    this.epaisseur = 2.4,
    this.libelle,
  });

  final double taille;

  /// `null` → la couleur d'accent courante (`MC.soleil`).
  final Color? couleur;
  final double epaisseur;

  /// Texte annoncé ; par défaut « Chargement… » dans la langue active.
  final String? libelle;

  @override
  Widget build(BuildContext context) {
    final Color teinte = couleur ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: libelle ?? L10n.t('loading'),
      liveRegion: true,
      child: ExcludeSemantics(
        child: SizedBox(
          width: taille,
          height: taille,
          child: CircularProgressIndicator(
              strokeWidth: epaisseur, color: teinte),
        ),
      ),
    );
  }
}
