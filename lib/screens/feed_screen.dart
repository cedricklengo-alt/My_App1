// lib/screens/feed_screen.dart
// Onglet « Accueil » : fil de publication branché sur le backend.
//
// Tout est réel : lecture paginée de `GET /api/feed`, statuts 24 h, j'aime,
// commentaires, publication (texte / photo / événement) et envoi de photo.
// Les états chargement / erreur / vide / fin de liste sont gérés, et
// l'API est injectable (`FeedScreen(api: …)`) pour les tests.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../config.dart';
import '../models/post.dart';
import '../state.dart';
import '../state/notifs.dart';
import '../tabs.dart';
import '../main.dart' show mboteRouteObserver;
import '../widgets/feed/media_view.dart';
import '../design.dart';
import '../l10n.dart';
import '../liens.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/feed/media_view.dart';
import '../widgets/feed/post_card.dart';
import '../widgets/feed/story_bar.dart';
import '../widgets/social/champ_social.dart';
import '../widgets/social/texte_social.dart';
import 'hashtag_screen.dart';
import 'notifications_screen.dart';
import 'recherche_screen.dart';
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

class _FeedScreenState extends State<FeedScreen> with RouteAware {
  late final Api _api;
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();

  List<Post> _posts = const [];
  List<StoryGroup> _groups = const [];
  int? _nextBefore;
  String? _nextCursor;

  /// Notifications de mention non lues (badge de l'en-tête).
  int? _nonLues;

  /// Suivi partagé des notifications : pastille + page, un seul minuteur.
  NotifsCtl? _notifs;

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
  String? _rankCursor;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    mboteRouteObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  /// 🛑 Un écran est poussé par-dessus le fil → pause immédiate des vidéos.
  @override
  void didPushNext() => MboteVideoBus.instance.pauseAll();

