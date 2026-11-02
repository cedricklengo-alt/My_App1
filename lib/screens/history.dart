import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../theme.dart';
import '../l10n.dart';
import 'call.dart';

/// Historique v1.3 : appels organisés par catégorie
/// (Tous · Sortants · Manqués) — sans totaux de minutes ni de dépenses.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with AutomaticKeepAliveClientMixin {
  List calls = [];
  bool loading = true;
  String filter = 'all'; // all | in | out | missed

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<AppState>().api.history();
      if (!mounted) return;
      setState(() {
        calls = r['calls'];
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  bool _isMissed(dynamic c) => (c['billed_sec'] ?? 0) == 0;
  bool _isIn(dynamic c) => (c['direction'] ?? 'out') == 'in';

  List get _visible => switch (filter) {
        'in' => calls.where((c) => _isIn(c) && !_isMissed(c)).toList(),
        'out' => calls.where((c) => !_isIn(c) && !_isMissed(c)).toList(),
        'missed' => calls.where(_isMissed).toList(),
        _ => calls,
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final visible = _visible;
    return SafeArea(
      child: RefreshIndicator(
        color: MC.soleil,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          children: [
            Text(L10n.t('nav_history'),
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: MC.ivoire)),
            const SizedBox(height: 14),
            // ---- Catégories ----
            Wrap(
              spacing: 8,
              children: [
                _chip('all', L10n.t('history_all')),
                _chip('in', L10n.t('history_in')),
                _chip('out', L10n.t('history_out')),
                _chip('missed', L10n.t('history_missed')),
              ],
            ),
            const SizedBox(height: 14),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Text(L10n.t('history_empty'),
                      style: TextStyle(color: MC.kaki)),
                ),
              ),
            ...visible.map((c) => _CallTile(
                call: c,
                missed: _isMissed(c),
                incoming: _isIn(c),
                onRedial: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => CallScreen(to: c['callee'])));
                })),
          ],
        ),
      ),
    );
  }

  Widget _chip(String value, String label) {
    final sel = filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => filter = value),
      selectedColor: MC.soleil,
      backgroundColor: MC.nuit3,
      labelStyle: TextStyle(
          color: sel ? MC.onAccent : MC.sable,
          fontWeight: FontWeight.w700,
          fontSize: 13),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), side: BorderSide.none),
    );
  }
}

class _CallTile extends StatelessWidget {
  final dynamic call;
  final bool missed;
  final bool incoming;
  final VoidCallback onRedial;
  const _CallTile(
      {required this.call,
      required this.missed,
      required this.incoming,
      required this.onRedial});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(call['started_at']);
    final when =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    // Renommage : les anciens appels « MboteCall → MboteCall » s'affichent « MboteCall »
    var dest = (call['destination'] ?? '').toString();
    if (dest.contains('MBOTE')) dest = 'MboteCall 💚';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: MC.nuit2, borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(
          missed
              ? Icons.phone_missed_rounded
              : incoming
                  ? Icons.call_received_rounded
                  : Icons.call_made_rounded,
          color: missed ? MC.rouge : MC.savane,
          size: 20,
        ),
        title: Text(call['callee'],
            style: TextStyle(
                color: MC.ivoire, fontSize: 14.5, fontWeight: FontWeight.w600)),
        subtitle: Text('$dest · $when',
            style: TextStyle(color: MC.kaki, fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!missed)
              Text(fmtDur(call['billed_sec'] ?? 0),
                  style: TextStyle(
                      color: MC.sable,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            IconButton(
              icon: Icon(Icons.call_rounded, color: MC.savane, size: 20),
              onPressed: onRedial,
            ),
          ],
        ),
      ),
    );
  }
}
