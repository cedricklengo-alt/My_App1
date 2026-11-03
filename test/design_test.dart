// Tests du SYSTÈME DE DESIGN (lib/design.dart + lib/theme.dart).
//
// Ces tests ne vérifient pas des goûts, mais des règles mesurables :
//  1. contraste WCAG AA (4.5:1 texte, 3:1 décoratif) sur toutes les palettes ;
//  2. plancher typographique : aucun texte sous 11 px, échelle unique ;
//  3. plus aucune couleur écrite en dur dans les écrans (tout passe par
//     une palette ou par les jetons de design.dart) ;
//  4. cibles tactiles suffisantes (onglets, bouton principal) ;
//  5. cohérence entre `MC` (couleurs actives) et la palette par défaut.
//
// Astuce : ces tests lisent aussi le code source (`lib/`). Une régression
// « visuelle » (un `fontSize: 9` réintroduit, un `Color(0xFF…)` oublié) fait
// donc échouer la suite, sans qu'il faille inspecter l'écran à la main.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mbote/design.dart';
import 'package:mbote/theme.dart';
import 'package:mbote/widgets/avatar.dart';
import 'package:mbote/widgets/floating_choice.dart';

/// Toutes les paires texte/fond à respecter, avec le seuil exigé.
const List<(String fg, String bg, double seuil, String quoi)> kPaires = [
  ('ivoire', 'nuit', 4.5, 'texte principal sur fond d\'écran'),
  ('ivoire', 'nuit2', 4.5, 'texte principal sur carte'),
  ('ivoire', 'nuit3', 4.5, 'texte principal sur champ'),
  ('sable', 'nuit', 4.5, 'texte secondaire sur fond d\'écran'),
  ('sable', 'nuit2', 4.5, 'texte secondaire sur carte'),
  ('sable', 'nuit3', 4.5, 'texte secondaire sur champ'),
  ('kaki', 'nuit', 4.5, 'texte discret sur fond d\'écran'),
  ('kaki', 'nuit2', 4.5, 'texte discret sur carte'),
  ('kaki', 'nuit3', 4.5, 'texte discret sur champ'),
  ('accent', 'nuit', 4.5, 'accent en texte/lien'),
  ('savane', 'nuit', 4.5, 'vert en texte'),
  ('rouge', 'nuit', 4.5, 'rouge en texte (erreur)'),
  // Icônes et aplats sur les surfaces plus claires : 3:1 suffit (WCAG 1.4.11)
  ('accent', 'nuit2', 3.0, 'accent en icône sur carte'),
  ('accent', 'nuit3', 3.0, 'accent en icône sur champ'),
  ('savane', 'nuit3', 3.0, 'vert en icône sur champ'),
  ('rouge', 'nuit3', 3.0, 'rouge en icône sur champ'),
  ('terre', 'nuit', 3.0, 'terre (décoratif : dégradés, avatars)'),
  ('terre', 'nuit2', 3.0, 'terre sur carte'),
  ('terre', 'nuit3', 3.0, 'terre sur champ'),
  // Texte posé SUR un aplat de couleur (boutons pleins)
  ('onAccent', 'accent', 4.5, 'texte du bouton sur accent'),
  ('onAccent', 'accent2', 4.5, 'texte du bouton sur accent2'),
];

Color _champ(Palette p, String nom) => switch (nom) {
      'nuit' => p.nuit,
      'nuit2' => p.nuit2,
      'nuit3' => p.nuit3,
      'accent' => p.accent,
      'accent2' => p.accent2,
      'terre' => p.terre,
      'savane' => p.savane,
      'rouge' => p.rouge,
      'ivoire' => p.ivoire,
      'sable' => p.sable,
      'kaki' => p.kaki,
      'ligne' => p.ligne,
      'onAccent' => p.onAccent,
      'halo' => p.halo,
      _ => throw ArgumentError('champ inconnu : $nom'),
    };

/// Tous les fichiers Dart de `lib/`, avec leur chemin relatif.
List<(String chemin, String source)> _sources() {
  final racine = Directory('lib');
  expect(racine.existsSync(), isTrue,
      reason: 'les tests doivent tourner depuis la racine du projet');
  return racine
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => (f.path.replaceAll('\\', '/'), f.readAsStringSync()))
      .toList();
}

