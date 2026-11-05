// lib/widgets/feed/media_view.dart
//Lecture des médias du fil : image (aperçu plein écran) et vidéo courte
// (lecture directe dans la carte).
//
// Tout est fait pour ne jamais casser l'écran :
//   • chargement  → indicateur de progression ;
//   • erreur      → message clair + bouton « Réessayer » ;
// • vidéo → aucune donnée téléchargée avant l'appui sur (éco data) ;
//   • plugin absent (tests d'interface) → état d'erreur propre, pas de crash.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../../design.dart';
import '../../local/media_store.dart';
import '../../theme.dart';

/// Une URL de média est-elle une vidéo ? (extension ou paramètre explicite)
bool isVideoUrl(String? url) {
  if (url == null) return false;
  final path = url.split('?').first.toLowerCase();
  return path.endsWith('.mp4') ||
      path.endsWith('.mov') ||
      path.endsWith('.m4v') ||
      path.endsWith('.webm') ||
      path.endsWith('.avi') ||
      path.contains('/video/');
}

///Affiche une image servie par le serveur.
///
/// • `height` : hauteur fixe dans la carte (0 = au ratio naturel, plein écran).
/// • un appui ouvre l'aperçu plein écran (zoom, fermeture).
class MboteImage extends StatelessWidget {
  final String url;
  final double height;
  final BoxFit fit;
  final bool preview;

  /// Texte lu par un lecteur d'écran à la place de la photo.
  /// `null` → « Photo » dans la langue active.
  final String? semanticLabel;

  const MboteImage({
    super.key,
    required this.url,
    this.height = 220,
    this.fit = BoxFit.cover,
    this.preview = true,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final image = _RetryNetworkImage(
        url: url, fit: fit, height: height, semanticLabel: semanticLabel);
    if (!preview) return image;
    return GestureDetector(
      onTap: () => showMediaPreview(context, url),
      child: Hero(tag: 'photo-$url', child: image),
    );
  }
}

/// Image réseau avec chargement, erreur et **nouvel essai**.
class _RetryNetworkImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final double height;
  final String? semanticLabel;
  const _RetryNetworkImage(
      {required this.url,
      required this.fit,
      required this.height,
      this.semanticLabel});

  @override
  State<_RetryNetworkImage> createState() => _RetryNetworkImageState();
}

class _RetryNetworkImageState extends State<_RetryNetworkImage> {
  /// Incrémenté à chaque « Réessayer » pour forcer un nouveau téléchargement
  /// (Flutter garde l'erreur en cache pour la même URL).
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Image.network(
        _attempt == 0 ? widget.url : '${widget.url}#retry=$_attempt',
        key: ValueKey('${widget.url}#$_attempt'),
        semanticLabel: widget.semanticLabel ?? L10n.t('photo'),
        fit: widget.fit,
        cacheWidth: 1080,
        gaplessPlayback: true,
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
        errorBuilder: (_, __, ___) => _MediaError(
          icon: Icons.broken_image_rounded,
          label: 'Image indisponible',
          onRetry: () => setState(() => _attempt++),
        ),
      ),
    );
  }
}

/// Aperçu d'une vidéo : la miniature capturée par le serveur, un bouton de
/// lecture par-dessus et la durée en bas à droite.
///
/// Si la miniature ne se charge pas (fichier retiré, réseau capricieux), on
/// retombe proprement sur un fond neutre et le bouton reste utilisable : la
/// lecture, elle, ne dépend pas de l'image d'aperçu.
class _PosterVideo extends StatelessWidget {
  final String url;
  final double height;
  final String? dureeLabel;
  final VoidCallback onPlay;

