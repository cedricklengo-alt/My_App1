import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../chat_format.dart';
import '../l10n.dart';
import '../rtc.dart';
import '../state.dart';
import '../design.dart';
import '../theme.dart';
import '../widgets/floating_choice.dart';
import 'call.dart';

/// 💬 DISCUSSIONS — une conversation avec un proche.
///
/// Tout dans le même fil : textes, photos, fichiers et notes vocales traduites.
/// - envoi optimiste (le message apparaît tout de suite, puis se confirme)
/// - états ✓ envoyé · ✓✓ reçu · ✓✓ lu
/// - temps réel (nouveau message, lecture, note écoutée, suppression)
/// - indicateur « écrit… »
/// - appel audio / vidéo depuis l'en-tête
class ChatScreen extends StatefulWidget {
  final String peerPhone;
  final String? peerName;

  /// Fil actuellement ouvert : la liste des discussions s'en sert pour ne pas
  /// compter ses messages comme « non lus ».
  static String? openPeer;

  const ChatScreen({super.key, required this.peerPhone, this.peerName});

  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final List<Map> msgs = [];
  final TextEditingController ctrl = TextEditingController();
  final ScrollController scroll = ScrollController();
  final FocusNode focus = FocusNode();
  final ImagePicker picker = ImagePicker();

  /// Créés au premier usage (écoute / enregistrement) : ouvrir une discussion
  /// ne touche ni au microphone ni au haut-parleur.
  AudioPlayer? _player;
  AudioRecorder? _recorder;

  AudioPlayer get player => _player ??= (AudioPlayer()
    ..onPlayerComplete.listen((_) {
      if (mounted) setState(() => playingId = null);
    }));

  AudioRecorder get recorder => _recorder ??= AudioRecorder();

  bool loading = true;
  String? error;
  bool hasMore = false;
  bool loadingMore = false;
  bool sending = false;

  late String peerName;
  bool online = false;
  String? lastSeen;

  String? playingId;
  bool recording = false;
  int recSec = 0;
  Timer? recTimer;

  /// Brouillons par proche : on retrouve son texte en revenant dans le fil.
  static final Map<String, String> drafts = {};

  /// Des messages sont arrivés pendant que l'utilisateur lisait plus haut.
  bool newBelow = false;

  DateTime? typingAt;
  Timer? typingTimer;
  DateTime? typingSentAt;
  Timer? typingSendTimer;

  String langFrom = 'fr';
  String langTo = 'ln';
  int _nextLocalId = 0;

  Api get api => context.read<AppState>().api;

  void _onScroll() {
    if (!newBelow) return;
    if (_nearBottom()) setState(() => newBelow = false);
  }

  bool _nearBottom() {
    if (!scroll.hasClients) return true;
    return scroll.position.maxScrollExtent - scroll.position.pixels < 120;
  }

  @override
  void initState() {
    super.initState();
    peerName = (widget.peerName ?? '').trim().isEmpty
        ? widget.peerPhone
        : widget.peerName!.trim();
    Rtc.addMessageListener(handleRealtime);
    // 💬 On rouvre le brouillon laissé dans ce fil, s'il y en a un.
    ctrl.text = drafts[widget.peerPhone] ?? '';
    ChatScreen.openPeer = widget.peerPhone;
    scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    Rtc.removeMessageListener(handleRealtime);
    recTimer?.cancel();
    typingTimer?.cancel();
    typingSendTimer?.cancel();
    if (ChatScreen.openPeer == widget.peerPhone) ChatScreen.openPeer = null;
    if (ctrl.text.trim().isNotEmpty) {
      drafts[widget.peerPhone] = ctrl.text;
    }
    try {
      _recorder?.dispose();
    } catch (_) {}
    try {
      _player?.dispose();
    } catch (_) {}
    ctrl.dispose();
    scroll.dispose();
    focus.dispose();
    super.dispose();
  }

  // ═══════════════════════ Chargement ═══════════════════════

  Future<void> _load({bool older = false}) async {
    if (!mounted) return;
    if (older) {
      if (!hasMore || loadingMore) return;
      setState(() => loadingMore = true);
    }
    // On mémorise la position AVANT l'appel réseau : si l'utilisateur lit
    // l'historique plus haut, on ne le renvoie pas en bas de force.
    final stick = _nearBottom();
    try {
      final before = older ? _oldestCursor() : null;
      final r = await api.conversation(widget.peerPhone, before: before);
      final items = (r['items'] as List?) ?? const [];
      if (!mounted) return;
      final fresh =
          items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final premierChargement = msgs.isEmpty;
      setState(() {
        if (older) {
          final connus = {for (final m in msgs) '${m['id']}'};
          msgs.insertAll(
              0, fresh.where((m) => !connus.contains('${m['id']}')).toList());
        } else if (premierChargement) {
          msgs.addAll(fresh);
        } else {
          // Fusion : on garde l'historique déjà remonté et les messages en
          // cours d'envoi, on rafraîchit les états, on ajoute les nouveaux.
          _mergeTail(fresh);
        }
        hasMore = r['has_more'] == true;
        if ('${r['peer_name'] ?? ''}'.trim().isNotEmpty) {
          peerName = '${r['peer_name']}'.trim();
        }
        online = r['peer_online'] == true;
        lastSeen = r['peer_last_seen_at']?.toString();
        loading = false;
        loadingMore = false;
        error = null;
      });
      if (!older) {
        _markRead();
        if (stick) {
          _scrollToEnd();
        } else {
          setState(() => newBelow = true);
        }
      }
    } catch (e) {
      if (!mounted) return;
      final message = friendlyError(e);
      setState(() {
        loading = false;
        loadingMore = false;
        error = message;
      });
      // Une erreur pendant un rafraîchissement ne doit pas passer inaperçue.
      if (msgs.isNotEmpty) _snack(message, err: true);
    }
  }

