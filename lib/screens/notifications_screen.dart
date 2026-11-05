// lib/screens/notifications_screen.dart
// CENTRE DE NOTIFICATIONS — j'aime, commentaires, réponses, mentions, partages.
//
// Trois sections, comme demandé : Aujourd'hui, Cette semaine, Plus anciennes.
// Chaque ligne montre les visages concernés (jusqu'à trois, empilés), l'action,
// l'extrait du contenu et le temps écoulé. Un appui marque la ligne lue, ouvre
// la publication et se positionne sur le commentaire quand il y en a un.
//
// Le rafraîchissement ne dépend pas de cet écran : `NotifsCtl` interroge le
// serveur toutes les 25 s, met en pause en arrière-plan, et alimente aussi la
// pastille de l'en-tête du fil. Ouvrir cet écran relance une lecture complète.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../design.dart';
import '../models/social.dart';
import '../state.dart';
import '../state/notifs.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import 'engagement_screen.dart';

class NotificationsScreen extends StatefulWidget {
  /// Ouvre la publication, éventuellement sur un commentaire précis.
  final void Function(String postId, {String? commentId})? onOuvrirPublication;
  final void Function(String userId)? onOuvrirProfil;

  /// Contrôleur partagé avec le fil (pastille de l'en-tête). Laissé nul,
  /// l'écran crée le sien et le libère en partant.
  final NotifsCtl? controleur;

  const NotificationsScreen({
    super.key,
    this.onOuvrirPublication,
    this.onOuvrirProfil,
    this.controleur,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late NotifsCtl _ctl;
  late bool _jePossede;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Si le fil nous passe son contrôleur, on réutilise le sien : deux
    // minuteurs pour la même chose, c'est de la data gaspillée.
    _jePossede = widget.controleur == null;
    _ctl = widget.controleur ?? NotifsCtl(context.read<AppState>().api);
    _ctl.addListener(_surChangement);
    _ctl.demarrer();
    _ctl.charger();
    _scroll.addListener(_peutEtrePlus);
  }

  void _surChangement() {
    if (mounted) setState(() {});
  }

  void _peutEtrePlus() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 240) {
      _ctl.chargerPlus();
    }
  }

  @override
  void dispose() {
    _ctl.removeListener(_surChangement);
    if (_jePossede) _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ouvrir(NotificationSociale n) async {
    await _ctl.marquerLue(n);
    if (!mounted) return;
    if (n.aUnePublication && widget.onOuvrirPublication != null) {
      Navigator.of(context).pop();
      widget.onOuvrirPublication!(n.postId!, commentId: n.commentId);
    } else if (n.expediteur != null && widget.onOuvrirProfil != null) {
      widget.onOuvrirProfil!(n.expediteur!.id);
    }
  }

  void _statistiques() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EngagementScreen(api: context.read<AppState>().api),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = _ctl.items;
    // Découpage en sections : l'ordre du serveur est déjà antéchronologique,
    // il suffit donc de regrouper au fil de la lecture.
    final sections = <TrancheNotifs, List<NotificationSociale>>{};
    for (final n in items) {
      sections.putIfAbsent(trancheDe(n.createdAt), () => []).add(n);
    }

    return Scaffold(
      backgroundColor: MC.nuit,
      appBar: AppBar(
        backgroundColor: MC.nuit,
        elevation: 0,
        title: Text('Notifications',
            style: TextStyle(
                color: MC.ivoire,
                fontSize: Tx.subtitle,
                fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            onPressed: _statistiques,
            tooltip: 'Mes statistiques',
            icon: Icon(Icons.insights_rounded, color: MC.soleil, size: 20),
          ),
          if (_ctl.nonLues > 0)
            TextButton(
              onPressed: _ctl.toutLire,
              child: Text('Tout lire',
                  style: TextStyle(color: MC.soleil, fontSize: Tx.label)),
            ),
        ],
      ),
      body: _ctl.charge && items.isEmpty
          ? Center(
              child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: MC.soleil, strokeWidth: 2)))
          : _ctl.erreur != null && items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_ctl.erreur!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
                  ),
                )
              : items.isEmpty
                  ? _Vide()
                  : RefreshIndicator(
                      color: MC.soleil,
                      onRefresh: () => _ctl.charger(),
                      child: ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.only(bottom: 30),
                        children: [
                          for (final t in const [
                            TrancheNotifs.aujourdhui,
                            TrancheNotifs.semaine,
                            TrancheNotifs.anciennes,
                          ])
                            if (sections[t] != null) ...[
                              _Entete(titre: _titre(t), nombre: sections[t]!.length),
                              for (final n in sections[t]!)
                                _Ligne(
                                  notification: n,
                                  onTap: () => _ouvrir(n),
                                  onProfil: widget.onOuvrirProfil == null ||
                                          n.acteurs.isEmpty
                                      ? null
                                      : () => widget
                                          .onOuvrirProfil!(n.acteurs.first.id),
                                ),
                            ],
                          if (_ctl.aPlus)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: Sp.x5, vertical: Sp.x4),
                              child: TextButton(
                                onPressed: _ctl.chargerPlus,
                                child: Text('Voir plus anciennes',
                                    style: TextStyle(
                                        color: MC.soleil, fontSize: Tx.label)),
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }

  String _titre(TrancheNotifs t) => switch (t) {
        TrancheNotifs.aujourdhui => 'Aujourd’hui',
        TrancheNotifs.semaine => 'Cette semaine',
        TrancheNotifs.anciennes => 'Plus anciennes',
      };
}