  const _PosterVideo({
    required this.url,
    required this.height,
    required this.onPlay,
    this.dureeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Lire la vidéo${dureeLabel != null ? ' ($dureeLabel)' : ''}',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => Container(color: MC.nuit3),
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : Container(color: MC.nuit3),
            ),
            // Voile sombre : garantit que le bouton reste visible sur une image
            // claire.
            Container(color: Colors.black.withValues(alpha: .18)),
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MC.soleil,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .35),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(Icons.play_arrow_rounded,
                    color: MC.nuit, size: 34),
              ),
            ),
            if (dureeLabel != null && dureeLabel!.isNotEmpty)
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .65),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    dureeLabel!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: Tx.caption,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            // Le bouton de lecture est aussi une cible tactile explicite.
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: onPlay),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

///Vidéo courte jouée **dans** la carte (pas d'écran intermédiaire).
///
/// Rien n'est téléchargé avant l'appui sur : sur une connexion 3G congolaise,
/// c'est la différence entre un fil fluide et un fil qui rame.
/// Bus d'autoplay intelligent du fil : une seule vidéo joue à la fois,
/// lecture auto uniquement si ≥ 70 % de la carte est visible, pause sinon.
class MboteVideoBus {
  MboteVideoBus._();
  static final MboteVideoBus instance = MboteVideoBus._();
  final Map<GlobalKey, _Entry> _entries = {};

  void register(GlobalKey key, VideoPlayerController c, bool autoPlay,
      Future<void> Function() onPlay, Future<void> Function() onPause) {
    _entries[key] = _Entry(key, c, autoPlay, onPlay, onPause);
  }

  void unregister(GlobalKey key) => _entries.remove(key);

  /// 🛑 Pause IMMÉDIATE de toutes les vidéos + coupure du son.
  /// Appelé au changement d'onglet, navigation, mise en arrière-plan, verrouillage.
  void pauseAll() {
    for (final e in _entries.values) {
      try {
        if (e.c.value.isInitialized) {
          if (e.c.value.isPlaying) e.c.pause();
          e.c.setVolume(0);
        }
      } catch (_) {}
    }
  }

  void onScroll(BuildContext ctx) {
    final h = MediaQuery.of(ctx).size.height;
    _Entry? best;
    for (final e in _entries.values) {
      final ro = e.key.currentContext?.findRenderObject();
      if (ro is! RenderBox || !ro.attached) continue;
      final rect = (ro.localToGlobal(Offset.zero) & ro.size);
      final visibleH = (rect.bottom.clamp(0.0, h) - rect.top.clamp(0.0, h));
      e.visible = rect.height == 0 ? 0 : visibleH / rect.height;
      if (e.autoPlay && e.visible >= 0.70 &&
          (best == null || e.visible > best.visible)) best = e;
    }
    for (final e in _entries.values) {
      if (!e.c.value.isInitialized) continue;
      if (e == best && !e.c.value.isPlaying) e.onPlay();
      else if (e != best && e.c.value.isPlaying && e.autoPlay) e.onPause();
    }
  }
}

class _Entry {
  final GlobalKey key;
  final VideoPlayerController c;
  final bool autoPlay;
  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;
  double visible = 0;
  _Entry(this.key, this.c, this.autoPlay, this.onPlay, this.onPause);
}

/// Mémorise la position de lecture pour une reprise automatique silencieuse.
class VideoResume {
  static Future<void> save(String url, Duration pos) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('vpos_$url', pos.inMilliseconds);
  }

  static Future<Duration?> read(String url) async {
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt('vpos_$url') ?? 0;
    return ms > 0 ? Duration(milliseconds: ms) : null;
  }

  static Future<void> clear(String url) async {
    final p = await SharedPreferences.getInstance();
    await p.remove('vpos_$url');
  }
}

class MboteVideo extends StatefulWidget {
  final String url;
  final double height;
  final bool autoPlay;
  final bool loop;

  /// Miniature fournie par le serveur (première image de la vidéo, capturée à
  /// l'envoi). Quand elle existe, l'aperçu s'affiche **immédiatement** et la
  /// vidéo n'est téléchargée qu'à l'appui sur la lecture : sur une connexion
  /// mobile congolaise, c'est la différence entre un fil qui défile et un fil
  /// qui attend.
  final String? posterUrl;

  /// Durée affichée sur la miniature (ex. « 0:42 »).
  final String? dureeLabel;

