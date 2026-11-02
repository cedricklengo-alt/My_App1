// lib/group_call.dart
// 👥 Appel de groupe « Mbote Famille » — audio ou vidéo, jusqu'à 4 personnes.
//
// Topologie **maillée (mesh)** : chaque participant est relié directement aux
// autres (une connexion WebRTC par pair). Le serveur ne transporte que les
// messages techniques (offres, réponses, candidats réseau) : la voix et l'image
// ne passent jamais par lui.
//
// Déroulement :
//   1. tout le monde envoie `group_join` sur le canal temps réel ;
//   2. le serveur répond `group_joined` avec la liste des pairs déjà présents ;
//   3. **le nouveau venu offre** à chacun des pairs existants (eux répondent) ;
//   4. `group_peer_joined` / `group_peer_left` tiennent la grille à jour ;
//   5. `group_mute` diffuse l'état micro/caméra de chacun.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'rtc.dart';

/// Un autre participant de l'appel.
class GroupPeer {
  final String phone;
  String name;
  RTCPeerConnection? pc;
  MediaStream? stream;
  bool connected = false;
  bool muted = false;
  bool videoOff = false;

  GroupPeer({required this.phone, this.name = ''});

  /// Nom affichable (à défaut, le numéro).
  String get label => name.isNotEmpty ? name : phone;
}

/// Session d'appel de groupe : signalisation + une connexion par pair.
class GroupCallSession extends ChangeNotifier {
  final String callId;
  final String myPhone;
  final String myName;
  final bool video; // 📹 appel vidéo de groupe ?

  GroupCallSession({
    required this.callId,
    required this.myPhone,
    required this.myName,
    this.video = false,
  });

  final Map<String, GroupPeer> peers = {};

  MediaStream? localStream;
  bool joined = false;
  bool muted = false;
  bool cameraOn = false;
  String? error;

  /// Durée écoulée (secondes) — affichée en haut de l'écran.
  int elapsed = 0;
  Timer? _chrono;

  /// Config réseau : même logique que les appels simples (STUN + TURN serveur).
  static Map<String, dynamic> _ice = {};

  /// Abonnement aux messages `group_*` du canal temps réel.
  void Function(Map msg)? _sink;

  bool get isHost =>
      peers.isEmpty && joined; // indicatif (l'hôte crée la salle)
  int get count => peers.length + 1;

  // ── Cycle de vie ────────────────────────────────────────────────

