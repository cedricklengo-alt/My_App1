import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../design.dart';
import '../theme.dart';
import '../l10n.dart';
import 'contacts.dart';

/// 📱 Offrir du crédit GSM : recharge le téléphone d'un proche en RDC
/// (Vodacom, Orange, Airtel, Africell) depuis le solde MboteCall.
class AirtimeScreen extends StatefulWidget {
  const AirtimeScreen({super.key});
  @override
  State<AirtimeScreen> createState() => _AirtimeScreenState();
}

class _AirtimeScreenState extends State<AirtimeScreen> {
  final phone = TextEditingController(text: '+243');
  int amountCents = 200;
  bool sending = false;
  List history = [];

  static const amounts = [100, 200, 300, 500, 1000, 2000];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final h = await context.read<AppState>().api.airtimeHistory();
      if (mounted) setState(() => history = h);
    } catch (_) {/* non bloquant */}
  }

  Future<void> _send() async {
    final st = context.read<AppState>();
    final p = phone.text.replaceAll(RegExp(r'[\s.\-()]'), '');
    if (!RegExp(r'^\+?\d{8,15}$').hasMatch(p)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Numéro invalide — format +243…'),
          backgroundColor: MC.rouge));
      return;
    }
    setState(() => sending = true);
    try {
      final r = await st.api.sendAirtime(p, amountCents);
      await st.refresh();
      await _loadHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${L10n.t('airtime_sent')} $p (${r['operator']}) ✓'),
          backgroundColor: MC.savane));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: MC.rouge));
    }
    if (mounted) setState(() => sending = false);
  }

  String _date(dynamic iso) {
    try {
      final d = DateTime.parse(iso.toString()).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t('airtime_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        children: [
          Text(L10n.t('airtime_sub'),
              style: TextStyle(color: MC.sable, fontSize: Tx.label, height: 1.5)),
          const SizedBox(height: 16),

          // Solde disponible
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: MC.nuit2, borderRadius: BorderRadius.circular(Rd.md)),
            child: Row(children: [
              const Text('💰 ', style: TextStyle(fontSize: Tx.subtitle)),
              Text('${L10n.t('my_credit')} : ',
                  style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
              Text(fmtMoney(st.balanceCents),
                  style: TextStyle(
                      color: MC.soleil,
                      fontWeight: FontWeight.w800,
                      fontSize: Tx.body)),
            ]),
          ),
          const SizedBox(height: 16),

          Text(L10n.t('recipient'),
              style:
                  TextStyle(color: MC.kaki, fontSize: Tx.label, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            style: TextStyle(color: MC.ivoire, fontSize: Tx.subtitle),
            decoration: InputDecoration(
              labelText: L10n.t('label_phone'),
              hintText: '+243 ...',
              suffixIcon: IconButton(
                tooltip: L10n.t('pick_contact'),
                icon: Icon(Icons.contacts_rounded, color: MC.soleil),
                onPressed: () async {
                  final picked = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ContactsScreen(pick: true)));
                  if (picked != null) {
                    setState(() => phone.text = picked);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(L10n.t('amount'),
              style:
                  TextStyle(color: MC.kaki, fontSize: Tx.label, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: amounts.map((a) {
              final sel = a == amountCents;
              return GestureDetector(
                onTap: () => setState(() => amountCents = a),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  decoration: BoxDecoration(
                    gradient: sel ? MC.degrade : null,
                    color: sel ? null : MC.nuit3,
                    borderRadius: BorderRadius.circular(Rd.md),
                  ),
                  child: Text(fmtMoney(a),
                      style: TextStyle(
                          color: sel ? MC.onAccent : MC.ivoire,
                          fontWeight: FontWeight.w800,
                          fontSize: Tx.body)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          MboteButton(
            label: '📱 ${L10n.t('send')} ${fmtMoney(amountCents)}',
            loading: sending,
            onTap: _send,
          ),
          const SizedBox(height: 26),

          // Historique
          if (history.isNotEmpty) ...[
            Text(L10n.t('airtime_hist'),
                style: TextStyle(
                    color: MC.kaki, fontSize: Tx.label, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            ...history.map((h) {
              final ok = h['status'] == 'success';
              final pending = h['status'] == 'pending';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                    color: MC.nuit2, borderRadius: BorderRadius.circular(Rd.md)),
                child: Row(children: [
                  Text(ok ? '✅' : (pending ? '⏳' : '↩️'),
                      style: const TextStyle(fontSize: Tx.subtitle)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${h['phone']} · ${h['operator'] ?? ''}',
                            style: TextStyle(
                                color: MC.ivoire,
                                fontWeight: FontWeight.w600,
                                fontSize: Tx.label)),
                        Text(_date(h['created_at']),
                            style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
                      ],
                    ),
                  ),
                  Text(fmtMoney(h['amount_cents']),
                      style: TextStyle(
                          color: ok ? MC.savane : MC.kaki,
                          fontWeight: FontWeight.w800,
                          fontSize: Tx.label,
                          decoration: ok ? null : TextDecoration.lineThrough)),
                ]),
              );
            }),
          ],
        ],
      ),
    );
  }
}