class _Entete extends StatelessWidget {
  final String titre;
  final int nombre;

  const _Entete({required this.titre, required this.nombre});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x5, Sp.x4, Sp.x2),
        child: Row(
          children: [
            Text(titre.toUpperCase(),
                style: TextStyle(
                    color: MC.kaki,
                    fontSize: Tx.caption,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1)),
            const SizedBox(width: 8),
            if (nombre > 0)
              Text('$nombre',
                  style: TextStyle(color: MC.kaki, fontSize: Tx.caption)),
          ],
        ),
      );
}

/// Une notification : visages empilés + pastille du type + phrase.
class _Ligne extends StatelessWidget {
  final NotificationSociale notification;
  final VoidCallback? onTap;
  final VoidCallback? onProfil;

  const _Ligne({required this.notification, this.onTap, this.onProfil});

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final visages = n.acteurs.isNotEmpty
        ? n.acteurs
        : (n.expediteur != null ? [n.expediteur!] : const <Personne>[]);
    final montres = visages.take(2).toList();

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: n.lu ? Colors.transparent : MC.soleil.withValues(alpha: .05),
        padding: const EdgeInsets.fromLTRB(Sp.x4, 12, Sp.x4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Deux visages au plus : au-delà, la phrase dit « et N autres ».
            SizedBox(
              width: montres.length > 1 ? 58 : 40,
              height: 40,
              child: Stack(
                children: [
                  for (var i = montres.length - 1; i >= 0; i--)
                    Positioned(
                      left: i * 20.0,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: MC.nuit, width: 2),
                        ),
                        child: MboteAvatar(
                          name: montres[i].name.isEmpty ? 'MboteCall' : montres[i].name,
                          size: 30,
                          image: (montres[i].avatar ?? '').isNotEmpty
                              ? NetworkImage(montres[i].avatar!)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          n.resume,
                          style: TextStyle(
                              color: MC.ivoire,
                              fontSize: Tx.label,
                              height: 1.35,
                              fontWeight:
                                  n.lu ? FontWeight.w600 : FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _TypeIcone(type: n.type),
                    ],
                  ),
                  if (n.texte.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text('« ${n.texte} »',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: MC.kaki, fontSize: Tx.caption, height: 1.35)),
                  ],
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(quandNotif(n.createdAt),
                          style:
                              TextStyle(color: MC.kaki, fontSize: Tx.caption)),
                      if (!n.lu) ...[
                        const SizedBox(width: 8),
                        Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                                color: MC.soleil, shape: BoxShape.circle)),
                      ],
                      if (n.estGroupee) ...[
                        const SizedBox(width: 8),
                        Text('${n.nbActeurs} personnes',
                            style: TextStyle(
                                color: MC.kaki, fontSize: Tx.caption)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (n.aUnePublication)
              IconButton(
                onPressed: onTap,
                tooltip: 'Ouvrir la publication',
                icon: Icon(Icons.chevron_right_rounded, color: MC.kaki, size: 20),
              )
            else if (onProfil != null)
              IconButton(
                onPressed: onProfil,
                tooltip: 'Voir le profil',
                icon: Icon(Icons.person_outline_rounded, color: MC.kaki, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pastille du type d'interaction : un seul signal visuel, discret.
class _TypeIcone extends StatelessWidget {
  final String type;
  const _TypeIcone({required this.type});

  @override
  Widget build(BuildContext context) {
    final (icone, couleur) = switch (type) {
      'post_like' => (Icons.favorite_rounded, MC.braise),
      'comment' => (Icons.chat_bubble_rounded, MC.soleil),
      'comment_reply' => (Icons.reply_rounded, MC.soleil),
      'share' => (Icons.repeat_rounded, MC.savane),
      'follow' => (Icons.person_add_alt_1_rounded, MC.savane),
      _ => (Icons.alternate_email_rounded, MC.soleil),
    };
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: .14),
        shape: BoxShape.circle,
      ),
      child: Icon(icone, size: 13, color: couleur),
    );
  }
}

class _Vide extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none_rounded, size: 36, color: MC.kaki),
              const SizedBox(height: 10),
              Text('Aucune notification pour l’instant',
                  style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
              const SizedBox(height: 6),
              Text(
                'Les j’aime, commentaires, mentions et partages sur vos '
                'publications apparaîtront ici.',
                textAlign: TextAlign.center,
                style: TextStyle(color: MC.kaki, fontSize: Tx.caption),
              ),
            ],
          ),
        ),
      );
}

/// « à l'instant », « il y a 5 min », « hier », puis la date.
String quandNotif(DateTime t, {DateTime? maintenant}) {
  final now = maintenant ?? DateTime.now();
  final d = now.difference(t);
  if (d.isNegative || d.inMinutes < 1) return 'à l’instant';
  if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
  if (d.inHours < 24) return 'il y a ${d.inHours} h';
  if (d.inDays == 1) return 'hier';
  if (d.inDays < 7) return 'il y a ${d.inDays} jours';
  return '${t.day}/${t.month}/${t.year}';
}