  /// Rentre dans la salle et branche la signalisation.
  Future<void> join({Map<String, dynamic>? iceConfig}) async {
    _ice = iceConfig ?? _ice;
    try {
      localStream = await navigator.mediaDevices.getUserMedia({
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
      cameraOn = video;
    } catch (_) {
      if (video) {
        // Pas de caméra (perMission refusée) : on rejoint quand même en audio.
        try {
          localStream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': false,
          });
          cameraOn = false;
        } catch (e) {
          error = 'Micro indisponible — vérifie la permission micro';
          notifyListeners();
          return;
        }
      } else {
        error = 'Micro indisponible — vérifie la permission micro';
        notifyListeners();
        return;
      }
    }

    void sink(Map msg) => handle(msg);
    _sink = sink;
    Rtc.addGroupListener(sink);
    Rtc.send({'type': 'group_join', 'call_id': callId, 'video': video});

    _chrono = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed++;
      notifyListeners();
    });
    notifyListeners();
  }

  // ── Signalisation ───────────────────────────────────────────────

  Future<void> handle(Map msg) async {
    if (msg['call_id'] != null && '${msg['call_id']}' != callId) return;
    final type = '${msg['type']}';
    final from = '${msg['from'] ?? ''}';

    switch (type) {
      case 'group_joined':
        joined = true;
        // 3. Le nouveau venu offre à tous ceux déjà présents.
        for (final p in (msg['peers'] as List? ?? const [])) {
          final phone = '$p';
          if (phone.isEmpty || phone == myPhone) continue;
          final peer = _peer(phone);
          await _offerTo(peer);
        }
        notifyListeners();

      case 'group_peer_joined':
        if (from.isEmpty || from == myPhone) return;
        final peer = _peer(from, name: '${msg['from_name'] ?? ''}');
        peer.name = '${msg['from_name'] ?? peer.name}';
        notifyListeners(); // on attend son offre

      case 'group_peer_left':
        await _dropPeer(from);
        notifyListeners();

      case 'group_offer':
        final peer = _peer(from);
        await _answerFrom(peer, Map.from(msg['sdp'] as Map));
        notifyListeners();

      case 'group_answer':
        final peer = peers[from];
        if (peer?.pc != null && msg['sdp'] is Map) {
          try {
            await peer!.pc!.setRemoteDescription(
              RTCSessionDescription(
                  '${msg['sdp']['sdp']}', '${msg['sdp']['type']}'),
            );
          } catch (_) {}
        }

      case 'group_ice':
        final peer = peers[from];
        final c = msg['candidate'];
        if (peer?.pc != null && c is Map) {
          try {
            await peer!.pc!.addCandidate(RTCIceCandidate(
              '${c['candidate']}',
              '${c['sdpMid']}',
              c['sdpMLineIndex'] is int ? c['sdpMLineIndex'] as int : 0,
            ));
          } catch (_) {}
        }

      case 'group_mute':
        final peer = peers[from];
        if (peer != null) {
          peer.muted = msg['muted'] == true;
          peer.videoOff = msg['video'] == false;
          notifyListeners();
        }

      case 'group_invite':
        // Une invitation reçue alors qu'on est déjà dans la salle : on rejoint
        // simplement (idempotent côté serveur).
        if (!joined) {
          joined = true;
          Rtc.send({'type': 'group_join', 'call_id': callId, 'video': video});
        }

      case 'group_error':
        error = switch ('${msg['reason']}') {
          'room_full' => 'La salle est pleine (4 personnes maximum)',
          'not_authorized' => 'Invitation expirée — demande à être réinvité',
          'peer_offline' =>
            '${msg['phone'] ?? 'Ce contact'} n’est pas joignable',
          _ => 'Problème de connexion à l’appel de groupe',
        };
        notifyListeners();
    }
  }

  GroupPeer _peer(String phone, {String name = ''}) {
    final p =
        peers.putIfAbsent(phone, () => GroupPeer(phone: phone, name: name));
    if (name.isNotEmpty) p.name = name;
    return p;
  }

  Future<RTCPeerConnection> _pcFor(GroupPeer peer) async {
    final existing = peer.pc;
    if (existing != null) return existing;
    final pc = await createPeerConnection(
      _ice.isEmpty
          ? {
              'iceServers': [
                {'urls': 'stun:stun.l.google.com:19302'}
              ]
            }
          : _ice,
    );
    peer.pc = pc;

    for (final t in (localStream?.getTracks() ?? const <MediaStreamTrack>[])) {
      try {
        await pc.addTrack(t, localStream!);
      } catch (_) {}
    }

    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      Rtc.send({
        'type': 'group_ice',
        'call_id': callId,
        'to': peer.phone,
        'candidate': {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        },
      });
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        peer.stream = event.streams.first;
        notifyListeners();
      }
    };
    pc.onConnectionState = (st) {
      peer.connected =
          st == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      notifyListeners();
    };
    return pc;
  }

  Future<void> _offerTo(GroupPeer peer) async {
    try {
      final pc = await _pcFor(peer);
      final offer = await pc.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': video ? 1 : 0,
      });
      await pc.setLocalDescription(offer);
      Rtc.send({
        'type': 'group_offer',
        'call_id': callId,
        'to': peer.phone,
        'video': video,
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
    } catch (_) {/* on retentera à la prochaine reconnexion */}
  }

  Future<void> _answerFrom(GroupPeer peer, Map sdp) async {
    try {
      final pc = await _pcFor(peer);
      await pc.setRemoteDescription(
          RTCSessionDescription('${sdp['sdp']}', '${sdp['type']}'));
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      Rtc.send({
        'type': 'group_answer',
        'call_id': callId,
        'to': peer.phone,
        'sdp': {'type': answer.type, 'sdp': answer.sdp},
      });
    } catch (_) {}
  }

  Future<void> _dropPeer(String phone) async {
    final p = peers.remove(phone);
    try {
      await p?.pc?.close();
    } catch (_) {}
    p?.pc = null;
  }

  // ── Actions ─────────────────────────────────────────────────────

  /// ➕ Invite un contact dans la salle.
  void invite(String phone, {String? name}) {
    if (phone.isEmpty || phone == myPhone) return;
    Rtc.send({
      'type': 'group_invite',
      'call_id': callId,
      'to': phone,
      'video': video,
      if (name != null) 'from_name': myName,
    });
  }

  void setMuted(bool m) {
    muted = m;
    localStream?.getAudioTracks().forEach((t) => t.enabled = !m);
    _broadcastState();
    notifyListeners();
  }

  void setCameraOn(bool on) {
    cameraOn = on;
    localStream?.getVideoTracks().forEach((t) => t.enabled = on);
    _broadcastState();
    notifyListeners();
  }

  Future<void> switchCamera() async {
    try {
      final tracks =
          localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
      if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
    } catch (_) {}
  }

  void _broadcastState() {
    Rtc.send({
      'type': 'group_mute',
      'call_id': callId,
      'muted': muted,
      'video': cameraOn,
    });
  }

  /// 🚪 Quitte la salle et raccroche toutes les connexions.
  Future<void> leave() async {
    _chrono?.cancel();
    _chrono = null;
    try {
      if (_sink != null) Rtc.removeGroupListener(_sink!);
    } catch (_) {}
    Rtc.send({'type': 'group_leave', 'call_id': callId});
    for (final p in peers.values) {
      try {
        await p.pc?.close();
      } catch (_) {}
    }
    peers.clear();
    try {
      await localStream?.dispose();
    } catch (_) {}
    localStream = null;
  }

  @override
  void dispose() {
    _chrono?.cancel();
    super.dispose();
  }
}
