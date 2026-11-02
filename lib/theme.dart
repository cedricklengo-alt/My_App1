import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 🎨 Une palette = un thème complet de MboteCall.
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

/// Les 4 thèmes de MboteCall.
const Map<String, Palette> kPalettes = {
  // 🌅 L'identité originale « Soleil de Kin »
  'kin': Palette(
    nuit: Color(0xFF14100E),
    nuit2: Color(0xFF201915),
    nuit3: Color(0xFF2C231D),
    accent: Color(0xFFF5A623),
    accent2: Color(0xFFE85D2A),
    terre: Color(0xFFB4532A),
    savane: Color(0xFF2EA06B),
    rouge: Color(0xFFD94436),
    ivoire: Color(0xFFFBF3E4),
    sable: Color(0xFFE8D5B5),
    kaki: Color(0xFF9C8A70),
    ligne: Color(0xFF39302A),
    onAccent: Color(0xFF241204),
    halo: Color(0xFF33210F),
  ),
  // 💬 Émeraude — inspiré de WhatsApp
  'emeraude': Palette(
    nuit: Color(0xFF0B141A),
    nuit2: Color(0xFF111B21),
    nuit3: Color(0xFF202C33),
    accent: Color(0xFF25D366),
    accent2: Color(0xFF128C7E),
    terre: Color(0xFF075E54),
    savane: Color(0xFF25D366),
    rouge: Color(0xFFEF5350),
    ivoire: Color(0xFFE9EDEF),
    sable: Color(0xFFC3CCD2),
    kaki: Color(0xFF8696A0),
    ligne: Color(0xFF233138),
    onAccent: Color(0xFF062B1A),
    halo: Color(0xFF13272F),
  ),
  // 💼 Océan — inspiré de LinkedIn
  'ocean': Palette(
    nuit: Color(0xFF15181B),
    nuit2: Color(0xFF1E2226),
    nuit3: Color(0xFF2C3237),
    accent: Color(0xFF70B5F9),
    accent2: Color(0xFF0A66C2),
    terre: Color(0xFF0A66C2),
    savane: Color(0xFF57A863),
    rouge: Color(0xFFE06055),
    ivoire: Color(0xFFF3F6F8),
    sable: Color(0xFFC9D1D9),
    kaki: Color(0xFF9AA4AE),
    ligne: Color(0xFF2E3338),
    onAccent: Color(0xFF0D1A26),
    halo: Color(0xFF1C2630),
  ),
  // 👥 Bleu Nuit — inspiré de Facebook
  'bleu': Palette(
    nuit: Color(0xFF18191A),
    nuit2: Color(0xFF242526),
    nuit3: Color(0xFF3A3B3C),
    accent: Color(0xFF2D88FF),
    accent2: Color(0xFF1877F2),
    terre: Color(0xFF1877F2),
    savane: Color(0xFF45BD62),
    rouge: Color(0xFFF02849),
    ivoire: Color(0xFFE4E6EB),
    sable: Color(0xFFB0B3B8),
    kaki: Color(0xFF8A8D91),
    ligne: Color(0xFF3A3B3C),
    onAccent: Color(0xFFFFFFFF),
    halo: Color(0xFF1F2533),
  ),
};

/// Couleurs actives de l'app — mises à jour quand on change de thème.
/// (les noms historiques « soleil/braise » = accent/accent2 du thème actif)
class MC {
  static Color nuit = const Color(0xFF14100E);
  static Color nuit2 = const Color(0xFF201915);
  static Color nuit3 = const Color(0xFF2C231D);
  static Color soleil = const Color(0xFFF5A623);
  static Color braise = const Color(0xFFE85D2A);
  static Color terre = const Color(0xFFB4532A);
  static Color savane = const Color(0xFF2EA06B);
  static Color rouge = const Color(0xFFD94436);
  static Color ivoire = const Color(0xFFFBF3E4);
  static Color sable = const Color(0xFFE8D5B5);
  static Color kaki = const Color(0xFF9C8A70);
  static Color ligne = const Color(0xFF39302A);
  static Color onAccent = const Color(0xFF241204);
  static Color halo = const Color(0xFF33210F);

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

/// 🎛️ Thème + police choisis par l'utilisateur (persistés).
class ThemeCtl {
  static String theme = 'kin';
  static String font = 'standard';
  static final ValueNotifier<int> version = ValueNotifier(0);

  static const themes = {
    'kin': 'Soleil de Kin 🌅',
    'emeraude': 'Émeraude 💬',
    'ocean': 'Océan 💼',
    'bleu': 'Bleu Nuit 👥',
  };
  static const fonts = {
    'standard': 'Standard',
    'serif': 'Serif',
    'condensed': 'Condensée',
    'mono': 'Mono',
  };

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    theme = p.getString('theme') ?? 'kin';
    font = p.getString('font') ?? 'standard';
    MC.apply(kPalettes[theme] ?? kPalettes['kin']!);
    version.value++;
  }

  static Future<void> setTheme(String t) async {
    theme = t;
    MC.apply(kPalettes[t] ?? kPalettes['kin']!);
    (await SharedPreferences.getInstance()).setString('theme', t);
    version.value++;
  }

  static Future<void> setFont(String f) async {
    font = f;
    (await SharedPreferences.getInstance()).setString('font', f);
    version.value++;
  }
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
          fontSize: 21,
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
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: MC.soleil, width: 1.6),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: MC.nuit3,
      contentTextStyle: TextStyle(color: MC.ivoire),
      behavior: SnackBarBehavior.floating,
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
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: MC.degrade,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: MC.braise.withValues(alpha: .35),
                blurRadius: 20,
                offset: const Offset(0, 8)),
          ],
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
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
      ),
    );
  }
}
