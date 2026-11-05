import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mbote/l10n.dart';

/// 🔍 Tests de CONTRAT — ils lisent le code source et vérifient que l'app et
/// le serveur parlent bien le même langage :
///
///   1. aucune clé de traduction utilisée dans l'interface ne manque ;
///   2. les trois langues (fr / ln / sw) ont exactement les mêmes clés ;
///   3. chaque route HTTP appelée par `Api` existe réellement côté backend.
///
/// Une régression ici se voit immédiatement : un libellé brut à l'écran, ou un
/// écran qui reçoit « Not Found » sans explication.
void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  String readLib() => libFiles.map((f) => f.readAsStringSync()).join('\n');

  group('Traductions', () {
    test('toutes les clés utilisées dans le code existent en fr', () {
      final used = RegExp(r"""L10n\.t\(\s*'([a-z0-9_]+)'""")
          .allMatches(readLib())
          .map((m) => m.group(1)!)
          .toSet();
      expect(used, isNotEmpty, reason: 'aucun L10n.t trouvé — test invalide');
      final missing = used.where((k) => L10n.raw('fr', k) == null).toList()
        ..sort();
      expect(missing, isEmpty,
          reason: 'Clés absentes du dictionnaire français : $missing');
    });

    test('les trois langues ont exactement les mêmes clés', () {
      final fr = L10n.keys('fr');
      final ln = L10n.keys('ln');
      final sw = L10n.keys('sw');
      expect(fr.length, greaterThan(100), reason: 'dictionnaire trop petit');
      expect(ln.difference(fr), isEmpty, reason: 'clés en lingala hors fr');
      expect(sw.difference(fr), isEmpty, reason: 'clés en swahili hors fr');
      expect(fr.difference(ln), isEmpty, reason: 'clés fr non traduites en ln');
      expect(fr.difference(sw), isEmpty, reason: 'clés fr non traduites en sw');
    });

    test('aucune traduction vide', () {
      for (final lang in ['fr', 'ln', 'sw']) {
        final vides = L10n.keys(lang)
            .where((k) => (L10n.raw(lang, k) ?? '').trim().isEmpty)
            .toList();
        expect(vides, isEmpty, reason: 'Traductions vides en $lang : $vides');
      }
    });

    test('lingala : la négation « te » ferme la phrase', () {
      // Règle de grammaire lingala (signalée par le relecteur natif) :
      //   « je ne suis pas à la maison » = « nazali na ndaku te »,
      //   et non « nazali te na ndaku ».
      // Le complément vient AVANT « te », qui termine l'énoncé. On refuse donc
      // « te na … » et « te ya … », qui retournent la négation.
      final fautives = <String>[];
      final motif = RegExp(r'\bte\s+(na|ya|moko)\b', caseSensitive: false);
      for (final cle in L10n.keys('ln')) {
        final v = L10n.raw('ln', cle) ?? '';
        if (motif.hasMatch(v)) fautives.add('$cle : $v');
      }
      expect(fautives, isEmpty,
          reason: '« te » doit fermer la phrase (… na ndaku te) :\n'
              '${fautives.join('\n')}');
    });

    test('l’onglet « Discussion » est bien nommé dans les trois langues', () {
      expect(L10n.t2('fr', 'nav_messages'), 'Discussion');
      expect(L10n.t2('ln', 'nav_messages'), 'Masolo');
      expect(L10n.t2('sw', 'nav_messages'), 'Majadiliano');
      // Deux onglets ne doivent jamais porter le même libellé.
      for (final lang in ['fr', 'ln', 'sw']) {
        final nav = ['nav_home', 'nav_calls', 'nav_messages', 'nav_more']
            .map((k) => L10n.t2(lang, k))
            .toList();
        expect(nav.toSet().length, nav.length,
            reason: 'Libellés d’onglets en doublon ($lang) : $nav');
      }
    });

    test('une clé inconnue est détectée (pas de repli silencieux)', () {
      expect(L10n.raw('fr', 'cle_qui_nexiste_pas'), isNull);
    });
  });

  group('Contrat API ↔ backend', () {
    test('chaque route appelée par l’app existe côté backend', () {
      final backendDir = Directory('../mbote-backend/src/modules');
      final serverJs = File('../mbote-backend/src/server.js');
      if (!backendDir.existsSync() || !serverJs.existsSync()) {
        markTestSkipped('backend introuvable — contrat non vérifiable ici');
        return;
      }

      final prefixes = _prefixesByModule(serverJs.readAsStringSync());

      final dispo = <String>{};
      for (final f in backendDir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.routes.js')) continue;
        final rel = f.path.split('/').last.replaceAll('.js', '');
        final prefs = prefixes[rel] ??
            ['/api/${rel.replaceAll('.routes', '')}'];
        final src = f.readAsStringSync();
        for (final m in RegExp(r"""(\w+)\.(get|post|put|delete)\(\s*'([^']*)'""")
            .allMatches(src)) {
          final meth = m.group(2)!.toUpperCase();
          final path = m.group(3)!;
          for (final p in prefs) {
            dispo.add('$meth ${_norm(p + path)}');
          }
        }
      }
      expect(dispo.length, greaterThan(60),
          reason: 'routes backend mal extraites — test invalide');

      final appels = _appelsApi(File('lib/api.dart').readAsStringSync());
      expect(appels.length, greaterThan(30),
          reason: 'appels de l’app mal extraits — test invalide');

      final manquants = <String>[];
      for (final a in appels) {
        final space = a.indexOf(' ');
        final meth = a.substring(0, space);
        final chemin = _norm('/api${a.substring(space + 1)}');
        final trouve = dispo.any((d) {
          final i = d.indexOf(' ');
          return d.substring(0, i) == meth &&
              _samePath(d.substring(i + 1), chemin);
        });
        if (!trouve) manquants.add(a);
      }
      expect(manquants, isEmpty,
          reason: 'Routes appelées par l’app mais absentes du backend : $manquants');
    });

    test('les routes du backend utilisent des méthodes HTTP valides', () {
      final src = File('../mbote-backend/src/server.js');
      if (!src.existsSync()) {
        markTestSkipped('backend introuvable');
        return;
      }
      // Chaque module monté doit répondre à au moins une route : un routeur
      // vide signalerait un fichier cassé.
      final modules = Directory('../mbote-backend/src/modules')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.routes.js'));
      final vides = modules
          .where((f) =>
              !RegExp(r"""\w+\.(get|post|put|delete)\(""")
                  .hasMatch(f.readAsStringSync()))
          .map((f) => f.path.split('/').last)
          .toList();
      expect(vides, isEmpty, reason: 'Modules sans aucune route : $vides');
    });
  });
}

