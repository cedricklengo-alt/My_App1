// lib/widgets/feed/post_card.dart
// Carte de publication unifiée : photo · clip · texte · événement + bouton Appeler.
//
// Cette carte est **purement présentationnelle** : elle ne garde aucun état.
// L'état « j'aime » vit dans `FeedScreen` (et sur le serveur), ce qui évite
// qu'un compteur retombe à zéro quand la carte sort du cache de défilement.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/post.dart';
import '../../theme.dart';

class PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onCall;
  final bool dataSaverMode;

  const PostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onCall,
    this.dataSaverMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: MC.nuit2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MC.ligne),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(post: post),
          _MediaSection(post: post, dataSaverMode: dataSaverMode),
          _Actions(
            post: post,
            onLike: onLike,
            onComment: onComment,
            onShare: onShare,
            onCall: onCall,
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// En-tête : avatar · nom · localisation · badges
// ──────────────────────────────────────────────

class _Header extends StatelessWidget {
  final Post post;
  const _Header({required this.post});

  @override
  Widget build(BuildContext context) {
    final hasAvatar = post.authorAvatar != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
      child: Row(
        children: [
          // Avatar 40 dp — photo si disponible, initiale sinon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MC.nuit3,
              border: Border.all(
                  color: MC.soleil.withValues(alpha: .4), width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasAvatar
                ? Image.network(
                    post.authorAvatar!,
                    fit: BoxFit.cover,
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
                            ? 'Compte Mbote'
                            : post.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: MC.ivoire,
                          fontSize: 14,
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
                          style: TextStyle(color: MC.kaki, fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(post.age,
                        style: TextStyle(color: MC.kaki, fontSize: 11)),
                    const SizedBox(width: 6),
                    _Badge(type: post.type),
                  ],
                ),
              ],
            ),
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
            fontSize: 16,
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
      PostType.clip => (
          'CLIP',
          const Color(0xFFE8674F)
        ), // éclairci : contraste AA
      PostType.event => ('ÉVÉN.', const Color(0xFF9C6DFF)),
      _ => ('', MC.nuit3),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: .5), width: .8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
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
      return const Text('🇨🇩', style: TextStyle(fontSize: 12));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: MC.soleil.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Diaspora',
        style: TextStyle(
          color: MC.soleil,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Section média selon le type
// ──────────────────────────────────────────────

class _MediaSection extends StatelessWidget {
  final Post post;
  final bool dataSaverMode;
  const _MediaSection({required this.post, required this.dataSaverMode});

  @override
  Widget build(BuildContext context) {
    return switch (post.type) {
      PostType.photo => _PhotoMedia(post: post),
      PostType.clip => _ClipMedia(post: post, dataSaverMode: dataSaverMode),
      PostType.texte => _TexteMedia(post: post),
      PostType.event => _EventMedia(post: post),
    };
  }
}

/// Image réseau robuste : place-holder, erreur, et largeur bornée (mémoire).
class _RemoteImage extends StatelessWidget {
  final String url;
  final double height;
  const _RemoteImage({required this.url, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        cacheWidth: 1080,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          final total = progress.expectedTotalBytes;
          final ratio =
              total == null ? null : progress.cumulativeBytesLoaded / total;
          return Container(
            color: MC.nuit3,
            child: Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  value: ratio,
                  strokeWidth: 2,
                  color: MC.soleil,
                ),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          color: MC.nuit3,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_rounded, color: MC.kaki, size: 30),
                const SizedBox(height: 6),
                Text('Image indisponible',
                    style: TextStyle(color: MC.kaki, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoMedia extends StatelessWidget {
  final Post post;
  const _PhotoMedia({required this.post});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (post.texte != null && post.texte!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              post.texte!,
              style: TextStyle(color: MC.ivoire, fontSize: 13, height: 1.4),
            ),
          ),
        if (post.mediaUrl != null)
          _RemoteImage(url: post.mediaUrl!, height: 220)
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
  const _ClipMedia({required this.post, required this.dataSaverMode});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (post.texte != null && post.texte!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              post.texte!,
              style: TextStyle(color: MC.ivoire, fontSize: 13, height: 1.4),
            ),
          ),
        Stack(
          children: [
            if (post.mediaUrl != null && !dataSaverMode)
              _RemoteImage(url: post.mediaUrl!, height: 220)
            else
              Container(height: 220, color: MC.nuit3),
            Positioned.fill(
              child: Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MC.soleil.withValues(alpha: dataSaverMode ? .35 : 1),
                  ),
                  child:
                      Icon(Icons.play_arrow_rounded, color: MC.nuit, size: 32),
                ),
              ),
            ),
            if (post.clipDureeLabel.isNotEmpty)
              Positioned(
                bottom: 8,
                right: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    post.clipDureeLabel,
                    style: TextStyle(
                      color: MC.ivoire,
                      fontSize: 10,
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
                    borderRadius: BorderRadius.circular(6),
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
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TexteMedia extends StatelessWidget {
  final Post post;
  const _TexteMedia({required this.post});

  @override
  Widget build(BuildContext context) {
    if (post.texte == null || post.texte!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MC.nuit3,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MC.ligne),
      ),
      child: Text(
        post.texte!,
        style: TextStyle(color: MC.ivoire, fontSize: 14, height: 1.5),
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
    const violet = Color(0xFF9C6DFF);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
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
                        fontSize: 12,
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
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (post.texte != null && post.texte!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    post.texte!,
                    style:
                        TextStyle(color: MC.sable, fontSize: 13, height: 1.4),
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
                          style: TextStyle(color: MC.sable, fontSize: 12),
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
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '#$t',
                              style:
                                  const TextStyle(color: violet, fontSize: 11),
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

// ──────────────────────────────────────────────
// Barre d'actions : like · commentaire · partage · Appeler
// ──────────────────────────────────────────────

class _Actions extends StatelessWidget {
  final Post post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onCall;

  const _Actions({
    required this.post,
    this.onLike,
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
          ),
          _ActBtn(
            icon: Icons.chat_bubble_outline_rounded,
            count: post.comments,
            semanticLabel: 'Commenter',
            onTap: onComment,
          ),
          _ActBtn(
            icon: Icons.share_rounded,
            semanticLabel: 'Partager',
            onTap: onShare,
          ),
          const Spacer(),
          // Bouton Appeler : seulement si l'auteur est joignable (numéro fourni
          // par l'API pour les contacts). Sinon inutile de promettre un appel.
          if (post.canCall && onCall != null)
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
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.call_rounded, size: 15, color: MC.nuit),
                      const SizedBox(width: 5),
                      Text(
                        post.isContact ? 'Appeler' : 'Contacter',
                        style: TextStyle(
                          fontSize: 12,
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

class _ActBtn extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final int count;
  final String semanticLabel;
  final VoidCallback? onTap;

  const _ActBtn({
    required this.icon,
    this.color,
    this.count = 0,
    required this.semanticLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? MC.kaki;
    return Semantics(
      label: semanticLabel,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
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
                    fontSize: 12,
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
