// lib/screens/feed_screen.dart
// Onglet « Accueil » : fil de publication branché sur le backend.
//
// Tout est réel : lecture paginée de `GET /api/feed`, statuts 24 h, j'aime,
// commentaires, publication (texte / photo / événement) et envoi de photo.
// Les états chargement / erreur / vide / fin de liste sont gérés, et
// l'API est injectable (`FeedScreen(api: …)`) pour les tests.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models/post.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/feed/post_card.dart';
import '../widgets/feed/story_bar.dart';
import 'call_sheet.dart';

class FeedScreen extends StatefulWidget {
  /// Injectée par les tests ; en production on prend celle de `AppState`.
  final Api? api;

  const FeedScreen({super.key, this.api});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late final Api _api;
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();

  List<Post> _posts = const [];
  List<StoryGroup> _groups = const [];
  int? _nextBefore;
  String? _nextCursor;

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  bool _dataSaver = false;
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? context.read<AppState>().api;
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  // ── Chargement ─────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.feedPage();
      final stories = await _api.feedStories();
      if (!mounted) return;
      setState(() {
        _posts = page.posts;
        _nextBefore = page.nextBefore;
        _nextCursor = page.nextCursor;
        _groups = StoryGroup.group(stories, myUserId: _myId);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  String? get _myId {
    try {
      return context.read<AppState>().id;
    } catch (_) {
      return null;
    }
  }

  /// Tirer pour rafraîchir : en cas d'échec on garde le fil affiché.
  Future<void> _refresh() async {
    try {
      final page = await _api.feedPage();
      final stories = await _api.feedStories();
      if (!mounted) return;
      setState(() {
        _posts = page.posts;
        _nextBefore = page.nextBefore;
        _nextCursor = page.nextCursor;
        _groups = StoryGroup.group(stories, myUserId: _myId);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      _toast(friendlyError(e));
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextCursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page =
          await _api.feedPage(before: _nextBefore, cursor: _nextCursor);
      if (!mounted) return;
      final seen = _posts.map((p) => p.id).toSet();
      setState(() {
        _posts = [..._posts, ...page.posts.where((p) => !seen.contains(p.id))];
        _nextBefore = page.nextBefore;
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _toast(friendlyError(e));
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final remaining =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 600) _loadMore();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── J'aime ─────────────────────────────────────────────

  void _replace(Post updated) {
    setState(() {
      _posts = [
        for (final p in _posts)
          if (p.id == updated.id) updated else p,
      ];
    });
  }

  Future<void> _toggleLike(Post post) async {
    // Optimiste : l'utilisateur voit son geste tout de suite…
    final optimistic = post.copyWith(
      liked: !post.liked,
      likes:
          post.liked ? (post.likes > 0 ? post.likes - 1 : 0) : post.likes + 1,
    );
    _replace(optimistic);
    HapticFeedback.selectionClick();
    try {
      // …puis le serveur fait foi.
      final r = await _api.likePost(post.id);
      _replace(post.copyWith(
        liked: r['liked'] == true,
        likes: (r['likes'] as num?)?.toInt() ?? optimistic.likes,
      ));
    } catch (e) {
      _replace(post); // retour à l'état précédent
      _toast(friendlyError(e));
    }
  }

  // ── Commentaires ───────────────────────────────────────

  Future<void> _openComments(Post post) async {
    final count = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(api: _api, post: post),
    );
    if (count != null) _replace(post.copyWith(comments: count));
  }

  // ── Partage ────────────────────────────────────────────

  Future<void> _share(Post post) async {
    final text = [
      post.authorName,
      if ((post.texte ?? '').isNotEmpty) post.texte!,
      if ((post.eventTitle ?? '').isNotEmpty) post.eventTitle!,
    ].join(' — ');
    await Clipboard.setData(ClipboardData(text: text));
    _toast('Publication copiée — colle-la où tu veux');
  }

  // ── Appel ──────────────────────────────────────────────

  void _call(Post post) {
    final phone = post.authorPhone;
    if (phone == null) return;
    showCallModeSheet(context, phone,
        name: post.authorName, avatar: post.authorAvatar);
  }

  // ── Publication ────────────────────────────────────────

  Future<void> _openCreate() async {
    HapticFeedback.mediumImpact();
    final draft = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateSheet(),
    );
    if (draft == null) return;
    await _publish(draft);
  }

  Future<void> _publish(Map draft) async {
    try {
      if (draft['type'] == 'event') {
        _toast('Publication de l’événement…');
      }
      final post = await _api.createPost(
        type: postTypeFrom(draft['type']),
        texte: draft['texte'] as String?,
        mediaUrl: draft['media_url'] as String?,
        eventTitle: draft['event_title'] as String?,
        eventDate: draft['event_date'] as DateTime?,
        eventLieu: draft['event_lieu'] as String?,
        eventTags: (draft['event_tags'] as List?)?.cast<String>() ?? const [],
        visibilite: postVisibiliteFrom(draft['visibilite'] ?? 'contacts'),
        ville: draft['ville'] as String?,
      );
      if (!mounted) return;
      setState(() => _posts = [post, ..._posts]);
      _scrollToTop();
      _toast('Publication en ligne 🎉');
    } catch (e) {
      if (!mounted) return;
      _toast(friendlyError(e));
    }
  }

  void _scrollToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  // ── Statuts ────────────────────────────────────────────

  Future<void> _onMyStory(StoryGroup? mine) async {
    if (mine != null) {
      await _openStoryViewer(mine);
    } else {
      await _addStory();
    }
  }

  Future<void> _addStory() async {
    final picker = ImagePicker();
    final file =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;
    try {
      _toast('Envoi du statut…');
      final url = await _api.uploadMedia(file.path);
      await _api.postStory(mediaUrl: url);
      await _refresh();
      _toast('Statut publié — visible 24 h');
    } catch (e) {
      if (!mounted) return;
      _toast(friendlyError(e));
    }
  }

  Future<void> _openStoryViewer(StoryGroup group) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _StoryViewer(
          group: group,
          api: _api,
          onSeen: (storyId) {
            setState(() {
              _groups = [
                for (final g in _groups)
                  StoryGroup(
                    userId: g.userId,
                    authorName: g.authorName,
                    avatar: g.avatar,
                    isMe: g.isMe,
                    stories: [
                      for (final s in g.stories)
                        if (s.id == storyId) s.copyWith(seen: true) else s,
                    ],
                  ),
              ];
            });
          },
        ),
      ),
    );
  }

  // ── Interface ──────────────────────────────────────────

  List<Post> get _visible {
    if (_query.trim().isEmpty) return _posts;
    final q = _query.toLowerCase();
    return _posts
        .where((p) =>
            p.texte?.toLowerCase().contains(q) == true ||
            p.authorName.toLowerCase().contains(q) ||
            p.eventTitle?.toLowerCase().contains(q) == true ||
            p.ville?.toLowerCase().contains(q) == true)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final posts = _visible;
    return Scaffold(
      backgroundColor: MC.nuit,
      floatingActionButton: _Fab(onTap: _openCreate),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: MC.soleil,
        backgroundColor: MC.nuit2,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _FeedAppBar(
              dataSaver: _dataSaver,
              searching: _searching,
              searchController: _search,
              onToggleDataSaver: () => setState(() => _dataSaver = !_dataSaver),
              onToggleSearch: () {
                setState(() {
                  _searching = !_searching;
                  if (!_searching) {
                    _search.clear();
                    _query = '';
                  }
                });
              },
              onQuery: (v) => setState(() => _query = v),
            ),

            // Bande de statuts
            if (!_searching)
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                      child: Text(
                        'STATUTS',
                        style: TextStyle(
                          color: MC.kaki,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    StoryBar(
                      groups: _groups,
                      myAvatar: _myAvatar,
                      onGroupTap: _openStoryViewer,
                      onMyTap: _onMyStory,
                    ),
                    Divider(
                        height: 1, color: MC.ligne, indent: 12, endIndent: 12),
                    const SizedBox(height: 4),
                  ],
                ),
              ),

            // Contenu
            if (_loading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(
                      color: MC.soleil, strokeWidth: 2),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ErrorState(message: _error!, onRetry: _load),
              )
            else if (posts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  searching: _query.trim().isNotEmpty,
                  onCreate: _openCreate,
                ),
              )
            else
              SliverList.separated(
                itemCount: posts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (context, i) {
                  final post = posts[i];
                  return PostCard(
                    post: post,
                    dataSaverMode: _dataSaver,
                    onCall: post.canCall ? () => _call(post) : null,
                    onLike: () => _toggleLike(post),
                    onComment: () => _openComments(post),
                    onShare: () => _share(post),
                  );
                },
              ),

            // Pied de liste : chargement de la page suivante
            if (_loadingMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: MC.soleil, strokeWidth: 2),
                    ),
                  ),
                ),
              )
            else if (!_loading &&
                _error == null &&
                _nextCursor == null &&
                posts.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'Tu es à jour 🌞',
                      style: TextStyle(color: MC.kaki, fontSize: 12),
                    ),
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        ),
      ),
    );
  }

  String? get _myAvatar {
    try {
      return context.read<AppState>().avatar;
    } catch (_) {
      return null;
    }
  }
}

