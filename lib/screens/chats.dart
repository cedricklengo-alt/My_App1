import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../l10n.dart';
import '../rtc.dart';
import '../state.dart';
import '../tabs.dart';
import '../theme.dart';
import 'call.dart';
import 'chat.dart';

/// Le serveur date les fils en millisecondes.
DateTime? _dt(Object? v) {
  if (v == null) return null;
  final n = v is num ? v.toInt() : int.tryParse('$v'.trim());
  if (n == null) {
    final s = '$v'.trim();
    return s.isEmpty ? null : DateTime.tryParse(s);
  }
  if (n <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(n);
}

/// Premières [n] lettres d'un nom (compatible emoji / accents).
String _short(String s, int n) =>
    String.fromCharCodes(s.runes.take(n));

/// 💬 DISCUSSIONS — la liste des conversations.
///
/// Une seule liste pour tout : messages écrits, photos, fichiers et notes
/// vocales traduites. Le serveur renvoie déjà, pour chaque personne, le dernier
/// message, son état (envoyé / reçu / lu), le nombre de non-lus et la présence.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  /// Total des messages non lus — affiché en pastille sur l'onglet Messages.
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);

  @override
  State<ChatsScreen> createState() => ChatsScreenState();
}

class ChatsScreenState extends State<ChatsScreen> {
  List threads = [];
  bool loading = true;
  String? error;
  String query = '';
  Timer? _debounce;

