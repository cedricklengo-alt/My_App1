import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:provider/provider.dart';
import '../l10n.dart';
import '../state.dart';
import '../design.dart';
import '../theme.dart';
import '../local/local_first.dart';
import '../rtc.dart';
import '../prefs.dart';
import 'call.dart';

///Appel MboteCall ENTRANT — sonnerie système + vibration,
/// même langage visuel que l'écran d'appel : anneau dégradé + halo,
/// nom, icône officielle, puis décrocher (vert) ou refuser (rouge).
class IncomingCallScreen extends StatefulWidget {
  final Map offer; // {from, from_name, from_avatar, call_id, sdp}
  const IncomingCallScreen({super.key, required this.offer});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  Timer? vibre;
  bool done = false; // évite double pop / double journal
  final List<Map> earlyIce =
      []; //candidats réseau arrivés pendant la sonnerie

  @override
  void initState() {
    super.initState();
    //Sonnerie + vibration selon les préférences (Profil → Paramètres)
    _startRingAndVibe();
    //Si l'appelant raccroche pendant la sonnerie → appel manqué
    //Et on mémorise les candidats réseau (ICE) reçus pendant qu'on sonne :
    //    ils seront rejoués au décrochage (indispensable quand on répond
    //    tard, par ex. après avoir touché la notification)
    Rtc.onSignal = (msg) {
      if (msg['call_id'] != widget.offer['call_id']) return;
      if (msg['type'] == 'hangup') {
        _finish(missed: true);
      } else if (msg['type'] == 'ice' && msg['candidate'] != null) {
        earlyIce.add(Map.from(msg['candidate']));
      }
    };
  }

  ///Démarre la sonnerie choisie par l'utilisateur + la vibration
  void _startRingAndVibe() {
    final player = FlutterRingtonePlayer();
    switch (CallPrefs.ringtone) {
      case 'douce':
        player.play(
            android: AndroidSounds.notification,
            ios: IosSounds.triTone,
            looping: true,
            volume: 0.9);
      case 'forte':
        player.playAlarm(looping: true, volume: 1.0);
      case 'silencieux':
        break; // pas de son — vibration seule si activée
      default: // 'classique'
        player.playRingtone(looping: true, volume: 1.0);
    }
    if (CallPrefs.vibration) {
      HapticFeedback.vibrate();
      vibre = Timer.periodic(
          const Duration(milliseconds: 1200), (_) => HapticFeedback.vibrate());
    }
  }

  void _stopRing() {
    vibre?.cancel();
    FlutterRingtonePlayer().stop();
  }

  /// Fin sans décrocher (refus ou appelant parti) → journal « manqué »
  void _finish({required bool missed}) {
    if (done) return;
    done = true;
    _stopRing();
    Rtc.onSignal = null;
    if (missed) {
      //Journalise l'appel manqué (sans bloquer l'interface)
      try {
        //Le journal part en tâche de fond : un réseau coupé ne doit ni
        // planter l'écran ni empêcher de raccrocher.
        unawaited(context
            .read<AppState>()
            .api
            .logIncoming(widget.offer['from'].toString(), 0)
            .catchError((_) {}));
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _stopRing();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final name = (offer['from_name'] ?? '').toString().isNotEmpty
        ? offer['from_name'].toString()
        : offer['from'].toString();
    final avatar = offer['from_avatar']?.toString();
    final hasPhoto = avatar != null && avatar.isNotEmpty;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

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
              const Spacer(flex: 2),
              Text('APPEL ENTRANT',
                  style: TextStyle(
                      color: MC.sable, fontSize: Tx.label, letterSpacing: 2)),
              const SizedBox(height: 26),
              //Même anneau doré que l'écran d'appel
              Container(
                width: 128,
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
                          base64Decode(avatar.split(',').last),
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                          gaplessPlayback: true,
                        )
                      : Center(
                          child: Text(initial,
                              style: TextStyle(
                                  fontSize: Tx.display,
                                  fontWeight: FontWeight.w800,
                                  color: MC.soleil)),
                        ),
                ),
              ),
              const SizedBox(height: 18),
              Text(name,
                  style: TextStyle(
                      fontSize: Tx.headline,
                      fontWeight: FontWeight.w800,
                      color: MC.ivoire)),
              const SizedBox(height: 14),
              //Précise le type d'appel entrant
              if (widget.offer['video'] == true)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_rounded, size: 15, color: MC.soleil),
                      const SizedBox(width: 6),
                      Text('Appel vidéo entrant',
                          style: TextStyle(color: MC.soleil, fontSize: Tx.label)),
                    ],
                  ),
                ),
              //Icône officielle : c'est un appel MboteCall gratuit
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
              ),
              const Spacer(flex: 2),
              // Refuser (rouge) · Décrocher (vert)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _big(Icons.call_end_rounded, MC.rouge, L10n.t('call_decline'), () {
                    Rtc.send({
                      'type': 'reject',
                      'to': offer['from'],
                      'call_id': offer['call_id'],
                    });
                    _finish(missed: true);
                  }),
                  const SizedBox(width: 70),
                  _big(Icons.call_rounded, MC.savane, L10n.t('call_accept'), () {
                    if (done) return;
                    done = true;
                    _stopRing();
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CallScreen(
                          to: offer['from'],
                          displayName: offer['from_name']?.toString(),
                          //l'appelant a demandé la vidéo → on l'ouvre en vidéo
                          video: offer['video'] == true,
                          incomingOffer: {...offer, 'early_ice': earlyIce},
                        ),
                      ),
                    );
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

  /// Bouton rond de l'écran d'appel. Il porte toujours un **nom accessible** :
  /// un lecteur d'écran annonçait jusqu'ici « bouton » sans dire lequel.
  Widget _big(IconData icon, Color color, String libelle, VoidCallback onTap) =>
      Semantics(
        button: true,
        label: libelle,
        child: Tooltip(
          message: libelle,
          child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                  color: color.withValues(alpha: .4),
                  blurRadius: 26,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
          ),
        ),
      );
}