  const MboteVideo({
    super.key,
    required this.url,
    this.height = 220,
    this.autoPlay = false,
    this.loop = true,
    this.posterUrl,
    this.dureeLabel,
  });

  @override
  State<MboteVideo> createState() => _MboteVideoState();
}

class _MboteVideoState extends State<MboteVideo> {
  final GlobalKey _key = GlobalKey();
  Timer? _posTimer;
  bool _vdragLeft = true;
  VideoPlayerController? _c;
  bool _starting = false;
  String? _error;

  // ── Contrôles premium ──
  bool _showControls = true;
  Timer? _hideTimer;
  bool _scrubbing = false;
  Duration _scrubPos = Duration.zero;
  double _speed = 1.0;
  bool _boost2x = false; // appui long → 2x temporaire
  String? _hint; // 'recul' | 'avance' affiché après double tap
  Timer? _hintTimer;
  double _brightness = 1.0; // glisser vertical gauche (voile de luminosité)
  double? _dragVol; // volume pendant le glisser vertical droit
  bool _wasPlayingBeforeFullscreen = true;

  bool get _ready => _c != null && _c!.value.isInitialized;
  Duration get _pos => _scrubbing ? _scrubPos : (_c?.value.position ?? Duration.zero);
  Duration get _dur => _c?.value.duration ?? Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.autoPlay) _start();
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await c.initialize();
      await c.setLooping(widget.loop);
      // Volume persisté (mémoire du niveau sonore entre les vidéos)
      final prefs = await SharedPreferences.getInstance();
      await c.setVolume(prefs.getDouble('video_volume') ?? 1.0);
      await c.setPlaybackSpeed(_speed);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _c = c;
        _starting = false;
      });
      // Autoplay intelligent : enregistré dans le bus (70 % visible, 1 seule vidéo)
      if (widget.autoPlay) {
        MboteVideoBus.instance.register(_key, c, widget.autoPlay, () async {
          if (!c.value.isPlaying) await c.play();
          if (mounted) setState(() {});
        }, () async {
          if (c.value.isPlaying) await c.pause();
          if (mounted) setState(() {});
        });
      }
      // Reprise de lecture SILENCIEUSE : plus de boîte de dialogue gênante.
      // La vidéo reprend automatiquement là où elle s'était arrêtée (style TikTok).
      final saved = await VideoResume.read(widget.url);
      if (saved != null && saved.inSeconds > 5) {
        await c.seekTo(saved);
      }
      await c.play();
      _armHide();
      // Mémorise la position toutes les 2 s (reprise après coupure / fermeture)
      _posTimer?.cancel();
      _posTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (c.value.isInitialized) VideoResume.save(widget.url, c.value.position);
      });
    } catch (_) {
      try {
        await c.dispose();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _c = null;
        _starting = false;
        _error = 'Vidéo indisponible — vérifie ta connexion';
      });
    }
  }

  Future<void> _toggle() async {
    final c = _c;
    if (c == null) {
      await _start();
      return;
    }
    if (c.value.isPlaying) {
      await c.pause();
      _showCtrl();
    } else {
      await c.play();
      _armHide();
    }
    if (mounted) setState(() {});
  }

  void _showCtrl() {
    setState(() => _showControls = true);
    _armHide();
  }

  void _armHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_c?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  Future<void> _seek(Duration d) async {
    final c = _c;
    if (c == null) return;
    final max = _dur.inMilliseconds;
    var ms = d.inMilliseconds.clamp(0, max > 0 ? max : 0);
    await c.seekTo(Duration(milliseconds: ms));
    if (mounted) setState(() {});
  }

  Future<void> _skip(int seconds) async {
    HapticFeedback.selectionClick();
    await _seek(_pos + Duration(seconds: seconds));
    setState(() {
      _hint = seconds < 0 ? 'recul' : 'avance';
    });
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  Future<void> _setSpeed(double v) async {
    _speed = v;
    await _c?.setPlaybackSpeed(v);
    if (mounted) setState(() {});
  }

  /// Plein écran : même contrôleur (aucun rechargement), rotation auto.
  Future<void> _openFullscreen() async {
    final c = _c;
    if (c == null) return;
    _wasPlayingBeforeFullscreen = c.value.isPlaying;
    await c.pause();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    if (!mounted) return;
    await Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      pageBuilder: (_, __, ___) => _FullscreenVideo(
        controller: c,
        speed: _speed,
        onSpeed: _setSpeed,
        onExit: () async {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
          if (_wasPlayingBeforeFullscreen) await c.play();
          if (mounted) setState(() {});
        },
      ),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOut),
          ),
          child: child,
        ),
      ),
    ));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hintTimer?.cancel();
    _posTimer?.cancel();
    final c = _c;
    if (c != null && c.value.isInitialized) {
      VideoResume.save(widget.url, c.value.position);
    }
    MboteVideoBus.instance.unregister(_key);
    _c = null;
    c?.dispose();
    super.dispose();
  }

  // ── Gestes ─────────────────────────────────────────────
  void _onTap() {
    if (!_ready) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) _armHide();
  }

  void _onDoubleTap(Offset pos, double width) {
    if (!_ready) return;
    if (pos.dx < width / 2) {
      _skip(-10); // double tap gauche : -10 s
    } else {
      _skip(10); // double tap droite : +10 s
    }
  }

  void _onLongPressStart() {
    if (!_ready) return;
    _boost2x = true;
    _setSpeed(2.0); // appui long : 2x temporaire
  }

  void _onLongPressEnd() {
    if (!_boost2x) return;
    _boost2x = false;
    _setSpeed(_speed); // retour à la vitesse choisie
  }

  void _onHorizontalDrag(double dx, double width) {
    if (!_ready) return;
    final total = _dur.inSeconds == 0 ? 1 : _dur.inSeconds;
    final delta = (dx / width) * total * 0.6; // glisser = navigation temporelle
    setState(() {
      _scrubbing = true;
      _scrubPos = Duration(
          milliseconds: ((_c!.value.position.inMilliseconds + delta * 1000)
                  .clamp(0, _dur.inMilliseconds))
              .toInt());
    });
  }

  void _onHDragEnd() async {
    if (!_scrubbing) return;
    await _seek(_scrubPos);
    if (mounted) setState(() => _scrubbing = false);
  }

  void _onVerticalDrag(double dy, double height, bool leftHalf) {
    if (!_ready) return;
    final delta = -dy / height; // haut = +, bas = −
    if (leftHalf) {
      // Luminosité (voile appliqué au lecteur)
      setState(() => _brightness = (_brightness + delta * 0.8).clamp(0.2, 1.0));
    } else {
      // Volume
      final c = _c!;
      final v = ((_dragVol ?? c.value.volume) + delta * 0.8).clamp(0.0, 1.0);
      _dragVol = v;
      c.setVolume(v);
      setState(() {});
    }
  }

  void _onVDragEnd() {
    _dragVol = null;
    if (mounted) setState(() {});
  }

  // ── UI ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SizedBox(
        height: widget.height,
        width: double.infinity,
        child: _MediaError(
          icon: Icons.videocam_off_rounded,
          label: _error!,
          onRetry: _start,
        ),
      );
    }

    if (!_ready) {
      final poster = widget.posterUrl;
      if (poster != null && poster.isNotEmpty && !_starting) {
        return GestureDetector(
          onTap: _start,
          child: _PosterVideo(
            url: poster,
            height: widget.height,
            dureeLabel: widget.dureeLabel,
            onPlay: _start,
          ),
        );
      }
      return GestureDetector(
        onTap: _starting ? null : _start,
        child: Container(
          height: widget.height,
          width: double.infinity,
          color: MC.nuit3,
          child: Center(
            child: _starting
                ? SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: MC.soleil))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: MC.soleil,
                          boxShadow: [
                            BoxShadow(
                                color: MC.soleil.withValues(alpha: .3),
                                blurRadius: 18,
                                spreadRadius: 2),
                          ],
                        ),
                        child: Icon(Icons.play_arrow_rounded,
                            color: MC.nuit, size: 34),
                      ),
                      const SizedBox(height: 8),
                      Text('Appuyer pour lire la vidéo',
                          style: TextStyle(color: MC.kaki, fontSize: Tx.caption)),
                    ],
                  ),
          ),
        ),
      );
    }

    final c = _c!;
    return KeyedSubtree(
      key: _key,
      child: LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          onDoubleTapDown: (d) => _onDoubleTap(d.localPosition, w),
          onLongPressStart: (_) => _onLongPressStart(),
          onLongPressEnd: (_) => _onLongPressEnd(),
          onHorizontalDragUpdate: (d) => _onHorizontalDrag(d.delta.dx, w),
          onHorizontalDragEnd: (_) => _onHDragEnd(),
          onVerticalDragStart: (d) => _vdragLeft = d.localPosition.dx < w / 2,
          onVerticalDragUpdate: (d) =>
              _onVerticalDrag(d.delta.dy, h, _vdragLeft),
          onVerticalDragEnd: (_) => _onVDragEnd(),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: c.value.size.width,
                    height: c.value.size.height,
                    child: VideoPlayer(c),
                  ),
                ),
                // Buffering : reprise automatique après coupure réseau
                if (c.value.isBuffering)
                  Center(
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: MC.soleil),
                    ),
                  ),
                // Voile de luminosité (glisser vertical gauche)
                if (_brightness < 1)
                  Container(
                      color: Colors.black
                          .withValues(alpha: (1 - _brightness).clamp(0, .8))),
                // Indicateur geste (recul / avance / 2x)
                if (_hint != null || _boost2x)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .6),
                        borderRadius: BorderRadius.circular(Rd.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _boost2x
                                ? Icons.fast_forward_rounded
                                : _hint == 'recul'
                                    ? Icons.replay_10_rounded
                                    : Icons.forward_10_rounded,
                            color: MC.soleil,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _boost2x
                                ? '2x'
                                : _hint == 'recul'
                                    ? '−10 s'
                                    : '+10 s',
                            style: TextStyle(
                                color: MC.ivoire,
                                fontSize: Tx.body,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Voile + bouton central quand pause
                if (!c.value.isPlaying && !_showControls)
                  Container(
                    color: Colors.black.withValues(alpha: .35),
                    child: Center(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: MC.soleil.withValues(alpha: .92),
                        ),
                        child: Icon(Icons.play_arrow_rounded,
                            color: MC.nuit, size: 32),
                      ),
                    ),
                  ),
                // Barre de contrôle premium (masquée auto après 3 s)
                if (_showControls) _buildControls(c),
              ],
            ),
          ),
        );
      },
      ),
    );
  }

  Widget _buildControls(VideoPlayerController c) {
    final playing = c.value.isPlaying;
    return Stack(
      fit: StackFit.expand,
      children: [
        // dégradés haut/bas pour lisibilité
        Positioned(
          top: 0, left: 0, right: 0, height: 70,
          child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                Colors.black.withValues(alpha: .55),
                Colors.transparent
              ]))),
        ),
        Positioned(
          bottom: 0, left: 0, right: 0, height: 110,
          child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                Colors.black.withValues(alpha: .65),
                Colors.transparent
              ]))),
        ),
        // bouton central play/pause
        Center(
          child: GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: .55),
                border: Border.all(color: MC.soleil.withValues(alpha: .8)),
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: MC.soleil,
                size: 34,
              ),
            ),
          ),
        ),
        // barre du bas : progression + boutons
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ProgressBar(
                  pos: _pos,
                  dur: _dur,
                  buffered: c.value.buffered.isNotEmpty
                      ? c.value.buffered.last.end
                      : Duration.zero,
                  onScrubStart: () {
                    _scrubbing = true;
                    _hideTimer?.cancel();
                  },
                  onScrubUpdate: (d) => setState(() => _scrubPos = d),
                  onScrubEnd: (d) async {
                    await _seek(d);
                    setState(() => _scrubbing = false);
                    _armHide();
                  },
                ),
                Row(
                  children: [
                    _ctrlBtn(Icons.replay_10_rounded, () => _skip(-10),
                        'Reculer de 10 secondes'),
                    _ctrlBtn(
                        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        _toggle,
                        playing ? 'Pause' : 'Lecture'),
                    _ctrlBtn(Icons.forward_10_rounded, () => _skip(10),
                        'Avancer de 10 secondes'),
                    const SizedBox(width: 6),
                    Text(
                      '${_fmt(_pos)} / ${_fmt(_dur)}',
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.caption,
                          fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    const Spacer(),
                    // volume
                    _ctrlBtn(
                      c.value.volume > 0
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      () async {
                        final v = c.value.volume > 0 ? 0.0 : 1.0;
                        await c.setVolume(v);
                        final p = await SharedPreferences.getInstance();
                        await p.setDouble('video_volume', v);
                        if (mounted) setState(() {});
                      },
                      'Volume',
                    ),
                    // vitesse
                    _ctrlBtn(Icons.speed_rounded, () => _showSpeedMenu(),
                        'Vitesse de lecture'),
                    // qualité
                    _ctrlBtn(Icons.hd_rounded, () => _showQualityMenu(),
                        'Qualité vidéo'),
                    // plein écran
                    _ctrlBtn(Icons.fullscreen_rounded, _openFullscreen,
                        'Plein écran'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _ctrlBtn(IconData icon, VoidCallback onTap, String tooltip) {
    return Semantics(
      button: true,
      label: tooltip,
      child: IconButton(
        icon: Icon(icon, color: MC.ivoire, size: 22),
        tooltip: tooltip,
        onPressed: () {
          HapticFeedback.selectionClick();
          onTap();
        },
      ),
    );
  }

  /// Menu qualité : « Auto » est la seule source disponible côté serveur
  /// aujourd'hui ; les autres paliers apparaîtront dès que le backend
  /// fournira des variantes (sans relancer la vidéo).
  void _showQualityMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.nuit2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Rd.lg))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final q in ['Auto', '1080p', '720p', '480p', '360p', '240p'])
              ListTile(
                leading: Icon(
                  q == 'Auto'
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: q == 'Auto' ? MC.soleil : MC.kaki,
                  size: 20,
                ),
                title: Text(q,
                    style: TextStyle(
                        color: q == 'Auto' ? MC.soleil : MC.ivoire,
                        fontWeight: FontWeight.w700)),
                subtitle: q == 'Auto'
                    ? const Text('Recommandé — s’adapte à ta connexion')
                    : const Text('Disponible quand le serveur fournit la variante'),
                onTap: q == 'Auto' ? () => Navigator.pop(context) : null,
              ),
          ],
        ),
      ),
    );
  }

  void _showSpeedMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.nuit2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Rd.lg))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final v in [0.5, 1.0, 1.5, 2.0])
              ListTile(
                leading: Icon(
                  _speed == v ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: _speed == v ? MC.soleil : MC.kaki,
                  size: 20,
                ),
                title: Text('${v}x',
                    style: TextStyle(
                        color: _speed == v ? MC.soleil : MC.ivoire,
                        fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.pop(context);
                  _setSpeed(v);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// Barre de progression moderne : piste visible, zone tamponnée, tête de
/// lecture, aperçu de position pendant le glisser.
class _ProgressBar extends StatelessWidget {
  final Duration pos;
  final Duration dur;
  final Duration buffered;
  final VoidCallback onScrubStart;
  final ValueChanged<Duration> onScrubUpdate;
  final ValueChanged<Duration> onScrubEnd;
  const _ProgressBar({
    required this.pos,
    required this.dur,
    required this.buffered,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
  });

  @override
  Widget build(BuildContext context) {
    final total = dur.inMilliseconds == 0 ? 1 : dur.inMilliseconds;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => onScrubStart(),
          onHorizontalDragUpdate: (d) =>
              onScrubUpdate(Duration(
                  milliseconds: ((d.localPosition.dx / w) * total).clamp(0, total).toInt())),
          onHorizontalDragEnd: (d) => onScrubEnd(Duration(
              milliseconds: ((d.localPosition.dx / w) * total).clamp(0, total).toInt())),
          onTapDown: (d) => onScrubEnd(Duration(
              milliseconds: ((d.localPosition.dx / w) * total).clamp(0, total).toInt())),
          child: SizedBox(
            height: 22,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                    height: 4,
                    width: w,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .25),
                        borderRadius: BorderRadius.circular(Rd.pill))),
                Container(
                    height: 4,
                    width: w * (buffered.inMilliseconds / total).clamp(0, 1),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(Rd.pill))),
                Container(
                    height: 4,
                    width: w * (pos.inMilliseconds / total).clamp(0, 1),
                    decoration: BoxDecoration(
                        color: MC.soleil,
                        borderRadius: BorderRadius.circular(Rd.pill))),
                Positioned(
                  left: (w * (pos.inMilliseconds / total).clamp(0, 1)) - 6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: MC.soleil),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Écran plein écran : réutilise le MÊME contrôleur (aucun rechargement),
/// masque les éléments système, rotation paysage autorisée.
class _FullscreenVideo extends StatefulWidget {
  final VideoPlayerController controller;
  final double speed;
  final Future<void> Function(double) onSpeed;
  final Future<void> Function() onExit;
  const _FullscreenVideo({
    required this.controller,
    required this.speed,
    required this.onSpeed,
    required this.onExit,
  });
  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo> {
  bool _show = true;
  bool _locked = false; // verrouillage de l'orientation vidéo
  Timer? _t;

  Future<void> _toggleLock() async {
    setState(() => _locked = !_locked);
    HapticFeedback.selectionClick();
    await SystemChrome.setPreferredOrientations(_locked
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
            DeviceOrientation.portraitUp,
          ]);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _arm() {
    _t?.cancel();
    _t = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _show = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          await widget.onExit();
          if (context.mounted) Navigator.of(context).pop();
        },
        child: GestureDetector(
          onTap: () {
            setState(() => _show = !_show);
            if (_show) _arm();
          },
          onDoubleTapDown: (d) {
            final w = MediaQuery.of(context).size.width;
            final target = c.value.position +
                Duration(seconds: d.localPosition.dx < w / 2 ? -10 : 10);
            final dur = c.value.duration;
            c.seekTo(target < Duration.zero
                ? Duration.zero
                : (dur > Duration.zero && target > dur ? dur : target));
            HapticFeedback.selectionClick();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: c.value.size.width,
                    height: c.value.size.height,
                    child: VideoPlayer(c),
                  ),
                ),
              ),
              if (_show)
                SafeArea(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded,
                                color: Colors.white),
                            onPressed: () async {
                              await widget.onExit();
                              if (context.mounted) Navigator.of(context).pop();
                            },
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                                _locked
                                    ? Icons.screen_lock_landscape_rounded
                                    : Icons.screen_rotation_rounded,
                                color: Colors.white),
                            tooltip: 'Verrouiller la rotation',
                            onPressed: _toggleLock,
                          ),
                          IconButton(
                            icon: const Icon(Icons.speed_rounded,
                                color: Colors.white),
                            tooltip: 'Vitesse ${widget.speed}x — changer',
                            onPressed: () async {
                              HapticFeedback.selectionClick();
                              final next = widget.speed >= 2.0
                                  ? 0.5
                                  : widget.speed >= 1.5
                                      ? 2.0
                                      : widget.speed >= 1.0
                                          ? 1.5
                                          : 1.0;
                              await widget.onSpeed(next);
                              if (mounted) setState(() {});
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.fullscreen_exit_rounded,
                                color: Colors.white),
                            onPressed: () async {
                              await widget.onExit();
                              if (context.mounted) Navigator.of(context).pop();
                            },
                          ),
                        ],
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: VideoProgressIndicator(
                          c,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Color(0xFFE9C27C),
                            bufferedColor: Color(0x59E9C27C),
                            backgroundColor: Color(0x59000000),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}