  /// Numéros en train d'écrire (avec l'heure de l'évènement).
  final Map<String, DateTime> _typing = {};
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    Rtc.addMessageListener(handleRealtime);
    Tabs.listen(Tabs.messages, _onTabRefresh);
    _load();
  }

  @override
  void dispose() {
    Rtc.removeMessageListener(handleRealtime);
    Tabs.stopListening(Tabs.messages, _onTabRefresh);
    _debounce?.cancel();
    _typingTimer?.cancel();
    super.dispose();
  }

  /// Temps réel : un message arrive, un message est lu ou supprimé → on
  /// rafraîchit la liste (regroupé pour ne pas marteler le serveur).
  /// Entrée temps réel : nouveau message / lecture / suppression → la liste se
  /// resynchronise ; « écrit… » s'affiche dans la conversation concernée.
  /// Publique pour être testable sans serveur.
  void handleRealtime(Map msg) {
    if (!mounted) return;
    if (msg['type'] == 'typing') {
      final from = '${msg['from'] ?? ''}';
      if (from.isEmpty) return;
      _typing[from] = DateTime.now();
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 4), () {
        if (!mounted) return;
        setState(() => _typing.clear());
      });
      setState(() {});
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  void _onTabRefresh() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final t = await context.read<AppState>().api.messageThreads();
      if (!mounted) return;
      setState(() {
        threads = t;
        loading = false;
        error = null;
      });
      ChatsScreen.unread.value = _unread;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = friendlyError(e);
      });
    }
  }

  int get _unread => threads.fold<int>(
      0, (sum, t) => sum + (int.tryParse('${(t as Map)['unread'] ?? 0}') ?? 0));

  Future<void> _open(Map t) async {
    final phone = '${t['peer_phone'] ?? ''}';
    final name = _displayName(t);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(peerPhone: phone, peerName: name),
      ),
    );
    _load();
  }

  bool _isTyping(Map t) {
    final phone = '${t['peer_phone'] ?? ''}';
    final at = _typing[phone];
    if (at == null) return false;
    return DateTime.now().difference(at).inSeconds < 4;
  }

  /// Appui long : appeler (audio/vidéo) ou marquer comme lu.
  Future<void> _threadActions(Map t) async {
    final phone = '${t['peer_phone'] ?? ''}';
    final name = _displayName(t);
    final unread = int.tryParse('${t['unread'] ?? 0}') ?? 0;
    HapticFeedback.mediumImpact();
    final choix = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MC.nuit2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.call_rounded, color: MC.savane),
              title: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: MC.ivoire, fontWeight: FontWeight.w700)),
              subtitle: Text(phone,
                  style: TextStyle(color: MC.kaki, fontSize: 12)),
            ),
            ListTile(
              leading: Icon(Icons.call_rounded, color: MC.savane),
              title: Text(L10n.t('chat_call_audio'),
                  style: TextStyle(color: MC.ivoire)),
              onTap: () => Navigator.pop(ctx, 'audio'),
            ),
            ListTile(
              leading: Icon(Icons.videocam_rounded, color: MC.soleil),
              title: Text(L10n.t('chat_call_video'),
                  style: TextStyle(color: MC.ivoire)),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            if (unread > 0)
              ListTile(
                leading: Icon(Icons.mark_chat_read_rounded, color: MC.sable),
                title: Text(L10n.t('chats_mark_read'),
                    style: TextStyle(color: MC.ivoire)),
                onTap: () => Navigator.pop(ctx, 'read'),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (!mounted || choix == null) return;
    if (choix == 'read') {
      try {
        await context.read<AppState>().api.markConversationRead(phone);
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(friendlyError(e)), backgroundColor: MC.rouge));
        }
      }
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CallScreen(
                to: phone,
                displayName: name,
                video: choix == 'video'),
      ),
    ).then((_) => _load());
  }

  String _displayName(Map t) {
    final n = '${t['peer_name'] ?? ''}'.trim();
    if (n.isNotEmpty) return n;
    final p = '${t['peer_phone'] ?? ''}';
    return p.isEmpty ? L10n.t('chats_unknown') : p;
  }

  /// ➕ Écrire à quelqu'un : on pioche dans les contacts du téléphone.
  Future<void> _newChat() async {
    final app = context.read<AppState>();
    List contacts = app.contacts;
    if (contacts.isEmpty) {
      try {
        await app.loadContacts();
        contacts = app.contacts;
      } catch (_) {}
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MC.nuit2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => _ContactPicker(contacts: contacts),
    );
    if (picked == null || !mounted) return;
    final phone = '${picked['phone'] ?? ''}'.trim();
    if (phone.isEmpty) return;
    final name = '${picked['name'] ?? ''}'.trim();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
            peerPhone: phone, peerName: name.isEmpty ? phone : name),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = query.isEmpty
        ? threads
        : threads.where((t) {
            final m = t as Map;
            final q = query.toLowerCase();
            return '${m['peer_name'] ?? ''}'.toLowerCase().contains(q) ||
                '${m['peer_phone'] ?? ''}'.toLowerCase().contains(q);
          }).toList();

    return Scaffold(
      backgroundColor: MC.nuit,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Text(L10n.t('chats_title'),
                style: TextStyle(
                    color: MC.ivoire,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            if (_unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: MC.soleil, borderRadius: BorderRadius.circular(11)),
                child: Text('$_unread',
                    style: TextStyle(
                        color: MC.onAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: L10n.t('chats_new'),
            onPressed: _newChat,
            icon: Icon(Icons.edit_square, color: MC.soleil),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => query = v.trim()),
              style: TextStyle(color: MC.ivoire, fontSize: 15),
              decoration: InputDecoration(
                isDense: true,
                hintText: L10n.t('chats_search'),
                hintStyle: TextStyle(color: MC.kaki, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: MC.kaki, size: 20),
                filled: true,
                fillColor: MC.nuit2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(child: _body(visible)),
        ],
      ),
    );
  }

  Widget _body(List visible) {
    if (loading) {
      return Center(child: CircularProgressIndicator(color: MC.soleil));
    }
    if (error != null) {
      return _hint(Icons.cloud_off, error!, retry: true);
    }
    if (visible.isEmpty) {
      return _hint(
        Icons.forum_outlined,
        query.isEmpty ? L10n.t('chats_empty') : L10n.t('chats_no_result'),
        retry: query.isEmpty,
        action: query.isEmpty
            ? (L10n.t('chats_new'), _newChat)
            : null,
      );
    }
    return RefreshIndicator(
      color: MC.soleil,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 90),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: visible.length,
        separatorBuilder: (_, __) => Divider(
            height: 1, indent: 78, endIndent: 14, color: MC.ligne),
        itemBuilder: (_, i) => _ThreadTile(
          thread: visible[i] as Map,
          name: _displayName(visible[i] as Map),
          typing: _isTyping(visible[i] as Map),
          onTap: () => _open(visible[i] as Map),
          onLongPress: () => _threadActions(visible[i] as Map),
        ),
      ),
    );
  }

  Widget _hint(IconData icon, String text,
      {bool retry = false, (String, VoidCallback)? action}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 110),
        Icon(icon, size: 54, color: MC.kaki.withValues(alpha: 0.5)),
        const SizedBox(height: 14),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: MC.kaki, fontSize: 14.5)),
        if (action != null) ...[
          const SizedBox(height: 20),
          Center(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: MC.soleil, foregroundColor: MC.onAccent),
              onPressed: action.$2,
              icon: const Icon(Icons.edit_square, size: 18),
              label: Text(action.$1),
            ),
          ),
        ],
        if (retry) ...[
          const SizedBox(height: 18),
          Center(
            child: TextButton(
              onPressed: () {
                setState(() => loading = true);
                _load();
              },
              child: Text(L10n.t('chats_refresh'),
                  style: TextStyle(
                      color: MC.soleil, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ],
    );
  }
}

/// Une ligne de la liste : avatar, nom, aperçu du dernier message, heure,
/// pastille de non-lus et point de présence.
class _ThreadTile extends StatelessWidget {
  final Map thread;
  final String name;
  final bool typing;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ThreadTile({
    required this.thread,
    required this.name,
    required this.typing,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final unread = int.tryParse('${thread['unread'] ?? 0}') ?? 0;
    final online = thread['online'] == true;
    final mine = thread['last_mine'] == true;
    final type = '${thread['last_type'] ?? ''}';
    final preview = typing
        ? L10n.t('chat_typing')
        : _preview(type, thread['last_preview'], mine);
    final dark = unread > 0;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: dark ? MC.degrade : null,
                      color: dark ? null : MC.nuit3,
                    ),
                    alignment: Alignment.center,
                    child: Text(_initials(name),
                        style: TextStyle(
                            color: dark ? MC.onAccent : MC.sable,
                            fontWeight: FontWeight.w800,
                            fontSize: 17)),
                  ),
                  if (online)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: MC.savane,
                          shape: BoxShape.circle,
                          border: Border.all(color: MC.nuit, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: MC.ivoire,
                                fontSize: 15.5,
                                fontWeight:
                                    dark ? FontWeight.w800 : FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      Text(_when(thread['last_at']),
                          style: TextStyle(
                              color: dark ? MC.soleil : MC.kaki,
                              fontSize: 11.5,
                              fontWeight:
                                  dark ? FontWeight.w700 : FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (mine) ...[
                        Icon(_stateIcon(thread['last_state']),
                            size: 15,
                            color: _stateColor(thread['last_state'])),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: typing
                                    ? MC.savane
                                    : unread > 0
                                        ? MC.sable
                                        : MC.kaki,
                                fontSize: 13.2,
                                fontStyle:
                                    typing ? FontStyle.italic : FontStyle.normal,
                                fontWeight:
                                    unread > 0 || typing ? FontWeight.w600 : null)),
                      ),
                      if (unread > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: MC.soleil,
                              borderRadius: BorderRadius.circular(10)),
                          child: Text(unread > 99 ? '99+' : '$unread',
                              style: TextStyle(
                                  color: MC.onAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _preview(String type, Object? body, bool mine) {
    final text = '${body ?? ''}'.trim();
    String prefix;
    switch (type) {
      case 'note':
      case 'voice':
        prefix = '🎙️ ${L10n.t('chats_voice')}';
      case 'image':
        prefix = '📷 ${L10n.t('chats_photo')}';
      case 'file':
        prefix = '📎 ${L10n.t('chats_file')}';
      case 'deleted':
        prefix = '🚫 ${L10n.t('chats_deleted')}';
      default:
        prefix = '';
    }
    if (prefix.isEmpty) {
      final body = text.isEmpty ? L10n.t('chats_no_message') : text;
      return mine ? '${L10n.t('chats_you')} : $body' : body;
    }
    return text.isEmpty ? prefix : '$prefix · $text';
  }

  static String _initials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return '?';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length == 1) return _short(parts.first, 2).toUpperCase();
    return (_short(parts.first, 1) + _short(parts.last, 1)).toUpperCase();
  }

  static IconData _stateIcon(Object? state) {
    switch ('$state') {
      case 'read':
      case 'done':
        return Icons.done_all_rounded;
      case 'delivered':
        return Icons.done_all_rounded;
      case 'sent':
        return Icons.done_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  static Color _stateColor(Object? state) {
    switch ('$state') {
      case 'read':
      case 'done':
        return const Color(0xFF53BDEB);
      case 'delivered':
        return MC.kaki;
      default:
        return MC.kaki;
    }
  }

  /// Heure du jour, « Hier », sinon la date — comme dans une vraie messagerie.
  static String _when(Object? iso) {
    final d = _dt(iso);
    if (d == null) return '';
    final local = d.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    String two(int v) => v.toString().padLeft(2, '0');
    if (diff == 0) return '${two(local.hour)}:${two(local.minute)}';
    if (diff == 1) return L10n.t('chats_yesterday');
    if (diff < 7) return L10n.t('chats_days_ago').replaceAll('%s', '$diff');
    return '${two(local.day)}/${two(local.month)}';
  }
}

/// Choix d'un destinataire dans le répertoire du téléphone.
class _ContactPicker extends StatefulWidget {
  final List contacts;
  const _ContactPicker({required this.contacts});

  @override
  State<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends State<_ContactPicker> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.contacts.where((c) {
      final m = c is Map ? c : <String, dynamic>{};
      final n = '${m['name'] ?? ''}'.toLowerCase();
      final p = '${m['phone'] ?? ''}'.toLowerCase();
      return q.isEmpty || n.contains(q) || p.contains(q);
    }).toList();

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
                color: MC.kaki.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Row(
              children: [
                Text(L10n.t('chats_new'),
                    style: TextStyle(
                        color: MC.ivoire,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
              style: TextStyle(color: MC.ivoire),
              decoration: InputDecoration(
                isDense: true,
                hintText: L10n.t('chats_search'),
                hintStyle: TextStyle(color: MC.kaki),
                filled: true,
                fillColor: MC.nuit3,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(L10n.t('chats_no_contact'),
                        style: TextStyle(color: MC.kaki)))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i] as Map;
                      final name = '${c['name'] ?? c['phone'] ?? ''}'.trim();
                      final phone = '${c['phone'] ?? ''}'.trim();
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: MC.nuit3,
                          child: Text(
                              name.isEmpty
                                  ? '?'
                                  : _short(name, 2).toUpperCase(),
                              style: TextStyle(
                                  color: MC.sable,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ),
                        title: Text(name.isEmpty ? phone : name,
                            style: TextStyle(
                                color: MC.ivoire, fontWeight: FontWeight.w600)),
                        subtitle: Text(phone,
                            style: TextStyle(color: MC.kaki, fontSize: 12.5)),
                        onTap: () => Navigator.pop(context, c),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
