// lib/screens/recherche_screen.dart
// RECHERCHE UNIVERSELLE.
//
// Une barre, une intention : `#mbote` cherche un hashtag, `@ced` cherche une
// personne, le reste cherche partout. Les résultats sont groupés — personnes,
// hashtags, publications, statuts, événements — comme chez X et Instagram, avec
// le groupe le plus probable en premier.
//
// Rien n'est filtré côté application : les publications renvoyées respectent
// déjà la visibilité décidée par leur auteur.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../design.dart';
import '../models/social.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/social/texte_social.dart';
import 'hashtag_screen.dart';

class RechercheScreen extends StatefulWidget {
  /// Requête initiale (barre de recherche du fil).
  final String? requeteInitiale;

  /// Appui sur une personne : ouvrir son profil.
  final void Function(String id)? onPersonne;

  /// Appui sur une publication : l'ouvrir.
  final void Function(String id)? onPublication;

  const RechercheScreen({
    super.key,
    this.requeteInitiale,
    this.onPersonne,
    this.onPublication,
  });

  @override
  State<RechercheScreen> createState() => _RechercheScreenState();
}

class _RechercheScreenState extends State<RechercheScreen> {
  late final TextEditingController _champ =
      TextEditingController(text: widget.requeteInitiale ?? '');
  late Api _api;

  Timer? _attente;
  ResultatsRecherche? _resultats;
  bool _charge = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _api = context.read<AppState>().api;
    if (_champ.text.trim().isNotEmpty) _lancer(_champ.text);
  }

  @override
  void dispose() {
    _attente?.cancel();
    _champ.dispose();
    super.dispose();
  }

  /// Petite attente avant d'interroger : on ne lance pas une requête par
  /// touche frappée.
  void _surFrappe(String valeur) {
    _attente?.cancel();
    if (valeur.trim().isEmpty) {
      setState(() {
        _resultats = null;
        _erreur = null;
        _charge = false;
      });
      return;
    }
    _attente = Timer(const Duration(milliseconds: 300), () => _lancer(valeur));
  }

  Future<void> _lancer(String q) async {
    if (!mounted) return;
    setState(() {
      _charge = true;
      _erreur = null;
    });
    try {
      final r = await _api.rechercher(q.trim());
      if (!mounted) return;
      setState(() {
        _resultats = r;
        _charge = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _charge = false;
        _erreur = friendlyError(e);
      });
    }
  }

  void _ouvrirHashtag(String tag) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HashtagScreen(tag: tag),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final r = _resultats;
    return Scaffold(
      backgroundColor: MC.nuit,
      appBar: AppBar(
        backgroundColor: MC.nuit,
        elevation: 0,
        titleSpacing: 0,
        title: TextField(
          controller: _champ,
          autofocus: widget.requeteInitiale == null,
          onChanged: _surFrappe,
          onSubmitted: _lancer,
          textInputAction: TextInputAction.search,
          style: TextStyle(color: MC.ivoire, fontSize: Tx.body),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Rechercher : #hashtag, @personne, texte',
            hintStyle: TextStyle(color: MC.kaki, fontSize: Tx.label),
            filled: true,
            fillColor: MC.nuit3,
            prefixIcon: Icon(Icons.search_rounded, size: 19, color: MC.kaki),
            suffixIcon: _champ.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Effacer la recherche',
                    icon: Icon(Icons.close_rounded, size: 17, color: MC.kaki),
                    onPressed: () {
                      _champ.clear();
                      _surFrappe('');
                    },
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          ),
        ),
      ),
      body: _charge && r == null
          ? const Center(
              child: SizedBox(
                  width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
          : _erreur != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_erreur!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
                  ),
                )
              : r == null
                  ? const _Aide()
                  : r.vide
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off_rounded, size: 34, color: MC.kaki),
                                const SizedBox(height: 10),
                                Text('Aucun résultat pour « ${r.q} »',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
                                const SizedBox(height: 6),
                                Text(
                                  'Essaie un hashtag (#Kinshasa), un identifiant (@pseudo) ou un mot du texte.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: MC.kaki, fontSize: Tx.caption),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 30),
                          children: [
                            if (r.hashtags.isNotEmpty) ...[
                              const _Titre(texte: 'Hashtags', icone: Icons.tag_rounded),
                              for (final h in r.hashtags)
                                _LigneHashtag(hashtag: h, onTap: () => _ouvrirHashtag(h.tag)),
                            ],
                            if (r.personnes.isNotEmpty) ...[
                              const _Titre(texte: 'Personnes', icone: Icons.alternate_email_rounded),
                              for (final p in r.personnes)
                                _LignePersonne(
                                  personne: p,
                                  onTap: widget.onPersonne == null
                                      ? null
                                      : () => widget.onPersonne!(p.id),
                                ),
                            ],
                            if (r.publications.isNotEmpty) ...[
                              const _Titre(texte: 'Publications', icone: Icons.article_rounded),
                              for (final p in r.publications)
                                _LignePublication(
                                  donnees: p,
                                  onTap: widget.onPublication == null
                                      ? null
                                      : () => widget.onPublication!('${p['id']}'),
                                  onHashtag: _ouvrirHashtag,
                                ),
                            ],
                            if (r.evenements.isNotEmpty) ...[
                              const _Titre(texte: 'Événements', icone: Icons.event_rounded),
                              for (final e in r.evenements)
                                ListTile(
                                  leading: Icon(Icons.event_rounded,
                                      color: MC.soleil, size: 20),
                                  title: Text('${e['titre'] ?? 'Événement'}',
                                      style: TextStyle(
                                          color: MC.ivoire,
                                          fontSize: Tx.label,
                                          fontWeight: FontWeight.w700)),
                                  subtitle: Text('${e['lieu'] ?? ''}',
                                      style: TextStyle(
                                          color: MC.kaki, fontSize: Tx.caption)),
                                  onTap: widget.onPublication == null
                                      ? null
                                      : () => widget.onPublication!('${e['id']}'),
                                ),
                            ],
                            if (r.statuts.isNotEmpty) ...[
                              const _Titre(texte: 'Statuts', icone: Icons.auto_awesome_rounded),
                              for (final s in r.statuts)
                                ListTile(
                                  leading: Icon(Icons.circle,
                                      size: 10, color: MC.savane),
                                  title: TexteSocial(
                                    '${s['texte'] ?? ''}',
                                    fontSize: Tx.label,
                                    onHashtag: _ouvrirHashtag,
                                  ),
                                  subtitle: Text(
                                      '${(s['auteur'] as Map?)?['name'] ?? ''}',
                                      style: TextStyle(
                                          color: MC.kaki, fontSize: Tx.caption)),
                                ),
                            ],
                          ],
                        ),
    );
  }
}