class _MediaError extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onRetry;
  const _MediaError(
      {required this.icon, required this.label, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      width: double.infinity,
      color: MC.nuit3,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: MC.kaki, size: 30),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MC.kaki, fontSize: Tx.caption)),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded, size: 14, color: MC.soleil),
              label: Text('Réessayer',
                  style: TextStyle(color: MC.soleil, fontSize: Tx.label)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aperçu plein écran PREMIUM d'une image :
/// • transition Hero depuis la miniature du fil
/// • pincer pour zoomer (jusqu'à 5×) + double-tap pour zoomer 1×↔2,5×
/// • glisser vers le bas (sans zoom) pour fermer, ✕ ou retour arrière
/// • barre d'actions : partager le lien, télécharger la photo
Future<void> showMediaPreview(BuildContext context, String url) {
  return Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black,
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, animation, __) => _PhotoViewerPage(url: url),
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
  ));
}

class _PhotoViewerPage extends StatefulWidget {
  final String url;
  const _PhotoViewerPage({required this.url});
  @override
  State<_PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<_PhotoViewerPage> {
  final _tc = TransformationController();
  double _dragDy = 0;
  bool _busy = false;
  bool _ui = true; // tap simple : masque/affiche les barres (style Facebook)

  bool get _zoomed => _tc.value.getMaxScaleOnAxis() > 1.05;

  void _doubleTap() {
    if (_zoomed) {
      _tc.value = Matrix4.identity();
    } else {
      _tc.value = Matrix4.identity()..scale(2.5);
    }
  }

  Future<void> _share() async {
    HapticFeedback.selectionClick();
    await Share.share(widget.url, subject: 'Photo — MboteCall');
  }

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await http.get(Uri.parse(widget.url));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final dir = await MediaStore.instance.dir;
      final name = 'mbote_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(r.bodyBytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L10n.t('saved')),
          backgroundColor: MC.savane,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L10n.t('error')),
          backgroundColor: MC.rouge,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dismiss = (_dragDy / 220).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 1 - dismiss * .85),
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onVerticalDragUpdate: (d) {
                if (!_zoomed) setState(() => _dragDy += d.delta.dy);
              },
              onVerticalDragEnd: (d) {
                if (!_zoomed && (_dragDy > 120 || d.velocity.pixelsPerSecond.dy > 600)) {
                  Navigator.of(context).pop();
                } else {
                  setState(() => _dragDy = 0);
                }
              },
              onTap: () => setState(() => _ui = !_ui),
              onDoubleTap: _doubleTap,
              child: Transform.translate(
                offset: Offset(0, _dragDy),
                child: InteractiveViewer(
                  transformationController: _tc,
                  minScale: 1,
                  maxScale: 5,
                  onInteractionEnd: (_) => setState(() {}),
                  child: Center(
                    child: Hero(
                      tag: 'photo-${widget.url}',
                      child: Image.network(
                        widget.url,
                        semanticLabel: L10n.t('photo'),
                        fit: BoxFit.contain,
                        loadingBuilder: (c, child, p) => p == null
                            ? child
                            : const Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white)),
                        errorBuilder: (_, __, ___) => const Center(
                          child: Text('Image indisponible',
                              style: TextStyle(color: Colors.white70)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _ui ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_ui,
                child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 26),
                      tooltip: L10n.t('close'),
                    ),
                    const SizedBox(width: 6),
                    Text(L10n.t('photo'),
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: Tx.bodyLg,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _ui ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_ui,
                child: SafeArea(
              top: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _action(Icons.share_rounded, L10n.t('share'), _share),
                    _action(
                        _busy
                            ? Icons.hourglass_top_rounded
                            : Icons.download_rounded,
                        L10n.t('download'),
                        _busy ? () {} : _download),
                  ],
                ),
              ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .14),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
