import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design.dart';

///Une palette = un thème complet de MboteCall.
class Palette {
  final Color nuit, nuit2, nuit3; // fonds (écran, carte, carte claire)
  final Color accent, accent2; // couleur signature + dégradé
  final Color terre, savane, rouge; // sémantiques
  final Color ivoire, sable, kaki; // textes (principal, secondaire, discret)
  final Color ligne, onAccent, halo; // bordures, texte sur accent, lueur
  const Palette({
    required this.nuit,
    required this.nuit2,
    required this.nuit3,
    required this.accent,
    required this.accent2,
    required this.terre,
    required this.savane,
    required this.rouge,
    required this.ivoire,
    required this.sable,
    required this.kaki,
    required this.ligne,
    required this.onAccent,
    required this.halo,
  });
}

/// Les thèmes de MboteCall. « Fleuve Congo » est l'identité par défaut.
const Map<String, Palette> kPalettes = {
  //L'identité de référence — « Fleuve Congo »
  //    Bleu-vert profond du fleuve, sable des berges, corail des pirogues.
  //    Contraste vérifié : 21 paires texte/fond conformes WCAG AA
  //    (voir `test/design_test.dart`).
  'fleuve': Palette(
    nuit: Color(0xFF0B1518),
    nuit2: Color(0xFF132124),
    nuit3: Color(0xFF1C2E31),
    accent: Color(0xFFE9C27C),
    accent2: Color(0xFFE2664A),
    terre: Color(0xFF2E8077),
    savane: Color(0xFF4FB477),
    rouge: Color(0xFFEE6459),
    ivoire: Color(0xFFF2F7F6),
    sable: Color(0xFFC4D4D2),
    kaki: Color(0xFF93A8A6),
    ligne: Color(0xFF274043),
    onAccent: Color(0xFF10201F),
    halo: Color(0xFF1B3034),
  ),
  //L'identité originale « Soleil de Kin »
  'kin': Palette(
    nuit: Color(0xFF14100E),
    nuit2: Color(0xFF201915),
    nuit3: Color(0xFF2C231D),
    accent: Color(0xFFF5A623),
    accent2: Color(0xFFE85D2A),
    terre: Color(0xFFB4532A),
    savane: Color(0xFF2EA06B),
    rouge: Color(0xFFD94C3E),
    ivoire: Color(0xFFFBF3E4),
    sable: Color(0xFFE8D5B5),
    kaki: Color(0xFF9C8A70),
    ligne: Color(0xFF39302A),
    onAccent: Color(0xFF241204),
    halo: Color(0xFF33210F),
  ),
  //Émeraude — inspiré de WhatsApp
  'emeraude': Palette(
    nuit: Color(0xFF0B141A),
    nuit2: Color(0xFF111B21),
    nuit3: Color(0xFF202C33),
    accent: Color(0xFF25D366),
    accent2: Color(0xFF129C8E),
    terre: Color(0xFF078278),
    savane: Color(0xFF25D366),
    rouge: Color(0xFFEF5350),
    ivoire: Color(0xFFE9EDEF),
    sable: Color(0xFFC3CCD2),
    kaki: Color(0xFF8696A0),
    ligne: Color(0xFF233138),
    onAccent: Color(0xFF062B1A),
    halo: Color(0xFF13272F),
  ),
  //Océan — inspiré de LinkedIn
  'ocean': Palette(
    nuit: Color(0xFF15181B),
    nuit2: Color(0xFF1E2226),
    nuit3: Color(0xFF2C3237),
    accent: Color(0xFF70B5F9),
    accent2: Color(0xFF0B80F5),
    terre: Color(0xFF0A79E8),
    savane: Color(0xFF57A863),
    rouge: Color(0xFFE06055),
    ivoire: Color(0xFFF3F6F8),
    sable: Color(0xFFC9D1D9),
    kaki: Color(0xFF9AA4AE),
    ligne: Color(0xFF2E3338),
    onAccent: Color(0xFF0D1A26),
    halo: Color(0xFF1C2630),
  ),
  //Bleu Nuit — inspiré de Facebook
  //`onAccent` est volontairement SOMBRE : l'accent bleu clair
  //    (#318AFF) n'offre que ~5,5:1 avec du blanc, qui échoue en AA sur
  //    les petits textes. Un texte presque noir y monte à ~7:1.
  'bleu': Palette(
    nuit: Color(0xFF18191A),
    nuit2: Color(0xFF242526),
    nuit3: Color(0xFF3A3B3C),
    accent: Color(0xFF318AFF),
    accent2: Color(0xFF1C79F2),
    terre: Color(0xFF3083F2),
    savane: Color(0xFF45BD62),
    rouge: Color(0xFFF14161),
    ivoire: Color(0xFFE4E6EB),
    sable: Color(0xFFB0B3B8),
    kaki: Color(0xFFA2A5A9),
    ligne: Color(0xFF3A3B3C),
    onAccent: Color(0xFF06121F),
    halo: Color(0xFF1F2533),
  ),
};

