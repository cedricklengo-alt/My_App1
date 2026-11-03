// lib/screens/group_call.dart
//Écran d'appel de groupe (audio ou vidéo) — jusqu'à 4 personnes.
//
// La grille montre chaque participant : sa vidéo quand elle arrive, son
// initiale sinon. Les commandes sont les mêmes que pour un appel simple,
// avec en plus « inviter » (choisir des contacts) et « changer de caméra ».

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../group_call.dart';
import '../l10n.dart';
import '../rtc.dart';
import '../state.dart';
import '../design.dart';
import '../theme.dart';
import '../widgets/avatar.dart';

/// Lance un appel de groupe et pousse l'écran.
Future<void> startGroupCall(
  BuildContext context, {
  required bool video,
  List<Map> invites = const [],
}) async {
  final callId =
      'g${DateTime.now().millisecondsSinceEpoch.toString().substring(4)}';
  await Navigator.push(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          GroupCallScreen(callId: callId, video: video, invites: invites),
    ),
  );
}

class GroupCallScreen extends StatefulWidget {
  final String callId;
  final bool video;

  /// Contacts à inviter dès l'entrée dans la salle.
  final List<Map> invites;

  const GroupCallScreen({
    super.key,
    required this.callId,
    required this.video,
    this.invites = const [],
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  GroupCallSession? _session;
  final Map<String, RTCVideoRenderer> _remoteRenders = {};
  RTCVideoRenderer? _localRender;
  bool _leaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final st = context.read<AppState>();
    final session = GroupCallSession(
      callId: widget.callId,
      myPhone: st.phone,
      myName: st.name,
      video: widget.video,
    );
    session.addListener(_onChange);
    setState(() => _session = session);

    final ice = await RtcSession.iceConfig();
    await session.join(iceConfig: ice);
    if (!mounted) return;
    if (session.error != null) {
      setState(() => _error = session.error);
      return;
    }
    //Journal de l'appel de groupe (gratuit, mais visible dans l'historique)
    try {
      await st.api.startGroupCall(widget.callId);
    } catch (_) {/* le journal ne bloque jamais l'appel */}

    // Aperçu local
    if (widget.video && session.localStream != null) {
      final r = RTCVideoRenderer();
      await r.initialize();
      r.srcObject = session.localStream;
      if (mounted) setState(() => _localRender = r);
    }

    // Invitations demandées à l'ouverture
    for (final c in widget.invites) {
      final phone = '${c['phone'] ?? ''}';
      if (phone.isNotEmpty) session.invite(phone, name: '${c['name'] ?? ''}');
    }
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    _syncRemoteRenderers();
  }

  /// Crée un moteur d'affichage par participant dont la vidéo est arrivée.
  Future<void> _syncRemoteRenderers() async {
    final s = _session;
    if (s == null) return;
    for (final p in s.peers.values) {
      final stream = p.stream;
      if (stream == null) continue;
      if (_remoteRenders.containsKey(p.phone)) {
        final r = _remoteRenders[p.phone]!;
        if (r.srcObject != stream) r.srcObject = stream;
        continue;
      }
      final r = RTCVideoRenderer();
      try {
        await r.initialize();
        r.srcObject = stream;
        if (mounted) setState(() => _remoteRenders[p.phone] = r);
      } catch (_) {}
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    final s = _session;
    final st = context.read<AppState>();
    final duree = s?.elapsed ?? 0;
    await s?.leave();
    try {
      await st.api.endGroupCall(widget.callId, duree);
    } catch (_) {}
    if (!mounted) return;
    Navigator.maybePop(context);
  }

  Future<void> _inviteSheet() async {
    final s = _session;
    if (s == null) return;
    final st = context.read<AppState>();
    final contacts = st.contacts;
    await showModalBottomSheet<void>(
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
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Row(
                children: [
                  Text('Inviter dans l’appel',
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.subtitle,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            if (contacts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Aucun contact MboteCall pour l’instant.',
                  style: TextStyle(color: MC.kaki, fontSize: Tx.label),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: contacts.length,
                  itemBuilder: (_, i) {
                    final c = Map.from(contacts[i] as Map);
                    final phone = '${c['phone'] ?? ''}';
                    final name = '${c['name'] ?? phone}';
                    final deja = s.peers.containsKey(phone);
                    return ListTile(
                      enabled: !deja,
                      leading: Container(
                        width: Densite.avatar,
                        height: Densite.avatar,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: MC.nuit3,
                          borderRadius: BorderRadius.circular(Rd.avatar),
                          border: Border.all(color: MC.ligne),
                        ),
                        child: Text(
                          name.isEmpty ? '?' : name[0].toUpperCase(),
                          style: TextStyle(
                              color: MC.soleil,
                              fontSize: Tx.body,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                      title: Text(name,
                          style: TextStyle(color: MC.ivoire, fontSize: Tx.body)),
                      subtitle: Text(phone,
                          style: TextStyle(color: MC.kaki, fontSize: Tx.caption)),
                      trailing: deja
                          ? Text('Déjà là',
                              style: TextStyle(color: MC.savane, fontSize: Tx.caption))
                          : Icon(Icons.person_add_alt_1_rounded,
                              color: MC.soleil, size: 20),
                      onTap: deja
                          ? null
                          : () {
                              s.invite(phone, name: name);
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text('Invitation envoyée à $name'),
                                backgroundColor: MC.nuit3,
                              ));
                            },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _session?.removeListener(_onChange);
    _session?.dispose();
    for (final r in _remoteRenders.values) {
      r.dispose();
    }
    _localRender?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final peers = s?.peers.values.toList() ?? const <GroupPeer>[];
    // Grille : 1 → plein écran, 2 → deux colonnes, 3-4 → 2×2.
    final cols = peers.isEmpty ? 1 : (peers.length == 1 ? 1 : 2);

    return Scaffold(
      backgroundColor: MC.nuit,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(s),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam_off_rounded,
                                color: MC.rouge, size: 40),
                            const SizedBox(height: 12),
                            Text(_error!,
                                textAlign: TextAlign.center,
                                style:
                                    TextStyle(color: MC.sable, fontSize: Tx.body)),
                            const SizedBox(height: 18),
                            MboteButton(
                                label: 'Fermer',
                                onTap: () => Navigator.maybePop(context)),
                          ],
                        ),
                      ),
                    )
                  : GridView.count(
                      crossAxisCount: cols,
                      padding: const EdgeInsets.all(8),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.78,
                      children: [
                        // Moi
                        _tile(
                          name: '${L10n.t('you')} (${s?.myName ?? ''})',
                          muted: s?.muted ?? false,
                          videoOff: !(s?.cameraOn ?? false),
                          local: true,
                        ),
                        for (final p in peers)
                          _tile(
                            name: p.label,
                            muted: p.muted,
                            videoOff: p.videoOff || p.stream == null,
                            phone: p.phone,
                          ),
                      ],
                    ),
            ),
            _controls(s),
          ],
        ),
      ),
    );
  }

