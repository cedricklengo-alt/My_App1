// lib/screens/feed_screen.dart
// Écran principal Mbote Feed — statuts + flux unifié

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/post.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/feed/post_card.dart';
import '../widgets/feed/story_bar.dart';
import 'call_sheet.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<Post> _posts = [];
  List<StoryContact> _stories = [];
  bool _loading = true;
  bool _dataSaver = false;

  // ── Chargement ─────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  Future<void> _loadFeed() async {
    // TODO : remplacer par Api().feedPosts() + Api().feedStories()
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() {
      _posts = List.from(demoPosts);
      _stories = List.from(demoStories);
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    await _loadFeed();
  }

  // ── Appel depuis une carte ──────────────────────────────
  void _onCall(Post post) {
    final appState = context.read<AppState>();
    // Ouvre la fiche d'appel Mbote (même logique que depuis le chat)
    showCallModeSheet(
      context,
      // phone : utiliser l'ID auteur comme numéro si pas de champ dédié
      post.authorId,
      post.authorName,
    );
  }

  // ── Création de contenu ─────────────────────────────────
  void _showCreateSheet() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.nuit2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poignée
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: MC.nuit3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Publier',
              style: TextStyle(
                color: MC.ivoire,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _CreateBtn(
                  icon: Icons.image_rounded,
                  label: 'Photo',
                  color: MC.savane,
                  onTap: () => Navigator.pop(context),
                ),
                _CreateBtn(
                  icon: Icons.videocam_rounded,
                  label: 'Clip',
                  color: MC.rouge,
                  onTap: () => Navigator.pop(context),
                ),
                _CreateBtn(
                  icon: Icons.edit_rounded,
                  label: 'Texte',
                  color: MC.soleil,
                  onTap: () => Navigator.pop(context),
                ),
                _CreateBtn(
                  icon: Icons.event_rounded,
                  label: 'Événement',
                  color: const Color(0xFF7C4DFF),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Interface ───────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MC.nuit,
      floatingActionButton: _FAB(onTap: _showCreateSheet),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: MC.soleil,
        backgroundColor: MC.nuit2,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // AppBar
            _FeedAppBar(dataSaver: _dataSaver, onToggleDataSaver: () {
              setState(() => _dataSaver = !_dataSaver);
            }),

            // Bande statuts
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: Text(
                      'STATUTS',
                      style: TextStyle(
                        color: MC.kaki,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  StoryBar(
                    stories: _stories,
                    onStoryTap: (s) {
                      // TODO : ouvrir le visualiseur de statut
                    },
                    onAddTap: () {
                      // TODO : ouvrir caméra / galerie pour statut
                    },
                  ),
                  Divider(
                    height: 1,
                    color: MC.ligne,
                    indent: 12,
                    endIndent: 12,
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),

            // Contenu
            if (_loading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                    color: MC.soleil,
                    strokeWidth: 2,
                  ),
                ),
              )
            else if (_posts.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Text(
                    'Aucune publication pour le moment.',
                    style: TextStyle(color: MC.kaki, fontSize: 14),
                  ),
                ),
              )
            else
              SliverList.separated(
                itemCount: _posts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (context, i) {
                  final post = _posts[i];
                  return PostCard(
                    post: post,
                    dataSaverMode: _dataSaver,
                    onCall: () => _onCall(post),
                    onLike: () {},
                    onComment: () {},
                    onShare: () {},
                  );
                },
              ),

            // Espace bas pour le FAB
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// AppBar Mbote Feed
// ──────────────────────────────────────────────

class _FeedAppBar extends StatelessWidget {
  final bool dataSaver;
  final VoidCallback onToggleDataSaver;

  const _FeedAppBar({
    required this.dataSaver,
    required this.onToggleDataSaver,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: MC.nuit.withOpacity(.95),
      elevation: 0,
      scrolledUnderElevation: 0,
      title: const Text(
        'Mbote',
        style: TextStyle(
          color: MC.soleil,
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: -.5,
        ),
      ),
      actions: [
        // Indicateur mode data saver
        if (dataSaver)
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: MC.soleil.withOpacity(.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Éco',
              style: TextStyle(
                color: MC.soleil,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        IconButton(
          icon: Icon(
            dataSaver
                ? Icons.data_saver_on_rounded
                : Icons.data_saver_off_rounded,
            color: dataSaver ? MC.soleil : MC.kaki,
            size: 20,
          ),
          tooltip: dataSaver ? 'Mode éco actif' : 'Activer mode éco data',
          onPressed: onToggleDataSaver,
        ),
        IconButton(
          icon: const Icon(
            Icons.search_rounded,
            color: MC.kaki,
            size: 22,
          ),
          onPressed: () {
            // TODO : ouvrir recherche feed
          },
        ),
        IconButton(
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: MC.kaki,
            size: 22,
          ),
          onPressed: () {
            // TODO : ouvrir notifications
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ──────────────────────────────────────────────
// FAB central de création
// ──────────────────────────────────────────────

class _FAB extends StatelessWidget {
  final VoidCallback onTap;
  const _FAB({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Publier',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: MC.degrade,
            boxShadow: [
              BoxShadow(
                color: Color(0x44F2B430),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.add_rounded,
            color: MC.nuit,
            size: 28,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Bouton de création dans le sheet
// ──────────────────────────────────────────────

class _CreateBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CreateBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(.15),
              border: Border.all(color: color.withOpacity(.4)),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: MC.sable,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
