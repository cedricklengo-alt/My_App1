// lib/widgets/feed/post_card.dart
// Carte de publication unifiée : photo · clip · texte · événement + bouton Appeler.
//
// Cette carte est **purement présentationnelle** : elle ne garde aucun état.
// L'état « j'aime » vit dans `FeedScreen` (et sur le serveur), ce qui évite
// qu'un compteur retombe à zéro quand la carte sort du cache de défilement.

import 'package:flutter/material.dart';
import 'reaction_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../design.dart';
import '../../models/post.dart';
import '../../theme.dart';
import 'media_view.dart';
import '../social/texte_social.dart';

class PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback? onLike;
  final void Function(String type)? onReact;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onCall;

  ///Fourni seulement pour MES publications (suppression autorisée).
  final VoidCallback? onDelete;

  /// Édition de la publication (auteur seul) — ouvre la feuille préremplie.
  final VoidCallback? onEdit;

  /// Suivre / ne plus suivre l'auteur (jamais proposé sur mes publications).
  final VoidCallback? onFollow;

  /// Appui sur un mot-clé : ouvre la découverte filtrée sur ce mot-clé.
  final ValueChanged<String>? onTag;

  /// Appui sur un hashtag écrit dans le texte (clé sans dièse).
  final ValueChanged<String>? onHashtag;

  /// Appui sur une mention écrite dans le texte (identifiant sans arobase).
  final ValueChanged<String>? onMention;

  /// Mon identifiant : sert à ne jamais afficher « Appeler » sur ma propre
  /// publication, et à proposer la suppression au bon endroit.
  final String? myId;

  final bool dataSaverMode;

  const PostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onReact,
    this.onComment,
    this.onShare,
    this.onCall,
    this.onDelete,
    this.onEdit,
    this.onFollow,
    this.onTag,
    this.onHashtag,
    this.onMention,
    this.myId,
    this.dataSaverMode = false,
  });

  /// Cette publication est-elle la mienne ?
  bool get isMine => myId != null && myId!.isNotEmpty && myId == post.authorId;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: Sp.x2),
      decoration: BoxDecoration(
        // Carte flottante : fond surface, rayon large, ombre très douce.
        color: MC.nuit2,
        borderRadius: BorderRadius.circular(Rd.lg),
        boxShadow: const [
          BoxShadow(
              color: Surcouche.ombre, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            post: post,
            isMine: isMine,
            onDelete: onDelete,
            onEdit: onEdit,
            onFollow: isMine ? null : onFollow,
            onShare: onShare,
          ),
          _MediaSection(
            post: post,
            dataSaverMode: dataSaverMode,
            onHashtag: onHashtag,
            onMention: onMention,
          ),
          if (post.tags.isNotEmpty)
            _MotsCles(tags: post.tags, onTag: onTag),
          _Actions(
            post: post,
            isMine: isMine,
            onLike: onLike,
            onReact: onReact,
            onComment: onComment,
            onShare: onShare,
            onCall: onCall,
          ),
        ],
      ),
    );
  }
}

