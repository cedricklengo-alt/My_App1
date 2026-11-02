import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../theme.dart';
import '../l10n.dart';
import 'call.dart';

/// 📒 Contacts du téléphone, avec badge 💚 pour ceux qui ont déjà MboteCall.
/// - mode normal : toucher un contact → l'appeler (gratuit si MboteCall).
/// - mode [pick] : toucher un contact → renvoie son numéro à l'écran appelant
///   (utilisé par Transfert 💸 et Crédit GSM 📱).
class ContactsScreen extends StatefulWidget {
  final bool pick;
  const ContactsScreen({super.key, this.pick = false});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _Entry {
  final String name;
  final String rawPhone; // tel qu'écrit dans le répertoire
  final String e164; // normalisé pour appeler / transférer
  String? mbotePhone; // numéro du compte MboteCall si trouvé
  _Entry(this.name, this.rawPhone, this.e164);
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<_Entry> all = [];
  String query = '';
  bool loading = true;
  bool denied = false;

  static final colors = [MC.soleil, MC.savane, MC.terre, MC.braise];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Normalisation vers le format international :
  /// "081 234 56 78" → "+243812345678" · "0033 6…" → "+336…"
  static String _toE164(String raw) {
    var d = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (d.startsWith('+')) return d;
    if (d.startsWith('00')) return '+${d.substring(2)}';
    if (d.startsWith('0') && d.length == 10) return '+243${d.substring(1)}';
    return '+$d';
  }

  Future<void> _load() async {
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      if (mounted) {
        setState(() {
          denied = true;
          loading = false;
        });
      }
      return;
    }
    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final entries = <_Entry>[];
    final seen = <String>{};
    for (final c in contacts) {
      final name = c.displayName.trim();
      if (name.isEmpty) continue;
      for (final p in c.phones.take(2)) {
        final raw = p.number.trim();
        if (raw.replaceAll(RegExp(r'\D'), '').length < 8) continue;
        final e164 = _toE164(raw);
        if (!seen.add(e164)) continue; // évite les doublons
        entries.add(_Entry(name, raw, e164));
      }
    }
    entries
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (mounted) {
      setState(() {
        all = entries;
        loading = false;
      });
    }
    _checkMbote(entries);
  }

  /// Interroge le serveur par lots : qui a déjà un compte MboteCall ? 💚
  Future<void> _checkMbote(List<_Entry> entries) async {
    final api = context.read<AppState>().api;
    try {
      for (var i = 0; i < entries.length; i += 300) {
        final batch = entries.skip(i).take(300).toList();
        final found = await api.checkMbote(batch.map((e) => e.e164).toList());
        if (!mounted) return;
        setState(() {
          for (final e in batch) {
            if (found[e.e164] != null) e.mbotePhone = found[e.e164];
          }
          // 💚 les contacts MboteCall remontent en tête de liste
          all.sort((a, b) {
            final am = a.mbotePhone != null ? 0 : 1;
            final bm = b.mbotePhone != null ? 0 : 1;
            return am != bm
                ? am - bm
                : a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
        });
      }
    } catch (_) {/* hors-ligne : la liste reste utilisable sans badge */}
  }

  void _onTap(_Entry e) {
    final phone = e.mbotePhone ?? e.e164;
    if (widget.pick) {
      Navigator.pop(context, phone);
    } else {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => CallScreen(to: phone, displayName: e.name)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase();
    final visible = q.isEmpty
        ? all
        : all
            .where((e) =>
                e.name.toLowerCase().contains(q) ||
                e.e164.contains(q) ||
                e.rawPhone.contains(q))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.pick ? L10n.t('pick_contact') : L10n.t('contacts_title')),
      ),
      body: loading
          ? Center(child: CircularProgressIndicator(color: MC.soleil))
          : denied
              ? _PermissionAsk(onRetry: () {
                  setState(() {
                    denied = false;
                    loading = true;
                  });
                  _load();
                })
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                      child: TextField(
                        onChanged: (v) => setState(() => query = v),
                        style: TextStyle(color: MC.ivoire),
                        decoration: InputDecoration(
                          hintText: L10n.t('contacts_search'),
                          prefixIcon:
                              Icon(Icons.search_rounded, color: MC.kaki),
                        ),
                      ),
                    ),
                    Expanded(
                      child: visible.isEmpty
                          ? Center(
                              child: Text(L10n.t('contacts_empty'),
                                  style: TextStyle(
                                      color: MC.kaki, fontSize: 13.5)))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              itemCount: visible.length,
                              itemBuilder: (_, i) {
                                final e = visible[i];
                                final isMbote = e.mbotePhone != null;
                                final color = colors[
                                    e.name.hashCode.abs() % colors.length];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: MC.nuit2,
                                    borderRadius: BorderRadius.circular(16),
                                    border: isMbote
                                        ? Border.all(
                                            color: MC.savane
                                                .withValues(alpha: .45))
                                        : null,
                                  ),
                                  child: ListTile(
                                    onTap: () => _onTap(e),
                                    leading: Container(
                                      width: 42,
                                      height: 42,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                          color: color,
                                          borderRadius:
                                              BorderRadius.circular(14)),
                                      child: Text(e.name[0].toUpperCase(),
                                          style: TextStyle(
                                              color: MC.onAccent,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16)),
                                    ),
                                    title: Text(e.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: MC.ivoire,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15)),
                                    subtitle: Text(e.rawPhone,
                                        style: TextStyle(
                                            color: MC.kaki, fontSize: 12)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Icône officielle MboteCall = ce contact a l'app
                                        if (isMbote)
                                          ClipOval(
                                            child: Image.asset(
                                              'assets/icon/icon_small.png',
                                              width: 22,
                                              height: 22,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        if (!widget.pick) ...[
                                          const SizedBox(width: 10),
                                          Icon(Icons.call_rounded,
                                              color:
                                                  isMbote ? MC.savane : MC.kaki,
                                              size: 20),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

/// Permission refusée : explication claire + bouton pour réessayer.
class _PermissionAsk extends StatelessWidget {
  final VoidCallback onRetry;
  const _PermissionAsk({required this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(34),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📒', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(L10n.t('contacts_perm'),
                textAlign: TextAlign.center,
                style: TextStyle(color: MC.sable, fontSize: 14.5, height: 1.5)),
            const SizedBox(height: 22),
            MboteButton(label: L10n.t('contacts_allow'), onTap: onRetry),
          ],
        ),
      );
}
