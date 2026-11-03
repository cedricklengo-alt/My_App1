import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'config.dart';

///Canal temps réel + moteur voix WebRTC.
///
/// - `Rtc` : connexion WebSocket permanente vers le serveur (standardiste).
///   Reçoit les appels entrants et fait passer les messages techniques.
/// - `RtcSession` : UN appel voix (micro, connexion directe téléphone↔téléphone).
///
/// La voix ne passe PAS par notre serveur : elle circule en direct entre les
/// deux téléphones (STUN/TURN publics gratuits pour traverser box et 4G).
class Rtc {
  static WebSocket? _ws;
  static String? _token;
  static bool _wanted = false;
  static bool _fg = true; // l'app démarre au premier plan

  ///Voyant : sommes-nous connectés au standardiste ?
  /// (affiché sur l'écran Clavier — vert = prêt à appeler/recevoir)
  static final ValueNotifier<bool> connected = ValueNotifier(false);

  ///Appel entrant (offre reçue) — posé par le Shell
  static void Function(Map msg)? onOffer;

  /// Messages de l'appel en cours (answer/ice/hangup/reject/peer-offline)
  /// — posé par l'écran d'appel actif
  static void Function(Map msg)? onSignal;

  ///Auditeurs des messages d'appel de groupe (`group_*`).
  /// Une liste (et non un seul emplacement) : l'écran d'accueil écoute en
  /// permanence pour les invitations, pendant que l'écran d'appel de groupe
  /// écoute la même salle.
  static final List<void Function(Map msg)> _groupListeners = [];

  static void addGroupListener(void Function(Map msg) f) {
    if (!_groupListeners.contains(f)) _groupListeners.add(f);
  }

  static void removeGroupListener(void Function(Map msg) f) {
    _groupListeners.remove(f);
  }

  ///Auditeurs des messages de discussion (`msg` : nouveau message, lu,
  /// écouté, supprimé) et de l'indicateur « écrit… » (`typing`).
  static final List<void Function(Map msg)> _messageListeners = [];

  static void addMessageListener(void Function(Map msg) f) {
    if (!_messageListeners.contains(f)) _messageListeners.add(f);
  }

  static void removeMessageListener(void Function(Map msg) f) {
    _messageListeners.remove(f);
  }

  static String get _url {
    // https://…/api  →  wss://…/ws   (et http → ws en local)
    return Config.apiBase
        .replaceFirst('/api', '/ws')
        .replaceFirst('http', 'ws');
  }

  /// Connexion (avec reconnexion automatique tant qu'on est connecté)
  static void connect(String token) {
    if (_wanted && _token == token) return; // déjà en route
    _token = token;
    if (!_wanted) {
      _wanted = true;
      _loop();
    }
  }

  static Future<void> _loop() async {
    while (_wanted) {
      try {
        _ws = await WebSocket.connect('$_url?token=$_token');
        connected.value = true; //prêt à appeler/recevoir
        setForeground(_fg); //état initial annoncé au serveur
        await for (final data in _ws!) {
          Map msg;
          try {
            msg = jsonDecode(data as String) as Map;
          } catch (_) {
            continue;
          }
          final type = '${msg['type']}';
          if (type == 'offer') {
            onOffer?.call(msg);
          } else if (type == 'msg' || type == 'typing') {
            //Discussions : l'écran ouvert et la liste écoutent en parallèle.
            for (final f in List.of(_messageListeners)) {
              try {
                f(msg);
              } catch (_) {}
            }
          } else if (type.startsWith('group_')) {
            //Signalisation d'appel de groupe : à tous les auditeurs.
            for (final f in List.of(_groupListeners)) {
              try {
                f(msg);
              } catch (_) {}
            }
          } else {
            onSignal?.call(msg);
          }
        }
      } catch (_) {/* serveur injoignable : on retente */}
      _ws = null;
      connected.value = false; //reconnexion…
      if (_wanted) await Future.delayed(const Duration(seconds: 4));
    }
  }

  static void send(Map msg) {
    try {
      _ws?.add(jsonEncode(msg));
    } catch (_) {}
  }

  ///Annonce au serveur si l'app est au premier plan ou non.
  /// Le serveur part de « arrière-plan » : sans ce message il croit l'app
  /// fermée et double chaque appel d'un push de réveil inutile.
  /// À appeler juste après la connexion et à chaque changement d'état.
  static void setForeground(bool fg) {
    _fg = fg;
    if (_ws == null) return;
    try {
      _ws!.add(jsonEncode({'type': 'presence', 'state': fg ? 'fg' : 'bg'}));
    } catch (_) {}
  }

  static void disconnect() {
    _wanted = false;
    _token = null;
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
  }
}

///Une session d'appel (audio seul, ou audio + vidéo si `video: true`).
class RtcSession {
  final String peer; // numéro de l'autre téléphone
  final String callId;

  ///true = appel vidéo (caméra + micro), false = appel audio.
  final bool video;

  RTCPeerConnection? _pc;
  MediaStream? _mic;

  void Function()? onConnected; // la voix/limage passe !
  void Function()? onEnded; // connexion perdue

  /// Flux local (ma caméra + mon micro) → aperçu « moi » à l'écran.
  void Function(MediaStream stream)? onLocalStream;

  /// Flux distant (la caméra/l'image de l'autre) → plein écran.
  void Function(MediaStream stream)? onRemoteStream;

