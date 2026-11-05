// lib/screens/hashtag_screen.dart
// PAGE D'UN HASHTAG — #MboteCall
//
// Ce qu'on y trouve, comme chez X, TikTok ou Instagram :
//   - l'en-tête : nom, nombre de publications, nombre d'abonnés ;
//   - le bouton « Suivre » / « Suivi » ;
//   - quatre onglets : Récentes · Populaires · Vidéos · Photos ;
//   - la liste des publications, chacune cliquable (hashtags, mentions, profil).
//
// Les quatre onglets sont servis par le serveur (`?tri=`), pas filtrés côté
// application : c'est ce qui permet à « Populaires » de classer sur
// l'engagement réel plutôt que sur l'ordre d'arrivée.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../design.dart';
import '../models/post.dart';
import '../models/social.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/feed/post_card.dart';

class HashtagScreen extends StatefulWidget {
  final String tag;

  /// Ouvre la publication depuis cette page (le fil fournit son propre
  /// gestionnaire, la page se contente de le prévenir).
  final void Function(Post post)? onOuvrirPublication;

  const HashtagScreen({super.key, required this.tag, this.onOuvrirPublication});

  @override
  State<HashtagScreen> createState() => _HashtagScreenState();
}

class _HashtagScreenState extends State<HashtagScreen> {
  static const _onglets = ['recentes', 'populaires', 'videos', 'photos'];
  static const _libelles = {
    'recentes': 'Récentes',
    'populaires': 'Populaires',
    'videos': 'Vidéos',
    'photos': 'Photos',
  };

  late Api _api;
  String _tri = 'recentes';
  bool _charge = true;
  String? _erreur;

  Hashtag? _hashtag;
  List<Post> _posts = const [];
  bool _suiviEnCours = false;

  @override
  void initState() {
    super.initState();
    _api = context.read<AppState>().api;
    _charger();
  }

