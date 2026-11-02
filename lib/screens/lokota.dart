import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../l10n.dart';

/// 🗣️ LOKOTA 1 — Notes vocales traduites (pilote)
/// « Parle ta langue. Ils entendront la leur. »
///
/// - LokotaScreen : liste des fils de discussion + nouvelle note
/// - LokotaThread : un fil avec un proche — écoute, transcription,
///   traduction, et enregistreur en bas (choix des langues).

const _langNames = {'fr': 'Français', 'ln': 'Lingala', 'sw': 'Swahili'};
const _langFlags = {'fr': '🇫🇷', 'ln': '🇨🇩', 'sw': '🌍'};

class LokotaScreen extends StatefulWidget {
  const LokotaScreen({super.key});
  @override
  State<LokotaScreen> createState() => _LokotaScreenState();
}

class _LokotaScreenState extends State<LokotaScreen> {
  List threads = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await context.read<AppState>().api.lokotaThreads();
      if (mounted) {
        setState(() {
          threads = t;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  void _openThread(String phone, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => LokotaThread(peerPhone: phone, peerName: name)),
    ).then((_) => _load());
  }

  void _newNote() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: MC.nuit2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L10n.t('lokota_new'),
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: MC.ivoire)),
            const SizedBox(height: 6),
            Text(L10n.t('lokota_new_hint'),
                style: TextStyle(color: MC.kaki, fontSize: 12.5)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.phone,
              style: TextStyle(color: MC.ivoire, fontSize: 17),
              decoration: InputDecoration(
                  hintText: '+243…', hintStyle: TextStyle(color: MC.kaki)),
            ),
            const SizedBox(height: 14),
            MboteButton(
              label: L10n.t('lokota_open'),
              onTap: () {
                final p = ctrl.text.trim();
                if (p.isEmpty) return;
                Navigator.pop(ctx);
                _openThread(p, p);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Row(children: [
          const Text('🗣️ '),
          Text('Lokota',
              style: TextStyle(color: MC.ivoire, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: MC.soleil.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: MC.soleil)),
            child: Text(L10n.t('lokota_pilot'),
                style: TextStyle(
                    color: MC.soleil,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: MC.soleil,
        onPressed: _newNote,
        icon: Icon(Icons.mic_rounded, color: MC.onAccent),
        label: Text(L10n.t('lokota_new'),
            style: TextStyle(color: MC.onAccent, fontWeight: FontWeight.w800)),
      ),
      body: loading
          ? Center(child: CircularProgressIndicator(color: MC.soleil))
          : threads.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(36),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🗣️', style: TextStyle(fontSize: 52)),
                        const SizedBox(height: 12),
                        Text(L10n.t('lokota_empty_title'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: MC.ivoire,
                                fontSize: 17,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text(L10n.t('lokota_empty_body'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: MC.kaki, fontSize: 13.5, height: 1.5)),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: MC.soleil,
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                    itemCount: threads.length,
                    itemBuilder: (_, i) {
                      final t = threads[i];
                      final name = (t['peer_name'] ?? '').toString().isNotEmpty
                          ? t['peer_name'].toString()
                          : t['peer_phone'].toString();
                      final unread = (t['unread'] ?? 0) as int;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                            color: MC.nuit2,
                            borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: MC.nuit3,
                            child: Text(name[0].toUpperCase(),
                                style: TextStyle(
                                    color: MC.soleil,
                                    fontWeight: FontWeight.w800)),
                          ),
                          title: Text(name,
                              style: TextStyle(
                                  color: MC.ivoire,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                          subtitle: Text(
                              '${t['last_mine'] == true ? '↗ ' : '↙ '}🎙️ ${t['last_duration']}s',
                              style: TextStyle(color: MC.kaki, fontSize: 12)),
                          trailing: unread > 0
                              ? CircleAvatar(
                                  radius: 12,
                                  backgroundColor: MC.savane,
                                  child: Text('$unread',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800)))
                              : Icon(Icons.chevron_right_rounded,
                                  color: MC.kaki),
                          onTap: () =>
                              _openThread(t['peer_phone'].toString(), name),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

/// 💬 Un fil de notes vocales avec un proche
class LokotaThread extends StatefulWidget {
  final String peerPhone;
  final String peerName;
  const LokotaThread(
      {super.key, required this.peerPhone, required this.peerName});
  @override
  State<LokotaThread> createState() => _LokotaThreadState();
}

class _LokotaThreadState extends State<LokotaThread> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  List notes = [];
  String peerName = '';
  bool recording = false;
  bool sending = false;
  int recSec = 0;
  Timer? recTimer;
  Timer? refresh;
  String? playingId;
  String langFrom = L10n.lang == 'fr' ? 'fr' : L10n.lang; // je parle…
  String langTo = L10n.lang == 'fr' ? 'ln' : 'fr'; // il/elle lit…
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    peerName = widget.peerName;
    _load(markRead: true);
    // ⏳ Les traductions arrivent en tâche de fond → petit rafraîchissement
    refresh = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!recording && !sending) _load();
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => playingId = null);
    });
  }

  @override
  void dispose() {
    recTimer?.cancel();
    refresh?.cancel();
    _recorder.dispose();
    _player.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool markRead = false}) async {
    try {
      final api = context.read<AppState>().api;
      final r = await api.lokotaWith(widget.peerPhone);
      if (markRead) api.lokotaMarkRead(widget.peerPhone).catchError((_) {});
      if (mounted) {
        setState(() {
          notes = r['notes'] ?? [];
          if ((r['peer_name'] ?? '').toString().isNotEmpty) {
            peerName = r['peer_name'].toString();
          }
        });
      }
    } catch (_) {}
  }

  // ---- 🎙️ Enregistrement ----
  Future<void> _startRec() async {
    try {
      if (!await _recorder.hasPermission()) return;
      final dir = await getTemporaryDirectory();
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 22050,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: '${dir.path}/lokota_note.m4a',
      );
      recSec = 0;
      recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => recSec++);
        if (recSec >= 60) _stopAndSend(); // ⏱️ 60 s max
      });
      setState(() => recording = true);
    } catch (_) {
      _snack(L10n.t('lokota_mic_error'), err: true);
    }
  }

  Future<void> _cancelRec() async {
    recTimer?.cancel();
    try {
      await _recorder.cancel();
    } catch (_) {}
    setState(() => recording = false);
  }

  Future<void> _stopAndSend() async {
    // État lu avant tout `await` (sinon `context` peut être démonté).
    final appState = context.read<AppState>();
    recTimer?.cancel();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    setState(() {
      recording = false;
      sending = true;
    });
    try {
      if (path == null) throw Exception();
      final bytes = await File(path).readAsBytes();
      if (bytes.length < 800) throw Exception(); // trop court
      final dataUri = 'data:audio/m4a;base64,${base64Encode(bytes)}';
      await appState.api.lokotaSend(
          widget.peerPhone, dataUri, recSec.clamp(1, 90), langFrom, langTo);
      await _load();
      if (scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent + 200,
            duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
      }
    } catch (e) {
      _snack(friendlyError(e), err: true);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  // ---- ▶️ Écoute ----
  Future<void> _play(Map n) async {
    try {
      if (playingId == n['id']) {
        await _player.stop();
        setState(() => playingId = null);
        return;
      }
      final b64 = (n['audio'] ?? '').toString().split(',').last;
      await _player.stop();
      await _player.play(BytesSource(base64Decode(b64)));
      setState(() => playingId = n['id'].toString());
    } catch (_) {
      _snack(L10n.t('lokota_play_error'), err: true);
    }
  }

  void _snack(String m, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: err ? MC.rouge : MC.savane));
  }

  void _swapLangs() => setState(() {
        final t = langFrom;
        langFrom = langTo;
        langTo = t;
      });

  void _pickLang(bool from) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.nuit2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _langNames.entries
              .map((e) => ListTile(
                    leading: Text(_langFlags[e.key]!,
                        style: const TextStyle(fontSize: 20)),
                    title: Text(e.value,
                        style: TextStyle(
                            color: MC.ivoire, fontWeight: FontWeight.w600)),
                    onTap: () {
                      setState(() => from ? langFrom = e.key : langTo = e.key);
                      Navigator.pop(ctx);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(peerName,
            style: TextStyle(color: MC.ivoire, fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              itemCount: notes.length,
              itemBuilder: (_, i) => _bubble(notes[i] as Map),
            ),
          ),
          _composer(),
        ],
      ),
    );
  }

  Widget _bubble(Map n) {
    final mine = n['mine'] == true;
    final status = (n['status'] ?? '').toString();
    final playing = playingId == n['id'];
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine ? MC.nuit3 : MC.nuit2,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ▶️ lecteur + langues
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => _play(n),
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: MC.soleil,
                    child: Icon(
                        playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        color: MC.onAccent,
                        size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                Text('🎙️ ${n['duration_sec']}s',
                    style: TextStyle(color: MC.sable, fontSize: 12.5)),
                const SizedBox(width: 8),
                Text(
                    '${_langFlags[n['lang_from']] ?? ''}→${_langFlags[n['lang_to']] ?? ''}',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
            // 📝 transcription + traduction
            if (status == 'done') ...[
              if ((n['transcript'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(n['transcript'].toString(),
                    style: TextStyle(
                        color: MC.kaki,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        height: 1.4)),
              ],
              if ((n['translation'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(n['translation'].toString(),
                    style: TextStyle(
                        color: MC.ivoire, fontSize: 13.5, height: 1.45)),
              ],
            ] else if (status == 'pending') ...[
              const SizedBox(height: 8),
              Text('⏳ ${L10n.t('lokota_translating')}',
                  style: TextStyle(color: MC.soleil, fontSize: 12)),
            ] else if (status == 'no_ai') ...[
              const SizedBox(height: 8),
              Text('🔑 ${L10n.t('lokota_no_ai')}',
                  style: TextStyle(color: MC.kaki, fontSize: 11.5)),
            ] else if (status == 'failed') ...[
              const SizedBox(height: 8),
              Text('⚠️ ${L10n.t('lokota_failed')}',
                  style: TextStyle(color: MC.rouge, fontSize: 11.5)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      decoration: BoxDecoration(
          color: MC.nuit2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🌍 Je parle X → il/elle lit Y
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _langChip(true, langFrom),
              GestureDetector(
                onTap: _swapLangs,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Icons.swap_horiz_rounded, color: MC.soleil),
                ),
              ),
              _langChip(false, langTo),
            ],
          ),
          const SizedBox(height: 12),
          if (recording) ...[
            Text('🔴 ${recSec}s / 60s',
                style: TextStyle(
                    color: MC.rouge,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _bigBtn(Icons.delete_rounded, MC.nuit3, MC.sable, _cancelRec),
                const SizedBox(width: 40),
                _bigBtn(
                    Icons.send_rounded, MC.savane, Colors.white, _stopAndSend),
              ],
            ),
          ] else if (sending) ...[
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: MC.soleil, strokeWidth: 2.5)),
                  const SizedBox(width: 10),
                  Text(L10n.t('lokota_sending'),
                      style: TextStyle(color: MC.sable, fontSize: 13)),
                ],
              ),
            ),
          ] else ...[
            GestureDetector(
              onTap: _startRec,
              child: Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  gradient: MC.degrade,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: MC.soleil.withValues(alpha: .35),
                        blurRadius: 20,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: Icon(Icons.mic_rounded, color: MC.onAccent, size: 30),
              ),
            ),
            const SizedBox(height: 6),
            Text(L10n.t('lokota_tap_record'),
                style: TextStyle(color: MC.kaki, fontSize: 11.5)),
          ],
        ],
      ),
    );
  }

  Widget _langChip(bool from, String code) => GestureDetector(
        onTap: () => _pickLang(from),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: MC.nuit3,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: from ? MC.soleil : MC.savane),
          ),
          child: Text(
            '${from ? '🎙️' : '👂'} ${_langFlags[code]} ${_langNames[code]}',
            style: TextStyle(
                color: MC.ivoire, fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      );

  Widget _bigBtn(IconData i, Color bg, Color fg, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(i, color: fg, size: 24),
        ),
      );
}