  /// ▶ On revient sur le fil → l'autoplay reprend selon visibilité.
  @override
  void didPopNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) MboteVideoBus.instance.onScroll(context);
    });
  }

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? context.read<AppState>().api;
    _scroll.addListener(_onScroll);
    Tabs.listen(Tabs.feed, _onTabRefresh);
    //Lien partagé ouvert depuis l'extérieur : mbote://post/<id>
    Liens.post.addListener(_surLienPartage);
    _load();
    _notifs = NotifsCtl(_api)..addListener(_surNotifs);
    _notifs!.demarrer();
    _surLienPartage();
  }

  @override
  void dispose() {
    mboteRouteObserver.unsubscribe(this);
    Liens.post.removeListener(_surLienPartage);
    Tabs.stopListening(Tabs.feed, _onTabRefresh);
    _notifs?.removeListener(_surNotifs);
    _notifs?.dispose();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Re-tap sur l'onglet Accueil → on remonte en haut et on recharge.
  void _onTabRefresh() {
    if (!mounted) return;
    _chargerBadge();
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
        // v4.1 : classement par algorithme (35/25/15/15/10), repli affinité.
        _rankCursor = null;
        return _api
            .feedRanked(tab: 'for_you')
            .catchError((_) => _api.filPersonnalise());
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
        if (_rankCursor != null) return _api.feedRanked(tab: 'for_you', cursor: _rankCursor);
        if (_nextOffset != null) return _api.filPersonnalise(offset: _nextOffset!);
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
        if (_onglet == _Onglet.pourToi) _rankCursor = page.nextCursor;
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
        if (_onglet == _Onglet.pourToi) _rankCursor = page.nextCursor;
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
    // « Tendances » avance par décalage, les autres par curseur de date.
    // « Pour toi » accepte les deux : décalage quand le classement est
    // disponible, curseur de date en repli.
    final bloque = switch (_onglet) {
      _Onglet.tendances => _nextOffset == null,
      _Onglet.pourToi => _nextOffset == null && _nextCursor == null,
      _Onglet.abonnements => _nextCursor == null,
    };
    if (bloque) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _lirePageSuivante();
      if (!mounted) return;
      final seen = _posts.map((p) => p.id).toSet();
      setState(() {
        _posts = [..._posts, ...page.posts.where((p) => !seen.contains(p.id))];
        _nextBefore = page.nextBefore;
        _nextCursor = page.nextCursor;
        if (_onglet == _Onglet.pourToi) _rankCursor = page.nextCursor;
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

  /// Réaction Facebook-like (8 types) — met à jour le score du fil.
  Future<void> _react(Post post, String type) async {
    HapticFeedback.selectionClick();
    try {
      await _api.reactPost(post.id, type);
      await _api.feedEvent('like', postId: post.id, authorId: post.authorId, tag: null);
      if (mounted) setState(() {});
    } catch (_) {}
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

  Future<void> _openComments(Post post, {String? focusCommentId}) async {
    final count = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(
        api: _api,
        post: post,
        focusCommentId: focusCommentId,
      ),
    );
    // Le fil affiche le nouveau total sans recharger.
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

  /// #hashtag → page dédiée (publications, abonnés, suivi, onglets).
  void _ouvrirHashtag(String tag) {
    if (tag.trim().isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HashtagScreen(tag: tag),
    ));
  }

  /// @mention → profil de la personne. Le serveur fournit la correspondance
  /// identifiant ↔ personne avec chaque publication ; à défaut (identifiant
  /// inconnu ou compte supprimé), la recherche universelle prend le relais.
  void _ouvrirMention(Post post, String handle) {
    final connue = post.mentionsListe
        .where((m) => m.handle.toLowerCase() == handle.toLowerCase())
        .toList();
    if (connue.isNotEmpty) {
      _ouvrirProfil(connue.first.id, connue.first.name);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RechercheScreen(
        requeteInitiale: '@$handle',
        onPersonne: (id) => _ouvrirProfil(id, handle),
      ),
    ));
  }

  /// Profil public d'une personne : ce qu'il faut pour décider de la suivre,
  /// et ses publications visibles.
  Future<void> _ouvrirProfil(String id, String nom) async {
    try {
      final profil = await _api.authorProfile(id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _ProfilPublic(profil: profil, nom: nom, api: _api),
      );
    } catch (e) {
      if (!mounted) return;
      _toast(friendlyError(e));
    }
  }

  /// Centre de notifications : j'aime, commentaires, réponses, mentions,
  /// partages. Le contrôleur est partagé avec le fil, donc la pastille de
  /// l'en-tête suit immédiatement ce qui vient d'être lu.
  Future<void> _ouvrirNotifications() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NotificationsScreen(
        controleur: _notifs,
        onOuvrirProfil: (id) => _ouvrirProfil(id, ''),
        onOuvrirPublication: (postId, {String? commentId}) =>
            _ouvrirPublicationId(postId, commentId: commentId),
      ),
    ));
    if (!mounted) return;
    _notifs?.rafraichirBadge();
  }

  /// Ouvre une publication depuis son identifiant (notification, recherche).
  /// Quand la notification vise un commentaire, on ouvre la feuille de
  /// commentaires positionnée dessus, surligné.
  Future<void> _ouvrirPublicationId(String id, {String? commentId}) async {
    try {
      final post = await _api.lirePublication(id);
      if (!mounted) return;
      setState(() {
        if (!_posts.any((p) => p.id == post.id)) _posts = [post, ..._posts];
      });
      _scrollToTop();
      if (commentId != null) {
        // Laisse le fil se poser avant d'ouvrir la feuille par-dessus.
        await Future<void>.delayed(const Duration(milliseconds: 180));
        if (mounted) await _openComments(post, focusCommentId: commentId);
      }
    } catch (e) {
      if (!mounted) return;
      _toast(friendlyError(e));
    }
  }

  /// Le contrôleur a changé d'état (badge, liste) : on redessine l'en-tête.
  void _surNotifs() {
    if (!mounted) return;
    if (_nonLues != _notifs!.nonLues) {
      setState(() => _nonLues = _notifs!.nonLues);
    }
  }

  /// Badge de l'en-tête : nombre de notifications non lues. Appelé à
  /// l'ouverture, au retour sur l'onglet et au réveil de l'application.
  void _chargerBadge() {
    _notifs?.rafraichirBadge();
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

  Future<void> _openCreate({String? type}) async {
    HapticFeedback.mediumImpact();
    // La feuille gère elle-même l'envoi (états chargement/erreur/réessayer) ;
    // elle ne se ferme qu'après une publication confirmée par le serveur.
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateSheet(
        typeInitial: type,
        onPublish: _publierDepuisFeuille,
      ),
    );
    if (ok == true && mounted) {
      // Le post est déjà inséré en tête de liste ; on resynchronise en fond.
      unawaited(_refresh());
    }
  }

  /// Appelé par la feuille de création : lève une erreur si l'envoi échoue,
  /// pour que la feuille garde le brouillon et propose « Réessayer ».
  Future<void> _publierDepuisFeuille(Map draft) async {
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
      allowCalls: draft['allow_calls'] != false,
      ville: draft['ville'] as String?,
    );
    if (!mounted) return;
    setState(() => _posts = [post, ..._posts]);
    _scrollToTop();
    _toast('Publication en ligne');
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
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            MboteVideoBus.instance.onScroll(context); // autoplay 70 % / 1 seule vidéo
            return false;
          },
          child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _FeedAppBar(
              dataSaver: _dataSaver,
              searching: _searching,
              searchController: _search,
              onglet: _onglet,
              onChoixOnglet: _changerOnglet,
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
              nonLues: _nonLues,
              onNotifications: _ouvrirNotifications,
              onRechercheUniverselle: () {
                final q = _search.text.trim();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RechercheScreen(
                    requeteInitiale: q.isEmpty ? null : q,
                    onPersonne: (id) => _ouvrirProfil(id, ''),
                    onPublication: _ouvrirPublicationId,
                  ),
                ));
              },
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
            // Erreur réseau AVEC des publications déjà affichées : on garde
            // le contenu visible et on signale l'erreur en haut du fil.
            else if (_error != null && posts.isEmpty)
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
            else ...[
              // Erreur réseau AVEC publications affichées : bannière en haut,
              // le contenu local reste visible (hors-ligne).
              if (_error != null)
                SliverToBoxAdapter(
                  child: _BandeauErreur(message: _error!, onRetry: _load),
                ),
              SliverList.separated(
                itemCount: posts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
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
                    onHashtag: _ouvrirHashtag,
                    onMention: (handle) => _ouvrirMention(post, handle),
                    //Jamais d'appel sur sa propre publication (double
                    // sécurité : la carte le vérifie aussi).
                    onCall: (!mine && post.canCall) ? () => _call(post) : null,
                    onDelete: mine ? () => _confirmDelete(post) : null,
                    onLike: () => _toggleLike(post),
                    onReact: (t) => _react(post, t),
                    onComment: () => _openComments(post),
                    onShare: () => _share(post),
                  );
                },
              ),
            ],

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
    ));
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
  final _Onglet onglet;
  final ValueChanged<_Onglet> onChoixOnglet;
  final VoidCallback onToggleDataSaver;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onQuery;

  /// Recherche universelle (hashtags, personnes, publications…).
  final VoidCallback onRechercheUniverselle;

  /// Boîte de réception des mentions.
  final VoidCallback onNotifications;

  /// Mentions non lues, affichées en pastille.
  final int? nonLues;

  const _FeedAppBar({
    required this.dataSaver,
    required this.searching,
    required this.searchController,
    required this.onglet,
    required this.onChoixOnglet,
    required this.onToggleDataSaver,
    required this.onToggleSearch,
    required this.onQuery,
    required this.onRechercheUniverselle,
    required this.onNotifications,
    this.nonLues,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true, // barre fixe : toujours visible au scroll
      backgroundColor: MC.nuit.withValues(alpha: .88), // léger effet verre
      elevation: 0,
      scrolledUnderElevation: 0,
      // Rangée d'icônes « Pour toi / Abonnements / Tendances » fusionnée
      // dans le bloc fixe, sous le titre — aucun libellé texte affiché.
      bottom: searching
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(50),
              child: _IconTabs(onglet: onglet, onChoix: onChoixOnglet),
            ),
      title: searching
          ? TextField(
              controller: searchController,
              autofocus: true,
              onChanged: onQuery,
              // Valider une recherche depuis la barre ouvre la recherche
              // universelle : hashtags, personnes, publications, statuts.
              onSubmitted: (v) {
                if (v.trim().isEmpty) return;
                onRechercheUniverselle();
              },
              textInputAction: TextInputAction.search,
              style: TextStyle(color: MC.ivoire, fontSize: Tx.bodyLg),
              decoration: InputDecoration(
                hintText: 'Rechercher dans le fil…',
                hintStyle: TextStyle(color: MC.kaki, fontSize: Tx.body),
                border: InputBorder.none,
              ),
            )
          : Text(
              'MboteCall',
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
        // Cloche : mentions reçues. La pastille ne s'affiche que s'il y a du
        // nouveau — pas de point rouge permanent.
        Stack(
          alignment: Alignment.topRight,
          children: [
            IconButton(
              icon: Icon(Icons.notifications_none_rounded, color: MC.kaki, size: 21),
              tooltip: 'Notifications',
              onPressed: onNotifications,
            ),
            if ((nonLues ?? 0) > 0)
              Positioned(
                right: 6,
                top: 6,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: MC.rouge,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      (nonLues! > 99 ? '99+' : '$nonLues'),
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.caption,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
          ],
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
// Onglets du fil en icônes (barre fixe, sans texte)
//───────────────────────────────────────────

/// Icônes « Pour toi / Abonnements / Tendances » : grandes, premium,
/// conteneur arrondi, ombre légère, état actif en accent MboteCall,
/// animation subtile + haptique au clic. Aucun libellé texte affiché.
class _IconTabs extends StatelessWidget {
  final _Onglet onglet;
  final ValueChanged<_Onglet> onChoix;
  const _IconTabs({required this.onglet, required this.onChoix});

  static const _icones = {
    _Onglet.pourToi: Icons.home_rounded,
    _Onglet.abonnements: Icons.people_alt_rounded,
    _Onglet.tendances: Icons.local_fire_department_rounded,
  };
  // Libellés UNIQUEMENT pour l'accessibilité (Semantics), jamais affichés.
  static const _labels = {
    _Onglet.pourToi: 'Fil Pour toi',
    _Onglet.abonnements: 'Fil Abonnements',
    _Onglet.tendances: 'Fil Tendances',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: Sp.x4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final o in _Onglet.values) ...[
            const SizedBox(width: 10),
            Semantics(
              button: true,
              selected: onglet == o,
              label: _labels[o],
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick(); // feedback haptique
                  onChoix(o);
                },
                child: AnimatedContainer(
                  // transition douce actif/inactif
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  width: 52,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: onglet == o
                        ? MC.soleil // fond distinct + accent MboteCall
                        : MC.nuit3.withValues(alpha: .8),
                    borderRadius: BorderRadius.circular(Rd.pill),
                    boxShadow: onglet == o
                        ? [
                            BoxShadow(
                              color: MC.soleil.withValues(alpha: .30),
                              blurRadius: 14,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: AnimatedScale(
                    scale: onglet == o ? 1.12 : 1.0, // présence visuelle
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: Icon(
                      _icones[o],
                      size: 23,
                      color: onglet == o ? MC.onAccent : MC.kaki,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
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

/// Profil public d'une personne mentionnée : identité, abonnés, publications.
/// C'est ce qui s'ouvre quand on appuie sur « @cedrick ».
class _ProfilPublic extends StatelessWidget {
  final Map profil;
  final String nom;
  final Api api;

  const _ProfilPublic({required this.profil, required this.nom, required this.api});

  @override
  Widget build(BuildContext context) {
    final auteur = (profil['auteur'] as Map?) ?? const {};
    final posts = ((profil['posts'] as List?) ?? const []);
    final handle = auteur['handle'] as String?;
    final suivi = auteur['suivi'] == 1 || auteur['suivi'] == true;

    return Container(
      decoration: BoxDecoration(
        color: MC.nuit2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: MC.ligne, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              MboteAvatar(
                name: '${auteur['name'] ?? nom}',
                size: 48,
                image: (auteur['avatar'] as String?)?.isNotEmpty == true
                    ? NetworkImage(auteur['avatar'] as String)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${auteur['name'] ?? nom}',
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.subtitle,
                          fontWeight: FontWeight.w800),
                    ),
                    if (handle != null && handle.isNotEmpty)
                      Text('@$handle',
                          style: TextStyle(
                              color: MC.braise,
                              fontSize: Tx.label,
                              fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              if (suivi)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: MC.savane.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('Suivi',
                      style: TextStyle(
                          color: MC.savane,
                          fontSize: Tx.caption,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${posts.length} publication(s) visible(s) pour toi',
            style: TextStyle(color: MC.kaki, fontSize: Tx.caption),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: MC.soleil,
                side: BorderSide(color: MC.soleil.withValues(alpha: .5)),
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RechercheScreen(
                    requeteInitiale: handle == null ? null : '@$handle',
                  ),
                ));
              },
              child: const Text('Voir ses publications'),
            ),
          ),
        ],
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

/// Bannière d'erreur affichée EN HAUT du fil quand des publications locales
/// existent déjà : le contenu reste visible, l'erreur est signalée sans
/// masquer la liste (mission « hors connexion »).
class _BandeauErreur extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _BandeauErreur({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: MC.nuit3,
        borderRadius: BorderRadius.circular(Rd.md),
        border: Border.all(color: MC.rouge.withValues(alpha: .5)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: MC.rouge),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$message — tes publications déjà chargées restent visibles.',
              style: TextStyle(color: MC.sable, fontSize: Tx.caption, height: 1.35),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text('Réessayer',
                style: TextStyle(color: MC.soleil, fontWeight: FontWeight.w700)),
          ),
        ],
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

  /// Commentaire sur lequel se positionner : c'est ce qui rend une
  /// notification « Patrick a répondu à votre commentaire » utile — on arrive
  /// directement sur la réponse, surlignée.
  final String? focusCommentId;

  const _CommentsSheet({
    required this.api,
    required this.post,
    this.focusCommentId,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _cles = {};

  List<Map> _comments = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  /// Commentaire auquel on répond (null : commentaire de premier niveau).
  Map? _reponseA;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
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
      _allerAuFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  /// Fait défiler jusqu'au commentaire visé par la notification.
  void _allerAuFocus() {
    final id = widget.focusCommentId;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cle = _cles[id];
      final ctx = cle?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 260),
            alignment: .35,
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final texte = _input.text.trim();
    if (texte.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final c = await widget.api.addComment(widget.post.id, texte,
          parentId: _reponseA?['id']?.toString());
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, c];
        _sending = false;
        _reponseA = null;
        _input.clear();
      });
      // Le nouveau commentaire est le dernier : on l'amène à l'écran.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  /// Commentaires de premier niveau, chacun suivi de ses réponses.
  List<Map> get _arbre {
    final parents = _comments.where((c) => c['parent_id'] == null).toList();
    final parParent = <String, List<Map>>{};
    for (final c in _comments) {
      final p = c['parent_id'];
      if (p == null) continue;
      parParent.putIfAbsent(p.toString(), () => []).add(c);
    }
    final sortie = <Map>[];
    for (final p in parents) {
      sortie.add(p);
      sortie.addAll(parParent[p['id'].toString()] ?? const []);
    }
    // Une réponse dont le parent a disparu ne doit pas être invisible.
    final orphelins = _comments.where((c) {
      final p = c['parent_id'];
      return p != null &&
          !parents.any((x) => x['id'].toString() == p.toString());
    });
    sortie.addAll(orphelins);
    return sortie;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final arbre = _arbre;
    return Container(
      height: MediaQuery.of(context).size.height * .78,
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
                  '$_count',
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
                    : arbre.isEmpty
                        ? Center(
                            child: Text(
                              'Aucun commentaire — sois le premier.',
                              style: TextStyle(color: MC.kaki, fontSize: Tx.label),
                            ),
                          )
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: arbre.length,
                            itemBuilder: (_, i) => _brique(arbre[i]),
                          ),
          ),
          if (_reponseA != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.reply_rounded, size: 14, color: MC.soleil),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Réponse à ${_reponseA!['author_name'] ?? 'un commentaire'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: MC.soleil, fontSize: Tx.caption),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _reponseA = null),
                    tooltip: 'Annuler la réponse',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, size: 16, color: MC.kaki),
                  ),
                ],
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
                        hintText: _reponseA == null
                            ? 'Écrire un commentaire…'
                            : 'Répondre à ${_reponseA!['author_name'] ?? ''}…',
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
                    tooltip: 'Envoyer',
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
                    onPressed: () => Navigator.pop(context, _count),
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

  int get _count => _comments.length;

  Widget _brique(Map c) {
    final id = c['id'].toString();
    final cle = _cles.putIfAbsent(id, () => GlobalKey());
    final estReponse = c['parent_id'] != null;
    final surligne = widget.focusCommentId != null &&
        widget.focusCommentId.toString() == id;
    return Container(
      key: cle,
      margin: EdgeInsets.only(left: estReponse ? 26 : 0, bottom: 6),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: surligne ? MC.soleil.withValues(alpha: .07) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: surligne
            ? Border.all(color: MC.soleil.withValues(alpha: .35), width: 1)
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MboteAvatar(
            name: '${c['author_name'] ?? '?'}',
            size: estReponse ? 26 : 30,
            // 📸 Photo de profil de l'auteur à côté de son nom (initiales sinon).
            image: (c['author_avatar'] is String && (c['author_avatar'] as String).isNotEmpty)
                ? NetworkImage(c['author_avatar'] as String)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (estReponse) ...[
                      Icon(Icons.subdirectory_arrow_right_rounded,
                          size: 12, color: MC.kaki),
                      const SizedBox(width: 3),
                    ],
                    Flexible(
                      child: Text(
                        (c['author_name'] ?? 'Compte MboteCall').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.label,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (c['a_moi'] == 1) ...[
                      const SizedBox(width: 6),
                      Text('vous',
                          style: TextStyle(
                              color: MC.soleil, fontSize: Tx.caption)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  (c['texte'] ?? '').toString(),
                  style: TextStyle(
                      color: MC.sable, fontSize: Tx.label, height: 1.35),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: () => setState(() => _reponseA = c),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('Répondre',
                        style: TextStyle(
                            color: MC.kaki,
                            fontSize: Tx.caption,
                            fontWeight: FontWeight.w700)),
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

//───────────────────────────────────────────
// Feuille de publication
//───────────────────────────────────────────

class _CreateSheet extends StatefulWidget {
  /// Type présélectionné depuis la zone de création du fil ('photo' | 'clip').
  final String? typeInitial;

  /// Envoi réel vers le serveur. Lève une erreur si l'envoi échoue : la
  /// feuille garde alors le brouillon et affiche « Réessayer ».
  final Future<void> Function(Map draft) onPublish;

  const _CreateSheet({this.typeInitial, required this.onPublish});

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

/// Clé SharedPreferences du brouillon de publication (texte + références
/// serveur des médias déjà envoyés + champs événement + visibilité).
const String _cleBrouillon = 'feed_brouillon_v1';

class _CreateSheetState extends State<_CreateSheet> {
  final TextEditingController _texte = TextEditingController();
  final TextEditingController _titre = TextEditingController();
  final TextEditingController _lieu = TextEditingController();
  final TextEditingController _tags = TextEditingController();
  final TextEditingController _villeCtrl = TextEditingController();

  String _type = 'texte';

  // PAR DÉFAUT : tout le monde. Le défaut précédent (« Mes contacts ») faisait
  // qu'une publication n'était vue que par les gens qui avaient déjà l'auteur
  // dans leur répertoire — c'est-à-dire, en pratique, par personne.
  String _visibilite = 'public';
  bool _allowCalls = true; // case « Autoriser les appels »
  String? _mediaUrl;

  /// Miniature de la vidéo, produite par le serveur au moment de l'envoi du
  /// fichier. On la transmet avec la publication pour que le fil affiche un
  /// aperçu immédiat, sans télécharger la vidéo.
  String? _thumbUrl;
  int? _clipSec; // durée de la vidéo, quand on publie un clip
  String? _ville;
  DateTime? _eventDate;
  bool _uploading = false;

  /// Envoi en cours : bloque le bouton Publier (anti double soumission).
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    // Pré-sélection depuis la zone de création du fil (icône photo/vidéo).
    final t = widget.typeInitial;
    if (t == 'photo' || t == 'clip') _type = t!;
    // Restaure un brouillon laissé en cours (fermeture, changement d'écran,
    // perte de connexion, erreur d'envoi) : rien n'est perdu silencieusement.
    _restaurerBrouillon();
    for (final c in [_texte, _titre, _lieu, _tags, _villeCtrl]) {
      c.addListener(_sauvegarderBrouillon);
    }
  }

  @override
  void dispose() {
    for (final c in [_texte, _titre, _lieu, _tags, _villeCtrl]) {
      c.removeListener(_sauvegarderBrouillon);
    }
    _texte.dispose();
    _titre.dispose();
    _lieu.dispose();
    _tags.dispose();
    _villeCtrl.dispose();
    super.dispose();
  }

  // ── Brouillon ────────────────────────────────────────────────────────

  /// Le brouillon a-t-il du contenu non publié ?
  bool get _aDuContenu =>
      _texte.text.trim().isNotEmpty ||
      _mediaUrl != null ||
      _titre.text.trim().isNotEmpty ||
      _lieu.text.trim().isNotEmpty ||
      _tags.text.trim().isNotEmpty ||
      _ville != null;

  Map<String, Object?> get _brouillon => {
        'type': _type,
        'texte': _texte.text,
        'media_url': _mediaUrl,
        'thumb_url': _thumbUrl,
        'clip_duree_seconds': _clipSec,
        'event_title': _titre.text,
        'event_date': _eventDate?.toIso8601String(),
        'event_lieu': _lieu.text,
        'event_tags': _tags.text,
        'visibilite': _visibilite,
        'allow_calls': _allowCalls,
        'ville': _ville,
      };

  Future<void> _sauvegarderBrouillon() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (_aDuContenu) {
        await p.setString(_cleBrouillon, jsonEncode(_brouillon));
      } else {
        await p.remove(_cleBrouillon);
      }
    } catch (_) {
      // Le brouillon est un confort, jamais un blocage.
    }
  }

  Future<void> _restaurerBrouillon() async {
    try {
      final p = await SharedPreferences.getInstance();
      final brut = p.getString(_cleBrouillon);
      if (brut == null || brut.isEmpty) return;
      final d = jsonDecode(brut);
      if (d is! Map) return;
      if (!mounted) return;
      setState(() {
        final t = d['type'];
        if (t == 'photo' || t == 'clip' || t == 'event' || t == 'texte') {
          _type = t as String;
        }
        _texte.text = (d['texte'] ?? '') as String;
        _mediaUrl = d['media_url'] as String?;
        _thumbUrl = d['thumb_url'] as String?;
        _clipSec = (d['clip_duree_seconds'] as num?)?.toInt();
        _titre.text = (d['event_title'] ?? '') as String;
        final ed = d['event_date'];
        if (ed is String) {
          try {
            _eventDate = DateTime.parse(ed);
          } catch (_) {}
        }
        _lieu.text = (d['event_lieu'] ?? '') as String;
        _tags.text = (d['event_tags'] ?? '') as String;
        _visibilite = (d['visibilite'] ?? 'public') as String;
        _allowCalls = d['allow_calls'] != false;
        _ville = d['ville'] as String?;
        _villeCtrl.text = _ville ?? '';
      });
    } catch (_) {
      // Brouillon illisible : on repart à zéro plutôt que de bloquer.
    }
  }

  Future<void> _viderBrouillon() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_cleBrouillon);
    } catch (_) {}
  }

  /// Fermeture de la feuille : un brouillon non vide demande confirmation
  /// avant d'être abandonné (jamais de perte silencieuse).
  Future<void> _fermer() async {
    if (_envoi) return;
    if (_aDuContenu) {
      final abandonner = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: MC.nuit2,
          title: Text('Abandonner le brouillon ?',
              style: TextStyle(color: MC.ivoire, fontSize: Tx.subtitle)),
          content: Text(
            'Ton texte et tes médias sélectionnés seront supprimés.',
            style: TextStyle(color: MC.sable, fontSize: Tx.label),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Continuer', style: TextStyle(color: MC.kaki)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Abandonner',
                  style: TextStyle(
                      color: MC.rouge, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (abandonner != true) return;
      await _viderBrouillon();
    }
    if (mounted) Navigator.of(context).pop(false);
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
      _sauvegarderBrouillon();
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
      _sauvegarderBrouillon();
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
    _sauvegarderBrouillon();
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

  /// Envoi avec états : le bouton Publier passe en chargement, la feuille
  /// reste ouverte en cas d'échec (brouillon conservé, « Réessayer »), et
  /// un double appui est impossible tant que l'envoi est en cours.
  Future<void> _envoyer() async {
    if (!_canPublish || _envoi) return;
    setState(() => _envoi = true);
    try {
      await widget.onPublish({
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
        'allow_calls': _allowCalls,
        'ville': _ville,
      });
      await _viderBrouillon();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e)),
          action: SnackBarAction(
            label: 'Réessayer',
            textColor: MC.soleil,
            onPressed: _envoyer,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final moi = context.watch<AppState>();
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: MC.nuit2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Rd.lg)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── En-tête compact et FIXE : même clavier ouvert, « Publier »
            // reste visible (seul le corps défile).
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 12, 8),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: MC.nuit3,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: MC.kaki),
                        tooltip: 'Fermer',
                        onPressed: _envoi ? null : _fermer,
                      ),
                      Expanded(
                        child: Text(
                          'Créer une publication',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: MC.ivoire,
                            fontSize: Tx.subtitle,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      // Bouton Publier à états : désactivé / actif / chargement.
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: MC.soleil,
                          foregroundColor: MC.nuit,
                          disabledBackgroundColor: MC.nuit3,
                          disabledForegroundColor: MC.kaki,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          minimumSize: const Size(0, 40),
                        ),
                        onPressed: (_canPublish && !_envoi) ? _envoyer : null,
                        child: _envoi
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.2, color: MC.nuit),
                              )
                            : const Text(
                                'Publier',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: Tx.body),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: MC.ligne),
            // ── Corps défilant ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Zone d'identité : avatar + nom, confidentialité à côté —
                    // le sélecteur réel, pris en charge par le backend.
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Rd.avatar),
                            color: MC.nuit3,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: (moi.avatar != null && moi.avatar!.isNotEmpty)
                              ? Image.network(moi.avatar!, fit: BoxFit.cover,
                                  excludeFromSemantics: true,
                                  errorBuilder: (_, __, ___) =>
                                      Icon(Icons.person_rounded, color: MC.kaki))
                              : Icon(Icons.person_rounded, color: MC.kaki),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                moi.name.isEmpty ? 'Compte MboteCall' : moi.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: MC.ivoire,
                                    fontSize: Tx.body,
                                    fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              DropdownButton<String>(
                                value: _visibilite,
                                dropdownColor: MC.nuit3,
                                underline: const SizedBox.shrink(),
                                icon: Icon(Icons.expand_more_rounded,
                                    size: 16, color: MC.kaki),
                                style: TextStyle(
                                    color: MC.soleil, fontSize: Tx.caption),
                                items: const [
                                  // Icône Material + libellé : pas d'emoji
                                  // (mêmes icônes que la pastille d'audience).
                                  DropdownMenuItem(
                                    value: 'public',
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.public_rounded, size: 16),
                                        SizedBox(width: 8),
                                        Text('Tout le monde'),
                                      ],
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'communaute',
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.groups_rounded, size: 16),
                                        SizedBox(width: 8),
                                        Text('Communauté MboteCall'),
                                      ],
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'contacts',
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.lock_outline_rounded,
                                            size: 16),
                                        SizedBox(width: 8),
                                        Text('Mes contacts seulement'),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: _envoi
                                    ? null
                                    : (v) {
                                        setState(
                                            () => _visibilite = v ?? 'public');
                                        _sauvegarderBrouillon();
                                      },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Ce que chaque choix de confidentialité implique réellement.
                    Text(
                      switch (_visibilite) {
                        'contacts' =>
                          'Seules les personnes qui ont ton numéro enregistré verront cette publication.',
                        'communaute' =>
                          'Tous les membres de MboteCall verront cette publication, sans apparaître dans les tendances.',
                        _ =>
                          'Tout le monde verra cette publication dans le fil et dans la découverte.',
                      },
                      style: TextStyle(
                          color:
                              _visibilite == 'contacts' ? MC.soleil : MC.kaki,
                          fontSize: Tx.caption,
                          height: 1.35),
                    ),
                    const SizedBox(height: 6),
                    // ✅ Case « Autoriser les appels » — le bouton d'appel
                    // n'apparaît sur la publication que si elle est cochée.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: MC.nuit3,
                        borderRadius: BorderRadius.circular(Rd.md),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: MC.savane.withValues(alpha: .16),
                            ),
                            child: Icon(Icons.phone_rounded,
                                color: MC.savane, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Autoriser les appels',
                                    style: TextStyle(
                                        color: MC.ivoire,
                                        fontSize: Tx.body,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(
                                    _allowCalls
                                        ? 'Les autres pourront t’appeler depuis cette publication.'
                                        : 'Personne ne verra le bouton d’appel sur cette publication.',
                                    style: TextStyle(
                                        color: MC.kaki,
                                        fontSize: Tx.caption,
                                        height: 1.3)),
                              ],
                            ),
                          ),
                          Switch(
                            value: _allowCalls,
                            activeThumbColor: MC.savane,
                            onChanged: _envoi
                                ? null
                                : (v) {
                                    HapticFeedback.selectionClick();
                                    setState(() => _allowCalls = v);
                                    _sauvegarderBrouillon();
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Champ central : sans fond ni contour, il s'agrandit avec
                    // le texte. Les hashtags s'écrivent ici (« #Innovation ») :
                    // aucun bouton #Tag n'existe.
                    ChampSocial(
                      controller: _texte,
                      hint: _type == 'event'
                          ? 'Description (facultatif)'
                          : 'Quoi de neuf ?',
                      maxLines: null, // s'agrandit avec le texte
                      minLines: 4,
                      sansFond: true,
                      autofocus: widget.typeInitial == null,
                      onChanged: (_) => setState(() {}),
                    ),

                    // Aperçu du média sélectionné : vignette + suppression.
                    if (_uploading) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: MC.soleil)),
                          const SizedBox(width: 8),
                          Text('Envoi du média…',
                              style: TextStyle(
                                  color: MC.kaki, fontSize: Tx.label)),
                        ],
                      ),
                    ] else if (_mediaUrl != null) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Rd.md),
                        child: Stack(
                          children: [
                            Image.network(
                              (_type == 'clip' && _thumbUrl != null)
                                  ? _thumbUrl!
                                  : _mediaUrl!,
                              semanticLabel: _type == 'clip'
                                  ? 'aperçu de la vidéo'
                                  : 'aperçu de la photo',
                              height: 150,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: 150,
                                color: MC.nuit3,
                                child: Center(
                                  child: Text('Aperçu indisponible',
                                      style: TextStyle(
                                          color: MC.kaki,
                                          fontSize: Tx.label)),
                                ),
                              ),
                            ),
                            if (_type == 'clip')
                              Positioned(
                                bottom: 8,
                                left: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: .6),
                                    borderRadius: BorderRadius.circular(Rd.xs),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.play_circle_fill_rounded,
                                          size: 13, color: MC.ivoire),
                                      const SizedBox(width: 4),
                                      Text('Vidéo',
                                          style: TextStyle(
                                              color: MC.ivoire,
                                              fontSize: Tx.caption,
                                              fontWeight: FontWeight.w700)),
                                    ],
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
                                onPressed: _envoi
                                    ? null
                                    : () {
                                        setState(() {
                                          _mediaUrl = null;
                                          _thumbUrl = null;
                                          _clipSec = null;
                                          if (_type == 'photo' ||
                                              _type == 'clip') {
                                            _type = 'texte';
                                          }
                                        });
                                        _sauvegarderBrouillon();
                                      },
                                icon: Icon(Icons.close_rounded,
                                    size: 16, color: MC.ivoire),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Champs de l'événement (type réellement pris en charge).
                    if (_type == 'event') ...[
                      const SizedBox(height: 12),
                      _Field(controller: _titre, hint: 'Titre de l’événement'),
                      const SizedBox(height: 10),
                      _Field(
                          controller: _lieu, hint: 'Lieu (ex. Palais du Peuple)'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: MC.soleil,
                              side: BorderSide(
                                  color: MC.soleil.withValues(alpha: .5)),
                            ),
                            onPressed: _envoi ? null : _pickDate,
                            icon: const Icon(Icons.calendar_today_rounded,
                                size: 16),
                            label: Text(
                              _eventDate == null
                                  ? 'Choisir une date'
                                  : '${_eventDate!.day}/${_eventDate!.month}/${_eventDate!.year}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _Field(
                          controller: _tags, hint: 'Mots-clés (ex. musique, kin)'),
                    ],

                    const SizedBox(height: 12),
                    _Field(
                      controller: _villeCtrl,
                      hint: 'Ville (facultatif)',
                      onChanged: (v) {
                        _ville = v.trim().isEmpty ? null : v.trim();
                      },
                    ),
                    const SizedBox(height: 14),

                    // Barre d'actions secondaires compacte : uniquement des
                    // fonctions réellement prises en charge (photo, vidéo
                    // 60 s, événement). Cibles tactiles ≥ 48 dp.
                    Row(
                      children: [
                        _ActionBarre(
                          icone: Icons.image_rounded,
                          label: 'Photo',
                          actif: _type == 'photo',
                          onTap: _envoi || _uploading ? null : _pickImage,
                        ),
                        _ActionBarre(
                          icone: Icons.videocam_rounded,
                          label: 'Vidéo',
                          actif: _type == 'clip',
                          onTap: _envoi || _uploading ? null : _pickVideo,
                        ),
                        _ActionBarre(
                          icone: Icons.event_rounded,
                          label: 'Événement',
                          actif: _type == 'event',
                          onTap: _envoi
                              ? null
                              : () {
                                  setState(() => _type =
                                      _type == 'event' ? 'texte' : 'event');
                                  _sauvegarderBrouillon();
                                },
                        ),
                      ],
                    ),
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

