import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../design.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../call_status.dart';
import '../l10n.dart';
import '../rtc.dart';

/// Écran d'appel : sonnerie → conversation avec chrono (maquette 03 + v1.2).
///
///Appel MboteCall → MboteCall : design épuré validé sur maquette —
/// photo dans un anneau doré, nom, chrono, et l'icône officielle MboteCall
/// à la place de tout texte technique (pas de « MboteCall → MboteCall », pas de coût).
///
/// Mode démo : l'audio est simulé ; en mode Twilio, brancher ici le SDK
/// `twilio_voice` avec le jeton de /api/calls/voice-token (le reste est identique).
class CallScreen extends StatefulWidget {
  final String to;
  final String? displayName;

  ///Si non nul : on est l'APPELÉ (offre WebRTC reçue, on décroche)
  final Map? incomingOffer;

  ///Appel vidéo (caméra + micro). Sinon appel audio classique.
  final bool video;

  const CallScreen({
    super.key,
    required this.to,
    this.displayName,
    this.incomingOffer,
    this.video = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  //Pulsation douce de l'anneau pendant la sonnerie (design fluide).
  // Elle ne démarre PAS d'emblée : on interroge d'abord le réglage système
  // « Réduire les animations » (WCAG 2.3.3 / réglages Android &
  // Accessibilité iOS). Une animation qui pulse en boucle peut provoquer un
  // malaise chez les personnes sensibles au mouvement.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
    lowerBound: 0.97,
    upperBound: 1.05,
  );
  /// Dernier état connu du réglage « Réduire les animations ».
  bool? _mouvementReduit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduit = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduit == _mouvementReduit) return;
    _mouvementReduit = reduit;
    if (reduit) {
      _pulse.stop();
      _pulse.value = 1.0;
    } else {
      _pulse.repeat(reverse: true);
    }
  }

  String? callId;
  String status = 'connexion'; // connexion | ringing | answered | ended | error
  String destination = '';
  int elapsed = 0;
  int cost = 0;
  int priceMin = 0;
  String? freeReason; // 'mbote' | 'package' | null
  String? calleeName; // nom du compte MboteCall appelé
  String? calleeAvatar; //photo de profil de l'appelé (data-URI)
  String? endReason;
  String? error;
  bool muted = false;
  bool speaker = false;
  bool cameraOn = false; //caméra active (appels vidéo)

  //Moteurs d'affichage (créés à la première image reçue)
  RTCVideoRenderer? _localRender;
  RTCVideoRenderer? _remoteRender;

  /// Cet appel est-il un appel vidéo ? (demandé, ou annoncé par l'appelant)
  bool get isVideoCall =>
      widget.video || widget.incomingOffer?['video'] == true;
  bool pushSent = false; //l'appelé est prévenu par notification
  Timer? poll;

  //Vraie voix (WebRTC) — utilisée si l'appelé a l'app ouverte
  RtcSession? rtc;
  bool rtcMode = false;
  Timer? chrono;
  Timer? rtcTimeout; // garde-fou : injoignable si pas de réponse

  ///Relie les flux de la session aux moteurs d'affichage.
  void _attachVideo(RtcSession s) {
    if (!isVideoCall) return;
    cameraOn = true;
    s.onLocalStream = (stream) async {
      var r = _localRender;
      if (r == null) {
        r = RTCVideoRenderer();
        await r.initialize();
        _localRender = r;
      }
      r.srcObject = stream;
      if (mounted) setState(() {});
    };
    s.onRemoteStream = (stream) async {
      var r = _remoteRender;
      if (r == null) {
        r = RTCVideoRenderer();
        await r.initialize();
        _remoteRender = r;
      }
      r.srcObject = stream;
      if (mounted) setState(() {});
    };
  }

  bool get isMbote => freeReason == 'mbote';
  bool get isCallee => widget.incomingOffer != null;

  @override
  void initState() {
    super.initState();
    cameraOn = isVideoCall; //un appel vidéo démarre caméra allumée
    if (isCallee) {
      _answerIncoming();
    } else {
      _start();
    }
  }

  ///Côté appelé : on décroche l'offre reçue
  Future<void> _answerIncoming() async {
    final offer = widget.incomingOffer!;
    rtcMode = true;
    freeReason = 'mbote';
    callId = offer['call_id'];
    calleeName = offer['from_name']?.toString();
    calleeAvatar = offer['from_avatar']?.toString();
    Rtc.onSignal = _onSignal;
    rtc = RtcSession(
      peer: widget.to,
      callId: callId!,
      video: isVideoCall,
    );
    rtc!.onConnected = _onVoiceConnected;
    rtc!.onEnded = () => _endRtc(remote: true);
    // Aucun chemin réseau trouvé (NAT symétrique, pas de relais TURN) : on le
    // dit clairement au lieu de fermer l'écran sans explication.
    rtc!.onFailed = () => _endRtc(remote: true, reseau: true);
    _attachVideo(rtc!);
    try {
      await rtc!.answer(Map.from(offer['sdp']));
      //Rejoue les candidats réseau arrivés pendant la sonnerie
      for (final c in (offer['early_ice'] as List? ?? const [])) {
        await rtc!.addIce(Map.from(c));
      }
      if (mounted) setState(() => status = 'ringing'); // connexion en cours
    } catch (e) {
      if (mounted) {
        setState(() {
          status = 'error';
          error = 'Micro indisponible — vérifie la permission micro';
        });
      }
    }
  }

  ///Côté appelant : lance la vraie voix après /calls/start
  Future<void> _startRtc() async {
    Rtc.onSignal = _onSignal;
    rtc = RtcSession(
      peer: widget.to,
      callId: callId!,
      video: isVideoCall,
    );
    rtc!.onConnected = _onVoiceConnected;
    rtc!.onEnded = () => _endRtc(remote: true);
    // Aucun chemin réseau trouvé (NAT symétrique, pas de relais TURN) : on le
    // dit clairement au lieu de fermer l'écran sans explication.
    rtc!.onFailed = () => _endRtc(remote: true, reseau: true);
    _attachVideo(rtc!);
 // Si rien ne se passe en 25 s → le téléphone d'en face est injoignable
    rtcTimeout = Timer(const Duration(seconds: 25), () {
      if (status != 'answered') _endRtc(remote: true, unreachable: true);
    });
    try {
      await rtc!.call();
    } catch (e) {
      if (mounted) {
        setState(() {
          status = 'error';
          error = 'Micro indisponible — vérifie la permission micro';
        });
      }
    }
  }

  /// Les deux téléphones sont reliés : la voix passe !
  void _onVoiceConnected() {
    if (!mounted || status == 'ended') return;
    rtcTimeout?.cancel();
    _pulse.animateTo(1.0,
        duration: const Duration(milliseconds: 400)); //l'anneau se pose
    setState(() => status = 'answered');
    chrono?.cancel();
    chrono = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && status == 'answered') setState(() => elapsed++);
    });
  }

  /// Messages du standardiste pendant l'appel
  void _onSignal(Map msg) async {
    if (!mounted) return;
    switch (msg['type']) {
      case 'ringing': //l'écran sonne bien chez l'appelé → on patiente
        rtcTimeout?.cancel();
        rtcTimeout = Timer(const Duration(seconds: 60), () {
          if (status != 'answered') _endRtc(remote: true, unreachable: true);
        });
      case 'push-sent': //app fermée chez l'appelé → notification envoyée
        setState(() => pushSent = true);
        rtcTimeout?.cancel();
        rtcTimeout = Timer(const Duration(seconds: 60), () {
          if (status != 'answered') _endRtc(remote: true, unreachable: true);
        });
      case 'answer': // l'appelé a décroché
        await rtc?.acceptAnswer(Map.from(msg['sdp']));
      case 'ice':
        await rtc?.addIce(Map.from(msg['candidate']));
      case 'reject':
        _endRtc(remote: true, rejected: true);
      case 'hangup':
        _endRtc(remote: true);
      case 'peer-offline':
        // L'app d'en face s'est fermée entre-temps → injoignable
        _endRtc(remote: true, unreachable: true);
    }
  }

  /// Fin d'un appel voix réelle
  Future<void> _endRtc(
      {bool remote = false,
      bool rejected = false,
      bool unreachable = false,
      bool reseau = false}) async {
    if (status == 'ended') return;
    // On lit l'état AVANT les `await` : après, le widget peut avoir été
    // démonté et `context` ne doit plus être utilisé.
    final appState = context.read<AppState>();
    chrono?.cancel();
    rtcTimeout?.cancel();
    Rtc.onSignal = null;
    await rtc?.close();
    if (!remote) {
      Rtc.send({'type': 'hangup', 'to': widget.to, 'call_id': callId});
    }
    if (isCallee) {
      //L'appelé journalise l'appel reçu (répondu si durée > 0)
      try {
        await appState.api.logIncoming(widget.to, elapsed);
      } catch (_) {}
    } else if (callId != null) {
      // L'appelant clôt son enregistrement côté serveur (gratuit)
      try {
        await appState.api.hangup(callId!);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        status = 'ended';
        if (rejected) endReason = 'rejected';
        if (unreachable) endReason = 'unreachable';
        if (reseau) endReason = 'network';
      });
      _pulse.stop();
      //L'écran se referme tout seul après 2 s (bouton Fermer toujours là)
      Timer(const Duration(seconds: 2), () {
        if (mounted && status == 'ended') Navigator.maybePop(context);
      });
    }
  }

  Future<void> _start() async {
    final st = context.read<AppState>();
    try {
      final r = await st.api.startCall(widget.to);
      // L'utilisateur a pu quitter l'écran pendant la requête : on ne touche
      // plus à l'état dans ce cas (sinon « setState() called after dispose »).
      if (!mounted) return;
      callId = r['call_id'];
      destination = '${r['destination']}';
      priceMin = r['price_per_min_cents'];
      freeReason = r['free_reason'];
      calleeName = r['callee_name'];
      calleeAvatar = r['callee_avatar'];
      setState(() => status = 'ringing');
      // MboteCall → MboteCall : VRAIE VOIX (WebRTC), que l'appelé soit déjà
      // connecté ou non (le standardiste le réveille par notification et garde
      // l'offre en salle d'attente). Voir `appelViaRtc` : dépendre de
      // `rtc_online` faisait basculer tous les appels dans la simulation.
      if (appelViaRtc(freeReason)) {
        rtcMode = true;
        await _startRtc();
      } else {
        // Appel vers un GSM / mode démonstration de l'opérateur : on suit
        // l'état côté serveur.
        poll = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        status = 'error';
        error = friendlyError(e);
      });
    }
  }

  Future<void> _tick() async {
    if (callId == null) return;
    final st = context.read<AppState>();
    try {
      final r = await st.api.callStatus(callId!);
      if (!mounted) return;
      setState(() {
        status = r['status'];
        elapsed = r['elapsed_sec'];
        cost = r['cost_cents'];
      });
      if (r['status'] == 'ended') {
        poll?.cancel();
        endReason = r['hangup_cause'];
        st.setBalance(r['balance_after_cents']);
      }
    } catch (_) {/* réseau instable : on retente au tick suivant */}
  }

  Future<void> _hangup() async {
    if (rtcMode) {
      await _endRtc();
      return;
    }
    poll?.cancel();
    final st = context.read<AppState>();
    if (callId != null) {
      try {
        final r = await st.api.hangup(callId!);
        elapsed = r['billed_sec'];
        cost = r['cost_cents'];
        await st.refresh();
      } catch (_) {}
    }
    if (mounted) setState(() => status = 'ended');
  }

  @override
  void dispose() {
    _pulse.dispose();
    poll?.cancel();
    chrono?.cancel();
    rtcTimeout?.cancel();
    if (Rtc.onSignal == _onSignal) Rtc.onSignal = null;
    rtc?.close();
    _localRender?.dispose();
    _remoteRender?.dispose();
    super.dispose();
  }

  /// Libellé calculé par `libelleAppel` (lib/call_status.dart) : la table des
  /// messages est testée séparément, sans monter l'écran.
  String get statusLabel =>
      libelleAppel(status: status, endReason: endReason, pushSent: pushSent);

  @override
  Widget build(BuildContext context) {
    final name = widget.displayName ??
        (calleeName?.isNotEmpty == true ? calleeName! : widget.to);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final hasPhoto = calleeAvatar != null && calleeAvatar!.isNotEmpty;
    //MboteCall → MboteCall en conversation : aucun texte technique
    final minimal = isMbote && status == 'answered';

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -.6),
            radius: 1.2,
            colors: [MC.halo, MC.nuit],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              //En vidéo, l'image prend la place : pas de grands blancs.
              if (!isVideoCall)
                const Spacer(flex: 2)
              else
                const SizedBox(height: 6),
              // Statut discret — masqué pendant la conversation MboteCall → MboteCall
              SizedBox(
                height: 18,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: minimal
                      ? const SizedBox.shrink()
                      : Text(statusLabel,
                          key: ValueKey('$statusLabel$pushSent'),
                          style: TextStyle(
                              color:
                                  status == 'answered' ? MC.savane : MC.sable,
                              fontSize: Tx.label,
                              letterSpacing: 2)),
                ),
              ),
              const SizedBox(height: 26),
              //Appel vidéo : l'image de l'autre (ou l'avatar en attendant)
              //Appel audio : anneau dégradé doré + halo, photo ou initiale
              if (isVideoCall)
                Expanded(child: _videoArea(name, initial, hasPhoto))
              else
                ScaleTransition(
                  scale: _pulse,
                  // Identité « Fleuve Congo » : plus d'anneau lumineux, un
                  // cadre net de 2 px — l'avatar est un carré arrondi, comme
                  // partout dans l'application.
                  child: Container(
                    width: 140,
                    height: 140,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Rd.lg),
                      border: Border.all(color: MC.soleil, width: 2),
                    ),
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Rd.lg - 2),
                          color: MC.nuit2),
                      child: hasPhoto
                          ? Image.memory(
                              base64Decode(calleeAvatar!.split(',').last),
                              fit: BoxFit.cover,
                              excludeFromSemantics: true,
                              gaplessPlayback: true,
                            )
                          : Center(
                              child: Text(initial,
                                  style: TextStyle(
                                      fontSize: Tx.display + 10,
                                      fontWeight: FontWeight.w800,
                                      color: MC.soleil)),
                            ),
                    ),
                  ),
                ), // fin ScaleTransition
              const SizedBox(height: 18),
              Text(name,
                  style: TextStyle(
                      fontSize: Tx.headline,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.4,
                      color: MC.ivoire)),
              // Numéro + destination : masqués pour un appel MboteCall → MboteCall
              if (!isMbote) ...[
                if (widget.displayName != null)
                  Text(widget.to,
                      style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.public_rounded, size: 13, color: MC.kaki),
                  const SizedBox(width: 4),
                  Text(destination,
                      style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
                ]),
              ],
              const SizedBox(height: 14),
              // Chrono doré
              Text(fmtDur(elapsed),
                  style: TextStyle(
                      fontSize: Tx.display,
                      fontWeight: FontWeight.w800,
                      color: MC.soleil,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 12),
              //MboteCall → MboteCall : l'icône officielle, sans texte
              if (isMbote)
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: MC.soleil.withValues(alpha: .3),
                          blurRadius: 22,
                          spreadRadius: 2),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset('assets/icon/icon_small.png',
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        excludeFromSemantics: true),
                  ),
                )
              else if (priceMin == 0 && freeReason == 'package')
                Text('${L10n.t('free_call')} — ${L10n.t('free_package')}',
                    style: TextStyle(
                        color: MC.savane,
                        fontWeight: FontWeight.w800,
                        fontSize: Tx.label))
              else
                Text(
                  status == 'ended'
                      ? 'Total : ${fmtMoney(cost)} · ${fmtDur(elapsed)}'
                      : 'Coût : ${fmtMoney(cost)} · ${(priceMin / 100).toStringAsFixed(2)} \$/min',
                  style: TextStyle(color: MC.sable, fontSize: Tx.label),
                ),
              if (!isVideoCall)
                const Spacer(flex: 2)
              else
                const SizedBox(height: 10),
              if (status == 'error')
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(error ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: MC.rouge, fontSize: Tx.body)),
                ),
              if (!isVideoCall)
                const Spacer(flex: 2)
              else
                const SizedBox(height: 12),
              // Commandes : micro · raccrocher · haut-parleur (maquette validée)
              if (status == 'ended' || status == 'error')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: MboteButton(
                      label: 'Fermer', onTap: () => Navigator.pop(context)),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _round(muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        muted, () {
                      setState(() => muted = !muted);
                      rtc?.setMuted(muted); //coupe réellement le micro
                    }),
                    const SizedBox(width: 26),
                    GestureDetector(
                      onTap: _hangup,
                      child: Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Rd.lg),
                          color: Semantique.raccrocher,
                        ),
                        child: const Icon(Icons.call_end_rounded,
                            color: Colors.white, size: 32),
                      ),
                    ),
                    const SizedBox(width: 26),
                    if (isVideoCall) ...[
                      _round(
                        cameraOn
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                        !cameraOn,
                        () {
                          setState(() => cameraOn = !cameraOn);
                          rtc?.setVideoEnabled(cameraOn);
                        },
                      ),
                      const SizedBox(width: 26),
                      _round(Icons.flip_camera_ios_rounded, false, () {
                        rtc?.switchCamera();
                      }),
                    ] else
                      _round(Icons.volume_up_rounded, speaker, () {
                        setState(() => speaker = !speaker);
                        rtc?.setSpeaker(speaker); //vrai haut-parleur
                      }),
                  ],
                ),
              const SizedBox(height: 46),
            ],
          ),
        ),
      ),
    );
  }

  ///Zone vidéo : image du correspondant + mon aperçu en petit.
  Widget _videoArea(String name, String initial, bool hasPhoto) {
    final remote = _remoteRender;
    final showRemote = remote != null && remote.srcObject != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Rd.lg),
              child: Container(
                color: MC.nuit2,
                child: showRemote
                    ? FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: remote.videoWidth == 0
                              ? 360
                              : remote.videoWidth.toDouble(),
                          height: remote.videoHeight == 0
                              ? 640
                              : remote.videoHeight.toDouble(),
                          child: RTCVideoView(remote),
                        ),
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MboteAvatar(
                              name: name,
                              size: 88,
                              image: hasPhoto
                                  ? MemoryImage(
                                      base64Decode(calleeAvatar!.split(',').last))
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isCallee
                                  ? 'Connexion vidéo…'
                                  : 'En attente de sa caméra…',
                              style: TextStyle(color: MC.kaki, fontSize: Tx.label),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            // Mon aperçu (petit, en bas à droite)
            if (_localRender != null && _localRender!.srcObject != null)
              Positioned(
                right: 10,
                bottom: 10,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Rd.md),
                  child: SizedBox(
                    width: 78,
                    height: 108,
                    child: RTCVideoView(_localRender!, mirror: true),
                  ),
                ),
              ),
            if (!cameraOn)
              Positioned(
                left: 10,
                bottom: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(Rd.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_off_rounded,
                          size: 12, color: MC.rouge),
                      const SizedBox(width: 4),
                      Text('Caméra coupée',
                          style: TextStyle(color: MC.sable, fontSize: Tx.caption)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _round(IconData icon, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: Tap.confort,
          height: Tap.confort,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rd.md),
            color: active ? MC.soleil : MC.nuit2,
            border: Border.all(color: active ? MC.soleil : MC.ligne),
          ),
          child: Icon(icon, color: active ? MC.onAccent : MC.sable, size: 22),
        ),
      );
}