void main() {
  group('Contraste — formule WCAG', () {
    test('références connues', () {
      expect(contrastRatio(Colors.white, Colors.black), closeTo(21.0, 0.1));
      expect(contrastRatio(Colors.black, Colors.black), closeTo(1.0, 0.01));
      expect(contrastRatio(Colors.white, Colors.white), closeTo(1.0, 0.01));
      // #767676 est LA valeur de référence : 4.54:1 sur blanc.
      expect(
          contrastRatio(const Color(0xFF767676), Colors.white),
          closeTo(4.54, 0.02));
    });

    test('luminance relative : noir = 0, blanc = 1', () {
      expect(luminanceRelative(Colors.black), closeTo(0.0, 0.001));
      expect(luminanceRelative(Colors.white), closeTo(1.0, 0.001));
    });
  });

  group('Contraste — les palettes sont lisibles', () {
    for (final entree in kPalettes.entries) {
      final nom = entree.key;
      final p = entree.value;
      for (final (fg, bg, seuil, quoi) in kPaires) {
        test('$nom · $quoi ($fg sur $bg ≥ $seuil)', () {
          final ratio = contrastRatio(_champ(p, fg), _champ(p, bg));
          expect(ratio, greaterThanOrEqualTo(seuil),
              reason: '$nom: $fg sur $bg = ${ratio.toStringAsFixed(2)}:1 '
                  '(< $seuil requis pour « $quoi »)');
        });
      }
    }

    test('les thèmes annoncés existent bien', () {
      expect(kPalettes.keys.toSet(),
          {'fleuve', 'kin', 'emeraude', 'ocean', 'bleu'});
      expect(ThemeCtl.themes.keys.toSet(), kPalettes.keys.toSet());
      // « Fleuve Congo » est l'identité de référence de l'application.
      expect(kPalettes.containsKey('fleuve'), isTrue);
      expect(ThemeCtl.themes['fleuve'], contains('Fleuve'));
    });

    test('le thème par défaut est « Fleuve Congo »', () async {
      SharedPreferences.setMockInitialValues({});
      await ThemeCtl.load();
      expect(ThemeCtl.theme, 'fleuve');
      expect(MC.nuit, kPalettes['fleuve']!.nuit);
      expect(MC.soleil, kPalettes['fleuve']!.accent);
    });

    test('le thème « bleu » garde un texte sombre sur son accent clair', () {
      // Régression : avec un `onAccent` blanc, le bouton dégradé du thème
      // Bleu Nuit tombait sous 4.5:1 (3.0:1) — illisible en plein soleil.
      final p = kPalettes['bleu']!;
      expect(luminanceRelative(p.onAccent), lessThan(0.2),
          reason: 'onAccent doit rester SOMBRE sur un accent bleu clair');
      expect(contrastRatio(p.onAccent, p.accent), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(p.onAccent, p.accent2), greaterThanOrEqualTo(4.5));
    });
  });

  group('Typographie', () {
    test('l\'échelle est croissante, sans doublon, et démarre à 11 px', () {
      expect(Tx.echelle, orderedEquals([...Tx.echelle]..sort()));
      expect(Tx.echelle.toSet().length, Tx.echelle.length,
          reason: 'deux rôles ne doivent pas avoir la même taille');
      expect(Tx.minimum, 11.0);
      expect(Tx.echelle.first, Tx.minimum);
      for (final taille in Tx.echelle) {
        expect(taille, greaterThanOrEqualTo(Tx.minimum));
      }
    });

    test('aucun texte de lib/ n\'est rendu sous 11 px', () {
      final coupables = <String>[];
      final taille = RegExp(r'fontSize:\s*([0-9]+(?:\.[0-9]+)?)');
      for (final (chemin, source) in _sources()) {
        for (final m in taille.allMatches(source)) {
          final px = double.parse(m.group(1)!);
          if (px < Tx.minimum) {
            final ligne = '\n'.allMatches(source.substring(0, m.start)).length + 1;
            coupables.add('$chemin:$ligne → ${m.group(1)} px');
          }
        }
      }
      expect(coupables, isEmpty,
          reason: 'tailles trop petites (plancher = ${Tx.minimum} px) :\n'
              '${coupables.join('\n')}');
    });

    test('aucune taille de police littérale ne subsiste dans lib/', () {
      // Fin de la migration : toutes les tailles passent par les jetons `Tx`.
      // Un `fontSize: 15` écrit à la main est désormais un échec.
      final intrus = <String>[];
      final taille = RegExp(r'fontSize:\s*[0-9]');
      for (final (chemin, source) in _sources()) {
        if (chemin.endsWith('lib/design.dart')) continue;
        for (final m in taille.allMatches(source)) {
          final ligne = '\n'.allMatches(source.substring(0, m.start)).length + 1;
          intrus.add('$chemin:$ligne');
        }
      }
      expect(intrus, isEmpty,
          reason: 'utilisez un jeton Tx.* plutôt qu\'un nombre de pixels :\n'
              '${intrus.join('\n')}');
    });

    test('les jetons Tx sont les seules tailles, et couvrent les rôles', () {
      final utilisees = <String>{};
      final jeton = RegExp(r'fontSize:\s*(Tx\.[a-zA-Z]+)');
      for (final (_, source) in _sources()) {
        for (final m in jeton.allMatches(source)) {
          utilisees.add(m.group(1)!);
        }
      }
      // Chaque rôle de l'échelle est réellement employé quelque part.
      for (final role in [
        'Tx.caption',
        'Tx.label',
        'Tx.body',
        'Tx.bodyLg',
        'Tx.subtitle',
        'Tx.title',
        'Tx.headline',
        'Tx.display',
      ]) {
        expect(utilisees, contains(role),
            reason: '$role n\'est utilisé nulle part : rôle inutile ou oubli');
      }
    });
  });

  group('Avatars', () {
    test('plus aucun CircleAvatar dans lib/ (identité : carrés arrondis)', () {
      final intrus = <String>[];
      for (final (chemin, source) in _sources()) {
        if (source.contains('CircleAvatar')) intrus.add(chemin);
      }
      expect(intrus, isEmpty,
          reason: 'utilisez MboteAvatar (lib/widgets/avatar.dart) :\n'
              '${intrus.join('\n')}');
    });

    testWidgets('MboteAvatar dessine un carré arrondi, pas un cercle',
        (testeur) async {
      await testeur.pumpWidget(MaterialApp(
        theme: mboteTheme(),
        home: const Scaffold(
          body: Center(
            child: MboteAvatar(key: Key('av'), name: 'Papa Joseph'),
          ),
        ),
      ));
      final taille = testeur.getSize(find.byKey(const Key('av')));
      expect(taille.width, Densite.avatar);
      expect(taille.height, Densite.avatar);
      final conteneur = testeur.widget<Container>(find
          .descendant(of: find.byKey(const Key('av')), matching: find.byType(Container))
          .first);
      final deco = conteneur.decoration as BoxDecoration;
      expect(deco.borderRadius, BorderRadius.circular(Rd.avatar));
      expect(deco.shape, BoxShape.rectangle);
      // « Papa Joseph » → « PJ », et le texte reste au-dessus du plancher.
      final texte = testeur.widget<Text>(find.text('PJ'));
      expect(texte.style?.fontSize, greaterThanOrEqualTo(Tx.minimum));
    });

    testWidgets('MboteAvatar en mode accent utilise le dégradé signature',
        (testeur) async {
      await testeur.pumpWidget(MaterialApp(
        theme: mboteTheme(),
        home: const Scaffold(
          body: Center(child: MboteAvatar(key: Key('av2'), name: 'Maman', accent: true)),
        ),
      ));
      final deco = (testeur
          .widget<Container>(find
              .descendant(
                  of: find.byKey(const Key('av2')),
                  matching: find.byType(Container))
              .first)
          .decoration as BoxDecoration);
      expect(deco.gradient, MC.degrade);
      final texte = testeur.widget<Text>(find.text('M'));
      expect(texte.style?.color, MC.onAccent);
    });
  });

  group('Boutons flottants (choix du type d’appel)', () {
    test('les trois couleurs de choix portent une icône lisible', () {
      // Le bouton est un aplat de couleur, l'icône est dessinée en MC.nuit :
      // il faut au moins 3:1 (règle 1.4.11 pour les éléments graphiques).
      for (final (nom, couleur) in [
        ('voix', MC.savane),
        ('vidéo', MC.soleil),
        ('groupe', MC.braise),
      ]) {
        final ratio = contrastRatio(MC.nuit, couleur);
        expect(ratio, greaterThanOrEqualTo(3.0),
            reason: 'icône « $nom » sur son aplat : ${ratio.toStringAsFixed(2)}:1');
      }
    });

    testWidgets('un bouton flottant ne contient aucun texte visible',
        (testeur) async {
      var touches = 0;
      await testeur.pumpWidget(MaterialApp(
        theme: mboteTheme(),
        home: Scaffold(
          body: Center(
            child: FloatingChoice(
              icon: Icons.call_rounded,
              color: MC.savane,
              label: 'Appel audio',
              hint: 'Voix sur Internet',
              onTap: () => touches++,
            ),
          ),
        ),
      ));
      // Aucun texte : l'icône et la couleur suffisent.
      expect(find.byType(Text), findsNothing);
      // Mais l'explication reste accessible.
      expect(find.bySemanticsLabel('Appel audio'), findsOneWidget);
      // Cible tactile confortable et appui fonctionnel.
      final taille = testeur.getSize(find.byType(InkWell).first);
      expect(taille.width, greaterThanOrEqualTo(Tap.min));
      await testeur.tap(find.byIcon(Icons.call_rounded));
      await testeur.pumpAndSettle();
      expect(touches, 1);
    });

    testWidgets('la version discrète reste cerclée et plus petite',
        (testeur) async {
      await testeur.pumpWidget(MaterialApp(
        theme: mboteTheme(),
        home: Scaffold(
          body: Center(
            child: FloatingChoice(
              icon: Icons.copy_rounded,
              color: MC.sable,
              label: 'Copier le numéro',
              size: 48,
              outlined: true,
              onTap: () {},
            ),
          ),
        ),
      ));
      final taille = testeur.getSize(find.byType(InkWell).first);
      expect(taille.width, 48);
      expect(taille.height, 48);
      expect(taille.width, greaterThanOrEqualTo(Tap.min));
    });
  });

  group('Couleurs centralisées', () {
    test('aucune couleur écrite en dur hors theme.dart / design.dart', () {
      final intrus = <String>[];
      for (final (chemin, source) in _sources()) {
        if (chemin.endsWith('lib/theme.dart') ||
            chemin.endsWith('lib/design.dart')) {
          continue;
        }
        final m = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)').allMatches(source);
        for (final match in m) {
          final ligne =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          intrus.add('$chemin:$ligne → ${match.group(0)}');
        }
      }
      expect(intrus, isEmpty,
          reason: 'passez par une palette (MC) ou par design.dart :\n'
              '${intrus.join('\n')}');
    });

    test('le bouton raccrocher porte une icône blanche lisible', () {
      // Convention universelle : icône blanche sur rouge foncé. Sur le rouge
      // d'erreur du thème, le blanc ne faisait que 3.18:1.
      expect(contrastRatio(Colors.white, Semantique.raccrocher),
          greaterThanOrEqualTo(4.5));
    });

    test('les couleurs de marque et sémantiques sont distinctes', () {
      final toutes = [
        Marques.mpesa,
        Marques.orangeMoney,
        Marques.airtelMoney,
        Marques.carteBancaire,
        Semantique.clip,
        Semantique.evenement,
        Semantique.appelClair,
        Semantique.lu,
        Semantique.luSurBulle,
        Semantique.raccrocher,
      ];
      expect(toutes.toSet().length, toutes.length);
    });

    test('les couleurs sémantiques restent visibles sur le fond', () {
      for (final p in kPalettes.values) {
        for (final c in [
          Semantique.clip,
          Semantique.evenement,
          Semantique.lu,
          Semantique.appelClair,
        ]) {
          expect(contrastRatio(c, p.nuit), greaterThanOrEqualTo(3.0),
              reason: '${c.toARGB32().toRadixString(16)} illisible sur '
                  '${p.nuit.toARGB32().toRadixString(16)}');
        }
      }
    });

    test('MC (couleurs actives) == palette « fleuve » par défaut', () async {
      SharedPreferences.setMockInitialValues({});
      await ThemeCtl.load();
      final ref = kPalettes['fleuve']!;
      expect(MC.nuit, ref.nuit);
      expect(MC.nuit2, ref.nuit2);
      expect(MC.nuit3, ref.nuit3);
      expect(MC.soleil, ref.accent);
      expect(MC.braise, ref.accent2);
      expect(MC.terre, ref.terre);
      expect(MC.savane, ref.savane);
      expect(MC.rouge, ref.rouge);
      expect(MC.ivoire, ref.ivoire);
      expect(MC.sable, ref.sable);
      expect(MC.kaki, ref.kaki);
      expect(MC.ligne, ref.ligne);
      expect(MC.onAccent, ref.onAccent);
      expect(MC.halo, ref.halo);
    });

    test('changer de thème applique bien toute la palette', () async {
      SharedPreferences.setMockInitialValues({});
      for (final nom in kPalettes.keys) {
        await ThemeCtl.setTheme(nom);
        final p = kPalettes[nom]!;
        expect(MC.nuit, p.nuit, reason: nom);
        expect(MC.soleil, p.accent, reason: nom);
        expect(MC.onAccent, p.onAccent, reason: nom);
        expect(ThemeCtl.theme, nom);
      }
      await ThemeCtl.setTheme('fleuve');
    });
  });

  group('Cibles tactiles et cohérence du thème', () {
    test('le bouton principal respecte la hauteur confortable', () {
      expect(Tap.confort, greaterThanOrEqualTo(Tap.min));
      expect(Tap.min, greaterThanOrEqualTo(48.0));
    });

    test('le thème Material utilise les jetons de design', () {
      final t = mboteTheme();
      expect(t.appBarTheme.titleTextStyle?.fontSize, Tx.title);
      expect(t.scaffoldBackgroundColor, MC.nuit);
      expect(t.colorScheme.primary, MC.soleil);
      expect(t.colorScheme.error, MC.rouge);
      final bord = t.inputDecorationTheme.border as OutlineInputBorder;
      expect(bord.borderRadius, BorderRadius.circular(Rd.md));
      expect(t.snackBarTheme.behavior, SnackBarBehavior.floating);
    });

    testWidgets('MboteButton est haut comme une cible confortable',
        (testeur) async {
      const cle = Key('cta');
      await testeur.pumpWidget(MaterialApp(
        theme: mboteTheme(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: MboteButton(key: cle, label: 'Continuer'),
            ),
          ),
        ),
      ));
      final taille = testeur.getSize(find.byKey(cle));
      expect(taille.height, Tap.confort);
      // Le libellé est lisible : ni la couleur du fond, ni une taille < 11.
      final texte = testeur.widget<Text>(find.text('Continuer'));
      expect(texte.style?.fontSize, greaterThanOrEqualTo(Tx.minimum));
      expect(texte.style?.color, MC.onAccent);
    });

    test('la densité reste compacte et tactile', () {
      expect(Densite.ligneListe, greaterThanOrEqualTo(Tap.min));
      expect(Densite.avatar, greaterThanOrEqualTo(40));
      expect(Densite.barre, greaterThanOrEqualTo(Tap.min));
      expect(Densite.separateur, 1);
    });

    test('les rayons et espacements restent sur la grille de 4', () {
      for (final r in [Rd.xs, Rd.sm, Rd.md, Rd.lg, Rd.avatar]) {
        expect(r % 4, 0, reason: 'rayon $r hors grille');
      }
      // Identité « Fleuve Congo » : bords nets, avatars carrés arrondis.
      expect(Rd.md, 12);
      expect(Rd.avatar, Rd.md);
      for (final e in [Sp.x1, Sp.x2, Sp.x3, Sp.x4, Sp.x5, Sp.x6, Sp.x8]) {
        expect(e % 4, 0, reason: 'espacement $e hors grille');
      }
      expect([Motion.rapide, Motion.base, Motion.lent].first.inMilliseconds,
          lessThan([Motion.rapide, Motion.base, Motion.lent].last.inMilliseconds));
    });
  });

  // ── Garde-fous issus de l'audit d'accessibilité international ────────────
  // Ces règles ne sont pas esthétiques : chacune correspond à un critère
  // WCAG 2.2 / Material Accessibility qu'un écran avait déjà enfreint.
  group('Audit international — garde-fous', () {
    test('tout bouton-icône possède un nom accessible', () {
      // WCAG 4.1.2 : un bouton sans texte doit au moins avoir un `tooltip`,
      // sinon un lecteur d'écran annonce « bouton » et rien d'autre.
      final coupables = <String>[];
      for (final (chemin, source) in _sources()) {
        for (final m in RegExp(r'IconButton\(').allMatches(source)) {
          final bloc = source.substring(m.start, math.min(source.length, m.start + 400));
          if (!bloc.contains('tooltip:')) {
            final ligne = '\n'.allMatches(source.substring(0, m.start)).length + 1;
            coupables.add('$chemin:$ligne');
          }
        }
      }
      expect(coupables, isEmpty,
          reason: 'ajoutez un `tooltip:` (nom lu par VoiceOver/TalkBack) :\n'
              '${coupables.join('\n')}');
    });

    test('toute image est soit décrite, soit explicitement décorative', () {
      // WCAG 1.1.1 : une photo qui porte du sens doit être annoncée ; un
      // avatar posé à côté du nom, lui, doit être ignoré (sinon le nom est
      // lu deux fois).
      final coupables = <String>[];
      final image = RegExp(r'Image\.(network|asset|memory|file)\(');
      for (final (chemin, source) in _sources()) {
        for (final m in image.allMatches(source)) {
          final bloc = source.substring(m.start, math.min(source.length, m.start + 400));
          if (!bloc.contains('semanticLabel') &&
              !bloc.contains('excludeFromSemantics')) {
            final ligne = '\n'.allMatches(source.substring(0, m.start)).length + 1;
            coupables.add('$chemin:$ligne');
          }
        }
      }
      expect(coupables, isEmpty,
          reason: 'ajoutez `semanticLabel:` (contenu) ou '
              '`excludeFromSemantics: true` (décor) :\n${coupables.join('\n')}');
    });

    test('les écrans ne posent pas de ListTile sur une surface opaque', () {
      // Flutter lève une assertion : le fond et l'effet d'encre du ListTile
      // sont peints par le `Material` le plus proche, donc invisibles sous un
      // `Container(decoration: …)`. Le retour au toucher disparaît.
      final coupables = <String>[];
      for (final (chemin, source) in _sources()) {
        for (final m in RegExp(r'child: ListTile\(').allMatches(source)) {
          final avant = source.substring(
              math.max(0, m.start - 700), m.start);
          // Un `Ink` posé DANS un `Material` est justement la bonne façon de
          // peindre un dégradé sous un ListTile : on l'accepte.
          if (avant.contains('decoration: BoxDecoration(') &&
              !avant.contains('child: Ink(') &&
              !avant.substring(avant.length - 260).contains('Material(')) {
            final ligne = '\n'.allMatches(source.substring(0, m.start)).length + 1;
            coupables.add('$chemin:$ligne');
          }
        }
      }
      expect(coupables, isEmpty,
          reason: 'peignez la surface avec un `Material(color:)` :\n'
              '${coupables.join('\n')}');
    });

    test('aucun écran n\'affiche un cercle de chargement muet', () {
      // WCAG 4.1.3 : un état de chargement doit être annoncé. Le jeton
      // `Chargement` (design.dart) porte le libellé et la région vivante.
      final coupables = <String>[];
      final muet = RegExp(r'Center\(child: CircularProgressIndicator');
      for (final (chemin, source) in _sources()) {
        for (final m in muet.allMatches(source)) {
          final ligne = '\n'.allMatches(source.substring(0, m.start)).length + 1;
          coupables.add('$chemin:$ligne');
        }
      }
      expect(coupables, isEmpty,
          reason: 'utilisez `const Center(child: Chargement())` :\n'
              '${coupables.join('\n')}');
    });

    test('les libellés de champ sont persistants (formulaires)', () {
      // WCAG 3.3.2 : un texte d'aide (« hint ») disparaît à la saisie ; un
      // formulaire doit garder un libellé. Les barres de recherche et de
      // saisie de message sont exclues (motif standard, contexte visible).
      const formulaires = [
        'lib/screens/login.dart',
        'lib/screens/transfer.dart',
        'lib/screens/airtime.dart',
        'lib/screens/favorites.dart',
        'lib/screens/lokota.dart',
        'lib/pin.dart',
      ];
      final coupables = <String>[];
      for (final (chemin, source) in _sources()) {
        if (!formulaires.contains(chemin)) continue;
        for (final m in RegExp(r'InputDecoration\(').allMatches(source)) {
          final bloc = source.substring(m.start, math.min(source.length, m.start + 500));
          if (bloc.contains('hintText') && !bloc.contains('labelText')) {
            final ligne = '\n'.allMatches(source.substring(0, m.start)).length + 1;
            coupables.add('$chemin:$ligne');
          }
        }
      }
      expect(coupables, isEmpty,
          reason: 'ajoutez `labelText:` à côté du `hintText:` :\n'
              '${coupables.join('\n')}');
    });
  });
}
