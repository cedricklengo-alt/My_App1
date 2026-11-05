import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../local/repository.dart';
import '../state.dart';
import '../tabs.dart';
import '../design.dart';
import '../theme.dart';
import '../l10n.dart';
import 'call_sheet.dart';
import 'chat.dart';
import 'keypad.dart';
import 'sms_compose.dart';
import 'call_detail.dart';
import 'contacts.dart';

///Onglet « Appels » : historique par catégorie.
///
/// Ce que l'écran sait faire :
///  • distinguer un appel **reçu** d'un appel **passé** (colonne `direction`)
///    et un appel **sans réponse** (jamais décroché = `answered_at` vide) ;
///  • regrouper par jour (Aujourd'hui · Hier · date) ;
///  • rappeler en audio **ou en vidéo** (même feuille que les contacts) ;
///  • ouvrir le clavier pour composer un numéro ;
///  • afficher une pastille de « manqués » sur l'onglet ;
///  • gérer chargement / erreur réseau / liste vide.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  /// Nombre d'appels manqués — pastille rouge sur l'onglet Appels.
  static final ValueNotifier<int> missed = ValueNotifier<int>(0);

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen>
    with AutomaticKeepAliveClientMixin {
  List calls = [];
  bool loading = true;
  String? error;
  String filter = 'all'; // all | in | out | missed | internet | gsm
  final _recherche = TextEditingController();
  Timer? _debounce;
  String query = '';
  bool _searching = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    Tabs.listen(Tabs.calls, _onTabRefresh);
    _load();
  }

  @override
  void dispose() {
    Tabs.stopListening(Tabs.calls, _onTabRefresh);
    _debounce?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  /// La recherche est faite CÔTÉ SERVEUR (nom du contact ou numéro) : le
  /// téléphone n'a pas à télécharger tout l'historique pour filtrer.
  void _chercher(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => query = v.trim());
      _load();
    });
  }

  void _onTabRefresh() {
    if (mounted) _load();
  }

  /// Rechargement (aussi appelé quand on retape l'onglet actif).
  Future<void> refresh() => _load();

  Future<void> _load() async {
    // 🏠 LOCAL-FIRST : l'historique des appels reste consultable HORS
    // CONNEXION depuis la base locale ; le réseau ne fait que compléter.
    final local = await LocalRepository.instance.listCalls(filter: filter);
    if (mounted && local.isNotEmpty) {
      setState(() {
        calls = local;
        loading = false;
      });
      HistoryScreen.missed.value = local.where((c) => _isMissed(c)).length;
    }
    try {
      final r = await context.read<AppState>().api
          .history(filter: filter, q: query, limit: 200);
      if (!mounted) return;
      final list = (r['calls'] as List?) ?? const [];
      setState(() {
        calls = list;
        loading = false;
        error = null;
      });
      HistoryScreen.missed.value =
          list.where((c) => _isMissed(c)).length;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        // Hors ligne : on conserve l'historique local.
        error = local.isEmpty ? friendlyError(e) : null;
      });
    }
  }

 // Lecture d'une ligne d'historique ───────────────────

  /// Champ normalisé : numéro appelé (serveur `callee`, local `peer_phone`).
  static String _num(dynamic c) => '${c['callee'] ?? c['peer_phone'] ?? ''}';

  static bool _isIn(dynamic c) {
    final d = '${c['direction'] ?? ''}';
    return d == 'incoming' || d == 'in'; // serveur / base locale
  }

  static int _answeredAt(dynamic c) =>
      int.tryParse('${c['answered_at'] ?? 0}') ?? 0;

  /// Décroché ? (`answered_at` renseigné ou durée facturée non nulle)
  static bool _answered(dynamic c) {
    // Format local (base offline) : champ `status` explicite.
    final st = '${c['status'] ?? ''}';
    if (st == 'completed') return true;
    if (st == 'missed' || st == 'refused' || st == 'failed' || st == 'canceled') {
      return false;
    }
    return _answeredAt(c) > 0 || (int.tryParse('${c['billed_sec'] ?? 0}') ?? 0) > 0;
  }

  /// Manqué = jamais décroché.
  static bool _isMissed(dynamic c) => !_answered(c);

  static bool _isVideo(dynamic c) =>
      (int.tryParse('${c['with_video'] ?? 0}') ?? 0) == 1;

  /// Un numéro joignable ressemble à un numéro (les appels de groupe, non).
  /// (Accepte le champ serveur `callee` et le champ local `peer_phone`.)
  static bool _dialable(dynamic c) =>
      RegExp(r'[0-9]{4,}').hasMatch('${c['callee'] ?? c['peer_phone'] ?? ''}');

  /// Le serveur applique `filter` (y compris internet/gsm) et `q` : on affiche
  /// ce qu'il renvoie, sans re-filtrer localement (les deux règles ne peuvent
  /// ainsi pas diverger).
  List get _visible => calls;

 // Actions ───────────────────────────────────────────

  void _call(dynamic c) {
    if (!_dialable(c)) return;
    showCallModeSheet(
      context,
      '${_num(c)}',
      name: '${_num(c)}',
    ).then((_) => _load());
  }

  /// Fiche détaillée : coût, durée, canal, tarif appliqué + actions.
  Future<void> _ouvrirFiche(dynamic c) async {
    HapticFeedback.selectionClick();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CallDetailSheet(
        callId: '${c['id']}',
        fallback: c is Map ? Map<String, dynamic>.from(c) : null,
        dialable: _dialable(c),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'call':
        _call(c);
        break;
      case 'message':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => ChatScreen(peerPhone: '${_num(c)}')));
        break;
      case 'sms':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => SmsComposeScreen(phone: '${_num(c)}')));
        break;
      case 'hidden':
        setState(() => loading = true);
        await _load();
        break;
    }
  }

  void _openKeypad() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const KeypadScreen())).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final visible = _visible;
    return SafeArea(
      child: Scaffold(
        backgroundColor: MC.nuit,
        // Onglet Appels = UN SEUL écran façon dialer Tecno Camon 40 Pro :
        // Récents en haut (onglets Tous/Manqués), pavé + pilule d'appel
        // toujours visibles en bas.
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Column(
                children: [
                  // Titre + recherche (icône) façon référence
                  Row(
                    children: [
                      Expanded(
                        child: Text(L10n.t('nav_calls'),
                            style: TextStyle(
                                fontSize: Tx.display,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -.6,
                                color: MC.ivoire)),
                      ),
                      IconButton(
                        tooltip: L10n.t('history_search'),
                        icon: Icon(Icons.search_rounded,
                            color: MC.kaki, size: 24),
                        onPressed: () => setState(() => _searching = true),
                      ),
                    ],
                  ),
                  if (_searching) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _recherche,
                      autofocus: true,
                      onChanged: _chercher,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(color: MC.ivoire, fontSize: Tx.bodyLg),
                      decoration: InputDecoration(
                        hintText: L10n.t('history_search'),
                        hintStyle: TextStyle(color: MC.kaki, fontSize: Tx.body),
                        prefixIcon:
                            Icon(Icons.search_rounded, color: MC.kaki, size: 22),
                        suffixIcon: IconButton(
                          tooltip: L10n.t('close'),
                          icon: Icon(Icons.close_rounded,
                              color: MC.kaki, size: 18),
                          onPressed: () {
                            _recherche.clear();
                            _chercher('');
                            setState(() => _searching = false);
                          },
                        ),
                        filled: true,
                        fillColor: MC.nuit3,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(Rd.pill),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Onglet segmenté façon référence : Tous / Manqués
                  Row(
                    children: [
                      _segTab('all', 'Tous', filter == 'all'),
                      const SizedBox(width: 22),
                      _segTab('missed', 'Manqués', filter == 'missed'),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            // Liste des récents (scrollable)
            Expanded(
              child: RefreshIndicator(
                color: MC.soleil,
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  children: [
                    if (loading)
                      ..._skeletons()
                    else if (error != null)
                      _errorBox(error!)
                    else if (visible.isEmpty)
                      _emptyBox()
                    else
                      ..._groupedWidgets(visible),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Barre LOCALE de l'écran Appels (façon Camon) :
        // à gauche « Recents | Contacts », à droite bouton clavier flottant.
        bottomNavigationBar: _CallsLocalBar(
          onContacts: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ContactsScreen())),
          onKeypad: _openKeypad,
        ),
      ),
    );
  }


  /// Onglet segmenté « Tous / Manqués » façon dialer Camon (souligné actif).
  Widget _segTab(String value, String label, bool active) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => filter = value);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: active ? MC.ivoire : MC.kaki,
                    fontSize: Tx.bodyLg,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500)),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 3,
              width: 34,
              decoration: BoxDecoration(
                color: active ? MC.soleil : Colors.transparent,
                borderRadius: BorderRadius.circular(Rd.pill),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Regroupe les appels par jour, avec un intertitre lisible., avec un intertitre lisible.
  List<Widget> _groupedWidgets(List visible) {
    final out = <Widget>[];
    String? lastDay;
    for (final c in visible) {
      final day = _dayLabel(c['started_at']);
      if (day != lastDay) {
        out.add(Padding(
          padding: EdgeInsets.only(top: out.isEmpty ? 0 : 14, bottom: 6),
          child: Text(day,
              style: TextStyle(
                  color: MC.kaki,
                  fontSize: Tx.caption,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8)),
        ));
        lastDay = day;
      }
      out.add(_CallTile(
        call: c,
        missed: _isMissed(c),
        incoming: _isIn(c),
        video: _isVideo(c),
        onCall: _dialable(c) ? () => _call(c) : null,
        onOpen: () => _ouvrirFiche(c),
      ));
    }
    return out;
  }


  List<Widget> _skeletons() => List<Widget>.generate(
        4,
        (i) => Container(
          height: 68,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
              color: MC.nuit2,
              borderRadius: BorderRadius.circular(Rd.md),
              border: Border.all(color: MC.ligne)),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                      color: MC.nuit3, shape: BoxShape.circle)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        width: 120,
                        height: 11,
                        decoration: BoxDecoration(
                            color: MC.nuit3,
                            borderRadius: BorderRadius.circular(Rd.xs))),
                    const SizedBox(height: 8),
                    Container(
                        width: 78,
                        height: 9,
                        decoration: BoxDecoration(
                            color: MC.nuit3,
                            borderRadius: BorderRadius.circular(Rd.xs))),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _errorBox(String message) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 40, 10, 10),
        child: Column(
          children: [
            Icon(Icons.cloud_off_rounded, size: 46, color: MC.kaki),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () {
                setState(() => loading = true);
                _load();
              },
              child: Text(L10n.t('history_retry'),
                  style: TextStyle(
                      color: MC.soleil, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  Widget _emptyBox() {
    final (icon, text) = switch (filter) {
      'in' => (Icons.call_received_rounded, L10n.t('history_empty_in')),
      'out' => (Icons.call_made_rounded, L10n.t('history_empty_out')),
      'missed' => (Icons.phone_missed_rounded, L10n.t('history_empty_missed')),
      'internet' => (Icons.wifi_rounded, L10n.t('history_empty')),
      'gsm' => (Icons.phone_in_talk_rounded, L10n.t('history_empty')),
      _ => (Icons.phone_in_talk_rounded, L10n.t('history_empty')),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 46, 10, 10),
      child: Column(
        children: [
          Icon(icon, size: 50, color: MC.kaki.withValues(alpha: 0.55)),
          const SizedBox(height: 14),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: MC.kaki, fontSize: Tx.body)),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: MC.nuit3,
                foregroundColor: MC.ivoire,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
            onPressed: _openKeypad,
            icon: Icon(Icons.dialpad_rounded, size: 18, color: MC.soleil),
            label: Text(L10n.t('history_dial')),
          ),
        ],
      ),
    );
  }

  /// Aujourd'hui · Hier · 12/10
  static String _dayLabel(Object? raw) {
    final ms = int.tryParse('${raw ?? 0}') ?? 0;
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    String two(int v) => v.toString().padLeft(2, '0');
    if (diff == 0) return L10n.t('history_today').toUpperCase();
    if (diff == 1) return L10n.t('chats_yesterday').toUpperCase();
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
}

/// Barre locale inférieure de l'onglet Appels (dans l'écran, pas la nav globale).
class _CallsLocalBar extends StatelessWidget {
  final VoidCallback onContacts;
  final VoidCallback onKeypad;
  const _CallsLocalBar({required this.onContacts, required this.onKeypad});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MC.nuit2,
        border: Border(top: BorderSide(color: MC.ligne, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    _segTab(context, 'Recents', true, () {}),
                    const SizedBox(width: 26),
                    _segTab(context, 'Contacts', false, onContacts),
                  ],
                ),
              ),
              // Bouton clavier flottant à droite
              Positioned(
                right: 16,
                top: -24,
                child: Semantics(
                  button: true,
                  label: L10n.t('nav_keypad'),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onKeypad();
                    },
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: MC.soleil,
                        boxShadow: [
                          BoxShadow(
                              color: MC.soleil.withValues(alpha: .35),
                              blurRadius: 16,
                              offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Icon(Icons.dialpad_rounded,
                          color: MC.onAccent, size: 28),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segTab(
      BuildContext context, String label, bool active, VoidCallback onTap) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Text(label,
                style: TextStyle(
                    color: active ? MC.soleil : MC.kaki,
                    fontSize: Tx.body,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500)),
            const SizedBox(height: 6),
            Container(
              height: 3,
              width: 30,
              decoration: BoxDecoration(
                color: active ? MC.soleil : Colors.transparent,
                borderRadius: BorderRadius.circular(Rd.pill),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallTile extends StatelessWidget {
  final dynamic call;
  final bool missed;
  final bool incoming;
  final bool video;
  final VoidCallback? onCall;
  final VoidCallback? onOpen;

  const _CallTile({
    required this.call,
    required this.missed,
    required this.incoming,
    required this.video,
    required this.onCall,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final ms = int.tryParse('${call['started_at'] ?? 0}') ?? 0;
    final date = DateTime.fromMillisecondsSinceEpoch(ms == 0 ? 0 : ms);
    final when =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    // Renommage : les anciens appels « MboteCall → MboteCall » s'affichent « MboteCall »
    var dest = (call['destination'] ?? '').toString();
    if (dest.isEmpty) dest = 'MboteCall';
    if (dest.contains('MBOTE')) dest = 'MboteCall';

    final dur = int.tryParse('${call['billed_sec'] ?? 0}') ?? 0;
    final name = HistoryScreenState._num(call).isEmpty ? 'Inconnu' : HistoryScreenState._num(call);
    final contactName = '${call['contact_name'] ?? call['peer_name'] ?? ''}';
    final display = contactName.isNotEmpty ? contactName : name;

    // 🎨 REFONTE UX — ligne PLATE style messagerie moderne (WhatsApp/Telegram) :
    // plus de carte ni de bordure, avatar circulaire avec initiale, nom en gras
    // (rouge si appel manqué), sous-titre avec petite icône de direction,
    // séparateur fin entre les lignes, bouton d'appel vert à droite.
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              // Zones tactiles généreuses (≥48 dp) pour le doigt.
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  // Avatar circulaire avec initiale (ou icône si pas de nom).
                  Semantics(
                    label: 'Appel avec $display',
                    excludeSemantics: true,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (missed ? MC.rouge : MC.savane)
                            .withValues(alpha: 0.13),
                      ),
                      child: Center(
                        child: Text(
                          display.isNotEmpty
                              ? display[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: missed ? MC.rouge : MC.savane,
                            fontSize: Tx.bodyLg,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Nom + sous-titre (direction · type · heure · durée).
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                display,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: missed ? MC.rouge : MC.ivoire,
                                  fontSize: Tx.body,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (video) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.videocam_rounded,
                                  size: 14, color: MC.soleil),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              missed
                                  ? Icons.phone_missed_rounded
                                  : incoming
                                      ? Icons.call_received_rounded
                                      : Icons.call_made_rounded,
                              size: 13,
                              color: missed ? MC.rouge : MC.kaki,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                missed
                                    ? '${L10n.t('history_unanswered')} · $dest · $when'
                                    : '$dest · $when'
                                        '${dur > 0 ? ' · ${_fmt(dur)}' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                      missed ? MC.rouge.withValues(alpha: .85) : MC.kaki,
                                  fontSize: Tx.label,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Bouton rappeler — vert, bien dimensionné.
                  if (onCall != null)
                    Semantics(
                      button: true,
                      label: L10n.t('chat_call_audio'),
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: L10n.t('chat_call_audio'),
                        icon: Icon(Icons.call_rounded,
                            color: missed ? MC.rouge : MC.savane, size: 22),
                        onPressed: onCall,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Divider(height: 1, color: MC.ligne, indent: 70, endIndent: 14),
      ],
    );
  }

  static String _fmt(int sec) {
    if (sec < 60) return '${sec}s';
    final m = sec ~/ 60;
    final s = sec % 60;
    return s == 0 ? '${m}min' : '$m:${s.toString().padLeft(2, '0')}';
  }
}