// ──────────────────────────────────────────────
// Barre du haut
// ──────────────────────────────────────────────

class _FeedAppBar extends StatelessWidget {
  final bool dataSaver;
  final bool searching;
  final TextEditingController searchController;
  final VoidCallback onToggleDataSaver;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onQuery;

  const _FeedAppBar({
    required this.dataSaver,
    required this.searching,
    required this.searchController,
    required this.onToggleDataSaver,
    required this.onToggleSearch,
    required this.onQuery,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: MC.nuit.withValues(alpha: .97),
      elevation: 0,
      scrolledUnderElevation: 0,
      title: searching
          ? TextField(
              controller: searchController,
              autofocus: true,
              onChanged: onQuery,
              style: TextStyle(color: MC.ivoire, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Rechercher dans le fil…',
                hintStyle: TextStyle(color: MC.kaki, fontSize: 14),
                border: InputBorder.none,
              ),
            )
          : Text(
              'Mbote',
              style: TextStyle(
                color: MC.soleil,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -.5,
              ),
            ),
      actions: [
        if (dataSaver)
          Container(
            margin: const EdgeInsets.only(right: 3),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: MC.soleil.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
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
            searching ? Icons.close_rounded : Icons.search_rounded,
            color: searching ? MC.soleil : MC.kaki,
            size: 21,
          ),
          tooltip: searching ? 'Fermer la recherche' : 'Rechercher',
          onPressed: onToggleSearch,
        ),
        IconButton(
          icon: Icon(
            dataSaver
                ? Icons.data_saver_on_rounded
                : Icons.data_saver_off_rounded,
            color: dataSaver ? MC.soleil : MC.kaki,
            size: 20,
          ),
          tooltip: dataSaver ? 'Mode éco actif' : 'Activer le mode éco data',
          onPressed: onToggleDataSaver,
        ),
        const SizedBox(width: 6),
      ],
    );
  }
}