/// `(méthode chemin)` appelés par `Api`, chemins normalisés.
List<String> _appelsApi(String src) {
  final out = <String>{};
  for (final m in RegExp(
          r"""_send<[^>]*>\(\s*'(GET|POST|PUT|DELETE)'\s*,\s*'([^']+)'""")
      .allMatches(src)) {
    out.add('${m.group(1)} ${m.group(2)}');
  }
  for (final m in RegExp(
          r"""_send\(\s*'(GET|POST|PUT|DELETE)'\s*,\s*'([^']+)'""")
      .allMatches(src)) {
    out.add('${m.group(1)} ${m.group(2)}');
  }
  // Corrige les appels dont l'URL est répartie sur plusieurs lignes
  for (final m in RegExp(r"""_send\(\s*'(GET|POST|PUT|DELETE)'\s*,\s*""")
      .allMatches(src)) {
    final reste = src.substring(m.end);
    final quote = reste.indexOf("'");
    if (quote < 0 || quote > 4) continue;
    final fin = reste.indexOf("'", quote + 1);
    if (fin < 0) continue;
    out.add('${m.group(1)} ${reste.substring(quote + 1, fin)}');
  }
  return out.toList();
}

/// Fichier de module → préfixes d'URL où il est monté.
Map<String, List<String>> _prefixesByModule(String serverSrc) {
  final map = <String, List<String>>{};
  void add(String file, String prefix) {
    final key = file.split('/').last.replaceAll('.js', '');
    map.putIfAbsent(key, () => <String>[]);
    if (!map[key]!.contains(prefix)) map[key]!.add(prefix);
  }

  // Déclarations : const x = require('./modules/x.routes');
  //               const { router: a, lokota: b } = require('./modules/y.routes');
  final varToFile = <String, String>{};
  for (final line in serverSrc.split('\n')) {
    final req = RegExp(r"""require\('([^']*routes[^']*)'\)""").firstMatch(line);
    if (req == null) continue;
    final file = req.group(1)!;
    if (line.contains('{')) {
      final inner = line.substring(line.indexOf('{') + 1, line.indexOf('}'));
      for (final part in inner.split(',')) {
        final nom = part.split(':').last.trim();
        if (nom.isNotEmpty) varToFile[nom] = file;
      }
    } else {
      final v = RegExp(r'const\s+(\w+)').firstMatch(line);
      if (v != null) varToFile[v.group(1)!] = file;
    }
  }

  // Montages : app.use('/api/x', ...)
  for (final line in serverSrc.split('\n')) {
    final use = RegExp(r"""app\.use\(\s*'([^']+)'\s*,\s*(.+)\)""").firstMatch(line);
    if (use == null) continue;
    final prefix = use.group(1)!;
    final arg = use.group(2)!;
    final req = RegExp(r"""require\('([^']*routes[^']*)'\)""").firstMatch(arg);
    if (req != null) {
      add(req.group(1)!, prefix);
      continue;
    }
    final nom = RegExp(r'^([A-Za-z_]\w*)').firstMatch(arg.trim());
    if (nom != null && varToFile.containsKey(nom.group(1)!)) {
      add(varToFile[nom.group(1)!]!, prefix);
    }
  }
  return map;
}

/// Normalise : interpolation Dart et query string → segment dynamique.
String _norm(String p) {
  var s = p.split('?').first;
  s = s.replaceAll(RegExp(r'\$\{[^}]+\}'), ':param');
  s = s.replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), ':param');
  return s;
}

/// Deux chemins désignent-ils la même route ? (`:param` = un segment libre)
bool _samePath(String a, String b) {
  final sa = a.split('/').where((s) => s.isNotEmpty).toList();
  final sb = b.split('/').where((s) => s.isNotEmpty).toList();
  if (sa.length != sb.length) return false;
  for (var i = 0; i < sa.length; i++) {
    final x = sa[i], y = sb[i];
    if (x == y) continue;
    if (x.startsWith(':') || y.startsWith(':')) continue;
    return false;
  }
  return true;
}