//───────────────────────────────────────────
// En-tête : avatar · nom · localisation · badges
//───────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool isMine;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onFollow;
  final VoidCallback? onShare;

  final Post post;
  const _Header({
    required this.post,
    this.isMine = false,
    this.onDelete,
    this.onEdit,
    this.onFollow,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatar = post.authorAvatar != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x3, Sp.x3, Sp.x2, Sp.x2),
      child: Row(
        children: [
          // Avatar carré arrondi — photo si disponible, initiale sinon
          Container(
            width: Densite.avatar,
            height: Densite.avatar,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Rd.avatar),
              color: MC.nuit3,
              border: Border.all(color: MC.ligne),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasAvatar
                ? Image.network(
                    post.authorAvatar!,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                    errorBuilder: (_, __, ___) =>
                        _Initial(name: post.authorName),
                  )
                : _Initial(name: post.authorName),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        post.authorName.isEmpty
                            ? 'Compte MboteCall'
                            : post.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.body,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _OrigineChip(origine: post.origine),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (post.ville != null) ...[
                      Icon(Icons.location_on_rounded, size: 11, color: MC.kaki),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          post.ville!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: MC.kaki, fontSize: Tx.caption),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(post.age,
                        style: TextStyle(color: MC.kaki, fontSize: Tx.caption)),
                    if (post.editedAt != null) ...[
                      const SizedBox(width: 4),
                      Text('· Modifié',
                          style: TextStyle(
                              color: MC.soleil, fontSize: Tx.caption,
                              fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(width: 6),
                    _Badge(type: post.type),
                    // Sur MES publications : rappeler qui peut la voir. Sans
                    // cette pastille, une publication « contacts » paraissait
                    // publique alors qu'elle n'atteignait personne.
                    if (isMine) ...[
                      const SizedBox(width: 6),
                      _Audience(visibilite: post.visibilite),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Suivre l'auteur : la façon la plus simple, pour un lecteur,
          // de retrouver ses publications.
          if (onFollow != null && !post.suivi)
            Semantics(
              button: true,
              label: 'Suivre ${post.authorName}',
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onFollow!.call();
                },
                child: Container(
                  // 48 dp : cible tactile minimale exigée par Android.
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.center,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: MC.nuit3,
                    borderRadius: BorderRadius.circular(Rd.lg),
                    border: Border.all(color: MC.soleil.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    'Suivre',
                    style: TextStyle(
                      color: MC.soleil,
                      fontSize: Tx.caption,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          if (onFollow != null && post.suivi)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('Suivi',
                  style: TextStyle(color: MC.kaki, fontSize: Tx.caption)),
            ),
          // Menu : action réelle (copier le texte), plus de bouton mort
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: MC.kaki, size: 20),
            tooltip: 'Plus d’options',
            color: MC.nuit3,
            onSelected: (value) async {
              if (value == 'copy') {
                final text = post.texte ?? post.eventTitle ?? '';
                if (text.isEmpty) return;
                await Clipboard.setData(ClipboardData(text: text));
              } else if (value == 'edit') {
                onEdit?.call();
              } else if (value == 'delete') {
                onDelete?.call();
              } else if (value == 'share') {
                // Avant, cette entrée ne faisait rien du tout : le menu se
                // fermait et l'utilisateur restait sans réponse.
                onShare?.call();
              }
            },
            itemBuilder: (_) => [
              if ((post.texte ?? post.eventTitle ?? '').isNotEmpty)
                PopupMenuItem(
                  value: 'copy',
                  child: Text('Copier le texte',
                      style: TextStyle(color: MC.ivoire)),
                ),
              PopupMenuItem(
                value: 'share',
                child: Text('Partager', style: TextStyle(color: MC.ivoire)),
              ),
              //Seul l'auteur voit ces entrées.
              if (isMine && onEdit != null)
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_rounded, size: 17, color: MC.soleil),
                      const SizedBox(width: 8),
                      Text('Modifier', style: TextStyle(color: MC.ivoire)),
                    ],
                  ),
                ),
              if (isMine && onDelete != null)
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded,
                          size: 17, color: MC.rouge),
                      const SizedBox(width: 8),
                      Text('Supprimer', style: TextStyle(color: MC.rouge)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  final String name;
  const _Initial({required this.name});

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: MC.soleil,
            fontSize: Tx.subtitle,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _Badge extends StatelessWidget {
  final PostType type;
  const _Badge({required this.type});

  @override
  Widget build(BuildContext context) {
    if (type == PostType.texte || type == PostType.photo) {
      return const SizedBox.shrink();
    }
    final (label, color) = switch (type) {
      PostType.clip => ('CLIP', Semantique.clip), // éclairci : contraste AA
      PostType.event => ('ÉVÉN.', Semantique.evenement),
      _ => ('', MC.nuit3),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(Rd.xs),
        border: Border.all(color: color.withValues(alpha: .5), width: .8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: Tx.caption,
          fontWeight: FontWeight.w800,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

class _OrigineChip extends StatelessWidget {
  final PostOrigine origine;
  const _OrigineChip({required this.origine});

  @override
  Widget build(BuildContext context) {
    if (origine == PostOrigine.rdc) {
      return Icon(Icons.public_rounded, size: Tx.label, color: MC.kaki);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: MC.soleil.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(Rd.xs),
      ),
      child: Text(
        'Diaspora',
        style: TextStyle(
          color: MC.soleil,
          fontSize: Tx.caption,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

//───────────────────────────────────────────
// Section média selon le type
//───────────────────────────────────────────

class _MediaSection extends StatelessWidget {
  final Post post;
  final bool dataSaverMode;
  final ValueChanged<String>? onHashtag;
  final ValueChanged<String>? onMention;

  const _MediaSection({
    required this.post,
    required this.dataSaverMode,
    this.onHashtag,
    this.onMention,
  });

  /// Noms affichés des personnes mentionnées, quand le serveur les a fournis :
  /// « @cedricklengo » s'affiche « @Cédrick Lengo ».
  Map<String, String>? get nomsParHandle {
    if (post.mentionsListe.isEmpty) return null;
    return {
      for (final m in post.mentionsListe)
        if (m.handle.isNotEmpty && m.name.isNotEmpty) m.handle.toLowerCase(): m.name,
    };
  }

  @override
  Widget build(BuildContext context) {
    return switch (post.type) {
      PostType.photo => _PhotoMedia(
          post: post, dataSaverMode: dataSaverMode, onHashtag: onHashtag,
          onMention: onMention, nomsParHandle: nomsParHandle),
      PostType.clip => _ClipMedia(
          post: post, dataSaverMode: dataSaverMode, onHashtag: onHashtag,
          onMention: onMention, nomsParHandle: nomsParHandle),
      PostType.texte => _TexteMedia(
          post: post, onHashtag: onHashtag, onMention: onMention,
          nomsParHandle: nomsParHandle),
      PostType.event => _EventMedia(post: post),
    };
  }
}

class _PhotoMedia extends StatelessWidget {
  final Post post;
  final bool dataSaverMode;
  final ValueChanged<String>? onHashtag;
  final ValueChanged<String>? onMention;
  final Map<String, String>? nomsParHandle;

  const _PhotoMedia({
    required this.post,
    this.dataSaverMode = false,
    this.onHashtag,
    this.onMention,
    this.nomsParHandle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (post.texte != null && post.texte!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TexteSocial(
              post.texte!,
              fontSize: Tx.label,
              onHashtag: onHashtag,
              onMention: onMention,
              nomsMentions: nomsParHandle,
            ),
          ),
        if (post.mediaUrl != null)
          isVideoUrl(post.mediaUrl)
              // Une « photo » qui pointe en réalité vers une vidéo : on la joue.
              ? MboteVideo(
                  autoPlay: !dataSaverMode,
                  url: post.mediaUrl!,
                  height: 220,
                  posterUrl: post.thumbUrl,
                  dureeLabel: post.clipDureeLabel,
                )
              : MboteImage(url: post.mediaUrl!, height: 340, fit: BoxFit.contain)
        else
          Container(
            height: 120,
            color: MC.nuit3,
            child: Center(
                child: Icon(Icons.image_rounded, color: MC.kaki, size: 36)),
          ),
      ],
    );
  }
}

class _ClipMedia extends StatelessWidget {
  final Post post;
  final bool dataSaverMode;
  final ValueChanged<String>? onHashtag;
  final ValueChanged<String>? onMention;
  final Map<String, String>? nomsParHandle;

  const _ClipMedia({
    required this.post,
    required this.dataSaverMode,
    this.onHashtag,
    this.onMention,
    this.nomsParHandle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (post.texte != null && post.texte!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TexteSocial(
              post.texte!,
              fontSize: Tx.label,
              onHashtag: onHashtag,
              onMention: onMention,
              nomsMentions: nomsParHandle,
            ),
          ),
        if (post.mediaUrl != null)
          Stack(
            children: [
              //La vidéo démarre au premier appui : aucune donnée consommée
              // avant (important sur une connexion 3G/4G limitée).
              MboteVideo(
                autoPlay: !dataSaverMode,
                url: post.mediaUrl!,
                height: 220,
                posterUrl: post.thumbUrl,
                dureeLabel: post.clipDureeLabel,
              ),
              // La durée est déjà affichée par la miniature quand elle existe :
              // la superposer deux fois ferait doublon sur l'image.
              if (post.clipDureeLabel.isNotEmpty && post.thumbUrl == null)
                Positioned(
                  bottom: 8,
                  right: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .6),
                      borderRadius: BorderRadius.circular(Rd.xs),
                    ),
                    child: Text(
                      post.clipDureeLabel,
                      style: TextStyle(
                        color: MC.ivoire,
                        fontSize: Tx.caption,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              if (dataSaverMode)
                Positioned(
                  top: 8,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: MC.soleil.withValues(alpha: .9),
                      borderRadius: BorderRadius.circular(Rd.xs),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.data_saver_on_rounded,
                            size: 11, color: MC.nuit),
                        const SizedBox(width: 3),
                        Text(
                          'Éco data',
                          style: TextStyle(
                            color: MC.nuit,
                            fontSize: Tx.caption,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          )
        else
          Container(
            height: 220,
            color: MC.nuit3,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_off_rounded, color: MC.kaki, size: 30),
                  const SizedBox(height: 6),
                  Text('Vidéo indisponible',
                      style: TextStyle(color: MC.kaki, fontSize: Tx.caption)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Publication textuelle : le texte est prioritaire — aucun conteneur
/// bordé, aucune carte imbriquée. Les textes longs sont tronqués avec une
/// commande « Voir plus » discrète (et « Voir moins » pour replier).
class _TexteMedia extends StatefulWidget {
  final Post post;
  final ValueChanged<String>? onHashtag;
  final ValueChanged<String>? onMention;
  final Map<String, String>? nomsParHandle;

  const _TexteMedia({
    required this.post,
    this.onHashtag,
    this.onMention,
    this.nomsParHandle,
  });

  @override
  State<_TexteMedia> createState() => _TexteMediaState();
}

class _TexteMediaState extends State<_TexteMedia> {
  /// Seuil au-delà duquel on propose « Voir plus » (en caractères).
  static const int _seuil = 280;
  bool _ouvert = false;

  @override
  Widget build(BuildContext context) {
    final texte = widget.post.texte;
    if (texte == null || texte.isEmpty) {
      return const SizedBox.shrink();
    }
    final tronque = !_ouvert && texte.length > _seuil;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TexteSocial(
            texte,
            fontSize: Tx.body,
            height: 1.5,
            maxLines: tronque ? 6 : null,
            onHashtag: widget.onHashtag,
            onMention: widget.onMention,
            nomsMentions: widget.nomsParHandle,
          ),
          if (texte.length > _seuil)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _ouvert = !_ouvert);
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Semantics(
                  button: true,
                  label: _ouvert ? 'Voir moins' : 'Voir plus',
                  child: Text(
                    _ouvert ? 'Voir moins' : 'Voir plus',
                    style: TextStyle(
                      color: MC.kaki,
                      fontSize: Tx.label,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EventMedia extends StatelessWidget {
  final Post post;
  const _EventMedia({required this.post});

  /// Formatage tolérant : si les données de langue ne sont pas chargées, on
  /// retombe sur un format numérique plutôt que de faire tomber l'écran.
  String? get _dateLabel {
    final d = post.eventDate;
    if (d == null) return null;
    try {
      return DateFormat("d MMM yyyy · HH'h'mm", 'fr_FR').format(d);
    } catch (_) {
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(d.day)}/${two(d.month)}/${d.year} · ${two(d.hour)}h${two(d.minute)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _dateLabel;
    const violet = Semantique.evenement;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Rd.md),
        border: Border.all(color: violet.withValues(alpha: .4)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [violet.withValues(alpha: .15), MC.nuit2],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dateLabel != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: violet.withValues(alpha: .2),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(11)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 12, color: violet),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      dateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: violet,
                        fontSize: Tx.label,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.eventTitle ?? '',
                  style: TextStyle(
                    color: MC.ivoire,
                    fontSize: Tx.bodyLg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (post.texte != null && post.texte!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    post.texte!,
                    style:
                        TextStyle(color: MC.sable, fontSize: Tx.label, height: 1.4),
                  ),
                ],
                if (post.eventLieu != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.place_rounded, size: 13, color: MC.kaki),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          post.eventLieu!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: MC.sable, fontSize: Tx.label),
                        ),
                      ),
                    ],
                  ),
                ],
                if (post.eventTags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: post.eventTags
                        .map(
                          (t) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: violet.withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(Rd.xs),
                            ),
                            child: Text(
                              '#$t',
                              style:
                                  const TextStyle(color: violet, fontSize: Tx.caption),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

//───────────────────────────────────────────
// Barre d'actions : like · commentaire · partage · Appeler
//───────────────────────────────────────────

class _Actions extends StatelessWidget {
  final Post post;
  final bool isMine;
  final VoidCallback? onLike;
  final void Function(String type)? onReact;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onCall;

  const _Actions({
    required this.post,
    this.isMine = false,
    this.onLike,
    this.onReact,
    this.onComment,
    this.onShare,
    this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 10, 8),
      child: Row(
        children: [
          _ActBtn(
            icon: post.liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: post.liked ? MC.rouge : MC.kaki,
            count: post.likes,
            semanticLabel: post.liked ? 'Retirer mon j’aime' : 'J’aime',
            onTap: onLike,
            onLongPress: onReact == null
                ? null
                : () {
                    final box = context.findRenderObject() as RenderBox;
                    final pos = box.localToGlobal(Offset.zero);
                    ReactionPicker.show(context, pos + const Offset(30, 0))
                        .then((t) => t != null ? onReact!(t) : null);
                  },
          ),
          _ActBtn(
            icon: Icons.chat_bubble_outline_rounded,
            count: post.comments,
            semanticLabel: 'Commenter',
            onTap: onComment,
          ),
          // Nombre de lectures : information publique, comme sur un fil
          // social classique. Non cliquable — on ne « clique » pas une vue.
          if (post.vues > 0)
            _ActBtn(
              icon: Icons.visibility_outlined,
              count: post.vues,
              semanticLabel: '${post.vues} vue(s)',
            ),
          _ActBtn(
            icon: Icons.share_rounded,
            count: post.partages,
            semanticLabel: post.partages > 0
                ? 'Partager (${post.partages} partage(s))'
                : 'Partager',
            onTap: onShare,
          ),
          const Spacer(),
          //Bouton Appeler :
          //   • jamais sur MA propre publication (on ne s'appelle pas soi-même) ;
          //   • seulement si l'API a fourni le numéro (auteur = contact) ;
          //   • jamais d'appel automatique : il faut un appui explicite.
          if (!isMine && post.canCall && onCall != null)
            Semantics(
              label:
                  post.isContact ? 'Appeler ${post.authorName}' : 'Contacter',
              button: true,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  onCall!.call();
                },
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: MC.soleil,
                    borderRadius: BorderRadius.circular(Rd.lg),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.call_rounded, size: 15, color: MC.nuit),
                      const SizedBox(width: 5),
                      Text(
                        post.isContact ? 'Appeler' : 'Contacter',
                        style: TextStyle(
                          fontSize: Tx.label,
                          fontWeight: FontWeight.w700,
                          color: MC.nuit,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bande de mots-clés sous le contenu. Un appui ouvre la découverte filtrée.
class _MotsCles extends StatelessWidget {
  final List<String> tags;
  final ValueChanged<String>? onTag;
  const _MotsCles({required this.tags, this.onTag});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x3, 0, Sp.x3, Sp.x2),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final t in tags.take(6))
            Semantics(
              button: onTag != null,
              label: 'Voir les publications du mot-clé $t',
              child: GestureDetector(
                onTap: onTag == null ? null : () => onTag!.call(t),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.center,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: MC.nuit3,
                    borderRadius: BorderRadius.circular(Rd.lg),
                    border: Border.all(color: MC.ligne),
                  ),
                  child: Text(
                    '#$t',
                    style: TextStyle(
                        color: MC.soleil,
                        fontSize: Tx.caption,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pastille d'audience, affichée sur MES publications seulement.
/// Elle répond à la question « qui voit ce que je publie ? » là où l'utilisateur
/// en a besoin : sur sa propre publication.
class _Audience extends StatelessWidget {
  final PostVisibilite visibilite;
  const _Audience({required this.visibilite});

  @override
  Widget build(BuildContext context) {
    final (icone, libelle) = switch (visibilite) {
      PostVisibilite.public => (Icons.public_rounded, 'Tout le monde'),
      PostVisibilite.communaute =>
        (Icons.groups_rounded, 'Communauté'),
      PostVisibilite.contacts => (Icons.lock_outline_rounded, 'Mes contacts'),
    };
    final couleur =
        visibilite == PostVisibilite.contacts ? MC.soleil : MC.kaki;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 11, color: couleur),
        const SizedBox(width: 3),
        Text(libelle,
            style: TextStyle(color: couleur, fontSize: Tx.caption)),
      ],
    );
  }
}

class _ActBtn extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final int count;
  final String semanticLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _ActBtn({
    required this.icon,
    this.color,
    this.count = 0,
    required this.semanticLabel,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? MC.kaki;
    return Semantics(
      label: semanticLabel,
      button: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(Rd.lg),
        child: Container(
          // Cible tactile confortable (≥ 44 dp) même avec une icône de 20 dp
          constraints: const BoxConstraints(minWidth: 46, minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: c),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Text(
                  _fmt(count),
                  style: TextStyle(
                    color: c,
                    fontSize: Tx.label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}