/// Bouton de la barre d'actions du formulaire : icône + libellé court,
/// cible tactile confortable, état actif visible.
class _ActionBarre extends StatelessWidget {
  final IconData icone;
  final String label;
  final bool actif;
  final VoidCallback? onTap;
  const _ActionBarre({
    required this.icone,
    required this.label,
    required this.actif,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final couleur = actif ? MC.soleil : MC.kaki;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Rd.sm),
          child: Container(
            constraints: const BoxConstraints(minHeight: Tap.min),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icone, size: 19, color: couleur),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color: couleur,
                        fontSize: Tx.label,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  const _Field({
    required this.controller,
    required this.hint,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
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
                  // Hashtags et mentions d'un statut sont cliquables, comme
                  // dans une publication : c'est le même texte, donc le même
                  // comportement.
                  child: TexteSocial(
                    story.texte ?? '',
                    fontSize: Tx.subtitle,
                    height: 1.5,
                    textAlign: TextAlign.center,
                    onHashtag: (t) {
                      Navigator.of(context).pop();
                      Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => HashtagScreen(tag: t)));
                    },
                    onMention: (h) {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => RechercheScreen(requeteInitiale: '@$h'),
                      ));
                    },
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
                child: TexteSocial(
                  story.texte!,
                  fontSize: Tx.bodyLg,
                  height: 1.4,
                  textAlign: TextAlign.center,
                  onHashtag: (t) {
                    Navigator.of(context).pop();
                    Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => HashtagScreen(tag: t)));
                  },
                  onMention: (h) {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RechercheScreen(requeteInitiale: '@$h'),
                    ));
                  },
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