  /// Curseur de pagination : la date du plus ancien message **réel**
  /// (on ignore les bulles optimistes, qui datent de maintenant).
  int? _oldestCursor() {
    for (final m in msgs) {
      if (m['_local'] == true || '${m['status']}' == 'sending') continue;
      final v = int.tryParse('${m['created_at'] ?? 0}') ?? 0;
      if (v > 0) return v;
    }
    return null;
  }

  /// Fusionne la dernière page du serveur dans la liste affichée.
  void _mergeTail(List<Map<String, dynamic>> fresh) {
    final parId = {for (final m in fresh) '${m['id']}': m};
    final enCours = {
      for (final m in msgs)
        if (m['_local'] == true || '${m['status']}' == 'sending') '${m['id']}'
    };
    final suite = <Map>[];
    for (final m in msgs) {
      final id = '${m['id']}';
      if (enCours.contains(id)) {
        suite.add(m); // on ne remplace pas une bulle encore « envoi… »
        continue;
      }
      suite.add(parId.remove(id) ?? m); // état rafraîchi (lu, supprimé…)
    }
    final nouveaux = parId.values.toList()
      ..sort((a, b) => _ms(a['created_at']).compareTo(_ms(b['created_at'])));
    msgs
      ..clear()
      ..addAll(suite)
      ..addAll(nouveaux);
  }

  static int _ms(Object? v) => int.tryParse('${v ?? 0}') ?? 0;

  void _scrollToEnd({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      final target = scroll.position.maxScrollExtent;
      if (animate && target > 400) {
        scroll.animateTo(target,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } else {
        scroll.jumpTo(target);
      }
    });
  }

  Future<void> _markRead() async {
    try {
      await api.markConversationRead(widget.peerPhone);
    } catch (_) {}
  }

  // ═══════════════════════ Temps réel ═══════════════════════

  bool _isPeer(Object? raw) => samePeerPhone(raw, widget.peerPhone);

