import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../l10n.dart';
import '../rtc.dart';

/// Écran d'appel : sonnerie → conversation avec chrono (maquette 03 + v1.2).
///
/// 💚 Appel MboteCall → MboteCall : design épuré validé sur maquette —
/// photo dans un anneau doré, nom, chrono, et l'icône officielle MboteCall
/// à la place de tout texte technique (pas de « MboteCall → MboteCall », pas de coût).
///
/// Mode démo : l'audio est simulé ; en mode Twilio, brancher ici le SDK
/// `twilio_voice` avec le jeton de /api/calls/voice-token (le reste est identique).
class CallScreen extends StatefulWidget {
  final String to;
  final String? displayName;

  /// 📲 Si non nul : on est l'APPELÉ (offre WebRTC reçue, on décroche)
  final Map? incomingOffer;

  const CallScreen(
      {super.key, required this.to, this.displayName, this.incomingOffer});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  // 💫 Pulsation douce de l'anneau pendant la sonnerie (design fluide)
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
    lowerBound: 0.97,
    upperBound: 1.05,
  )..repeat(reverse: true);

  String? callId;
  String status = 'connexion'; // connexion | ringing | answered | ended | error
  String destination = '';
  int elapsed = 0;
  int cost = 0;
  int priceMin = 0;
  String? freeReason; // 'mbote' | 'package' | null
  String? calleeName; // nom du compte MboteCall appelé
  String? calleeAvatar; // 📷 photo de profil de l'appelé (data-URI)
  String? endReason;
  String? error;
  bool muted = false;
  bool speaker = false;
  bool pushSent = false; // 📲 l'appelé est prévenu par notification
  Timer? poll;

  // 🎙️ Vraie voix (WebRTC) — utilisée si l'appelé a l'app ouverte
  RtcSession? rtc;
  bool rtcMode = false;
  Timer? chrono;
  Timer? rtcTimeout; // ⏱️ garde-fou : injoignable si pas de réponse

  bool get isMbote => freeReason == 'mbote';
  bool get isCallee => widget.incomingOffer != null;

  @override
  void initState() {
    super.initState();
    if (isCallee) {
      _answerIncoming();
    } else {
      _start();
    }
  }

  /// 📲 Côté appelé : on décroche l'offre reçue
  Future<void> _answerIncoming() async {
    final offer = widget.incomingOffer!;
    rtcMode = true;
    freeReason = 'mbote';
    callId = offer['call_id'];
    calleeName = offer['from_name']?.toString();
    calleeAvatar = offer['from_avatar']?.toString();
    Rtc.onSignal = _onSignal;
    rtc = RtcSession(peer: widget.to, callId: callId!);
    rtc!.onConnected = _onVoiceConnected;
    rtc!.onEnded = () => _endRtc(remote: true);
    try {
      await rtc!.answer(Map.from(offer['sdp']));
      // 🧊 Rejoue les candidats réseau arrivés pendant la sonnerie
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

  /// 🎙️ Côté appelant : lance la vraie voix après /calls/start
  Future<void> _startRtc() async {
    Rtc.onSignal = _onSignal;
    rtc = RtcSession(peer: widget.to, callId: callId!);
    rtc!.onConnected = _onVoiceConnected;
    rtc!.onEnded = () => _endRtc(remote: true);
    // ⏱️ Si rien ne se passe en 25 s → le téléphone d'en face est injoignable
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
        duration: const Duration(milliseconds: 400)); // 💫 l'anneau se pose
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
      case 'ringing': // 📳 l'écran sonne bien chez l'appelé → on patiente
        rtcTimeout?.cancel();
        rtcTimeout = Timer(const Duration(seconds: 60), () {
          if (status != 'answered') _endRtc(remote: true, unreachable: true);
        });
      case 'push-sent': // 📲 app fermée chez l'appelé → notification envoyée
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
      bool unreachable = false}) async {
    if (status == 'ended') return;
    chrono?.cancel();
    rtcTimeout?.cancel();
    Rtc.onSignal = null;
    await rtc?.close();
    if (!remote) {
      Rtc.send({'type': 'hangup', 'to': widget.to, 'call_id': callId});
    }
    if (isCallee) {
      // 📥 L'appelé journalise l'appel reçu (répondu si durée > 0)
      try {
        await context.read<AppState>().api.logIncoming(widget.to, elapsed);
      } catch (_) {}
    } else if (callId != null) {
      // L'appelant clôt son enregistrement côté serveur (gratuit)
      try {
        await context.read<AppState>().api.hangup(callId!);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        status = 'ended';
        if (rejected) endReason = 'rejected';
        if (unreachable) endReason = 'unreachable';
      });
      _pulse.stop();
      // 🚪 L'écran se referme tout seul après 2 s (bouton Fermer toujours là)
      Timer(const Duration(seconds: 2), () {
        if (mounted && status == 'ended') Navigator.maybePop(context);
      });
    }
  }

  Future<void> _start() async {
    final st = context.read<AppState>();
    try {
      final r = await st.api.startCall(widget.to);
      callId = r['call_id'];
      destination = '${r['flag']} ${r['destination']}';
      priceMin = r['price_per_min_cents'];
      freeReason = r['free_reason'];
      calleeName = r['callee_name'];
      calleeAvatar = r['callee_avatar'];
      setState(() => status = 'ringing');
      // 🎙️ L'appelé a l'app ouverte → VRAIE VOIX (WebRTC)
      if (r['rtc_online'] == true && freeReason == 'mbote') {
        rtcMode = true;
        await _startRtc();
      } else {
        // Mode démo (simulation) : GSM ou appelé hors ligne
        poll = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      }
    } catch (e) {
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
    super.dispose();
  }

  String get statusLabel => switch (status) {
        'connexion' => 'Connexion…',
        'ringing' => pushSent ? '📲 Notification envoyée…' : '🔔 Ça sonne…',
        'answered' => '● EN LIGNE · HD',
        'ended' => endReason == 'no_credit'
            ? 'Crédit épuisé'
            : endReason == 'rejected'
                ? 'Occupé — réessaie plus tard'
                : endReason == 'unreachable'
                    ? 'Pas de réponse — réessaie plus tard'
                    : 'Appel terminé',
        _ => 'Erreur',
      };

  @override
  Widget build(BuildContext context) {
    final name = widget.displayName ??
        (calleeName?.isNotEmpty == true ? calleeName! : widget.to);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final hasPhoto = calleeAvatar != null && calleeAvatar!.isNotEmpty;
    // 💚 MboteCall → MboteCall en conversation : aucun texte technique
    final minimal = isMbote && status == 'answered';

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -.6),
            radius: 1.2,
            colors: [MC.halo, MC.nuit],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
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
                              color: status == 'answered'
                                  ? MC.savane
                                  : MC.sable,
                              fontSize: 13,
                              letterSpacing: 2)),
                ),
              ),
              const SizedBox(height: 26),
              // 📷 Avatar : anneau dégradé doré + halo, photo ou initiale
              // 💫 … qui pulse doucement tant que ça sonne
              ScaleTransition(
                scale: _pulse,
                child: Container(
                width: 128,
                height: 128,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                      colors: [MC.soleil, MC.braise, MC.terre, MC.soleil]),
                  boxShadow: [
                    BoxShadow(
                        color: MC.soleil.withOpacity(.22),
                        blurRadius: 36,
                        spreadRadius: 6),
                  ],
                ),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: MC.nuit2),
                  child: hasPhoto
                      ? Image.memory(
                          base64Decode(calleeAvatar!.split(',').last),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                        : Center(
                          child: Text(initial,
                              style: TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w800,
                                  color: MC.soleil)),
                        ),
                ),
              ),
              ), // fin ScaleTransition 💫
              const SizedBox(height: 18),
              Text(name,
                  style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: MC.ivoire)),
              // Numéro + destination : masqués pour un appel MboteCall → MboteCall
              if (!isMbote) ...[
                if (widget.displayName != null)
                  Text(widget.to,
                      style: TextStyle(color: MC.kaki, fontSize: 13)),
                Text(destination,
                    style: TextStyle(color: MC.kaki, fontSize: 12.5)),
              ],
              const SizedBox(height: 14),
              // Chrono doré
              Text(fmtDur(elapsed),
                  style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      color: MC.soleil,
                      fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(height: 12),
              // 💚 MboteCall → MboteCall : l'icône officielle, sans texte
              if (isMbote)
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: MC.soleil.withOpacity(.3),
                          blurRadius: 22,
                          spreadRadius: 2),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset('assets/icon/icon_small.png',
                        width: 52, height: 52, fit: BoxFit.cover),
                  ),
                )
              else if (priceMin == 0 && freeReason == 'package')
                Text('${L10n.t('free_call')} — ${L10n.t('free_package')}',
                    style: TextStyle(
                        color: MC.savane,
                        fontWeight: FontWeight.w800,
                        fontSize: 13))
              else
                Text(
                  status == 'ended'
                      ? 'Total : ${fmtMoney(cost)} · ${fmtDur(elapsed)}'
                      : 'Coût : ${fmtMoney(cost)} · ${(priceMin / 100).toStringAsFixed(2)} \$/min',
                  style: TextStyle(color: MC.sable, fontSize: 12.5),
                ),
              if (status == 'error')
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(error ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: MC.rouge, fontSize: 14)),
                ),
              const Spacer(flex: 2),
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
                    _round(
                        muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        muted, () {
                      setState(() => muted = !muted);
                      rtc?.setMuted(muted); // 🎤 coupe réellement le micro
                    }),
                    const SizedBox(width: 26),
                    GestureDetector(
                      onTap: _hangup,
                      child: Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: MC.rouge,
                          boxShadow: [
                            BoxShadow(
                                color: MC.rouge.withOpacity(.4),
                                blurRadius: 26,
                                offset: const Offset(0, 8)),
                          ],
                        ),
                        child: const Icon(Icons.call_end_rounded,
                            color: Colors.white, size: 32),
                      ),
                    ),
                    const SizedBox(width: 26),
                    _round(Icons.volume_up_rounded, speaker, () {
                      setState(() => speaker = !speaker);
                      rtc?.setSpeaker(speaker); // 🔊 vrai haut-parleur
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

  Widget _round(IconData icon, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? MC.soleil : MC.nuit3,
          ),
          child: Icon(icon,
              color: active ? MC.onAccent : MC.sable, size: 22),
        ),
      );
}