/// Couleurs actives de l'app — mises à jour quand on change de thème.
/// (les noms historiques « soleil/braise » = accent/accent2 du thème actif)
class MC {
  static Color nuit = const Color(0xFF0B1518);
  static Color nuit2 = const Color(0xFF132124);
  static Color nuit3 = const Color(0xFF1C2E31);
  static Color soleil = const Color(0xFFE9C27C);
  static Color braise = const Color(0xFFE2664A);
  static Color terre = const Color(0xFF2E8077);
  static Color savane = const Color(0xFF4FB477);
  static Color rouge = const Color(0xFFEE6459);
  static Color ivoire = const Color(0xFFF2F7F6);
  static Color sable = const Color(0xFFC4D4D2);
  static Color kaki = const Color(0xFF93A8A6);
  static Color ligne = const Color(0xFF274043);
  static Color onAccent = const Color(0xFF10201F);
  static Color halo = const Color(0xFF1B3034);

  static LinearGradient get degrade => LinearGradient(
        colors: [soleil, braise],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static void apply(Palette p) {
    nuit = p.nuit;
    nuit2 = p.nuit2;
    nuit3 = p.nuit3;
    soleil = p.accent;
    braise = p.accent2;
    terre = p.terre;
    savane = p.savane;
    rouge = p.rouge;
    ivoire = p.ivoire;
    sable = p.sable;
    kaki = p.kaki;
    ligne = p.ligne;
    onAccent = p.onAccent;
    halo = p.halo;
  }
}

///Thème + police choisis par l'utilisateur (persistés).
class ThemeCtl {
  static String theme = 'fleuve';
  static String font = 'standard';

  ///Taille du texte de TOUTE l'application (1.0 = taille normale).
  /// L'utilisateur peut l'augmenter sans passer par les réglages du système :
  /// c'est un vrai réglage, enregistré et appliqué au démarrage.
  static double textScale = 1.0;
  static const double echelleMin = 0.85;
  static const double echelleMax = 1.5;

  static final ValueNotifier<int> version = ValueNotifier(0);

  static const themes = {
    'fleuve': 'Fleuve Congo',
    'kin': 'Soleil de Kin',
    'emeraude': 'Émeraude',
    'ocean': 'Océan',
    'bleu': 'Bleu Nuit',
  };
  static const fonts = {
    'standard': 'Standard',
    'serif': 'Serif',
    'condensed': 'Condensée',
    'mono': 'Mono',
  };

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    theme = p.getString('theme') ?? 'fleuve';
    font = p.getString('font') ?? 'standard';
    textScale = (p.getDouble('text_scale') ?? 1.0).clamp(echelleMin, echelleMax);
    MC.apply(kPalettes[theme] ?? kPalettes['fleuve']!);
    version.value++;
  }

  static Future<void> setTheme(String t) async {
    theme = t;
    MC.apply(kPalettes[t] ?? kPalettes['fleuve']!);
    (await SharedPreferences.getInstance()).setString('theme', t);
    version.value++;
  }

  static Future<void> setFont(String f) async {
    font = f;
    (await SharedPreferences.getInstance()).setString('font', f);
    version.value++;
  }

  /// Change la taille du texte (bornée) ; renvoie la valeur réellement retenue.
  static Future<double> setTextScale(double v) async {
    textScale = v.clamp(echelleMin, echelleMax);
    (await SharedPreferences.getInstance()).setDouble('text_scale', textScale);
    version.value++;
    return textScale;
  }

  /// Remet la taille du texte à la normale.
  static Future<double> resetTextScale() => setTextScale(1.0);
}

