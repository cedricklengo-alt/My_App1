import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../chat_format.dart';
import '../l10n.dart';
import '../local/repository.dart';
import '../prefs.dart';
import '../rtc.dart';
import '../state.dart';
import '../tabs.dart';
import '../design.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/etat.dart';
import 'call.dart';
import 'chat.dart';


///DISCUSSIONS — la liste des conversations.
///
/// Une seule liste pour tout : messages écrits, photos, fichiers et notes
/// vocales traduites. Le serveur renvoie déjà, pour chaque personne, le dernier
/// message, son état (envoyé / reçu / lu), le nombre de non-lus et la présence.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  /// Total des messages non lus — affiché en pastille sur l'onglet Discussion.
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);

  @override
  State<ChatsScreen> createState() => ChatsScreenState();
}

class ChatsScreenState extends State<ChatsScreen> {
  List threads = [];
  bool loading = true;
  String? error;
  String query = '';
  bool _searching = false;
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
    // 🏠 LOCAL-FIRST : on affiche IMMÉDIATEMENT la base locale (aucun
    // spinner bloquant hors connexion), puis on synchronise en arrière-plan.
    final local = await LocalRepository.instance.listThreads();
    if (mounted && local.isNotEmpty) {
      setState(() {
        threads = local;
        loading = false;
      });
      ChatsScreen.unread.value = _unread;
    }
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
        // Hors connexion : on garde la liste locale, on signale juste
        // discrètement que les données ne sont pas à jour.
        error = local.isEmpty ? friendlyError(e) : null;
      });
    }
  }

  /// Total des non-lus, **hors** conversation actuellement ouverte.
  /// (Accepte le format serveur `unread` et le format local `unread_count`.)
  int get _unread => threads.fold<int>(0, (sum, t) {
        final m = t as Map;
        if ('${m['peer_phone'] ?? ''}' == ChatScreen.openPeer) return sum;
        final u = m['unread_count'] ?? m['unread'] ?? 0;
        return sum + (int.tryParse('$u') ?? 0);
      });

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
                  style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
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
      // Bouton flottant « nouvelle discussion » : l'action principale de
      // l'onglet, atteignable au pouce sans remonter la liste.
      floatingActionButton: _NouvelleDiscussionButton(
        key: const Key('fab-nouvelle-discussion'),
        onTap: _newChat,
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Text(L10n.t('chats_title'),
                style: TextStyle(
                    color: MC.ivoire,
                    fontSize: Tx.headline,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6)),
            if (_unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: MC.soleil,
                    borderRadius: BorderRadius.circular(Rd.pill)),
                child: Text('$_unread',
                    style: TextStyle(
                        color: MC.onAccent,
                        fontSize: Tx.label,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
        // Plus d'icône « écrire » ici : l'action vit désormais dans le bouton
        // flottant, placé sous le pouce (une seule cible, un seul libellé).
        actions: [
          // 🎨 Recherche révélée à la demande (cohérent avec l'onglet Appels) :
          // l'en-tête reste discret, le champ n'encombre pas la liste.
          IconButton(
            tooltip: L10n.t('chats_search'),
            icon: Icon(
                _searching ? Icons.close_rounded : Icons.search_rounded,
                color: _searching ? MC.soleil : MC.kaki,
                size: 22),
            onPressed: () {
              setState(() {
                _searching = !_searching;
                if (!_searching) query = '';
              });
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x1, Sp.x4, Sp.x2),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => query = v.trim()),
                style: TextStyle(color: MC.ivoire, fontSize: Tx.body),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: Sp.x3, horizontal: 14),
                  hintText: L10n.t('chats_search'),
                  hintStyle: TextStyle(color: MC.kaki, fontSize: Tx.body),
                  prefixIcon: Icon(Icons.search, color: MC.kaki, size: 19),
                  filled: true,
                  fillColor: MC.nuit3,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Rd.pill),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          // Identité « Fleuve Congo » : un filet franc sépare l'en-tête du flux.
          Container(height: 1, color: MC.ligne),
          Expanded(child: _body(visible)),
        ],
      ),
    );
  }

  Widget _body(List visible) {
    if (loading) {
      return const Center(child: Chargement());
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
        padding: const EdgeInsets.only(bottom: 108),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: visible.length,
        separatorBuilder: (_, __) => Divider(
            height: 1, indent: 74, endIndent: Sp.x4, color: MC.ligne),
        itemBuilder: (_, i) => _ThreadTile(
          thread: visible[i] as Map,
          masqueNonLus:
              '${(visible[i] as Map)['peer_phone'] ?? ''}' == ChatScreen.openPeer,
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
        const SizedBox(height: 90),
        EtatPage(
          icone: icon,
          titre: text,
          actionLabel: action?.$1 ?? (retry ? L10n.t('chats_refresh') : null),
          onAction: action?.$2 ??
              (retry
                  ? () {
                      setState(() => loading = true);
                      _load();
                    }
                  : null),
        ),
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

  /// Ce fil est ouvert en ce moment : ses messages ne sont pas « non lus ».
  final bool masqueNonLus;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ThreadTile({
    required this.thread,
    required this.name,
    required this.typing,
    this.masqueNonLus = false,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final unread =
        masqueNonLus ? 0 : int.tryParse('${thread['unread'] ?? 0}') ?? 0;
    final online = thread['online'] == true;
    final mine = thread['last_mine'] == true;
    final type = '${thread['last_type'] ?? ''}';
    final preview = typing
        ? L10n.t('chat_typing')
        : _preview(type, thread['last_preview'], mine);
    final dark = unread > 0;
    // Icône Material du type de média (aucun emoji dans l'interface).
    final kindIc = typing ? null : _kindIcon(type);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x4, Sp.x2),
        child: Row(
          children: [
            SizedBox(
              width: Densite.avatar + Sp.x1,
              height: Densite.avatar + Sp.x1,
              child: Stack(
                children: [
                  // 📸 Photo de profil du contact ; anneau dégradé doré
                  // quand la conversation a des non lus (maquette premium).
                  Container(
                    width: Densite.avatar + Sp.x1,
                    height: Densite.avatar + Sp.x1,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Rd.avatar + 2),
                      gradient: dark ? MC.degrade : null,
                    ),
                    padding: EdgeInsets.all(dark ? 2 : 0),
                    child: Container(
                      width: Densite.avatar,
                      height: Densite.avatar,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Rd.avatar),
                        color: MC.nuit3,
                      ),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      child: _avatarPhoto(thread) != null
                          ? Image.network(
                              _avatarPhoto(thread)!,
                              fit: BoxFit.cover,
                              excludeFromSemantics: true,
                              errorBuilder: (_, __, ___) => Text(_initials(name),
                                  style: TextStyle(
                                      color: MC.sable,
                                      fontWeight: FontWeight.w800,
                                      fontSize: Tx.subtitle)),
                            )
                          : Text(_initials(name),
                              style: TextStyle(
                                  color: MC.sable,
                                  fontWeight: FontWeight.w800,
                                  fontSize: Tx.subtitle)),
                    ),
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
            const SizedBox(width: Sp.x4),
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
                                fontSize: Tx.bodyLg,
                                fontWeight:
                                    dark ? FontWeight.w800 : FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      Text(_when(thread['last_at']),
                          style: TextStyle(
                              color: dark ? MC.soleil : MC.kaki,
                              fontSize: Tx.label,
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
                      // Icône Material explicative selon le type du dernier
                      // message (photo, vidéo, note vocale…) — aucun emoji.
                      if (kindIc != null) ...[
                        Icon(kindIc, size: 14, color: MC.kaki),
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
                                fontSize: Tx.body,
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
                              borderRadius: BorderRadius.circular(Rd.pill)),
                          child: Text(unread > 99 ? '99+' : '$unread',
                              style: TextStyle(
                                  color: MC.onAccent,
                                  fontSize: Tx.caption,
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
        prefix = L10n.t('chats_voice');
      case 'image':
        prefix = L10n.t('chats_photo');
      case 'file':
        prefix = L10n.t('chats_file');
      case 'deleted':
        prefix = L10n.t('chats_deleted');
      default:
        prefix = '';
    }
    if (prefix.isEmpty) {
      final body = text.isEmpty ? L10n.t('chats_no_message') : text;
      return mine ? '${L10n.t('chats_you')} : $body' : body;
    }
    return text.isEmpty ? prefix : '$prefix · $text';
  }

  /// Icône Material associée au type du dernier message (aperçu de la liste).
  static IconData? _kindIcon(String type) => switch (type) {
        'image' => Icons.photo_rounded,
        'video' => Icons.videocam_rounded,
        'voice' || 'note' => Icons.mic_rounded,
        'audio' => Icons.graphic_eq_rounded,
        'file' => Icons.insert_drive_file_rounded,
        'deleted' => Icons.delete_outline_rounded,
        _ => null,
      };

  static String _initials(String name) => chatInitials(name);

  /// Photo de profil du contact si le serveur la fournit, sinon null
  /// (l'avatar retombe sur les initiales).
  static String? _avatarPhoto(Map thread) {
    final a = thread['peer_avatar'];
    return (a is String && a.isNotEmpty) ? a : null;
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
        return Semantique.lu;
      case 'delivered':
        return MC.kaki;
      default:
        return MC.kaki;
    }
  }

  /// Heure du jour, « Hier », sinon la date — comme dans une vraie messagerie.
  static String _when(Object? iso) => chatListTime(
        iso,
        yesterday: L10n.t('chats_yesterday'),
        daysAgo: L10n.t('chats_days_ago'),
      );
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
                        fontSize: Tx.subtitle,
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
                    borderRadius: BorderRadius.circular(Rd.md),
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
                        leading: MboteAvatar(
                          name: name.isEmpty ? '?' : chatInitials(name),
                          size: 40,
                        ),
                        title: Text(name.isEmpty ? phone : name,
                            style: TextStyle(
                                color: MC.ivoire, fontWeight: FontWeight.w600)),
                        subtitle: Text(phone,
                            style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
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

///BOUTON FLOTTANT — démarrer une nouvelle discussion.
///
/// 68 px, rayon 32 %, icône 42 %, appui qui réduit à .93 : mêmes constantes
/// que les autres boutons flottants de l'application. Le dégradé corail est
/// réservé aux actions **décisives** (publier, payer, écrire à quelqu'un).
///
/// Accessibilité : le bouton porte un libellé (« Nouvelle discussion ») lu par
/// le lecteur d'écran et une infobulle au survol — un simple `+` ne suffirait
/// pas (WCAG 1.1.1 et 4.1.2).
// 🎨 Le bouton flottant de traduction a quitté la liste des discussions :
// il vit désormais DANS chaque conversation (chat.dart), là où l'on
// décide d'activer ou non la traduction.

class _NouvelleDiscussionButton extends StatefulWidget {
  final VoidCallback onTap;
  const _NouvelleDiscussionButton({super.key, required this.onTap});

  @override
  State<_NouvelleDiscussionButton> createState() =>
      _NouvelleDiscussionButtonState();
}

class _NouvelleDiscussionButtonState extends State<_NouvelleDiscussionButton> {
  bool _appuye = false;

  void _set(bool v) {
    if (_appuye != v) setState(() => _appuye = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: L10n.t('chats_new'),
      child: Tooltip(
        message: L10n.t('chats_new'),
        child: GestureDetector(
          onTapDown: (_) => _set(true),
          onTapCancel: () => _set(false),
          onTapUp: (_) => _set(false),
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          child: AnimatedScale(
            scale: _appuye ? .93 : 1,
            duration: Motion.rapide,
            curve: Curves.easeOut,
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                gradient: MC.degrade,
                borderRadius: BorderRadius.circular(68 * .32),
                boxShadow: [
                  BoxShadow(
                      color: MC.braise.withValues(alpha: .38),
                      blurRadius: 22,
                      offset: const Offset(0, 10)),
                ],
              ),
              child: Icon(Icons.edit_square,
                  size: 68 * .42, color: MC.onAccent),
            ),
          ),
        ),
      ),
    );
  }
}
