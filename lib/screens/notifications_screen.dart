// lib/screens/notifications_screen.dart
// BOÎTE DE RÉCEPTION — mentions.
//
// Une mention produit un push (téléphone fermé) et une ligne ici (application
// ouverte). Sans cette page, une notification manquée l'était pour de bon.
//
// Un appui sur la ligne ouvre le profil de la personne qui a mentionné ; le
// bouton de la publication ouvre le contenu, quand l'appelant sait le faire.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../design.dart';
import '../models/social.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';

class NotificationsScreen extends StatefulWidget {
  final void Function(String postId)? onOuvrirPublication;
  final void Function(String userId)? onOuvrirProfil;

  const NotificationsScreen({
    super.key,
    this.onOuvrirPublication,
    this.onOuvrirProfil,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Api _api;
  bool _charge = true;
  String? _erreur;
  List<NotificationSociale> _items = const [];

  @override
  void initState() {
    super.initState();
    _api = context.read<AppState>().api;
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _charge = true;
      _erreur = null;
    });
    try {
      final r = await _api.notifications(limite: 40);
      if (!mounted) return;
      setState(() {
        _items = ((r['notifications'] as List?) ?? const [])
            .map((e) => NotificationSociale.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        _charge = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _charge = false;
        _erreur = friendlyError(e);
      });
    }
  }

  Future<void> _toutLire() async {
    try {
      await _api.marquerNotificationsLues();
      if (!mounted) return;
      setState(() {
        _items = _items
            .map((n) => NotificationSociale(
                  id: n.id,
                  type: n.type,
                  createdAt: n.createdAt,
                  postId: n.postId,
                  commentId: n.commentId,
                  sourceType: n.sourceType,
                  texte: n.texte,
                  lu: true,
                  expediteur: n.expediteur,
                ))
            .toList();
      });
    } catch (_) {/* le marquage n'est pas vital */}
  }

  @override
  Widget build(BuildContext context) {
    final nonLues = _items.where((n) => !n.lu).length;
    return Scaffold(
      backgroundColor: MC.nuit,
      appBar: AppBar(
        backgroundColor: MC.nuit,
        elevation: 0,
        title: Text('Notifications',
            style: TextStyle(
                color: MC.ivoire, fontSize: Tx.subtitle, fontWeight: FontWeight.w800)),
        actions: [
          if (nonLues > 0)
            TextButton(
              onPressed: _toutLire,
              child: Text('Tout lire',
                  style: TextStyle(color: MC.soleil, fontSize: Tx.label)),
            ),
        ],
      ),
      body: _charge
          ? const Center(
              child: SizedBox(
                  width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
          : _erreur != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_erreur!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_none_rounded,
                                size: 36, color: MC.kaki),
                            const SizedBox(height: 10),
                            Text('Aucune notification pour l’instant',
                                style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
                            const SizedBox(height: 6),
                            Text(
                              'Quand quelqu’un te mentionnera avec @, tu le verras ici.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: MC.kaki, fontSize: Tx.caption),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: MC.soleil,
                      onRefresh: _charger,
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 30),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: MC.ligne),
                        itemBuilder: (context, i) {
                          final n = _items[i];
                          return _Ligne(
                            notification: n,
                            onProfil: widget.onOuvrirProfil == null || n.expediteur == null
                                ? null
                                : () => widget.onOuvrirProfil!(n.expediteur!.id),
                            onPublication: widget.onOuvrirPublication == null || n.postId == null
                                ? null
                                : () => widget.onOuvrirPublication!(n.postId!),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _Ligne extends StatelessWidget {
  final NotificationSociale notification;
  final VoidCallback? onProfil;
  final VoidCallback? onPublication;

  const _Ligne({required this.notification, this.onProfil, this.onPublication});

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final avatar = n.expediteur?.avatar;
    return InkWell(
      onTap: onProfil ?? onPublication,
      child: Container(
        color: n.lu ? Colors.transparent : MC.soleil.withValues(alpha: .05),
        padding: const EdgeInsets.fromLTRB(Sp.x3, 12, Sp.x3, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MboteAvatar(
              name: n.expediteur?.name ?? 'Mbote',
              size: 36,
              image: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.resume,
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: Tx.label,
                          fontWeight: n.lu ? FontWeight.w600 : FontWeight.w800)),
                  if (n.texte.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text('« ${n.texte} »',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: MC.kaki, fontSize: Tx.caption, height: 1.35)),
                  ],
                  const SizedBox(height: 5),
                  Text(_quand(n.createdAt),
                      style: TextStyle(color: MC.kaki, fontSize: Tx.caption)),
                ],
              ),
            ),
            if (onPublication != null)
              IconButton(
                onPressed: onPublication,
                tooltip: 'Ouvrir la publication',
                icon: Icon(Icons.chevron_right_rounded, color: MC.kaki, size: 20),
              ),
          ],
        ),
      ),
    );
  }

  /// « à l'instant », « il y a 5 min », « hier », puis la date.
  String _quand(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'à l’instant';
    if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
    if (d.inHours < 24) return 'il y a ${d.inHours} h';
    if (d.inDays == 1) return 'hier';
    if (d.inDays < 7) return 'il y a ${d.inDays} jours';
    return '${t.day}/${t.month}/${t.year}';
  }
}