  /// Entrée temps réel (WebSocket) : « écrit… », nouveau message, lu, écouté,
  /// supprimé. Publique pour être testable sans serveur.
  void handleRealtime(Map raw) {
    if (!mounted) return;
    final m = raw;
    final type = '${m['type'] ?? ''}';

    if (type == 'typing') {
      if (!_isPeer(m['from'])) return;
      typingTimer?.cancel();
      setState(() => typingAt = DateTime.now());
      typingTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => typingAt = null);
      });
      return;
    }
    if (type != 'msg') return;

    final kind = '${m['kind'] ?? ''}';
    final from = m['from_phone'];
    final msgId = '${m['msg_id'] ?? ''}';

    switch (kind) {
      case 'message':
        if (from != null && !_isPeer(from)) return;
        setState(() => typingAt = null);
        _load();
      case 'delivered':
        // 📬 Mon message vient d'arriver sur le téléphone du proche.
        setState(() {
          for (final x in msgs) {
            if ('${x['id']}' == msgId && '${x['status']}' == 'sent') {
              x['status'] = 'delivered';
            }
          }
        });
      case 'read':
        setState(() {
          for (final x in msgs) {
            if (x['mine'] == true && '${x['status']}' != 'sending') {
              x['status'] = 'read';
              final readAt = int.tryParse('${x['read_at'] ?? 0}') ?? 0;
              if (readAt <= 0) x['read_at'] = DateTime.now().millisecondsSinceEpoch;
            }
          }
        });
      case 'played':
        setState(() {
          for (final x in msgs) {
            if ('${x['id']}' == msgId) {
              final playedAt = int.tryParse('${x['played_at'] ?? 0}') ?? 0;
              if (playedAt <= 0) x['played_at'] = DateTime.now().millisecondsSinceEpoch;
            }
          }
        });
      case 'deleted':
        setState(() {
          for (final x in msgs) {
            if ('${x['id']}' == msgId) {
              x['deleted'] = true;
              x['body'] = '';
              x['translation'] = '';
              x['transcript'] = '';
              x['has_media'] = false;
              x['kind'] = 'deleted';
            }
          }
        });
    }
  }

  /// « écrit… » envoyé au proche (au plus une fois toutes les 3 s).
  void _onTyping() {
    final now = DateTime.now();
    if (typingSentAt != null &&
        now.difference(typingSentAt!).inMilliseconds < 3000) {
      return;
    }
    typingSentAt = now;
    Rtc.send({'type': 'typing', 'to': widget.peerPhone});
  }

  // ═══════════════════════ Envois ═══════════════════════

  String _clientId() =>
      'c${DateTime.now().microsecondsSinceEpoch}_${_nextLocalId++}';

  void _addLocal(Map m) {
    setState(() => msgs.add(m));
    _scrollToEnd(animate: false);
  }

  void _dropLocal(String localId) =>
      setState(() => msgs.removeWhere((m) => '${m['id']}' == localId));

  Future<void> _sendText() async {
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    final clientId = _clientId();
    ctrl.clear();
    drafts.remove(widget.peerPhone);
    setState(() => sending = true);

    // 1. Affichage immédiat.
    _addLocal({
      'id': clientId,
      'kind': 'text',
      'mine': true,
      'body': text,
      'status': 'sending',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    // 2. Envoi réel (idempotent grâce au client_id).
    try {
      final row = await api.sendMessage(
        widget.peerPhone,
        text,
        clientId: clientId,
        langFrom: langFrom,
        langTo: langTo,
      );
      if (!mounted) return;
      final saved = Map<String, dynamic>.from(row);
      setState(() {
        final i = msgs.indexWhere((m) => '${m['id']}' == clientId);
        if (i >= 0) {
          msgs[i] = saved;
        } else if (!msgs.any((m) => '${m['id']}' == '${saved['id']}')) {
          msgs.add(saved);
        }
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final i = msgs.indexWhere((m) => '${m['id']}' == clientId);
        if (i >= 0) msgs[i]['status'] = 'failed';
      });
      _snack(friendlyError(e), err: true);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _retry(Map m) async {
    final text = '${m['body'] ?? ''}';
    _dropLocal('${m['id']}');
    ctrl.text = text;
    await _sendText();
  }

  Future<void> _sendImage() async {
    try {
      final x = await picker.pickImage(
          source: ImageSource.gallery, maxWidth: 1600, imageQuality: 78);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      await _sendMediaBytes(
        bytes: bytes,
        kind: 'image',
        mime: _mimeOf(x.name, 'image/jpeg'),
        name: x.name,
      );
    } catch (e) {
      _snack(friendlyError(e), err: true);
    }
  }

  Future<void> _sendCamera() async {
    try {
      final x = await picker.pickImage(
          source: ImageSource.camera, maxWidth: 1600, imageQuality: 78);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      await _sendMediaBytes(
        bytes: bytes,
        kind: 'image',
        mime: _mimeOf(x.name, 'image/jpeg'),
        name: x.name,
      );
    } catch (e) {
      _snack(friendlyError(e), err: true);
    }
  }

  Future<void> _sendFile() async {
    try {
      final r = await FilePicker.pickFiles(withData: true);
      if (r == null || r.files.isEmpty) return;
      final f = r.files.first;
      final bytes = f.bytes ??
          (f.path != null ? await File(f.path!).readAsBytes() : null);
      if (bytes == null) return;
      if (bytes.length > 20 * 1024 * 1024) {
        _snack(L10n.t('chat_too_big'), err: true);
        return;
      }
      await _sendMediaBytes(
        bytes: bytes,
        kind: 'file',
        mime: _mimeOf(f.name, 'application/octet-stream'),
        name: f.name,
      );
    } catch (e) {
      _snack(friendlyError(e), err: true);
    }
  }

  Future<void> _sendMediaBytes({
    required List<int> bytes,
    required String kind,
    required String mime,
    required String name,
  }) async {
    final clientId = _clientId();
    setState(() => sending = true);
    _addLocal({
      'id': clientId,
      'kind': kind,
      'mine': true,
      'body': '',
      'att_name': name,
      'att_mime': mime,
      'att_size': bytes.length,
      'status': 'sending',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      '_local': true,
    });
    try {
      final row = await api.sendMessageMedia(
        widget.peerPhone,
        bytes: bytes,
        kind: kind,
        mime: mime,
        name: name,
        clientId: clientId,
      );
      if (!mounted) return;
      final saved = Map<String, dynamic>.from(row);
      setState(() {
        final i = msgs.indexWhere((m) => '${m['id']}' == clientId);
        if (i >= 0) {
          msgs[i] = saved;
        } else if (!msgs.any((m) => '${m['id']}' == '${saved['id']}')) {
          msgs.add(saved);
        }
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final i = msgs.indexWhere((m) => '${m['id']}' == clientId);
        if (i >= 0) msgs[i]['status'] = 'failed';
      });
      _snack(friendlyError(e), err: true);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  // 🎙️ Note vocale traduite

  Future<void> _startRec() async {
    try {
      if (!await recorder.hasPermission()) {
        _snack(L10n.t('lokota_mic_error'), err: true);
        return;
      }
      final dir = await getTemporaryDirectory();
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 22050,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: '${dir.path}/mbote_note.m4a',
      );
      recSec = 0;
      recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => recSec++);
        if (recSec >= 60) _stopAndSend();
      });
      setState(() => recording = true);
    } catch (e) {
      _snack(friendlyError(e), err: true);
    }
  }

  Future<void> _cancelRec() async {
    recTimer?.cancel();
    try {
      await recorder.cancel();
    } catch (_) {}
    if (mounted) setState(() => recording = false);
  }

  Future<void> _stopAndSend() async {
    recTimer?.cancel();
    final secs = recSec;
    String? path;
    try {
      path = await recorder.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() => recording = false);
    if (path == null) return;
    String? localId;
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.length < 800) {
        _snack(L10n.t('chat_too_short'), err: true);
        return;
      }
      final clientId = _clientId();
      localId = clientId;
      setState(() => sending = true);
      _addLocal({
        'id': clientId,
        'kind': 'voice',
        'mine': true,
        'body': '',
        'duration_sec': math.max(1, secs),
        'status': 'sending',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      final row = await api.sendVoiceNote(
        widget.peerPhone,
        bytes: bytes,
        durationSec: math.max(1, secs),
        langFrom: langFrom,
        langTo: langTo,
        wave: _fakeWave(bytes.length),
        clientId: clientId,
      );
      if (!mounted) return;
      final saved = Map<String, dynamic>.from(row);
      setState(() {
        final i = msgs.indexWhere((m) => '${m['id']}' == clientId);
        if (i >= 0) {
          msgs[i] = saved;
        } else {
          msgs.add(saved);
        }
      });
      _scrollToEnd();
    } catch (e) {
      if (mounted) {
        setState(() {
          msgs.removeWhere((m) => '${m['id']}' == (localId ?? ''));
        });
        _snack(friendlyError(e), err: true);
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  /// Petite forme d'onde décorative (le serveur n'analyse pas l'audio).
  static List<int> _fakeWave(int seed) {
    final r = math.Random(seed);
    return List<int>.generate(28, (_) => 25 + r.nextInt(70));
  }

  // ▶️ Écoute d'une note vocale

  Future<void> _play(Map n) async {
    final id = '${n['id']}';
    if (playingId == id) {
      await player.stop();
      if (mounted) setState(() => playingId = null);
      return;
    }
    final api = this.api;
    try {
      await player.stop();
      if (n['_local'] == true || '${n['status']}' == 'sending') return;
      final r = await http.get(
        Uri.parse(api.messageMediaUrl(id)),
        headers: api.authHeaders,
      );
      if (r.statusCode >= 400) throw ApiException(L10n.t('lokota_play_error'));
      await player.play(BytesSource(r.bodyBytes));
      if (!mounted) return;
      setState(() => playingId = id);
      if (n['mine'] != true) {
        final played = int.tryParse('${n['played_at'] ?? 0}') ?? 0;
        if (played <= 0) {
          n['played_at'] = DateTime.now().millisecondsSinceEpoch;
          api.markMessagePlayed(id).catchError((Object _) {});
        }
      }
    } catch (e) {
      _snack(friendlyError(e), err: true);
    }
  }

  // 🖼️ / 📎 Ouverture d'une pièce jointe

  Future<void> _openFile(Map m) async {
    final api = this.api;
    try {
      _snack(L10n.t('chat_downloading'));
      final r = await http.get(
        Uri.parse(api.messageMediaUrl('${m['id']}')),
        headers: api.authHeaders,
      );
      if (r.statusCode >= 400) throw ApiException(L10n.t('chat_download_fail'));
      final dir = await getTemporaryDirectory();
      final safe = '${m['att_name'] ?? 'fichier'}'.replaceAll(RegExp(r'[^\w.\-]'), '_');
      final f = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$safe');
      await f.writeAsBytes(r.bodyBytes);
      await Share.shareXFiles([XFile(f.path)], text: '${m['att_name'] ?? ''}');
    } catch (e) {
      _snack(friendlyError(e), err: true);
    }
  }

  // 🗑️ Suppression

  Future<void> _menu(Map m) async {
    if ('${m['status']}' == 'sending') return;
    final mine = m['mine'] == true;
    final hasText = '${m['body'] ?? ''}'.trim().isNotEmpty;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MC.nuit2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasText)
              ListTile(
                leading: Icon(Icons.copy_rounded, color: MC.sable),
                title: Text(L10n.t('chat_copy'),
                    style: TextStyle(color: MC.ivoire)),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
            ListTile(
              leading: Icon(Icons.visibility_off_rounded, color: MC.sable),
              title: Text(L10n.t('chat_delete_me'),
                  style: TextStyle(color: MC.ivoire)),
              onTap: () => Navigator.pop(ctx, 'me'),
            ),
            if (mine)
              ListTile(
                leading: Icon(Icons.delete_forever_rounded, color: MC.rouge),
                title: Text(L10n.t('chat_delete_all'),
                    style: TextStyle(color: MC.rouge)),
                onTap: () => Navigator.pop(ctx, 'all'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final id = '${m['id']}';
    try {
      if (choice == 'copy') {
        await _copy('${m['body'] ?? ''}');
        _snack(L10n.t('chat_copied'));
        return;
      }
      if (choice == 'all') {
        await api.deleteMessageForAll(id);
        setState(() {
          final i = msgs.indexWhere((x) => '${x['id']}' == id);
          if (i >= 0) {
            msgs[i]
              ..['deleted'] = true
              ..['kind'] = 'deleted'
              ..['body'] = ''
              ..['translation'] = ''
              ..['transcript'] = ''
              ..['has_media'] = false;
          }
        });
      } else {
        await api.deleteMessagesForMe([id]);
        setState(() => msgs.removeWhere((x) => '${x['id']}' == id));
      }
    } catch (e) {
      _snack(friendlyError(e), err: true);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  static String _mimeOf(String name, String fallback) {
    final n = name.toLowerCase();
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.mp4')) return 'video/mp4';
    if (n.endsWith('.m4a')) return 'audio/mp4';
    if (n.endsWith('.mp3')) return 'audio/mpeg';
    if (n.endsWith('.doc')) return 'application/msword';
    if (n.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (n.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (n.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (n.endsWith('.txt')) return 'text/plain';
    if (n.endsWith('.zip')) return 'application/zip';
    return fallback;
  }

  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: err ? MC.rouge : MC.savane,
        duration: const Duration(seconds: 3)));
  }

  void _attachments() {
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.nuit2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.photo_library_rounded, color: MC.sable),
              title: Text(L10n.t('chat_photo'),
                  style: TextStyle(color: MC.ivoire)),
              onTap: () {
                Navigator.pop(ctx);
                _sendImage();
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_rounded, color: MC.sable),
              title: Text(L10n.t('chat_camera'),
                  style: TextStyle(color: MC.ivoire)),
              onTap: () {
                Navigator.pop(ctx);
                _sendCamera();
              },
            ),
            ListTile(
              leading: Icon(Icons.attach_file_rounded, color: MC.sable),
              title: Text(L10n.t('chat_file'),
                  style: TextStyle(color: MC.ivoire)),
              onTap: () {
                Navigator.pop(ctx);
                _sendFile();
              },
            ),
            ListTile(
              leading: Icon(Icons.mic_rounded, color: MC.sable),
              title: Text(L10n.t('chat_voice_note'),
                  style: TextStyle(color: MC.ivoire)),
              onTap: () {
                Navigator.pop(ctx);
                _startRec();
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  void _openImage(Map m) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ImageViewer(
          url: api.messageMediaUrl('${m['id']}'),
          headers: api.authHeaders,
          name: '${m['att_name'] ?? ''}',
        ),
      ),
    );
  }

  void _call({required bool video}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          to: widget.peerPhone,
          displayName: peerName,
          video: video,
        ),
      ),
    );
  }

  // ═══════════════════════ Interface ═══════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MC.nuit,
      appBar: AppBar(
        backgroundColor: MC.nuit2,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: MC.ligne)),
        leading: IconButton(
          tooltip: L10n.t('back'),
          icon: Icon(Icons.arrow_back_rounded, color: MC.ivoire),
          onPressed: () => Navigator.maybePop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: Densite.avatar,
              height: Densite.avatar,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Rd.avatar),
                gradient: MC.degrade,
              ),
              alignment: Alignment.center,
              child: Text(
                  peerName.isEmpty
                      ? '?'
                      : String.fromCharCodes(peerName.runes.take(2)).toUpperCase(),
                  style: TextStyle(
                      color: MC.onAccent,
                      fontSize: Tx.body,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: Sp.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(peerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.subtitle,
                          fontWeight: FontWeight.w800)),
                  Text(
                    typingAt != null
                        ? L10n.t('chat_typing')
                        : online
                            ? L10n.t('chat_online')
                            : _lastSeenLabel(),
                    maxLines: 1,
                    style: TextStyle(
                        color: typingAt != null ? MC.savane : MC.kaki,
                        fontSize: Tx.label,
                        fontWeight:
                            typingAt != null ? FontWeight.w600 : FontWeight.w400),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Choix du type d'appel : icônes seules, couleur = sens.
          FloatingChoice(
            icon: Icons.call_rounded,
            color: MC.savane,
            label: L10n.t('chat_call_audio'),
            size: 44,
            outlined: true,
            onTap: () => _call(video: false),
          ),
          const SizedBox(width: Sp.x2),
          FloatingChoice(
            icon: Icons.videocam_rounded,
            color: MC.soleil,
            label: L10n.t('chat_call_video'),
            size: 44,
            outlined: true,
            onTap: () => _call(video: true),
          ),
          const SizedBox(width: Sp.x3),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _list()),
                if (newBelow)
                  Positioned(
                    right: 14,
                    bottom: 12,
                    child: _newMessagePill(),
                  ),
              ],
            ),
          ),
          if (recording) _recBar() else _composer(),
        ],
      ),
    );
  }

  /// « ↓ nouveau message » : apparaît si l'on lit l'historique plus haut.
  Widget _newMessagePill() {
    return Material(
      color: MC.soleil,
      borderRadius: BorderRadius.circular(Rd.pill),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(Rd.pill),
        onTap: () {
          setState(() => newBelow = false);
          _scrollToEnd();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_downward_rounded, size: 15, color: MC.onAccent),
              const SizedBox(width: 5),
              Text(L10n.t('chat_new_messages'),
                  style: TextStyle(
                      color: MC.onAccent,
                      fontSize: Tx.label,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }

  String _lastSeenLabel() => chatLastSeen(
        lastSeen,
        now: L10n.t('chat_last_seen_now'),
        at: L10n.t('chat_last_seen_at'),
        yesterdayAt: L10n.t('chat_last_seen_yesterday'),
        offline: L10n.t('chats_offline'),
      );

  Widget _list() {
    if (loading) {
      return const Center(child: Chargement());
    }
    if (error != null && msgs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 46, color: MC.kaki),
              const SizedBox(height: 12),
              Text(error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MC.kaki)),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () {
                  setState(() => loading = true);
                  _load();
                },
                child: Text(L10n.t('chats_refresh'),
                    style: TextStyle(
                        color: MC.soleil, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }

    final rows = <Widget>[];
    if (loadingMore) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
            child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: MC.kaki))),
      ));
    }
    String? lastDay;
    for (final m in msgs) {
      final day = _dayLabel(m['created_at']);
      if (day != lastDay) {
        rows.add(_dayChip(day));
        lastDay = day;
      }
      rows.add(_Bubble(
        msg: m,
        playing: playingId == '${m['id']}',
        onPlay: () => _play(m),
        onLongPress: () => _menu(m),
        onRetry: () => _retry(m),
        onOpenImage: () => _openImage(m),
        onOpenFile: () => _openFile(m),
        imageUrl: api.messageMediaUrl('${m['id']}'),
        headers: api.authHeaders,
      ));
    }
    if (msgs.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(30, 90, 30, 0),
        child: Column(
          children: [
            Icon(Icons.waving_hand_rounded, size: 40, color: MC.soleil),
            const SizedBox(height: 12),
            Text(L10n.t('chat_empty'),
                textAlign: TextAlign.center,
                style: TextStyle(color: MC.kaki, fontSize: Tx.body)),
          ],
        ),
      ));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels <= 40 && hasMore && !loadingMore) _load(older: true);
        return false;
      },
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
        children: rows,
      ),
    );
  }

  Widget _dayChip(String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
                color: MC.nuit2, borderRadius: BorderRadius.circular(Rd.sm)),
            child: Text(label,
                style: TextStyle(
                    color: MC.kaki, fontSize: Tx.caption, fontWeight: FontWeight.w600)),
          ),
        ),
      );

  static String _dayLabel(Object? iso) => chatDayLabel(
        iso,
        today: L10n.t('chat_today'),
        yesterday: L10n.t('chats_yesterday'),
      );

  // ---- Barre de saisie ----

  Widget _composer() {
    return Container(
      color: MC.nuit2,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: _attachments,
              icon: Icon(Icons.add_circle_rounded, color: MC.kaki, size: 26),
              tooltip: L10n.t('chat_attach'),
            ),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 42, maxHeight: 130),
                decoration: BoxDecoration(
                    color: MC.nuit3, borderRadius: BorderRadius.circular(Rd.lg)),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: ctrl,
                  focusNode: focus,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  style: TextStyle(color: MC.ivoire, fontSize: Tx.bodyLg),
                  onChanged: (v) {
                    drafts[widget.peerPhone] = v;
                    setState(() {});
                    if (v.trim().isNotEmpty) _onTyping();
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: L10n.t('chat_hint'),
                    hintStyle: TextStyle(color: MC.kaki, fontSize: Tx.body),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (ctrl.text.trim().isEmpty)
              _roundButton(
                icon: Icons.mic_rounded,
                color: MC.nuit3,
                tint: MC.sable,
                onTap: _startRec,
              )
            else
              _roundButton(
                icon: Icons.send_rounded,
                color: MC.soleil,
                tint: MC.onAccent,
                onTap: _sendText,
              ),
          ],
        ),
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required Color color,
    required Color tint,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 42,
        height: 42,
        margin: const EdgeInsets.only(bottom: 0),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: tint, size: 21),
      ),
    );
  }

  Widget _recBar() {
    String two(int v) => v.toString().padLeft(2, '0');
    return Container(
      color: MC.nuit2,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Icon(Icons.fiber_manual_record, color: MC.rouge, size: 16),
              const SizedBox(width: 8),
              Text('${two(recSec ~/ 60)}:${two(recSec % 60)}',
                  style: TextStyle(
                      color: MC.ivoire,
                      fontSize: Tx.body,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: _pickLangs,
                  child: Row(
                    children: [
                      Icon(Icons.translate_rounded, color: MC.kaki, size: 15),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '$_langFromLabel → $_langToLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: MC.kaki, fontSize: Tx.label),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: _cancelRec,
                icon: Icon(Icons.close_rounded, color: MC.rouge),
                tooltip: L10n.t('chat_cancel'),
              ),
              IconButton(
                onPressed: _stopAndSend,
                icon: Icon(Icons.send_rounded, color: MC.savane),
                tooltip: L10n.t('chat_send'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _langFromLabel => _langName(langFrom);
  String get _langToLabel => _langName(langTo);

  static String _langName(String code) {
    switch (code) {
      case 'ln':
        return L10n.t('lang_ln');
      case 'sw':
        return L10n.t('lang_sw');
      default:
        return L10n.t('lang_fr');
    }
  }

  void _pickLangs() {
    const codes = ['fr', 'ln', 'sw'];
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.nuit2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.t('chat_lang_from'),
                  style: TextStyle(
                      color: MC.ivoire, fontWeight: FontWeight.w700)),
              Wrap(
                spacing: 8,
                children: codes
                    .map((c) => ChoiceChip(
                          label: Text(_langName(c)),
                          selected: langFrom == c,
                          onSelected: (_) => setState(() => langFrom = c),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 14),
              Text(L10n.t('chat_lang_to'),
                  style: TextStyle(
                      color: MC.ivoire, fontWeight: FontWeight.w700)),
              Wrap(
                spacing: 8,
                children: codes
                    .map((c) => ChoiceChip(
                          label: Text(_langName(c)),
                          selected: langTo == c,
                          onSelected: (_) => setState(() => langTo = c),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(L10n.t('chat_ok'),
                      style:
                          TextStyle(color: MC.soleil, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════ Bulles ═══════════════════════

class _Bubble extends StatelessWidget {
  final Map msg;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onLongPress;
  final VoidCallback onRetry;
  final VoidCallback onOpenImage;
  final VoidCallback onOpenFile;
  final String imageUrl;
  final Map<String, String> headers;

  const _Bubble({
    required this.msg,
    required this.playing,
    required this.onPlay,
    required this.onLongPress,
    required this.onRetry,
    required this.onOpenImage,
    required this.onOpenFile,
    required this.imageUrl,
    required this.headers,
  });

  @override
  Widget build(BuildContext context) {
    final mine = msg['mine'] == true;
    final status = '${msg['status'] ?? ''}';
    final failed = status == 'failed';
    final deleted = msg['deleted'] == true || '${msg['kind']}' == 'deleted';

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: deleted
              ? const EdgeInsets.fromLTRB(12, 9, 12, 7)
              : const EdgeInsets.fromLTRB(10, 7, 10, 6),
          // Identité « Fleuve Congo » : mes bulles sont un aplat de sable
          // (lisible en plein soleil), les autres un aplat de nuit3 cerclé.
          // Plus de dégradé par bulle : le dégradé reste la signature des
          // avatars et des boutons.
          decoration: BoxDecoration(
            color: deleted
                ? MC.nuit2
                : mine
                    ? MC.soleil
                    : MC.nuit3,
            border: Border.all(
                color: deleted
                    ? MC.ligne
                    : mine
                        ? MC.soleil
                        : MC.ligne),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(Rd.md),
              topRight: const Radius.circular(Rd.md),
              bottomLeft: Radius.circular(mine ? Rd.md : Rd.xs),
              bottomRight: Radius.circular(mine ? Rd.xs : Rd.md),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (deleted)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.block, size: 13, color: MC.kaki),
                    const SizedBox(width: 5),
                    Text(L10n.t('chats_deleted'),
                        style: TextStyle(
                            color: MC.kaki,
                            fontSize: Tx.label,
                            fontStyle: FontStyle.italic)),
                  ],
                )
              else
                _content(context),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_hhmm(msg['created_at']),
                      style: TextStyle(
                          color: mine
                              ? MC.onAccent.withValues(alpha: 0.65)
                              : MC.kaki,
                          fontSize: Tx.caption)),
                  const SizedBox(width: 4),
                  if (mine) _ticks(status),
                ],
              ),
              if (failed)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: InkWell(
                    onTap: onRetry,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: 13, color: MC.rouge),
                        const SizedBox(width: 4),
                        Text(L10n.t('chat_retry'),
                            style: TextStyle(
                                color: MC.rouge,
                                fontSize: Tx.caption,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final kind = '${msg['kind'] ?? 'text'}';
    final tint = msg['mine'] == true ? MC.onAccent : MC.ivoire;

    switch (kind) {
      case 'image':
        if (msg['_local'] == true || '${msg['status']}' == 'sending') {
          return _pending(tint, Icons.image_rounded);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: onOpenImage,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Rd.sm),
                child: Image.network(
                  imageUrl,
                  headers: headers,
                  semanticLabel: L10n.t('photo'),
                  width: 210,
                  fit: BoxFit.cover,
                  loadingBuilder: (c, child, p) => p == null
                      ? child
                      : Container(
                          width: 210,
                          height: 140,
                          color: MC.nuit.withValues(alpha: 0.25),
                          child: Center(
                              child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: tint.withValues(alpha: 0.6)))),
                        ),
                  errorBuilder: (c, e, s) => Container(
                    width: 210,
                    height: 120,
                    color: MC.nuit.withValues(alpha: 0.2),
                    child: Icon(Icons.broken_image_rounded,
                        color: tint.withValues(alpha: 0.7)),
                  ),
                ),
              ),
            ),
            if ('${msg['body'] ?? ''}'.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${msg['body']}',
                    style: TextStyle(color: tint, fontSize: Tx.body)),
              ),
          ],
        );

      case 'file':
        if (msg['_local'] == true || '${msg['status']}' == 'sending') {
          return _pending(tint, Icons.insert_drive_file_rounded);
        }
        return InkWell(
          onTap: onOpenFile,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file_rounded, color: tint, size: 26),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${msg['att_name'] ?? 'fichier'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: tint,
                            fontSize: Tx.label,
                            fontWeight: FontWeight.w600)),
                    Text(_size(msg['att_size']),
                        style: TextStyle(
                            color: tint.withValues(alpha: 0.7), fontSize: Tx.caption)),
                  ],
                ),
              ),
            ],
          ),
        );

      case 'note':
      case 'voice':
        if (msg['_local'] == true || '${msg['status']}' == 'sending') {
          return _pending(tint, Icons.mic_rounded);
        }
        return _voice(context, tint);

      default:
        return Text('${msg['body'] ?? ''}',
            style: TextStyle(color: tint, fontSize: Tx.bodyLg, height: 1.28));
    }
  }

  Widget _pending(Color tint, IconData icon) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tint.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.6, color: tint.withValues(alpha: 0.7))),
          const SizedBox(width: 6),
          Text(L10n.t('chat_sending'),
              style: TextStyle(
                  color: tint.withValues(alpha: 0.8), fontSize: Tx.label)),
        ],
      );

  Widget _voice(BuildContext context, Color tint) {
    final mine = msg['mine'] == true;
    final wave = (msg['wave'] is List && (msg['wave'] as List).isNotEmpty)
        ? (msg['wave'] as List)
        : List<int>.generate(24, (i) => 30 + (i * 7) % 60);
    final duration = int.tryParse('${msg['duration_sec'] ?? 0}') ?? 0;
    final transcript = '${msg['transcript'] ?? ''}'.trim();
    final translation = '${msg['translation'] ?? ''}'.trim();
    final played = (int.tryParse('${msg['played_at'] ?? 0}') ?? 0) > 0;

    return StatefulBuilder(builder: (ctx, setSt) {
      final showTrad = _showTrad[msg['id']] ?? false;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: onPlay,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: mine
                        ? MC.onAccent.withValues(alpha: 0.16)
                        : MC.soleil.withValues(alpha: 0.18),
                  ),
                  child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 20, color: tint),
                ),
              ),
              const SizedBox(width: 8),
              ..._bars(wave, tint, playing),
              const SizedBox(width: 8),
              Text(_dur(duration),
                  style: TextStyle(
                      color: tint.withValues(alpha: 0.8), fontSize: Tx.label)),
            ],
          ),
          // Le texte affiché : l'original, ou la traduction si on la demande.
          if (_voiceText(transcript, translation, showTrad).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 2),
              child: Text('« ${_voiceText(transcript, translation, showTrad)} »',
                  style: TextStyle(
                      color: tint.withValues(alpha: 0.85),
                      fontSize: Tx.label,
                      fontStyle: FontStyle.italic)),
            ),
          if (transcript.isNotEmpty && translation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: InkWell(
                onTap: () => setSt(() => _showTrad[msg['id']] = !showTrad),
                child: Text(
                    showTrad
                        ? L10n.t('chat_show_original')
                        : L10n.t('chat_show_translation'),
                    style: TextStyle(
                        color: tint.withValues(alpha: 0.7),
                        fontSize: Tx.caption,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline)),
              ),
            ),
          if (mine && played)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hearing_rounded,
                      size: 11, color: tint.withValues(alpha: 0.65)),
                  const SizedBox(width: 3),
                  Text(L10n.t('chat_listened'),
                      style: TextStyle(
                          color: tint.withValues(alpha: 0.65), fontSize: Tx.caption)),
                ],
              ),
            ),
        ],
      );
    });
  }

  /// Original ou traduction, selon le bouton 🌍 de la bulle.
  static String _voiceText(String transcript, String translation, bool showTrad) {
    if (showTrad) return translation.isNotEmpty ? translation : transcript;
    return transcript.isNotEmpty ? transcript : translation;
  }

  /// Barres de la forme d'onde : 8 à 32 traits, hauteur proportionnelle.
  List<Widget> _bars(List wave, Color tint, bool playing) {
    var values = wave
        .map((e) => (e as num?)?.toInt() ?? 40)
        .take(32)
        .toList();
    if (values.isEmpty) {
      values = List<int>.generate(24, (i) => 30 + (i * 7) % 60);
    }
    return List<Widget>.generate(values.length, (i) {
      final v = values[i].clamp(0, 100);
      return Container(
        width: 2.6,
        height: 6 + (v / 100) * 16,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
            color: playing ? tint : tint.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(2)),
      );
    });
  }

  /// Quelques bulles gardent l'état « traduction affichée ».
  static final Map<Object?, bool> _showTrad = {};

  Widget _ticks(String status) {
    switch (status) {
      case 'sending':
        return Icon(Icons.schedule_rounded,
            size: 13, color: MC.onAccent.withValues(alpha: 0.6));
      case 'failed':
        return Icon(Icons.error_outline_rounded, size: 13, color: MC.rouge);
      case 'read':
      case 'done':
        return const Icon(Icons.done_all_rounded,
            size: 15, color: Semantique.luSurBulle);
      case 'delivered':
        return Icon(Icons.done_all_rounded,
            size: 15, color: MC.onAccent.withValues(alpha: 0.55));
      default:
        return Icon(Icons.done_rounded,
            size: 14, color: MC.onAccent.withValues(alpha: 0.55));
    }
  }

  static String _hhmm(Object? iso) => chatClock(iso);

  static String _dur(int sec) => chatDuration(sec);

  static String _size(Object? raw) => chatSize(raw);
}

/// 🔍 Photo en plein écran (zoom, fermeture, partage).
class _ImageViewer extends StatelessWidget {
  final String url;
  final Map<String, String> headers;
  final String name;

  const _ImageViewer(
      {required this.url, required this.headers, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: Tx.body)),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 4,
          child: Image.network(
            url,
            headers: headers,
            semanticLabel: L10n.t('photo'),
            fit: BoxFit.contain,
            errorBuilder: (c, e, s) => const Icon(Icons.broken_image_rounded,
                color: Colors.white54, size: 60),
          ),
        ),
      ),
    );
  }
}