  Future<void> _charger([String? tri]) async {
    final cible = tri ?? _tri;
    setState(() {
      _tri = cible;
      _charge = true;
      _erreur = null;
    });
    try {
      final r = await _api.pageHashtag(widget.tag, tri: cible);
      if (!mounted) return;
      setState(() {
        _hashtag = Hashtag(
          tag: '${r['tag'] ?? widget.tag}',
          publications: (r['publications'] as num?)?.toInt() ?? 0,
          abonnes: (r['abonnes'] as num?)?.toInt() ?? 0,
          croissance: (r['croissance'] as num?)?.toDouble() ?? 0,
          tendance: r['tendance'] == 1,
          suivi: r['suivi'] == 1,
        );
        _posts = ((r['posts'] as List?) ?? const [])
            .map((e) => Post.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
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

  Future<void> _basculerSuivi() async {
    final h = _hashtag;
    if (h == null || _suiviEnCours) return;
    setState(() => _suiviEnCours = true);
    HapticFeedback.selectionClick();
    try {
      final maj = h.suivi
          ? await _api.nePlusSuivreHashtag(h.tag)
          : await _api.suivreHashtag(h.tag);
      if (!mounted) return;
      setState(() {
        _hashtag = maj;
        _suiviEnCours = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _suiviEnCours = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = _hashtag;
    return Scaffold(
      backgroundColor: MC.nuit,
      appBar: AppBar(
        backgroundColor: MC.nuit,
        elevation: 0,
        title: Text(
          h?.libelle ?? '#${widget.tag}',
          style: TextStyle(
              color: MC.ivoire, fontSize: Tx.subtitle, fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        color: MC.soleil,
        onRefresh: () => _charger(_tri),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Entete(
              hashtag: h,
              suivant: _suiviEnCours,
              onSuivre: _basculerSuivi,
            )),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
                  children: [
                    for (final o in _onglets)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _Onglet(
                          label: _libelles[o]!,
                          actif: _tri == o,
                          onTap: () => _charger(o),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_charge)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_erreur != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_erreur!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
                  ),
                ),
              )
            else if (_posts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tag_rounded, size: 34, color: MC.kaki),
                        const SizedBox(height: 10),
                        Text(
                          _tri == 'recentes'
                              ? 'Aucune publication pour ce hashtag'
                              : 'Rien dans cet onglet pour l’instant',
                          style: TextStyle(color: MC.kaki, fontSize: Tx.label),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverList.separated(
                itemCount: _posts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (context, i) {
                  final p = _posts[i];
                  return PostCard(
                    post: p,
                    onHashtag: (t) {
                      if (t == widget.tag) return;
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => HashtagScreen(tag: t),
                      ));
                    },
                    onShare: () {},
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 30)),
          ],
        ),
      ),
    );
  }
}

class _Entete extends StatelessWidget {
  final Hashtag? hashtag;
  final bool suivant;
  final VoidCallback onSuivre;

  const _Entete({required this.hashtag, required this.suivant, required this.onSuivre});

  @override
  Widget build(BuildContext context) {
    final h = hashtag;
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.x3, Sp.x2, Sp.x3, Sp.x2),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MC.nuit2,
        borderRadius: BorderRadius.circular(Rd.md),
        border: Border.all(color: MC.ligne),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: MC.soleil.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.tag_rounded, color: MC.soleil, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h?.libelle ?? '',
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.subtitle,
                          fontWeight: FontWeight.w800),
                    ),
                    if (h != null && h.tendance) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.trending_up_rounded, size: 13, color: MC.savane),
                          const SizedBox(width: 4),
                          Text('Tendance',
                              style: TextStyle(
                                  color: MC.savane,
                                  fontSize: Tx.caption,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: (h?.suivi ?? false) ? MC.nuit3 : MC.soleil,
                  foregroundColor: (h?.suivi ?? false) ? MC.ivoire : MC.nuit,
                  minimumSize: const Size(96, 38),
                ),
                onPressed: suivant ? null : onSuivre,
                child: Text(
                  (h?.suivi ?? false) ? 'Suivi' : 'Suivre',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: Tx.label),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Statistique(
                valeur: '${h?.publications ?? 0}',
                libelle: (h?.publications ?? 0) <= 1 ? 'publication' : 'publications',
              ),
              const SizedBox(width: 22),
              _Statistique(
                valeur: '${h?.abonnes ?? 0}',
                libelle: (h?.abonnes ?? 0) <= 1 ? 'abonné' : 'abonnés',
              ),
              if (h != null && h.croissance.abs() >= 0.01) ...[
                const SizedBox(width: 22),
                _Statistique(
                  valeur:
                      '${h.croissance > 0 ? '+' : ''}${(h.croissance * 100).round()} %',
                  libelle: 'sur 24 h',
                  couleur: h.croissance >= 0 ? MC.savane : MC.rouge,
                ),
              ],
            ],
          ),
          if (h != null && h.suivi) ...[
            const SizedBox(height: 10),
            Text(
              'Tu suis ce hashtag : ses publications remontent dans « Pour toi ».',
              style: TextStyle(color: MC.kaki, fontSize: Tx.caption, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _Statistique extends StatelessWidget {
  final String valeur;
  final String libelle;
  final Color? couleur;

  const _Statistique({required this.valeur, required this.libelle, this.couleur});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(valeur,
              style: TextStyle(
                  color: couleur ?? MC.ivoire,
                  fontSize: Tx.body,
                  fontWeight: FontWeight.w800)),
          const SizedBox(width: 5),
          Text(libelle, style: TextStyle(color: MC.kaki, fontSize: Tx.caption)),
        ],
      );
}

class _Onglet extends StatelessWidget {
  final String label;
  final bool actif;
  final VoidCallback onTap;

  const _Onglet({required this.label, required this.actif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: actif,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: actif ? MC.soleil.withValues(alpha: .16) : MC.nuit2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: actif ? MC.soleil.withValues(alpha: .5) : MC.ligne),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: actif ? MC.soleil : MC.kaki,
              fontSize: Tx.label,
              fontWeight: actif ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
