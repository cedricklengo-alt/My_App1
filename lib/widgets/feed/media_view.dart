// lib/widgets/feed/media_view.dart
//Lecture des médias du fil : image (aperçu plein écran) et vidéo courte
// (lecture directe dans la carte).
//
// Tout est fait pour ne jamais casser l'écran :
//   • chargement  → indicateur de progression ;
//   • erreur      → message clair + bouton « Réessayer » ;
// • vidéo → aucune donnée téléchargée avant l'appui sur (éco data) ;
//   • plugin absent (tests d'interface) → état d'erreur propre, pas de crash.

import 'package:flutter/material.dart';

import '../../l10n.dart';
import 'package:video_player/video_player.dart';

import '../../design.dart';
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
      child: image,
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

///Vidéo courte jouée **dans** la carte (pas d'écran intermédiaire).
///
/// Rien n'est téléchargé avant l'appui sur : sur une connexion 3G congolaise,
/// c'est la différence entre un fil fluide et un fil qui rame.
class MboteVideo extends StatefulWidget {
  final String url;
  final double height;
  final bool autoPlay;
  final bool loop;

  const MboteVideo({
    super.key,
    required this.url,
    this.height = 220,
    this.autoPlay = false,
    this.loop = true,
  });

  @override
  State<MboteVideo> createState() => _MboteVideoState();
}

class _MboteVideoState extends State<MboteVideo> {
  VideoPlayerController? _c;
  bool _starting = false;
  String? _error;

  bool get _ready => _c != null && _c!.value.isInitialized;

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
      await c.setVolume(1);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _c = c;
        _starting = false;
      });
      await c.play();
    } catch (_) {
      // Fichier introuvable, format non pris en charge, ou plugin absent
      // (tests d'interface) : on affiche une erreur propre.
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
    } else {
      await c.play();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final c = _c;
    _c = null;
    c?.dispose();
    super.dispose();
  }

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
                        strokeWidth: 2, color: MC.soleil),
                  )
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

    return GestureDetector(
      onTap: _toggle,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _c!.value.size.width,
                height: _c!.value.size.height,
                child: VideoPlayer(_c!),
              ),
            ),
 // Voile + bouton lecture au centre quand la vidéo est en pause
            if (!_c!.value.isPlaying)
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
            // Barre de progression fine en bas
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                _c!,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: MC.soleil,
                  bufferedColor: MC.soleil.withValues(alpha: .35),
                  backgroundColor: Colors.black.withValues(alpha: .45),
                ),
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
            ),
            // Bouton son
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () async {
                  final v = _c!.value.volume > 0 ? 0.0 : 1.0;
                  await _c!.setVolume(v);
                  if (mounted) setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: .55),
                  ),
                  child: Icon(
                    _c!.value.volume > 0
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    color: MC.ivoire,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
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

///Aperçu plein écran d'une image (pincer pour zoomer, glisser pour fermer).
Future<void> showMediaPreview(BuildContext context, String url) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .94),
    builder: (ctx) => Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: Image.network(
                url,
                semanticLabel: L10n.t('photo'),
                fit: BoxFit.contain,
                loadingBuilder: (c, child, p) => p == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                errorBuilder: (_, __, ___) => const Center(
                  child: Text('Image indisponible',
                      style: TextStyle(color: Colors.white70)),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 34,
          right: 16,
          child: IconButton(
            onPressed: () => Navigator.of(ctx).pop(),
            icon:
                const Icon(Icons.close_rounded, color: Colors.white, size: 26),
            tooltip: 'Fermer',
          ),
        ),
      ],
    ),
  );
}