ThemeData mboteTheme() {
  final fam = switch (ThemeCtl.font) {
    'serif' => 'serif',
    'condensed' => 'sans-serif-condensed',
    'mono' => 'monospace',
    _ => null,
  };
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: fam,
    scaffoldBackgroundColor: MC.nuit,
    colorScheme: ColorScheme.dark(
      primary: MC.soleil,
      secondary: MC.braise,
      surface: MC.nuit2,
      error: MC.rouge,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: MC.nuit,
      foregroundColor: MC.ivoire,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          color: MC.ivoire,
          fontSize: Tx.title,
          fontWeight: FontWeight.w800,
          fontFamily: fam),
    ),
    textTheme: TextTheme(
      bodyMedium: TextStyle(color: MC.ivoire),
      bodySmall: TextStyle(color: MC.sable),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MC.nuit3,
      hintStyle: TextStyle(color: MC.kaki),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Rd.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Rd.md),
        borderSide: BorderSide(color: MC.soleil, width: 1.6),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: MC.nuit3,
      contentTextStyle: TextStyle(color: MC.ivoire),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.md)),
    ),
 // Le reste de l'application suit la même identité « Fleuve Congo » :
    //    bords nets, surfaces franches, filets fins, aucune ombre lourde.
    dividerTheme: DividerThemeData(
      color: MC.ligne,
      thickness: Densite.separateur,
      space: Densite.separateur,
    ),
    cardTheme: CardThemeData(
      color: MC.nuit2,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rd.lg),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: MC.nuit2,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rd.lg),
        side: BorderSide(color: MC.ligne),
      ),
      titleTextStyle: TextStyle(
          color: MC.ivoire,
          fontSize: Tx.subtitle,
          fontWeight: FontWeight.w800,
          fontFamily: fam),
      contentTextStyle: TextStyle(color: MC.sable, fontSize: Tx.body),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: MC.nuit2,
      modalBackgroundColor: MC.nuit2,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Rd.lg)),
        side: BorderSide(color: MC.ligne),
      ),
      showDragHandle: true,
      dragHandleColor: MC.ligne,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MC.soleil,
        foregroundColor: MC.onAccent,
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(
            fontSize: Tx.bodyLg, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rd.md)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: MC.soleil,
        textStyle: const TextStyle(
            fontSize: Tx.body, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MC.soleil,
        minimumSize: const Size(0, 48),
        side: BorderSide(color: MC.soleil.withValues(alpha: .55)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rd.md)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: MC.sable),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: MC.nuit3,
      side: BorderSide(color: MC.ligne),
      labelStyle: TextStyle(color: MC.sable, fontSize: Tx.label),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rd.pill)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: MC.kaki,
      textColor: MC.ivoire,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rd.md)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: MC.soleil,
      linearTrackColor: MC.nuit3,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected) ? MC.onAccent : MC.kaki),
      trackColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected) ? MC.soleil : MC.nuit3),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: MC.nuit3,
        borderRadius: BorderRadius.circular(Rd.sm),
        border: Border.all(color: MC.ligne),
      ),
      textStyle: TextStyle(color: MC.ivoire, fontSize: Tx.label),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: MC.nuit2,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rd.md),
        side: BorderSide(color: MC.ligne),
      ),
      textStyle: TextStyle(color: MC.ivoire, fontSize: Tx.body),
    ),
  );
}

/// Formate des centimes en dollars : 1250 -> "12,50 $"
String fmtMoney(int cents) =>
    '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} \$';

/// Formate des secondes en "04:37"
String fmtDur(int sec) =>
    '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';

/// Bouton principal dégradé signature
class MboteButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  const MboteButton(
      {super.key, required this.label, this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: Tap.confort,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MC.soleil,
          borderRadius: BorderRadius.circular(Rd.pill),
        ),
        child: loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: MC.onAccent))
            : Text(label,
                style: TextStyle(
                    color: MC.onAccent,
                    fontSize: Tx.subtitle,
                    fontWeight: FontWeight.w800)),
      ),
    );
  }
}

///Applique la taille de texte choisie dans Réglages › Apparence.
///
/// Le réglage de l'application **multiplie** celui du système (jamais il ne
/// l'ignore : un utilisateur qui a agrandi le texte de son téléphone pour
/// raisons de vue garde son confort) et le résultat est borné pour éviter les
/// mises en page impossibles.
class EchelleTexte extends StatelessWidget {
  final Widget child;
  const EchelleTexte({super.key, required this.child});

  /// Facteur effectivement appliqué (utile aux tests et au diagnostic).
  static double facteur(BuildContext context) {
    final systeme = MediaQuery.textScalerOf(context).scale(1);
    return (systeme * ThemeCtl.textScale).clamp(0.85, 2.0);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(facteur(context))),
      child: child,
    );
  }
}
