// lib/screens/engagement_screen.dart
// MES STATISTIQUES — ce que mes publications ont produit.
//
// Une seule requête (`GET /feed/analytique`) : j'aime reçus, commentaires,
// partages, taux d'engagement et publications les plus fortes. Pas de graphe
// animé, pas de bibliothèque de courbes : quatre chiffres lisibles et un
// classement, c'est ce dont un créateur se sert réellement.

import 'package:flutter/material.dart';

import '../api.dart';
import '../design.dart';
import '../theme.dart';

class EngagementScreen extends StatefulWidget {
  final Api api;
  const EngagementScreen({super.key, required this.api});

  @override
  State<EngagementScreen> createState() => _EngagementScreenState();
}

class _EngagementScreenState extends State<EngagementScreen> {
  bool _charge = true;
  String? _erreur;
  Map<String, dynamic> _e = const {};
  List<Map> _top = const [];
  int _mentions = 0;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _charge = true;
      _erreur = null;
    });
    try {
      final r = await widget.api.analytiqueEngagement();
      if (!mounted) return;
      final e = Map<String, dynamic>.from((r['engagement'] as Map?) ?? const {});
      setState(() {
        _e = e;
        _top = ((e['top'] as List?) ?? const [])
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList();
        _mentions = ((r['mentions'] as Map?)?['recues'] as num?)?.toInt() ?? 0;
        _charge = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _charge = false;
        _erreur = friendlyError(err);
      });
    }
  }

  int _n(String cle) => (_e[cle] as num?)?.toInt() ?? 0;
  double _d(String cle) => (_e[cle] as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MC.nuit,
      appBar: AppBar(
        backgroundColor: MC.nuit,
        elevation: 0,
        title: Text('Mes statistiques',
            style: TextStyle(
                color: MC.ivoire,
                fontSize: Tx.subtitle,
                fontWeight: FontWeight.w800)),
      ),
      body: _charge
          ? Center(
              child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: MC.soleil, strokeWidth: 2)))
          : _erreur != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_erreur!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
                  ),
                )
              : RefreshIndicator(
                  color: MC.soleil,
                  onRefresh: _charger,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x4, Sp.x4, 32),
                    children: [
                      Wrap(
                        spacing: Sp.x3,
                        runSpacing: Sp.x3,
                        children: [
                          _Carte(
                              valeur: '${_n('likes')}',
                              libelle: 'J’aime reçus',
                              icone: Icons.favorite_rounded,
                              couleur: MC.braise),
                          _Carte(
                              valeur: '${_n('commentaires')}',
                              libelle: 'Commentaires',
                              icone: Icons.chat_bubble_rounded,
                              couleur: MC.soleil),
                          _Carte(
                              valeur: '${_n('partages')}',
                              libelle: 'Partages',
                              icone: Icons.repeat_rounded,
                              couleur: MC.savane),
                          _Carte(
                              valeur: '$_mentions',
                              libelle: 'Mentions',
                              icone: Icons.alternate_email_rounded,
                              couleur: MC.soleil),
                        ],
                      ),
                      const SizedBox(height: Sp.x5),
                      Container(
                        padding: const EdgeInsets.all(Sp.x4),
                        decoration: BoxDecoration(
                          color: MC.nuit2,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: MC.ligne),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Taux d’engagement',
                                style: TextStyle(
                                    color: MC.ivoire,
                                    fontSize: Tx.bodyLg,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            Text(
                              _e['taux_base'] == 'vues'
                                  ? '${_d('taux').toStringAsFixed(1)} % des vues'
                                  : '${_n('interactions')} interactions',
                              style: TextStyle(
                                  color: MC.soleil,
                                  fontSize: Tx.title,
                                  fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_n('publications')} publication(s) · '
                              '${_n('vues')} vue(s) · '
                              '${_d('likes_par_publication').toStringAsFixed(1)}'
                              ' j’aime par publication',
                              style: TextStyle(
                                  color: MC.kaki, fontSize: Tx.caption),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Sp.x5),
                      Text('Publications les plus populaires',
                          style: TextStyle(
                              color: MC.ivoire,
                              fontSize: Tx.bodyLg,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: Sp.x2),
                      if (_top.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                              'Publie pour voir apparaître tes statistiques ici.',
                              style: TextStyle(
                                  color: MC.kaki, fontSize: Tx.label)),
                        ),
                      for (var i = 0; i < _top.length; i++)
                        _LigneTop(position: i + 1, post: _top[i]),
                    ],
                  ),
                ),
    );
  }
}

class _Carte extends StatelessWidget {
  final String valeur;
  final String libelle;
  final IconData icone;
  final Color couleur;

  const _Carte({
    required this.valeur,
    required this.libelle,
    required this.icone,
    required this.couleur,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: 150,
        padding: const EdgeInsets.all(Sp.x4),
        decoration: BoxDecoration(
          color: MC.nuit2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MC.ligne),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 16, color: couleur),
            const SizedBox(height: 8),
            Text(valeur,
                style: TextStyle(
                    color: MC.ivoire,
                    fontSize: Tx.title,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(libelle,
                style: TextStyle(color: MC.kaki, fontSize: Tx.caption)),
          ],
        ),
      );
}

class _LigneTop extends StatelessWidget {
  final int position;
  final Map post;

  const _LigneTop({required this.position, required this.post});

  @override
  Widget build(BuildContext context) {
    final texte = '${post['texte'] ?? ''}'.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.x2),
      padding: const EdgeInsets.all(Sp.x3),
      decoration: BoxDecoration(
        color: MC.nuit2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$position',
              style: TextStyle(
                  color: MC.soleil,
                  fontSize: Tx.bodyLg,
                  fontWeight: FontWeight.w900)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  texte.isEmpty ? 'Publication sans texte' : texte,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: MC.ivoire, fontSize: Tx.label, height: 1.35),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(post['likes'] as num?)?.toInt() ?? 0} j’aime · '
                  '${(post['commentaires'] as num?)?.toInt() ?? 0} commentaires · '
                  '${(post['partages'] as num?)?.toInt() ?? 0} partages',
                  style: TextStyle(color: MC.kaki, fontSize: Tx.caption),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
