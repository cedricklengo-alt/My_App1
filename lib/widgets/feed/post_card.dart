// lib/widgets/feed/post_card.dart
// Carte post unifiée : photo · clip · texte · événement + bouton Appeler

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/post.dart';
import '../../theme.dart';

class PostCard extends StatefulWidget {
  final Post post;
  final VoidCallback? onCall;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final bool dataSaverMode;

  const PostCard({
    super.key,
    required this.post,
    this.onCall,
    this.onLike,
    this.onComment,
    this.onShare,
    this.dataSaverMode = false,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late bool _liked;
  late int _likes;

  @override
  void initState() {
    super.initState();
    _liked = false;
    _likes = widget.post.likes;
  }

  void _toggleLike() {
    HapticFeedback.selectionClick();
    setState(() {
      _liked = !_liked;
      _likes += _liked ? 1 : -1;
    });
    widget.onLike?.call();
  }

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
          _Header(post: widget.post),
          _MediaSection(
            post: widget.post,
            dataSaverMode: widget.dataSaverMode,
          ),
          _Actions(
            post: widget.post,
            liked: _liked,
            likes: _likes,
            onLike: _toggleLike,
            onComment: widget.onComment,
            onShare: widget.onShare,
            onCall: widget.onCall,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          // Avatar 36px
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MC.nuit3,
              border: Border.all(color: MC.soleil.withOpacity(.4), width: 1.5),
            ),
            child: Center(
              child: Text(
                post.authorName.isNotEmpty
                    ? post.authorName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: MC.soleil,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
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
                        post.authorName,
                        style: const TextStyle(
                          color: MC.ivoire,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _OrigineChip(origine: post.origine),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (post.ville != null) ...[
                      const Icon(
                        Icons.location_on_rounded,
                        size: 10,
                        color: MC.kaki,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        post.ville!,
                        style: const TextStyle(
                          color: MC.kaki,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      post.age,
                      style: const TextStyle(
                        color: MC.kaki,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _Badge(type: post.type),
                  ],
                ),
              ],
            ),
          ),
          // Menu
          GestureDetector(
            onTap: () {},
            child: const Icon(
              Icons.more_vert_rounded,
              color: MC.kaki,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
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
      PostType.clip => ('CLIP', MC.rouge),
      PostType.event => ('ÉVÉN.', const Color(0xFF7C4DFF)),
      _ => ('', MC.nuit3),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(.5), width: .8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 8,
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
      return const Text('🇨🇩', style: TextStyle(fontSize: 11));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: MC.soleil.withOpacity(.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'Diaspora',
        style: TextStyle(
          color: MC.soleil,
          fontSize: 8,
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

class _PhotoMedia extends StatelessWidget {
  final Post post;
  const _PhotoMedia({required this.post});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (post.texte != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              post.texte!,
              style: const TextStyle(color: MC.ivoire, fontSize: 13, height: 1.4),
            ),
          ),
        Container(
          height: 200,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: MC.nuit3,
            image: post.mediaUrl != null
                ? DecorationImage(
                    image: NetworkImage(post.mediaUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: post.mediaUrl == null
              ? const Center(
                  child: Icon(Icons.image_rounded, color: MC.kaki, size: 40),
                )
              : null,
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
        if (post.texte != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              post.texte!,
              style: const TextStyle(color: MC.ivoire, fontSize: 13, height: 1.4),
            ),
          ),
        Stack(
          children: [
            Container(
              height: 220,
              color: MC.nuit3,
              child: const Center(
                child: Icon(Icons.play_circle_fill_rounded,
                    color: Colors.transparent, size: 56),
              ),
            ),
            // Bouton play
            Positioned.fill(
              child: Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: MC.soleil,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: MC.nuit,
                    size: 32,
                  ),
                ),
              ),
            ),
            // Durée
            if (post.clipDureeSeconds != null)
              Positioned(
                bottom: 8,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    post.clipDureeLabel,
                    style: const TextStyle(
                      color: MC.ivoire,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            // Badge data saver
            if (dataSaverMode)
              Positioned(
                top: 8,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: MC.soleil.withOpacity(.9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.data_saver_on_rounded,
                          size: 10, color: MC.nuit),
                      SizedBox(width: 3),
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
    if (post.texte == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MC.nuit3,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MC.ligne),
      ),
      child: Text(
        post.texte!,
        style: const TextStyle(
          color: MC.ivoire,
          fontSize: 14,
          height: 1.5,
        ),
      ),
    );
  }
}

class _EventMedia extends StatelessWidget {
  final Post post;
  const _EventMedia({required this.post});

  @override
  Widget build(BuildContext context) {
    final dateLabel = post.eventDate != null
        ? DateFormat("d MMM yyyy · HH'h'mm", 'fr_FR').format(post.eventDate!)
        : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(.4)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF7C4DFF).withOpacity(.15),
            MC.nuit2,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bandeau date
          if (dateLabel != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF7C4DFF).withOpacity(.2),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(11),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 11,
                    color: Color(0xFF7C4DFF),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      color: Color(0xFF7C4DFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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
                  style: const TextStyle(
                    color: MC.ivoire,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (post.eventLieu != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_rounded,
                        size: 12,
                        color: MC.kaki,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          post.eventLieu!,
                          style: const TextStyle(
                            color: MC.sable,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (post.eventTags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: post.eventTags
                        .map(
                          (t) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C4DFF).withOpacity(.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '#$t',
                              style: const TextStyle(
                                color: Color(0xFF9C6DFF),
                                fontSize: 10,
                              ),
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
  final bool liked;
  final int likes;
  final VoidCallback onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onCall;

  const _Actions({
    required this.post,
    required this.liked,
    required this.likes,
    required this.onLike,
    this.onComment,
    this.onShare,
    this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    // Label selon type de contact
    final callLabel = post.isContact ? 'Appeler' : 'Contacter';

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
      child: Row(
        children: [
          _ActBtn(
            icon: liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: liked ? MC.rouge : MC.kaki,
            count: likes,
            semanticLabel: 'J\'aime',
            onTap: onLike,
          ),
          const SizedBox(width: 4),
          _ActBtn(
            icon: Icons.chat_bubble_outline_rounded,
            count: post.comments,
            semanticLabel: 'Commenter',
            onTap: onComment,
          ),
          const SizedBox(width: 4),
          _ActBtn(
            icon: Icons.share_rounded,
            semanticLabel: 'Partager',
            onTap: onShare,
          ),
          const Spacer(),
          // Bouton Appeler — le différenciateur Mbote
          Semantics(
            label: callLabel,
            button: true,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                onCall?.call();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: MC.soleil,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.call_rounded,
                      size: 14,
                      color: MC.nuit,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      callLabel,
                      style: const TextStyle(
                        fontSize: 11,
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
  final Color color;
  final int count;
  final String semanticLabel;
  final VoidCallback? onTap;

  const _ActBtn({
    required this.icon,
    this.color = MC.kaki,
    this.count = 0,
    required this.semanticLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Text(
                  _fmt(count),
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
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
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}