  RtcSession({required this.peer, required this.callId, this.video = false});

  ///Repli intégré si le serveur est injoignable : STUN seul.
  /// (L'ancien TURN public « openrelay » a été retiré par Metered —
  ///  le vrai TURN est désormais fourni par le serveur, voir _iceConfig.)
  static const _fallbackConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun.relay.metered.ca:80'},
    ],
  };

  /// Config ICE reçue du serveur (cache pour la session)
  static Map<String, dynamic>? _cachedIce;

  ///Config STUN/TURN publique (utilisée aussi par les appels de groupe).
  static Future<Map<String, dynamic>> iceConfig() => _iceConfig();

  ///Demande au serveur la liste STUN/TURN (identifiants TURN jamais
  /// écrits dans l'app → rotation possible sans recompiler). Repli : STUN.
  static Future<Map<String, dynamic>> _iceConfig() async {
    if (_cachedIce != null) return _cachedIce!;
    try {
      final c = HttpClient();
      final rq = await c
          .getUrl(Uri.parse('${Config.apiBase}/rtc/ice'))
          .timeout(const Duration(seconds: 4));
      rq.headers.set('Authorization', 'Bearer ${Rtc._token ?? ''}');
      final rs = await rq.close().timeout(const Duration(seconds: 4));
      final body = await rs.transform(utf8.decoder).join();
      c.close();
      if (rs.statusCode == 200) {
        final j = jsonDecode(body);
        if (j is Map && j['iceServers'] is List) {
          _cachedIce = {'iceServers': j['iceServers']};
          return _cachedIce!;
        }
      }
    } catch (_) {/* serveur injoignable → repli */}
    return Map<String, dynamic>.from(_fallbackConfig);
  }

  Future<void> _init() async {
    _pc = await createPeerConnection(await _iceConfig());
    //Micro (+caméra avant si appel vidéo). La permission est demandée
    // au premier appel ; si elle est refusée, l'appel bascule en audio seul.
    try {
      _mic = await navigator.mediaDevices.getUserMedia({
        //Qualité voix v1.8 : annulation d'écho, réduction de bruit,
        // gain automatique — indispensable en mains-libres.
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
                'frameRate': {'ideal': 24},
              }
            : false,
      });
    } catch (e) {
      if (!video) rethrow;
      // La caméra est indisponible (permission, matériel) : on continue en
      // audio pour ne pas perdre l'appel.
      _mic = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
    }
    if (video && _mic != null) {
      try {
        onLocalStream?.call(_mic!);
      } catch (_) {}
    }
    for (final t in _mic!.getTracks()) {
      await _pc!.addTrack(t, _mic!);
    }
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        try {
          onRemoteStream?.call(event.streams.first);
        } catch (_) {}
      }
    };
    _pc!.onIceCandidate = (c) {
      if (c.candidate != null) {
        Rtc.send({
          'type': 'ice',
          'to': peer,
          'call_id': callId,
          'candidate': {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          },
        });
      }
    };
    _pc!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onConnected?.call();
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        onEnded?.call();
      }
    };
  }

  /// Côté APPELANT : crée l'offre et l'envoie au standardiste
  Future<void> call() async {
    await _init();
    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': video ? 1 : 0,
    });
    await _pc!.setLocalDescription(offer);
    Rtc.send({
      'type': 'offer',
      'to': peer,
      'call_id': callId,
      'video': video, //l'appelé saura qu'il s'agit d'un appel vidéo
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
    });
  }

  /// Côté APPELÉ : répond à l'offre reçue (= décrocher)
  Future<void> answer(Map remoteSdp) async {
    await _init();
    await _pc!.setRemoteDescription(
        RTCSessionDescription(remoteSdp['sdp'], remoteSdp['type']));
    final ans = await _pc!.createAnswer();
    await _pc!.setLocalDescription(ans);
    Rtc.send({
      'type': 'answer',
      'to': peer,
      'call_id': callId,
      'sdp': {'type': ans.type, 'sdp': ans.sdp},
    });
  }

  /// Côté APPELANT : l'appelé a décroché
  Future<void> acceptAnswer(Map remoteSdp) async {
    await _pc?.setRemoteDescription(
        RTCSessionDescription(remoteSdp['sdp'], remoteSdp['type']));
  }

  Future<void> addIce(Map c) async {
    try {
      await _pc?.addCandidate(
          RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']));
    } catch (_) {}
  }

  void setMuted(bool m) {
    _mic?.getAudioTracks().forEach((t) => t.enabled = !m);
  }

  ///Coupe / réactive la caméra sans interrompre l'appel.
  void setVideoEnabled(bool on) {
    _mic?.getVideoTracks().forEach((t) => t.enabled = on);
  }

  bool get hasVideoTrack => (_mic?.getVideoTracks().isNotEmpty ?? false);

  ///Bascule caméra avant / arrière.
  Future<void> switchCamera() async {
    try {
      final tracks = _mic?.getVideoTracks() ?? const <MediaStreamTrack>[];
      if (tracks.isEmpty) return;
      await Helper.switchCamera(tracks.first);
    } catch (_) {/* certains appareils n'ont qu'une caméra */}
  }

  void setSpeaker(bool on) {
    Helper.setSpeakerphoneOn(on);
  }

  Future<void> close() async {
    try {
      await _mic?.dispose();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    _mic = null;
  }
}