  Widget _topBar(GroupCallSession? s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: MC.soleil.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(Rd.lg),
            ),
            child: Row(
              children: [
                Icon(widget.video ? Icons.videocam_rounded : Icons.call_rounded,
                    size: 13, color: MC.soleil),
                const SizedBox(width: 5),
                Text('Mbote Famille',
                    style: TextStyle(
                        color: MC.soleil,
                        fontSize: Tx.caption,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (s != null && s.joined)
            Text('${s.count}/4',
                style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
          const Spacer(),
          Text(
            fmtDur(s?.elapsed ?? 0),
            style: TextStyle(
              color: MC.sable,
              fontSize: Tx.label,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required String name,
    required bool muted,
    required bool videoOff,
    bool local = false,
    String? phone,
  }) {
    final renderer = local ? _localRender : _remoteRenders[phone];
    final showVideo =
        !videoOff && renderer != null && renderer.srcObject != null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Rd.md),
      child: Container(
        color: MC.nuit2,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showVideo)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: renderer.videoWidth == 0
                      ? 360
                      : renderer.videoWidth.toDouble(),
                  height: renderer.videoHeight == 0
                      ? 640
                      : renderer.videoHeight.toDouble(),
                  child: RTCVideoView(renderer, mirror: local),
                ),
              )
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MboteAvatar(
                      name: name.trim().isEmpty ? '?' : name.trim(),
                      size: 60,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: MC.ivoire, fontSize: Tx.label),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      showVideo
                          ? ''
                          : (widget.video ? 'Caméra coupée' : 'Audio'),
                      style: TextStyle(color: MC.kaki, fontSize: Tx.caption),
                    ),
                  ],
                ),
              ),
            if (muted)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: .55),
                  ),
                  child: Icon(Icons.mic_off_rounded, size: 13, color: MC.rouge),
                ),
              ),
            if (local)
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(Rd.xs),
                  ),
                  child: Text('Moi',
                      style: TextStyle(color: MC.ivoire, fontSize: Tx.caption)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _controls(GroupCallSession? s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _round(
            (s?.muted ?? false) ? Icons.mic_off_rounded : Icons.mic_rounded,
            s?.muted ?? false,
            () => s?.setMuted(!(s.muted)),
          ),
          if (widget.video) ...[
            _round(
              (s?.cameraOn ?? false)
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              !(s?.cameraOn ?? false),
              () => s?.setCameraOn(!(s.cameraOn)),
            ),
            _round(
                Icons.flip_camera_ios_rounded, false, () => s?.switchCamera()),
          ],
          _round(Icons.person_add_alt_1_rounded, false, _inviteSheet),
          GestureDetector(
            onTap: _leave,
            child: Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MC.rouge,
                boxShadow: [
                  BoxShadow(
                      color: MC.rouge.withValues(alpha: .4),
                      blurRadius: 22,
                      offset: const Offset(0, 6)),
                ],
              ),
              child: const Icon(Icons.call_end_rounded,
                  color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }

  Widget _round(IconData icon, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? MC.soleil : MC.nuit3,
          ),
          child: Icon(icon, color: active ? MC.onAccent : MC.sable, size: 21),
        ),
      );
}

///Invitation à un appel de groupe déjà en cours.
class IncomingGroupScreen extends StatelessWidget {
  final Map invite; // {call_id, from, from_name, video}
  const IncomingGroupScreen({super.key, required this.invite});

  @override
  Widget build(BuildContext context) {
    final video = invite['video'] == true;
    final name =
        invite['from_name']?.toString() ?? invite['from']?.toString() ?? '';
    return Scaffold(
      backgroundColor: MC.nuit,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Icon(video ? Icons.videocam_rounded : Icons.groups_rounded,
                size: 64, color: MC.soleil),
            const SizedBox(height: 18),
            Text('Appel de groupe',
                style:
                    TextStyle(color: MC.sable, fontSize: Tx.label, letterSpacing: 2)),
            const SizedBox(height: 8),
            Text(name,
                style: TextStyle(
                    color: MC.ivoire,
                    fontSize: Tx.headline,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(video ? 'Avec vidéo' : 'Audio',
                style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
            const Spacer(flex: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _big(Icons.call_end_rounded, MC.rouge, () {
                  Navigator.maybePop(context);
                }),
                const SizedBox(width: 70),
                _big(Icons.call_rounded, MC.savane, () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupCallScreen(
                        callId: '${invite['call_id']}',
                        video: video,
                      ),
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _big(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      );
}
