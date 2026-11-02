import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../tabs.dart';
import '../theme.dart';
import '../l10n.dart';
import 'call_sheet.dart';
import 'keypad.dart';

/// 📞 Onglet « Appels » : historique par catégorie.
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
  String filter = 'all'; // all | in | out | missed

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
    super.dispose();
  }

  void _onTabRefresh() {
    if (mounted) _load();
  }

  /// Rechargement (aussi appelé quand on retape l'onglet actif).
  Future<void> refresh() => _load();

  Future<void> _load() async {
    try {
      final r = await context.read<AppState>().api.history();
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
        error = friendlyError(e);
      });
    }
  }

  // ── Lecture d'une ligne d'historique ────────────────────

  static bool _isIn(dynamic c) => '${c['direction'] ?? ''}' == 'incoming';

  static int _answeredAt(dynamic c) =>
      int.tryParse('${c['answered_at'] ?? 0}') ?? 0;

  /// Décroché ? (`answered_at` renseigné ou durée facturée non nulle)
  static bool _answered(dynamic c) =>
      _answeredAt(c) > 0 || (int.tryParse('${c['billed_sec'] ?? 0}') ?? 0) > 0;

  /// Manqué = jamais décroché.
  static bool _isMissed(dynamic c) => !_answered(c);

  static bool _isVideo(dynamic c) =>
      (int.tryParse('${c['with_video'] ?? 0}') ?? 0) == 1;

  /// Un numéro joignable ressemble à un numéro (les appels de groupe, non).
  static bool _dialable(dynamic c) =>
      RegExp(r'[0-9]{4,}').hasMatch('${c['callee'] ?? ''}');

  List get _visible => switch (filter) {
        'in' => calls.where((c) => _isIn(c) && !_isMissed(c)).toList(),
        'out' => calls.where((c) => !_isIn(c) && !_isMissed(c)).toList(),
        'missed' => calls.where(_isMissed).toList(),
        _ => calls,
      };

  // ── Actions ────────────────────────────────────────────

  void _call(dynamic c) {
    if (!_dialable(c)) return;
    showCallModeSheet(
      context,
      '${c['callee']}',
      name: '${c['callee']}',
    ).then((_) => _load());
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
      child: RefreshIndicator(
        color: MC.soleil,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(L10n.t('nav_calls'),
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: MC.ivoire)),
                ),
                IconButton(
                  tooltip: L10n.t('nav_keypad'),
                  icon: Icon(Icons.dialpad_rounded, color: MC.soleil),
                  onPressed: _openKeypad,
                ),
              ],
            ),
            const SizedBox(height: 6),
            // ---- Catégories ----
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _chip('all', L10n.t('history_all'), calls.length),
                _chip('in', L10n.t('history_in'), null),
                _chip('out', L10n.t('history_out'), null),
                _chip('missed', L10n.t('history_missed'),
                    calls.where(_isMissed).length),
              ],
            ),
            const SizedBox(height: 14),
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
    );
  }

  /// Regroupe les appels par jour, avec un intertitre lisible.
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
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
        ));
        lastDay = day;
      }
      out.add(_CallTile(
        call: c,
        missed: _isMissed(c),
        incoming: _isIn(c),
        video: _isVideo(c),
        onCall: _dialable(c) ? () => _call(c) : null,
      ));
    }
    return out;
  }

  Widget _chip(String value, String label, int? count) {
    final sel = filter == value;
    return ChoiceChip(
      label: Text(count != null && count > 0 ? '$label · $count' : label),
      selected: sel,
      onSelected: (_) {
        HapticFeedback.selectionClick();
        setState(() => filter = value);
      },
      selectedColor: MC.soleil,
      backgroundColor: MC.nuit3,
      side: BorderSide.none,
      labelStyle: TextStyle(
          color: sel ? MC.onAccent : MC.sable,
          fontWeight: FontWeight.w700,
          fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  List<Widget> _skeletons() => List<Widget>.generate(
        4,
        (i) => Container(
          height: 68,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
              color: MC.nuit2, borderRadius: BorderRadius.circular(16)),
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
                            borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 8),
                    Container(
                        width: 78,
                        height: 9,
                        decoration: BoxDecoration(
                            color: MC.nuit3,
                            borderRadius: BorderRadius.circular(6))),
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
                style: TextStyle(color: MC.kaki, fontSize: 13.5)),
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
              style: TextStyle(color: MC.kaki, fontSize: 14)),
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

class _CallTile extends StatelessWidget {
  final dynamic call;
  final bool missed;
  final bool incoming;
  final bool video;
  final VoidCallback? onCall;

  const _CallTile({
    required this.call,
    required this.missed,
    required this.incoming,
    required this.video,
    required this.onCall,
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
    if (dest.contains('MBOTE')) dest = 'MboteCall 💚';

    final dur = int.tryParse('${call['billed_sec'] ?? 0}') ?? 0;
    final name = '${call['callee'] ?? ''}';

    // Material (et non Container) : l'effet d'appui du ListTile reste visible.
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: MC.nuit2,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
        onTap: onCall,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (missed ? MC.rouge : MC.savane).withValues(alpha: 0.14),
          ),
          child: Icon(
            missed
                ? Icons.phone_missed_rounded
                : incoming
                    ? Icons.call_received_rounded
                    : Icons.call_made_rounded,
            color: missed ? MC.rouge : MC.savane,
            size: 19,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: MC.ivoire,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600)),
            ),
            if (video) ...[
              const SizedBox(width: 6),
              Icon(Icons.videocam_rounded, size: 15, color: MC.soleil),
            ],
          ],
        ),
        subtitle: Text(
          missed
              ? '${L10n.t('history_unanswered')} · $dest · $when'
              : '$dest · $when',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: missed ? MC.rouge.withValues(alpha: 0.85) : MC.kaki,
              fontSize: 11.5),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dur > 0)
              Text(_fmt(dur),
                  style: TextStyle(
                      color: MC.sable,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            if (onCall != null)
              IconButton(
                tooltip: L10n.t('chat_call_audio'),
                icon: Icon(Icons.call_rounded,
                    color: missed ? MC.rouge : MC.savane, size: 20),
                onPressed: onCall,
              ),
          ],
        ),
        ),
      ),
    );
  }

  static String _fmt(int sec) {
    if (sec < 60) return '${sec}s';
    final m = sec ~/ 60;
    final s = sec % 60;
    return s == 0 ? '${m}min' : '$m:${s.toString().padLeft(2, '0')}';
  }
}