// ──────────────────────────────────────────────
// États vide / erreur
// ──────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool searching;
  final VoidCallback onCreate;
  const _EmptyState({required this.searching, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off_rounded : Icons.wb_sunny_rounded,
              size: 46,
              color: MC.kaki,
            ),
            const SizedBox(height: 14),
            Text(
              searching
                  ? 'Aucun résultat dans ce fil.'
                  : 'Le fil est encore vide par ici.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: MC.ivoire, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              searching
                  ? 'Essaie un autre mot.'
                  : 'Publie une photo, une pensée ou un événement — tes contacts le verront.',
              textAlign: TextAlign.center,
              style: TextStyle(color: MC.kaki, fontSize: 12.5, height: 1.4),
            ),
            if (!searching) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: MC.soleil,
                  foregroundColor: MC.nuit,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Publier quelque chose'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 46, color: MC.kaki),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: MC.ivoire, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: MC.soleil,
                side: BorderSide(color: MC.soleil.withValues(alpha: .6)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Bouton de création
// ──────────────────────────────────────────────

class _Fab extends StatelessWidget {
  final VoidCallback onTap;
  const _Fab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Publier',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: MC.degrade,
            boxShadow: [
              BoxShadow(
                color: MC.soleil.withValues(alpha: .28),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(Icons.add_rounded, color: MC.nuit, size: 30),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Feuille de commentaires
// ──────────────────────────────────────────────

class _CommentsSheet extends StatefulWidget {
  final Api api;
  final Post post;
  const _CommentsSheet({required this.api, required this.post});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final TextEditingController _input = TextEditingController();
  List<Map> _comments = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.postComments(widget.post.id);
      if (!mounted) return;
      setState(() {
        _comments = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _send() async {
    final texte = _input.text.trim();
    if (texte.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final c = await widget.api.addComment(widget.post.id, texte);
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, c];
        _sending = false;
        _input.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * .72,
      decoration: BoxDecoration(
        color: MC.nuit2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: MC.nuit3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Commentaires',
                  style: TextStyle(
                    color: MC.ivoire,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_comments.length}',
                  style: TextStyle(color: MC.kaki, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                        color: MC.soleil, strokeWidth: 2))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: MC.sable, fontSize: 13),
                          ),
                        ),
                      )
                    : _comments.isEmpty
                        ? Center(
                            child: Text(
                              'Aucun commentaire — sois le premier.',
                              style: TextStyle(color: MC.kaki, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _comments.length,
                            itemBuilder: (_, i) {
                              final c = _comments[i];
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 15,
                                      backgroundColor: MC.nuit3,
                                      child: Text(
                                        (c['author_name'] ?? '?')
                                            .toString()
                                            .characters
                                            .first
                                            .toUpperCase(),
                                        style: TextStyle(
                                          color: MC.soleil,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (c['author_name'] ?? 'Compte Mbote')
                                                .toString(),
                                            style: TextStyle(
                                              color: MC.ivoire,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            (c['texte'] ?? '').toString(),
                                            style: TextStyle(
                                                color: MC.sable,
                                                fontSize: 13,
                                                height: 1.35),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottom),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: TextStyle(color: MC.ivoire, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Écrire un commentaire…',
                        hintStyle: TextStyle(color: MC.kaki, fontSize: 13),
                        filled: true,
                        fillColor: MC.nuit3,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: MC.soleil,
                      foregroundColor: MC.nuit,
                    ),
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _comments.length),
                    child: Text('Fermer', style: TextStyle(color: MC.kaki)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Feuille de publication
// ──────────────────────────────────────────────

class _CreateSheet extends StatefulWidget {
  const _CreateSheet();

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  final TextEditingController _texte = TextEditingController();
  final TextEditingController _titre = TextEditingController();
  final TextEditingController _lieu = TextEditingController();
  final TextEditingController _tags = TextEditingController();

  String _type = 'texte';
  String _visibilite = 'contacts';
  String? _mediaUrl;
  String? _ville;
  DateTime? _eventDate;
  bool _uploading = false;

  @override
  void dispose() {
    _texte.dispose();
    _titre.dispose();
    _lieu.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 72,
        maxWidth: 1600,
      );
      if (file == null || !mounted) return;
      setState(() => _uploading = true);
      // On envoie la photo au serveur ; l'URL publique sera stockée dans le post.
      final url = await _apiUpload(file);
      if (!mounted) return;
      setState(() {
        _mediaUrl = url;
        _uploading = false;
        _type = 'photo';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<String> _apiUpload(XFile file) async {
    final api = context.read<AppState>().api;
    return api.uploadMedia(file.path);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
      locale: const Locale('fr'),
    );
    if (picked == null) return;
    setState(
        () => _eventDate = DateTime(picked.year, picked.month, picked.day, 18));
  }

  bool get _canPublish {
    if (_uploading) return false;
    return switch (_type) {
      'texte' => _texte.text.trim().isNotEmpty,
      'photo' => _mediaUrl != null,
      'event' => _titre.text.trim().isNotEmpty,
      _ => false,
    };
  }

  void _submit() {
    if (!_canPublish) return;
    Navigator.pop(context, {
      'type': _type,
      'texte': _texte.text.trim(),
      'media_url': _mediaUrl,
      'event_title': _titre.text.trim(),
      'event_date': _eventDate,
      'event_lieu': _lieu.text.trim(),
      'event_tags': _tags.text
          .split(RegExp(r'[,\s]+'))
          .map((e) => e.replaceAll('#', '').trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      'visibilite': _visibilite,
      'ville': _ville,
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: MC.nuit2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: MC.nuit3,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Publier',
                style: TextStyle(
                  color: MC.ivoire,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              // Type
              Row(
                children: [
                  _TypeChip(
                    label: 'Texte',
                    icon: Icons.edit_rounded,
                    active: _type == 'texte',
                    onTap: () => setState(() => _type = 'texte'),
                  ),
                  const SizedBox(width: 8),
                  _TypeChip(
                    label: 'Photo',
                    icon: Icons.image_rounded,
                    active: _type == 'photo',
                    onTap: () => setState(() => _type = 'photo'),
                  ),
                  const SizedBox(width: 8),
                  _TypeChip(
                    label: 'Événement',
                    icon: Icons.event_rounded,
                    active: _type == 'event',
                    onTap: () => setState(() => _type = 'event'),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Photo
              if (_type == 'photo') ...[
                if (_mediaUrl == null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MC.soleil,
                      side: BorderSide(color: MC.soleil.withValues(alpha: .5)),
                    ),
                    onPressed: _uploading ? null : _pickImage,
                    icon: _uploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_photo_alternate_rounded,
                            size: 18),
                    label: Text(_uploading ? 'Envoi…' : 'Choisir une photo'),
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        Image.network(
                          _mediaUrl!,
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 150,
                            color: MC.nuit3,
                            child: Center(
                              child: Text('Aperçu indisponible',
                                  style:
                                      TextStyle(color: MC.kaki, fontSize: 12)),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor:
                                  Colors.black.withValues(alpha: .55),
                            ),
                            onPressed: () => setState(() => _mediaUrl = null),
                            icon: Icon(Icons.close_rounded,
                                size: 16, color: MC.ivoire),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
              ],

              // Événement
              if (_type == 'event') ...[
                _Field(controller: _titre, hint: 'Titre de l’événement'),
                const SizedBox(height: 10),
                _Field(controller: _lieu, hint: 'Lieu (ex. Palais du Peuple)'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MC.soleil,
                        side:
                            BorderSide(color: MC.soleil.withValues(alpha: .5)),
                      ),
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_rounded, size: 16),
                      label: Text(
                        _eventDate == null
                            ? 'Choisir une date'
                            : '${_eventDate!.day}/${_eventDate!.month}/${_eventDate!.year}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _Field(controller: _tags, hint: 'Mots-clés (ex. musique, kin)'),
                const SizedBox(height: 12),
              ],

              // Texte
              _Field(
                controller: _texte,
                hint: _type == 'event'
                    ? 'Description (facultatif)'
                    : 'Quoi de neuf ?',
                maxLines: 4,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              _Field(
                controller: TextEditingController(text: _ville ?? ''),
                hint: 'Ville (facultatif)',
                onChanged: (v) => _ville = v.trim().isEmpty ? null : v.trim(),
              ),
              const SizedBox(height: 12),

              // Visibilité
              Row(
                children: [
                  Text('Visible par :',
                      style: TextStyle(color: MC.kaki, fontSize: 12)),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _visibilite,
                    dropdownColor: MC.nuit3,
                    underline: const SizedBox.shrink(),
                    style: TextStyle(color: MC.ivoire, fontSize: 13),
                    items: const [
                      DropdownMenuItem(
                          value: 'contacts', child: Text('Mes contacts')),
                      DropdownMenuItem(
                          value: 'communauté', child: Text('La communauté')),
                      DropdownMenuItem(
                          value: 'public', child: Text('Tout le monde')),
                    ],
                    onChanged: (v) =>
                        setState(() => _visibilite = v ?? 'contacts'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: MC.soleil,
                    foregroundColor: MC.nuit,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    disabledBackgroundColor: MC.nuit3,
                  ),
                  onPressed: _canPublish ? _submit : null,
                  child: const Text(
                    'Publier',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? MC.soleil.withValues(alpha: .18) : MC.nuit3,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? MC.soleil : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? MC.soleil : MC.kaki),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? MC.soleil : MC.kaki,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const _Field({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      style: TextStyle(color: MC.ivoire, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: MC.kaki, fontSize: 13),
        filled: true,
        fillColor: MC.nuit3,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Visionneuse de statuts
// ──────────────────────────────────────────────

class _StoryViewer extends StatefulWidget {
  final StoryGroup group;
  final Api api;
  final void Function(String storyId) onSeen;

  const _StoryViewer({
    required this.group,
    required this.api,
    required this.onSeen,
  });

  @override
  State<_StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<_StoryViewer> {
  int _index = 0;
  final Set<String> _marked = {};

  @override
  void initState() {
    super.initState();
    _mark(0);
  }

  void _mark(int i) {
    if (i < 0 || i >= widget.group.stories.length) return;
    final s = widget.group.stories[i];
    if (_marked.contains(s.id)) return;
    _marked.add(s.id);
    widget.onSeen(s.id);
    widget.api.markStorySeen(s.id).catchError((_) {});
  }

  void _next() {
    if (_index + 1 >= widget.group.stories.length) {
      Navigator.pop(context);
      return;
    }
    setState(() => _index++);
    _mark(_index);
  }

  void _prev() {
    if (_index == 0) return;
    setState(() => _index--);
  }

  @override
  Widget build(BuildContext context) {
    final stories = widget.group.stories;
    final story = stories[_index.clamp(0, stories.length - 1)];
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          if (d.localPosition.dx < w / 3) {
            _prev();
          } else {
            _next();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (story.mediaUrl != null)
              Image.network(
                story.mediaUrl!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Center(
                  child: Text('Statut indisponible',
                      style: TextStyle(color: MC.kaki, fontSize: 13)),
                ),
              )
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    story.texte ?? '',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: MC.ivoire, fontSize: 18, height: 1.5),
                  ),
                ),
              ),
            // Barres de progression
            Positioned(
              top: 44,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  for (var i = 0; i < stories.length; i++)
                    Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i <= _index
                              ? MC.soleil
                              : MC.ivoire.withValues(alpha: .3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Auteur + fermeture
            Positioned(
              top: 56,
              left: 12,
              right: 8,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: MC.nuit3,
                    backgroundImage: (widget.group.avatar != null &&
                            widget.group.avatar!.isNotEmpty)
                        ? NetworkImage(widget.group.avatar!)
                        : null,
                    child: (widget.group.avatar == null ||
                            widget.group.avatar!.isEmpty)
                        ? Text(
                            widget.group.authorName.isEmpty
                                ? '?'
                                : widget.group.authorName[0].toUpperCase(),
                            style: TextStyle(
                                color: MC.soleil,
                                fontSize: 13,
                                fontWeight: FontWeight.w700),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.group.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: 14,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: MC.ivoire, size: 22),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
