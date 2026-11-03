import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../state.dart';
import '../design.dart';
import '../theme.dart';
import '../l10n.dart';
import 'call.dart';

/// ⭐ Favoris — accessibles depuis le Clavier (v1.3).
/// Ajout rapide, appel en 1 geste, suppression par appui long.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  static final colors = [MC.soleil, MC.savane, MC.terre, MC.braise];

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t('favorites')),
        actions: [
          TextButton(
            onPressed: () => _addContact(context),
            child: Text(L10n.t('add'),
                style: TextStyle(
                    color: MC.soleil,
                    fontSize: Tx.body,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: st.contacts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text(L10n.t('empty_fav'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
              children: st.contacts
                  .map<Widget>((c) => _FavoriteTile(contact: c))
                  .toList(),
            ),
    );
  }

  void _addContact(BuildContext context) {
    final name = TextEditingController();
    final phone = TextEditingController(text: '+243');
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.nuit2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            22, 22, 22, MediaQuery.of(ctx).viewInsets.bottom + 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L10n.t('favorites'),
                style: TextStyle(
                    fontSize: Tx.title,
                    fontWeight: FontWeight.w800,
                    color: MC.ivoire)),
            const SizedBox(height: 16),
            TextField(
                controller: name,
                style: TextStyle(color: MC.ivoire),
                decoration: InputDecoration(
                    labelText: L10n.t('label_name'),
                    hintText: 'Maman, Papa, Chef…')),
            const SizedBox(height: 10),
            TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: MC.ivoire),
                decoration: InputDecoration(
                    labelText: L10n.t('label_phone'),
                    hintText: '+243…')),
            const SizedBox(height: 18),
            MboteButton(
              label: L10n.t('add'),
              onTap: () async {
                final st = ctx.read<AppState>();
                try {
                  await st.api.addContact(name.text.trim(), phone.text.trim());
                  await st.refresh();
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text(friendlyError(e)),
                      backgroundColor: MC.rouge));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  final dynamic contact;
  const _FavoriteTile({required this.contact});

  @override
  Widget build(BuildContext context) {
    final name = contact['name'] as String;
    final color = FavoritesScreen
        .colors[name.hashCode.abs() % FavoritesScreen.colors.length];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: MC.nuit2,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rd.md)),
        child: ListTile(
        onLongPress: () => _confirmDelete(context),
        leading: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(Rd.md)),
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                  color: MC.onAccent,
                  fontWeight: FontWeight.w800,
                  fontSize: Tx.subtitle)),
        ),
        title: Text(name,
            style: TextStyle(
                color: MC.ivoire, fontWeight: FontWeight.w600, fontSize: Tx.bodyLg)),
        subtitle: Text(contact['phone'],
            style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
        trailing: IconButton(
          tooltip: L10n.t('chat_call_audio'),
          icon: Icon(Icons.call_rounded, color: MC.savane),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => CallScreen(
                    to: contact['phone'], displayName: contact['name'])),
          ),
        ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.nuit2,
        title: Text(contact['name'], style: TextStyle(color: MC.ivoire)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Annuler', style: TextStyle(color: MC.kaki))),
          TextButton(
            onPressed: () async {
              final st = context.read<AppState>();
              await st.api.deleteContact(contact['id']);
              await st.refresh();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Supprimer', style: TextStyle(color: MC.rouge)),
          ),
        ],
      ),
    );
  }
}
