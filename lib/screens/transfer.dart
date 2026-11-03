import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../design.dart';
import '../theme.dart';
import '../l10n.dart';
import 'contacts.dart';

///Transfert de crédit MboteCall → MboteCall.
/// Le fils à Bruxelles envoie 10 $ de crédit d'appel à sa maman à Beni.
class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});
  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final phoneCtrl = TextEditingController(text: '+243');
  int amountCents = 200;
  bool loading = false;

  static const amounts = [100, 200, 500, 1000];

  Future<void> _send() async {
    final st = context.read<AppState>();
    setState(() => loading = true);
    try {
      final r = await st.api.transfer(phoneCtrl.text.trim(), amountCents);
      st.setBalance(r['balance_cents']);
      if (!mounted) return;
      final to = r['to'];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${L10n.t('sent_ok')} ${to['name']?.isNotEmpty == true ? to['name'] : to['phone']} (${fmtMoney(r['sent_cents'])})'),
        backgroundColor: MC.savane,
      ));
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: MC.rouge));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t('transfer_title'))),
      body: ListView(
        padding: const EdgeInsets.all(Sp.x4),
        children: [
          Text(L10n.t('transfer_sub'),
              style: TextStyle(color: MC.sable, fontSize: Tx.body)),
          const SizedBox(height: 20),
          Text(L10n.t('recipient').toUpperCase(),
              style: TextStyle(
                  color: MC.kaki,
                  fontSize: Tx.label,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
          const SizedBox(height: 8),
          TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            style: TextStyle(fontSize: Tx.title, color: MC.ivoire, letterSpacing: 1),
            decoration: InputDecoration(
              labelText: L10n.t('label_phone'),
              hintText: '+243 81 234 5678',
              suffixIcon: IconButton(
                tooltip: L10n.t('pick_contact'),
                icon: Icon(Icons.contacts_rounded, color: MC.soleil),
                onPressed: () async {
                  final picked = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ContactsScreen(pick: true)));
                  if (picked != null) {
                    setState(() => phoneCtrl.text = picked);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Raccourci : choisir un favori
          if (st.contacts.isNotEmpty)
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: st.contacts
                    .map<Widget>((c) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            label: Text(c['name'],
                                style:
                                    TextStyle(color: MC.sable, fontSize: Tx.label)),
                            backgroundColor: MC.nuit2,
                            side: BorderSide(color: MC.ligne),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(Rd.pill)),
                            onPressed: () =>
                                setState(() => phoneCtrl.text = c['phone']),
                          ),
                        ))
                    .toList(),
              ),
            ),
          const SizedBox(height: 22),
          Text(L10n.t('amount').toUpperCase(),
              style: TextStyle(
                  color: MC.kaki,
                  fontSize: Tx.label,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: amounts
                .map((a) => ChoiceChip(
                      label: Text(fmtMoney(a).replaceAll(',00', '')),
                      selected: amountCents == a,
                      onSelected: (_) => setState(() => amountCents = a),
                      selectedColor: MC.soleil,
                      backgroundColor: MC.nuit2,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                          color: amountCents == a ? MC.onAccent : MC.sable,
                          fontWeight: FontWeight.w700,
                          fontSize: Tx.body),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Rd.sm),
                          side: BorderSide(
                              color: amountCents == a ? MC.soleil : MC.ligne)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          Text('Solde disponible : ${fmtMoney(st.balanceCents)}',
              style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
          const SizedBox(height: 24),
          MboteButton(
            label:
                '${L10n.t('send')} ${fmtMoney(amountCents).replaceAll(',00', '')}',
            loading: loading,
            onTap: _send,
          ),
        ],
      ),
    );
  }
}