class _Aide extends StatelessWidget {
  const _Aide();

  @override
  Widget build(BuildContext context) {
    const exemples = [
      '#MboteCall',
      '#Kinshasa',
      '@cedrick',
      'concert',
    ];
    return ListView(
      padding: const EdgeInsets.all(Sp.x3),
      children: [
        Text('Chercher dans MboteCall',
            style: TextStyle(
                color: MC.ivoire, fontSize: Tx.subtitle, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(
          'La barre comprend ce que tu veux : un hashtag, une personne, un mot.',
          style: TextStyle(color: MC.kaki, fontSize: Tx.label, height: 1.4),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in exemples)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: MC.nuit2,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: MC.ligne),
                ),
                child: Text(e,
                    style: TextStyle(
                        color: e.startsWith('@') ? MC.braise : MC.soleil,
                        fontSize: Tx.label,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ],
    );
  }
}

class _Titre extends StatelessWidget {
  final String texte;
  final IconData icone;
  const _Titre({required this.texte, required this.icone});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.x3, 16, Sp.x3, 6),
        child: Row(
          children: [
            Icon(icone, size: 14, color: MC.kaki),
            const SizedBox(width: 6),
            Text(texte.toUpperCase(),
                style: TextStyle(
                    color: MC.kaki,
                    fontSize: Tx.caption,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6)),
          ],
        ),
      );
}

class _LigneHashtag extends StatelessWidget {
  final Hashtag hashtag;
  final VoidCallback onTap;
  const _LigneHashtag({required this.hashtag, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: MC.soleil.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(Icons.tag_rounded, color: MC.soleil, size: 17),
        ),
        title: Text(hashtag.libelle,
            style: TextStyle(
                color: MC.ivoire, fontSize: Tx.label, fontWeight: FontWeight.w700)),
        subtitle: Text(hashtag.volume,
            style: TextStyle(color: MC.kaki, fontSize: Tx.caption)),
        trailing: Icon(Icons.chevron_right_rounded, color: MC.kaki, size: 18),
        onTap: onTap,
      );
}

class _LignePersonne extends StatelessWidget {
  final Personne personne;
  final VoidCallback? onTap;
  const _LignePersonne({required this.personne, this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: MboteAvatar(
          name: personne.name,
          size: 34,
          image: (personne.avatar != null && personne.avatar!.isNotEmpty)
              ? NetworkImage(personne.avatar!)
              : null,
        ),
        title: Text(personne.name,
            style: TextStyle(
                color: MC.ivoire, fontSize: Tx.label, fontWeight: FontWeight.w700)),
        subtitle: Text(
          [
            if (personne.handle != null) '@${personne.handle}',
            if (personne.contact) 'Contact',
            if (personne.suivi) 'Suivi',
          ].join(' · '),
          style: TextStyle(color: MC.kaki, fontSize: Tx.caption),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: MC.kaki, size: 18),
        onTap: onTap,
      );
}

class _LignePublication extends StatelessWidget {
  final Map donnees;
  final VoidCallback? onTap;
  final ValueChanged<String> onHashtag;

  const _LignePublication({
    required this.donnees,
    required this.onHashtag,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final auteur = donnees['auteur'] as Map?;
    final texte = '${donnees['texte'] ?? donnees['event_title'] ?? ''}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.x3, 8, Sp.x3, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${auteur?['name'] ?? 'Auteur'}',
                style: TextStyle(
                    color: MC.ivoire, fontSize: Tx.caption, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            TexteSocial(
              texte,
              fontSize: Tx.label,
              maxLines: 3,
              couleur: MC.sable,
              onHashtag: onHashtag,
            ),
          ],
        ),
      ),
    );
  }
}
