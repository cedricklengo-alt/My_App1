// lib/screens/feed_screen.dart
// Onglet « Accueil » : fil de publication branché sur le backend.
//
// Tout est réel : lecture paginée de `GET /api/feed`, statuts 24 h, j'aime,
// commentaires, publication (texte / photo / événement) et envoi de photo.
// Les états chargement / erreur / vide / fin de liste sont gérés, et
// l'API est injectable (`FeedScreen(api: …)`) pour les tests.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../config.dart';
import '../models/post.dart';
import '../state.dart';
import '../tabs.dart';
import '../design.dart';
import '../l10n.dart';
import '../liens.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/feed/media_view.dart';
import '../widgets/feed/post_card.dart';
import '../widgets/feed/story_bar.dart';
import 'call_sheet.dart';

/// Les trois lectures du fil. Elles n'inventent rien : chacune interroge une
/// route différente du serveur, qui applique lui-même les règles de visibilité.
enum _Onglet { pourToi, abonnements, tendances }

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

  // ── Fil public : trois façons de lire les mêmes publications ─────────────
  //   pourToi     : tout ce que j'ai le droit de voir, du plus récent au plus ancien
  //   abonnements : les auteurs que je suis
  //   tendances   : la découverte publique, classée par intérêt
  _Onglet _onglet = _Onglet.pourToi;

  /// Mot-clé en cours de consultation (onglet Tendances).
  String? _tagFiltre;

  /// Curseur de la découverte (classement par intérêt → pagination par décalage).
  int? _nextOffset;

  /// Publications dont j'ai déjà annoncé la vue au serveur, pour ne pas
  /// marteler l'API à chaque reconstruction de la liste.
  final Set<String> _vuesAnnoncees = {};

  /// Vrai quand une de MES publications est encore limitée à mes contacts :
  /// on propose alors de l'ouvrir à tout le monde (aucun changement sans accord).
  bool _aDesPublicationsRestreintes = false;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? context.read<AppState>().api;
    _scroll.addListener(_onScroll);
    Tabs.listen(Tabs.feed, _onTabRefresh);
    //Lien partagé ouvert depuis l'extérieur : mbote://post/<id>
    Liens.post.addListener(_surLienPartage);
    _load();
    _surLienPartage();
  }

  @override
  void dispose() {
    Liens.post.removeListener(_surLienPartage);
    Tabs.stopListening(Tabs.feed, _onTabRefresh);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Re-tap sur l'onglet Accueil → on remonte en haut et on recharge.
  void _onTabRefresh() {
    if (!mounted) return;
    if (_scroll.hasClients && _scroll.offset > 0) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
    _refresh();
  }

 // Chargement ────────────────────────────────────────

  /// Lit la première page de l'onglet courant.
  Future<FeedPage> _lirePremierePage() {
    switch (_onglet) {
      case _Onglet.abonnements:
        return _api.followingPage();
      case _Onglet.tendances:
        return _api.discoverPage(tag: _tagFiltre);
      case _Onglet.pourToi:
        return _api.feedPage();
    }
  }

  /// Lit la page suivante de l'onglet courant.
  Future<FeedPage> _lirePageSuivante() {
    switch (_onglet) {
      case _Onglet.abonnements:
        return _api.followingPage(before: _nextBefore, cursor: _nextCursor);
      case _Onglet.tendances:
        return _api.discoverPage(tag: _tagFiltre, offset: _nextOffset);
      case _Onglet.pourToi:
        return _api.feedPage(before: _nextBefore, cursor: _nextCursor);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _lirePremierePage();
      final stories = await _api.feedStories();
      if (!mounted) return;
      setState(() {
        _posts = page.posts;
        _nextBefore = page.nextBefore;
        _nextCursor = page.nextCursor;
        _nextOffset = page.nextOffset;
        _groups = StoryGroup.group(stories, myUserId: _myId);
        _loading = false;
        _majBandeauAudience();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  /// Change d'onglet : on repart de la première page.
  void _changerOnglet(_Onglet o) {
    if (_onglet == o && _tagFiltre == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _onglet = o;
      _tagFiltre = null;
      _nextBefore = null;
      _nextCursor = null;
      _nextOffset = null;
      _posts = const [];
      _vuesAnnoncees.clear();
    });
    _load();
  }

  /// Affiche (ou masque) le rappel « tes publications sont limitées ».
  void _majBandeauAudience() {
    _aDesPublicationsRestreintes = _posts.any(
        (p) => (p.aMoi || p.authorId == _myId) && p.visibilite == PostVisibilite.contacts);
  }

  /// Ouvre TOUTES mes publications à tout le monde (action explicite).
  Future<void> _ouvrirMesPublications() async {
    try {
      final r = await _api.setAllPostsVisibility(PostVisibilite.public);
      if (!mounted) return;
      _toast('${r['publications'] ?? 0} publication(s) désormais visibles par tous');
      await _refresh();
      setState(() => _aDesPublicationsRestreintes = false);
    } catch (e) {
      if (!mounted) return;
      _toast(friendlyError(e));
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
      final page = await _lirePremierePage();
      final stories = await _api.feedStories();
      if (!mounted) return;
      setState(() {
        _posts = page.posts;
        _nextBefore = page.nextBefore;
        _nextCursor = page.nextCursor;
        _nextOffset = page.nextOffset;
        _groups = StoryGroup.group(stories, myUserId: _myId);
        _error = null;
        _majBandeauAudience();
      });
    } catch (e) {
      if (!mounted) return;
      _toast(friendlyError(e));
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    if (_onglet == _Onglet.tendances
        ? _nextOffset == null
        : _nextCursor == null) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final page = await _lirePageSuivante();
      if (!mounted) return;
      final seen = _posts.map((p) => p.id).toSet();
      setState(() {
        _posts = [..._posts, ...page.posts.where((p) => !seen.contains(p.id))];
        _nextBefore = page.nextBefore;
        _nextCursor = page.nextCursor;
        _nextOffset = page.nextOffset;
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

  // Compter une vue ───────────────────────────────────

  /// Annonce au serveur que cette publication a été lue. Le serveur ne compte
  /// qu'une fois par personne et ignore l'auteur ; l'application se contente
  /// donc d'afficher le chiffre qu'il renvoie.
  void _annoncerVue(Post post) {
    if (post.aMoi || post.authorId == _myId) return;
    if (!_vuesAnnoncees.add(post.id)) return;
    _api.viewPost(post.id).then((r) {
      if (!mounted) return;
      final n = (r['vues'] as num?)?.toInt();
      if (n == null) return;
      final i = _posts.indexWhere((p) => p.id == post.id);
      if (i == -1) return;
      setState(() => _posts[i] = _posts[i].copyWith(vues: n));
    }).catchError((_) {/* le compteur n'est pas vital */});
  }

  // Abonnements ───────────────────────────────────────

  /// Suivre / ne plus suivre l'auteur d'une publication.
  Future<void> _basculerSuivi(Post post) async {
    HapticFeedback.selectionClick();
    final suivre = !post.suivi;
    // Optimiste : toutes ses publications affichées passent à « suivi ».
    setState(() {
      _posts = [
        for (final p in _posts)
          if (p.authorId == post.authorId) p.copyWith(suivi: suivre) else p,
      ];
    });
    try {
      final r = suivre
          ? await _api.followAuthor(post.authorId)
          : await _api.unfollowAuthor(post.authorId);
      if (!mounted) return;
      final suivi = r['suivi'] == true;
      setState(() {
        _posts = [
          for (final p in _posts)
            if (p.authorId == post.authorId) p.copyWith(suivi: suivi) else p,
        ];
      });
      _toast(suivi
          ? 'Tu suis ${post.authorName}'
          : 'Tu ne suis plus ${post.authorName}');
    } catch (e) {
      if (!mounted) return;
      // On remet l'état d'avant : le serveur est la seule vérité.
      setState(() {
        _posts = [
          for (final p in _posts)
            if (p.authorId == post.authorId) p.copyWith(suivi: !suivre)
            else p,
        ];
      });
      _toast(friendlyError(e));
    }
  }

  // Mots-clés ─────────────────────────────────────────

  /// Ouvre la découverte filtrée sur un mot-clé.
  void _ouvrirTag(String tag) {
    setState(() {
      _onglet = _Onglet.tendances;
      _tagFiltre = tag;
      _nextBefore = null;
      _nextCursor = null;
      _nextOffset = null;
      _posts = const [];
      _vuesAnnoncees.clear();
    });
    _load();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

 // J'aime ────────────────────────────────────────────

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

 // Commentaires ──────────────────────────────────────

  Future<void> _openComments(Post post) async {
    final count = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(api: _api, post: post),
    );
    if (count != null) _replace(post.copyWith(comments: count));
  }

 // Partage ───────────────────────────────────────────

  /// Un lien partagé (`mbote://post/<id>`) ramène ici : on charge la
  /// publication et on l'affiche par-dessus le fil, sans perdre sa place.
  Future<void> _surLienPartage() async {
    final id = Liens.post.value;
    if (id == null || !mounted) return;
    Liens.post.value = null;

    try {
      final post = await _api.lirePublication(id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _PublicationPartagee(
          post: post,
          myId: _myId,
          dataSaver: _dataSaver,
          onLike: () {
            Navigator.pop(context);
            _toggleLike(post);
          },
          onComment: () {
            Navigator.pop(context);
            _openComments(post);
          },
          onShare: () => _share(post),
          onCall: (!post.aMoi && post.canCall) ? () => _call(post) : null,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _toast('Publication indisponible ou réservée à ses contacts');
    }
  }

  /// Lien de la publication : celui fourni par le serveur, sinon reconstruit
  /// depuis l'adresse de l'API (le serveur ne fournit `share_url` que s'il
  /// connaît sa propre adresse publique).
  String _lienDe(Post post) {
    final fourni = post.partageUrl;
    if (fourni != null && fourni.isNotEmpty) return fourni;
    final base = Config.apiBase.replaceAll(RegExp(r'/api/?$'), '');
    return '$base/p/${post.id}';
  }

  /// Texte prêt à coller dans une conversation : ce qui donne envie d'ouvrir,
  /// puis le lien. C'est la forme qu'attendent WhatsApp et compagnie.
  String _textePartage(Post post) {
    final contenu = (post.texte ?? post.eventTitle ?? '').trim();
    final morceau = contenu.length > 220 ? '${contenu.substring(0, 220)}…' : contenu;
    return [
      '${post.authorName} sur MboteCall',
      if (morceau.isNotEmpty) morceau,
      _lienDe(post),
    ].join('\n');
  }

  /// PARTAGE — le cycle complet, comme dans les autres applications sociales :
  ///   1. copier le lien (pour le coller où l'on veut) ;
  ///   2. envoyer vers une autre application (WhatsApp, SMS, e-mail…).
  /// Chaque envoi réel incrémente le compteur côté serveur.
  Future<void> _share(Post post) async {
    HapticFeedback.selectionClick();
    final choix = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeuillePartage(
        post: post,
        lien: _lienDe(post),
        onCopier: () => Navigator.pop(context, 'copier'),
        onPartager: () => Navigator.pop(context, 'partager'),
      ),
    );
    if (choix == null || !mounted) return;

    if (choix == 'copier') {
      // Le presse-papiers peut être refusé par certains appareils : on informe
      // quand même l'utilisateur, le lien restant affiché dans la feuille.
      try {
        await Clipboard.setData(ClipboardData(text: _textePartage(post)));
      } catch (_) {/* presse-papiers indisponible */}
      if (!mounted) return;
      _toast('Lien copié — colle-le où tu veux');
      _compterPartage(post);
      return;
    }

    if (choix == 'partager') {
      try {
        await Share.share(_textePartage(post), subject: 'Publication MboteCall');
        _compterPartage(post);
      } catch (e) {
        if (!mounted) return;
        _toast('Partage impossible sur cet appareil');
      }
    }
  }

  /// Enregistre le partage côté serveur (sans bloquer l'utilisateur).
  void _compterPartage(Post post) {
    _api.markShared(post.id).then((r) {
      if (!mounted) return;
      final n = (r['partages'] as num?)?.toInt();
      if (n == null) return;
      final i = _posts.indexWhere((p) => p.id == post.id);
      if (i == -1) return;
      setState(() => _posts[i] = _posts[i].copyWith(partages: n));
    }).catchError((_) {/* le compteur n'est pas vital */});
  }

 // Appel ─────────────────────────────────────────────

  void _call(Post post) {
    final phone = post.authorPhone;
    if (phone == null) return;
    showCallModeSheet(context, phone,
        name: post.authorName, avatar: post.authorAvatar);
  }

 // Suppression ───────────────────────────────────────

  ///Demande confirmation puis supprime la publication.
  /// L'élément disparaît de la liste **tout de suite** ; si le serveur refuse,
  /// il est remis à sa place (aucune perte silencieuse).
  Future<void> _confirmDelete(Post post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.nuit2,
        title: Text('Supprimer la publication ?',
            style: TextStyle(color: MC.ivoire, fontSize: Tx.subtitle)),
        content: Text(
          'Elle disparaîtra du fil pour tout le monde. Cette action est '
          'définitive.',
          style: TextStyle(color: MC.sable, fontSize: Tx.label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Annuler', style: TextStyle(color: MC.kaki)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Supprimer',
                style: TextStyle(color: MC.rouge, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final index = _posts.indexWhere((p) => p.id == post.id);
    if (index == -1) return;
    setState(() => _posts.removeAt(index)); //retrait immédiat
    try {
      await _api.deletePost(post.id);
      _toast('Publication supprimée');
    } catch (e) {
      if (!mounted) return;
      setState(() => _posts.insert(index, post)); // ↩remise en place
      _toast(friendlyError(e));
    }
  }

  ///Supprime un de mes statuts (confirmation incluse).
  Future<bool> _confirmDeleteStory(Story story) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.nuit2,
        title: Text('Supprimer ce statut ?',
            style: TextStyle(color: MC.ivoire, fontSize: Tx.subtitle)),
        content: Text('Il ne sera plus visible par personne.',
            style: TextStyle(color: MC.sable, fontSize: Tx.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Annuler', style: TextStyle(color: MC.kaki)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Supprimer',
                style: TextStyle(color: MC.rouge, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      await _api.deleteStory(story.id);
      _toast('Statut supprimé');
      return true;
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
      return false;
    }
  }

 // Publication ───────────────────────────────────────

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
        clipDureeSeconds: draft['clip_duree_seconds'] as int?,
        eventTitle: draft['event_title'] as String?,
        eventDate: draft['event_date'] as DateTime?,
        eventLieu: draft['event_lieu'] as String?,
        eventTags: (draft['event_tags'] as List?)?.cast<String>() ?? const [],
        thumbUrl: draft['thumb_url'] as String?,
        visibilite: postVisibiliteFrom(draft['visibilite'] ?? 'public'),
        ville: draft['ville'] as String?,
      );
      if (!mounted) return;
      setState(() => _posts = [post, ..._posts]);
      _scrollToTop();
      _toast('Publication en ligne');
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

 // Statuts ───────────────────────────────────────────

  Future<void> _onMyStory(StoryGroup? mine) async {
    if (mine != null) {
      await _openStoryViewer(mine);
    } else {
      await _addStory();
    }
  }

  ///Nouveau statut : photo, courte vidéo ou texte.
  Future<void> _addStory() async {
    final choix = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MC.nuit2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
              child: Row(
                children: [
                  Text('Nouveau statut',
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.subtitle,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            _StoryOption(
              icon: Icons.photo_camera_rounded,
              label: 'Photo',
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            _StoryOption(
              icon: Icons.videocam_rounded,
              label: 'Vidéo courte (60 s max)',
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            _StoryOption(
              icon: Icons.text_fields_rounded,
              label: 'Texte',
              onTap: () => Navigator.pop(ctx, 'texte'),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (choix == null || !mounted) return;

    if (choix == 'texte') {
      await _addTextStory();
      return;
    }

    final picker = ImagePicker();
    XFile? file;
    try {
      file = choix == 'video'
          ? await picker.pickVideo(
              source: ImageSource.gallery,
              maxDuration: const Duration(seconds: 60))
          : await picker.pickImage(
              source: ImageSource.gallery, imageQuality: 80);
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
      return;
    }
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

  ///Statut texte seul (sans photo) — accepté par le serveur depuis la v3.6.
  Future<void> _addTextStory() async {
    final ctrl = TextEditingController();
    final texte = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.nuit2,
        title: Text('Statut texte',
            style: TextStyle(color: MC.ivoire, fontSize: Tx.subtitle)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 300,
          maxLines: 4,
          style: TextStyle(color: MC.ivoire),
          decoration: InputDecoration(
            hintText: 'Quoi de neuf ?',
            hintStyle: TextStyle(color: MC.kaki),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Annuler', style: TextStyle(color: MC.kaki))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Publier',
                style:
                    TextStyle(color: MC.soleil, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (texte == null || texte.isEmpty || !mounted) return;
    try {
      await _api.postStory(texte: texte);
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
          //Suppression possible seulement sur mes propres statuts.
          onDelete: group.isMe ? _confirmDeleteStory : null,
          onDeleted: (storyId) {
            if (!mounted) return;
            setState(() {
              _groups = [
                for (final g in _groups)
                  if (g.userId != group.userId)
                    g
                  else if (g.stories.any((s) => s.id != storyId))
                    StoryGroup(
                      userId: g.userId,
                      authorName: g.authorName,
                      avatar: g.avatar,
                      isMe: g.isMe,
                      stories: [
                        for (final s in g.stories)
                          if (s.id != storyId) s,
                      ],
                    ),
              ];
            });
          },
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

 // Interface ─────────────────────────────────────────

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

            // Choix de lecture : tout · abonnements · tendances
            if (!_searching)
              SliverToBoxAdapter(
                child: _OngletBar(
                  onglet: _onglet,
                  tagFiltre: _tagFiltre,
                  onChoix: _changerOnglet,
                  onEffacerTag: () => _changerOnglet(_Onglet.tendances),
                ),
              ),

            // Rappel : mes anciennes publications sont encore limitées
            if (!_searching && _aDesPublicationsRestreintes)
              SliverToBoxAdapter(
                child: _BandeauAudience(onOuvrir: _ouvrirMesPublications),
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
                          fontSize: Tx.caption,
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
              const SliverToBoxAdapter(
                  child: _FeedSkeleton(key: Key('feed-skeleton')))
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
                  onglet: _onglet,
                ),
              )
            else
              SliverList.separated(
                itemCount: posts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (context, i) {
                  final post = posts[i];
                  final mine = _myId != null && post.authorId == _myId;
                  // Une publication affichée est une publication lue.
                  if (!post.aMoi && !mine) _annoncerVue(post);
                  return PostCard(
                    post: post,
                    myId: _myId,
                    dataSaverMode: _dataSaver,
                    onFollow: mine ? null : () => _basculerSuivi(post),
                    onTag: _ouvrirTag,
                    //Jamais d'appel sur sa propre publication (double
                    // sécurité : la carte le vérifie aussi).
                    onCall: (!mine && post.canCall) ? () => _call(post) : null,
                    onDelete: mine ? () => _confirmDelete(post) : null,
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
                      'Tu es à jour',
                      style: TextStyle(color: MC.kaki, fontSize: Tx.label),
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

//───────────────────────────────────────────
// Barre du haut
//───────────────────────────────────────────

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
              style: TextStyle(color: MC.ivoire, fontSize: Tx.bodyLg),
              decoration: InputDecoration(
                hintText: 'Rechercher dans le fil…',
                hintStyle: TextStyle(color: MC.kaki, fontSize: Tx.body),
                border: InputBorder.none,
              ),
            )
          : Text(
              'Mbote',
              style: TextStyle(
                color: MC.soleil,
                fontSize: Tx.headline,
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
              borderRadius: BorderRadius.circular(Rd.sm),
            ),
            child: Text(
              'Éco',
              style: TextStyle(
                color: MC.soleil,
                fontSize: Tx.caption,
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

//───────────────────────────────────────────
// États vide / erreur
//───────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool searching;
  final VoidCallback onCreate;
  final _Onglet onglet;
  const _EmptyState({
    required this.searching,
    required this.onCreate,
    this.onglet = _Onglet.pourToi,
  });

  String get _titre {
    if (searching) return 'Aucun résultat dans ce fil.';
    switch (onglet) {
      case _Onglet.abonnements:
        return 'Tu ne suis encore personne.';
      case _Onglet.tendances:
        return 'Rien à découvrir pour le moment.';
      case _Onglet.pourToi:
        return 'Le fil est encore vide par ici.';
    }
  }

  String get _detail {
    if (searching) return 'Essaie un autre mot.';
    switch (onglet) {
      case _Onglet.abonnements:
        return 'Ouvre la découverte, puis appuie sur « Suivre » : les publications de cet auteur arriveront ici.';
      case _Onglet.tendances:
        return 'Les publications publiques apparaîtront ici dès que la communauté en aura partagé.';
      case _Onglet.pourToi:
        return 'Publie une photo, une pensée ou un événement — tout le monde le verra si tu choisis « Tout le monde ».';
    }
  }

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
              _titre,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: MC.ivoire, fontSize: Tx.bodyLg, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              _detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: MC.kaki, fontSize: Tx.label, height: 1.4),
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

/// Publication ouverte depuis un lien partagé : la carte complète, comme dans
/// le fil, avec un bandeau qui rappelle d'où l'on vient.
class _PublicationPartagee extends StatelessWidget {
  final Post post;
  final String? myId;
  final bool dataSaver;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback? onCall;

  const _PublicationPartagee({
    required this.post,
    required this.myId,
    required this.dataSaver,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .72,
      minChildSize: .4,
      maxChildSize: .95,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: MC.nuit,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 10, 4),
              child: Row(
                children: [
                  Icon(Icons.link_rounded, size: 16, color: MC.soleil),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Publication partagée',
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.label,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Fermer',
                    icon: Icon(Icons.close_rounded, color: MC.kaki, size: 20),
                  ),
                ],
              ),
            ),
            PostCard(
              post: post,
              myId: myId,
              dataSaverMode: dataSaver,
              onLike: onLike,
              onComment: onComment,
              onShare: onShare,
              onCall: onCall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Feuille de partage : aperçu du lien, deux actions réelles.
///
/// Rien de décoratif : « Copier le lien » copie le texte complet (auteur,
/// extrait, lien) et « Partager vers une autre application » ouvre le partage
/// du système, donc WhatsApp, Telegram, les SMS, l'e-mail… Le lien lui-même est
/// montré en clair, ce qui permet de le lire à voix haute ou de le recopier.
class _FeuillePartage extends StatelessWidget {
  final Post post;
  final String lien;
  final VoidCallback onCopier;
  final VoidCallback onPartager;

  const _FeuillePartage({
    required this.post,
    required this.lien,
    required this.onCopier,
    required this.onPartager,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MC.nuit2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      // Défilement interne : sur un petit écran (ou en mode paysage), une
      // feuille trop haute débordait et la dernière action devenait inatteignable.
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: MC.ligne,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Partager cette publication',
            style: TextStyle(
                color: MC.ivoire, fontSize: Tx.bodyLg, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Toute personne qui reçoit le lien verra un aperçu de la publication.',
            style: TextStyle(color: MC.kaki, fontSize: Tx.caption, height: 1.35),
          ),
          const SizedBox(height: 14),

          // Le lien en clair
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: MC.nuit3,
              borderRadius: BorderRadius.circular(Rd.md),
              border: Border.all(color: MC.ligne),
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 15, color: MC.kaki),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lien,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: MC.ivoire, fontSize: Tx.caption),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          _ActionPartage(
            icon: Icons.copy_all_rounded,
            titre: 'Copier le lien',
            detail: 'Pour le coller dans une conversation ou une publication',
            onTap: onCopier,
          ),
          const SizedBox(height: 8),
          _ActionPartage(
            icon: Icons.ios_share_rounded,
            titre: 'Partager vers une autre application',
            detail: 'WhatsApp, Telegram, SMS, e-mail…',
            onTap: onPartager,
          ),
          const SizedBox(height: 6),
        ],
        ),
      ),
    );
  }
}

class _ActionPartage extends StatelessWidget {
  final IconData icon;
  final String titre;
  final String detail;
  final VoidCallback onTap;

  const _ActionPartage({
    required this.icon,
    required this.titre,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: titre,
      // GestureDetector plutôt qu'InkWell : la feuille de partage est une
      // surface transparente sans `Material` au-dessus, où l'effet d'encre ne
      // s'applique pas et où l'appui pouvait ne rien déclencher.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: MC.nuit3,
            borderRadius: BorderRadius.circular(Rd.md),
            border: Border.all(color: MC.ligne),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: MC.soleil.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(Rd.sm),
                ),
                child: Icon(icon, color: MC.soleil, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titre,
                        style: TextStyle(
                            color: MC.ivoire,
                            fontSize: Tx.label,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(detail,
                        style:
                            TextStyle(color: MC.kaki, fontSize: Tx.caption)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: MC.kaki, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barre de choix du fil : « Pour toi », « Abonnements », « Tendances ».
/// Elle indique aussi le mot-clé en cours de consultation, avec un bouton pour
/// revenir à la découverte complète.
class _OngletBar extends StatelessWidget {
  final _Onglet onglet;
  final String? tagFiltre;
  final ValueChanged<_Onglet> onChoix;
  final VoidCallback onEffacerTag;

  const _OngletBar({
    required this.onglet,
    required this.onChoix,
    required this.onEffacerTag,
    this.tagFiltre,
  });

  static const _libelles = {
    _Onglet.pourToi: 'Pour toi',
    _Onglet.abonnements: 'Abonnements',
    _Onglet.tendances: 'Tendances',
  };

  static const _icones = {
    _Onglet.pourToi: Icons.home_rounded,
    _Onglet.abonnements: Icons.people_alt_rounded,
    _Onglet.tendances: Icons.local_fire_department_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x3, Sp.x2, Sp.x3, Sp.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final o in _Onglet.values) ...[
                Expanded(
                  child: Semantics(
                    selected: onglet == o,
                    button: true,
                    label: 'Fil ${_libelles[o]}',
                    child: GestureDetector(
                      onTap: () => onChoix(o),
                      child: Container(
                        // 48 dp : cible tactile minimale exigée par Android.
                        constraints: const BoxConstraints(minHeight: 48),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 9),
                        decoration: BoxDecoration(
                          color: onglet == o ? MC.soleil : MC.nuit2,
                          borderRadius: BorderRadius.circular(Rd.lg),
                          border: Border.all(
                              color: onglet == o ? MC.soleil : MC.ligne),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _icones[o],
                              size: 14,
                              color: onglet == o ? MC.nuit : MC.kaki,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                _libelles[o]!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: onglet == o ? MC.nuit : MC.kaki,
                                  fontSize: Tx.caption,
                                  fontWeight: onglet == o
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (tagFiltre != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.tag_rounded, size: 13, color: MC.soleil),
                  const SizedBox(width: 4),
                  Text(
                    tagFiltre!,
                    style: TextStyle(
                        color: MC.soleil,
                        fontSize: Tx.caption,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onEffacerTag,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: MC.nuit3,
                        borderRadius: BorderRadius.circular(Rd.lg),
                        border: Border.all(color: MC.ligne),
                      ),
                      child: Text(
                        'Voir toute la découverte',
                        style: TextStyle(color: MC.ivoire, fontSize: Tx.caption),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Rappel d'audience : une de mes publications est encore limitée à mes
/// contacts — donc vue par presque personne. L'ouverture est proposée, jamais
/// imposée.
class _BandeauAudience extends StatelessWidget {
  final VoidCallback onOuvrir;
  const _BandeauAudience({required this.onOuvrir});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.x3, Sp.x2, Sp.x3, Sp.x1),
      padding: const EdgeInsets.all(Sp.x3),
      decoration: BoxDecoration(
        color: MC.nuit2,
        borderRadius: BorderRadius.circular(Rd.md),
        border: Border.all(color: MC.soleil.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: MC.soleil),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Tes anciennes publications sont limitées à tes contacts',
                  style: TextStyle(
                      color: MC.ivoire,
                      fontSize: Tx.label,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Seules les personnes qui ont ton numéro enregistré les voient. '
            'Tu peux les ouvrir à tout le monde en un geste.',
            style: TextStyle(color: MC.kaki, fontSize: Tx.caption, height: 1.35),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: MC.soleil,
                foregroundColor: MC.nuit,
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              onPressed: onOuvrir,
              icon: const Icon(Icons.public_rounded, size: 16),
              label: const Text(
                'Rendre mes publications visibles par tous',
                style: TextStyle(fontSize: Tx.label, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Squelette du fil : trois cartes grises pendant le premier chargement.
/// Plus rassurant qu'une roue qui tourne, et zéro saut de mise en page.
class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(
        3,
        (i) => Container(
          margin: const EdgeInsets.fromLTRB(Sp.x3, Sp.x2, Sp.x3, Sp.x1),
          padding: const EdgeInsets.all(Sp.x3),
          decoration: BoxDecoration(
              color: MC.nuit2,
              borderRadius: BorderRadius.circular(Rd.md),
              border: Border.all(color: MC.ligne)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _bar(Densite.avatar, Densite.avatar, radius: Rd.avatar),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bar(110, 10),
                      const SizedBox(height: 7),
                      _bar(70, 8),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _bar(double.infinity, 9),
              const SizedBox(height: 7),
              _bar(double.infinity, 9),
              const SizedBox(height: 7),
              _bar(160, 9),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(double w, double h, {double radius = 6}) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
            color: MC.nuit3, borderRadius: BorderRadius.circular(radius)),
      );
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
              style: TextStyle(color: MC.ivoire, fontSize: Tx.body, height: 1.4),
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

//───────────────────────────────────────────
// Bouton de création
//───────────────────────────────────────────

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

//───────────────────────────────────────────
// Feuille de commentaires
//───────────────────────────────────────────

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
                    fontSize: Tx.bodyLg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_comments.length}',
                  style: TextStyle(color: MC.kaki, fontSize: Tx.label),
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
                            style: TextStyle(color: MC.sable, fontSize: Tx.label),
                          ),
                        ),
                      )
                    : _comments.isEmpty
                        ? Center(
                            child: Text(
                              'Aucun commentaire — sois le premier.',
                              style: TextStyle(color: MC.kaki, fontSize: Tx.label),
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
                                    MboteAvatar(
                                      name: '${c['author_name'] ?? '?'}',
                                      size: 30,
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
                                              fontSize: Tx.label,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            (c['texte'] ?? '').toString(),
                                            style: TextStyle(
                                                color: MC.sable,
                                                fontSize: Tx.label,
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
                      style: TextStyle(color: MC.ivoire, fontSize: Tx.body),
                      decoration: InputDecoration(
                        hintText: 'Écrire un commentaire…',
                        hintStyle: TextStyle(color: MC.kaki, fontSize: Tx.label),
                        filled: true,
                        fillColor: MC.nuit3,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(Rd.lg),
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

//───────────────────────────────────────────
// Feuille de publication
//───────────────────────────────────────────

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
  // PAR DÉFAUT : tout le monde. Le défaut précédent (« Mes contacts ») faisait
  // qu'une publication n'était vue que par les gens qui avaient déjà l'auteur
  // dans leur répertoire — c'est-à-dire, en pratique, par personne.
  String _visibilite = 'public';
  String? _mediaUrl;

  /// Miniature de la vidéo, produite par le serveur au moment de l'envoi du
  /// fichier. On la transmet avec la publication pour que le fil affiche un
  /// aperçu immédiat, sans télécharger la vidéo.
  String? _thumbUrl;
  int? _clipSec; // durée de la vidéo, quand on publie un clip
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
      final envoi = await _apiUpload(file);
      if (!mounted) return;
      setState(() {
        _mediaUrl = envoi.url;
        _thumbUrl = envoi.thumbUrl;
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

  ///Choisit une courte vidéo (60 s max) et l'envoie.
  Future<void> _pickVideo() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 60),
      );
      if (file == null || !mounted) return;
      setState(() => _uploading = true);
      final duree = await _videoSeconds(file.path);
      final envoi = await _apiUpload(file);
      if (!mounted) return;
      setState(() {
        _mediaUrl = envoi.url;
        // 🖼️ Aperçu de la vidéo : le serveur l'a capturé pendant l'envoi.
        _thumbUrl = envoi.thumbUrl;
        _clipSec = duree;
        _uploading = false;
        _type = 'clip';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  /// Durée de la vidéo (meilleur effort) : si la lecture locale n'est pas
  /// disponible, on publie sans durée plutôt que de bloquer l'envoi.
  Future<int?> _videoSeconds(String path) async {
    VideoPlayerController? c;
    try {
      c = VideoPlayerController.file(File(path));
      await c.initialize().timeout(const Duration(seconds: 6));
      final ms = c.value.duration.inMilliseconds;
      return ms > 0 ? (ms / 1000).round() : null;
    } catch (_) {
      return null;
    } finally {
      try {
        await c?.dispose();
      } catch (_) {}
    }
  }

  Future<UploadResult> _apiUpload(XFile file) async {
    final api = context.read<AppState>().api;
    return api.uploadMediaFull(file.path);
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
      'photo' || 'clip' => _mediaUrl != null,
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
      'thumb_url': _thumbUrl,
      'clip_duree_seconds': _clipSec,
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
                  fontSize: Tx.subtitle,
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
                    label: 'Vidéo',
                    icon: Icons.videocam_rounded,
                    active: _type == 'clip',
                    onTap: () => setState(() => _type = 'clip'),
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

              // Photo / Vidéo
              if (_type == 'photo' || _type == 'clip') ...[
                // Aperçu : pour une vidéo, la miniature produite par le
                // serveur (elle existe déjà, autant la montrer tout de suite).
                if (_mediaUrl == null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MC.soleil,
                      side: BorderSide(color: MC.soleil.withValues(alpha: .5)),
                    ),
                    onPressed: _uploading
                        ? null
                        : (_type == 'clip' ? _pickVideo : _pickImage),
                    icon: _uploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(
                            _type == 'clip'
                                ? Icons.video_call_rounded
                                : Icons.add_photo_alternate_rounded,
                            size: 18),
                    label: Text(_uploading
                        ? 'Envoi…'
                        : (_type == 'clip'
                            ? 'Choisir une vidéo (60 s max)'
                            : 'Choisir une photo')),
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Rd.md),
                    child: Stack(
                      children: [
                        Image.network(
                          // Pour une vidéo, la miniature capturée par le
                          // serveur ; `Image.network` sur un MP4 échouerait.
                          (_type == 'clip' && _thumbUrl != null)
                              ? _thumbUrl!
                              : _mediaUrl!,
                          semanticLabel: _type == 'clip'
                              ? 'aperçu de la vidéo'
                              : L10n.t('photo'),
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 150,
                            color: MC.nuit3,
                            child: Center(
                              child: Text('Aperçu indisponible',
                                  style:
                                      TextStyle(color: MC.kaki, fontSize: Tx.label)),
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
                            onPressed: () => setState(() {
                              _mediaUrl = null;
                              _thumbUrl = null;
                            }),
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
                      style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _visibilite,
                    dropdownColor: MC.nuit3,
                    underline: const SizedBox.shrink(),
                    style: TextStyle(color: MC.ivoire, fontSize: Tx.label),
                    items: const [
                      DropdownMenuItem(
                          value: 'public', child: Text('Tout le monde')),
                      DropdownMenuItem(
                          value: 'communaute', child: Text('Communauté Mbote')),
                      DropdownMenuItem(
                          value: 'contacts',
                          child: Text('Mes contacts seulement')),
                    ],
                    onChanged: (v) =>
                        setState(() => _visibilite = v ?? 'public'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Dire clairement ce que chaque choix implique : c'est ce qui
              // manquait, et c'est ce qui a rendu le fil vide sans que personne
              // ne s'en aperçoive.
              Text(
                switch (_visibilite) {
                  'contacts' =>
                    'Seules les personnes qui ont ton numéro enregistré verront cette publication.',
                  'communaute' =>
                    'Tous les membres de Mbote verront cette publication, sans apparaître dans les tendances.',
                  _ => 'Tout le monde verra cette publication dans le fil et dans la découverte.',
                },
                style: TextStyle(
                    color: _visibilite == 'contacts' ? MC.soleil : MC.kaki,
                    fontSize: Tx.caption,
                    height: 1.35),
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
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: Tx.body),
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
      borderRadius: BorderRadius.circular(Rd.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? MC.soleil.withValues(alpha: .18) : MC.nuit3,
          borderRadius: BorderRadius.circular(Rd.lg),
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
                fontSize: Tx.label,
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
      style: TextStyle(color: MC.ivoire, fontSize: Tx.body),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: MC.kaki, fontSize: Tx.label),
        filled: true,
        fillColor: MC.nuit3,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rd.md),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

//───────────────────────────────────────────
// Visionneuse de statuts
//───────────────────────────────────────────

class _StoryViewer extends StatefulWidget {
  final StoryGroup group;
  final Api api;
  final void Function(String storyId) onSeen;

  /// Présent uniquement pour MES statuts : renvoie `true` si la suppression
  /// a bien été faite côté serveur.
  final Future<bool> Function(Story story)? onDelete;

  /// Prévient l'écran d'accueil qu'un statut a disparu.
  final void Function(String storyId)? onDeleted;

  const _StoryViewer({
    required this.group,
    required this.api,
    required this.onSeen,
    this.onDelete,
    this.onDeleted,
  });

  @override
  State<_StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<_StoryViewer> {
  int _index = 0;
  final Set<String> _marked = {};
  late List<Story> _stories;
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _stories = List<Story>.from(widget.group.stories);
    // Le marquage « vu » remonte au fil (onSeen) : le faire pendant initState
    // déclencherait un setState sur un parent en pleine construction. On le
    // décale d'une frame, la barre de progression démarre tout de suite.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mark(_index);
    });
    _armAutoAdvance();
  }

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  Story? get _story =>
      _stories.isEmpty ? null : _stories[_index.clamp(0, _stories.length - 1)];

  ///Les statuts photo/texte avancent seuls (5 s) ; une vidéo se termine
  /// naturellement, on ne la coupe pas au milieu.
  void _armAutoAdvance() {
    _auto?.cancel();
    final st = _story;
    if (st == null) return;
    final video = st.mediaUrl != null && isVideoUrl(st.mediaUrl);
    if (video) return;
    _auto = Timer(const Duration(seconds: 5), () {
      if (mounted) _next();
    });
  }

  void _mark(int i) {
    if (i < 0 || i >= _stories.length) return;
    final s = _stories[i];
    if (_marked.contains(s.id)) return;
    _marked.add(s.id);
    widget.onSeen(s.id);
    widget.api.markStorySeen(s.id).catchError((_) {});
  }

  void _next() {
    if (_index + 1 >= _stories.length) {
      Navigator.pop(context);
      return;
    }
    setState(() => _index++);
    _mark(_index);
    _armAutoAdvance();
  }

  void _prev() {
    if (_index == 0) return;
    setState(() => _index--);
    _armAutoAdvance();
  }

  ///Supprime le statut affiché (confirmation gérée par l'écran d'accueil).
  Future<void> _delete() async {
    final st = _story;
    final cb = widget.onDelete;
    if (st == null || cb == null) return;
    _auto?.cancel();
    final done = await cb(st);
    if (!mounted || !done) {
      _armAutoAdvance();
      return;
    }
    widget.onDeleted?.call(st.id);
    setState(() {
      _stories.removeAt(_index);
      if (_index >= _stories.length) _index = _stories.length - 1;
    });
    if (_stories.isEmpty) {
      Navigator.pop(context);
      return;
    }
    _mark(_index);
    _armAutoAdvance();
  }

  @override
  Widget build(BuildContext context) {
    final story = _story;
    final height = MediaQuery.of(context).size.height;
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
            if (story == null)
              const SizedBox.shrink()
            else if (story.mediaUrl != null)
              //Vidéo jouée directement dans le statut, sinon photo.
              isVideoUrl(story.mediaUrl)
                  ? MboteVideo(
                      url: story.mediaUrl!,
                      height: height,
                      autoPlay: true,
                    )
                  : MboteImage(
                      url: story.mediaUrl!,
                      height: height,
                      fit: BoxFit.contain,
                    )
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    story.texte ?? '',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: MC.ivoire, fontSize: Tx.subtitle, height: 1.5),
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
                  for (var i = 0; i < _stories.length; i++)
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
            // Auteur + suppression + fermeture
            Positioned(
              top: 56,
              left: 12,
              right: 8,
              child: Row(
                children: [
                  MboteAvatar(
                    name: widget.group.authorName,
                    size: 32,
                    image: (widget.group.avatar != null &&
                            widget.group.avatar!.isNotEmpty)
                        ? NetworkImage(widget.group.avatar!)
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
                          fontSize: Tx.body,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (widget.onDelete != null)
                    IconButton(
                      onPressed: _delete,
                      tooltip: 'Supprimer ce statut',
                      icon: Icon(Icons.delete_outline_rounded,
                          color: MC.ivoire, size: 22),
                    ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: MC.ivoire, size: 22),
                  ),
                ],
              ),
            ),
            // Légende éventuelle sous une photo/vidéo
            if (story != null &&
                story.texte != null &&
                story.texte!.isNotEmpty &&
                story.mediaUrl != null)
              Positioned(
                left: 18,
                right: 18,
                bottom: 60,
                child: Text(
                  story.texte!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: MC.ivoire,
                    fontSize: Tx.bodyLg,
                    height: 1.4,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 8),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ligne d'option de la feuille « Nouveau statut ».
class _StoryOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _StoryOption(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: MC.soleil.withValues(alpha: .15),
        ),
        child: Icon(icon, color: MC.soleil, size: 19),
      ),
      title: Text(label, style: TextStyle(color: MC.ivoire, fontSize: Tx.body)),
    );
  }
}
