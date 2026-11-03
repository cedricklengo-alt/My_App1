import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api.dart';
import '../state.dart';
import '../design.dart';
import '../theme.dart';
import '../l10n.dart';
import '../pin.dart';
import 'settings.dart';

/// Profil : infos compte, grille des tarifs, sécurité PIN, déconnexion.
class ProfileScreen extends StatefulWidget {
  /// Ouvre directement la feuille « Paramètres » (langue, thème, police).
  final bool startWithSettings;

  const ProfileScreen({super.key, this.startWithSettings = false});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool pinSet = false;

  @override
  void initState() {
    super.initState();
    Pin.isSet().then((v) {
      if (mounted) setState(() => pinSet = v);
    });
    if (widget.startWithSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openSettings(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        children: [
          // Titre + ⋮ Paramètres (langue, thème, police, à propos)
          Row(
            children: [
              Expanded(
                child: Text(L10n.t('profile'),
                    style: TextStyle(
                        fontSize: Tx.headline,
                        fontWeight: FontWeight.w800,
                        color: MC.ivoire)),
              ),
              IconButton(
                tooltip: L10n.t('settings'),
                icon: Icon(Icons.more_vert_rounded, color: MC.ivoire),
                onPressed: () => _openSettings(context),
              ),
            ],
          ),
          const SizedBox(height: 10),
          //Avatar : photo si définie, sinon initiale · toucher = changer
          Center(
            child: GestureDetector(
              onTap: () => _changePhoto(context),
              child: Stack(
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    alignment: Alignment.center,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                        gradient: MC.degrade, shape: BoxShape.circle),
                    child: st.avatar != null && st.avatar!.isNotEmpty
                        ? Image.memory(
                            base64Decode(st.avatar!.split(',').last),
                            width: 86,
                            height: 86,
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                            gaplessPlayback: true,
                          )
                        : Text(
                            st.name.isNotEmpty ? st.name[0].toUpperCase() : '?',
                            style: TextStyle(
                                fontSize: Tx.display,
                                fontWeight: FontWeight.w800,
                                color: MC.onAccent),
                          ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: MC.nuit3,
                        shape: BoxShape.circle,
                        border: Border.all(color: MC.soleil, width: 1.4),
                      ),
                      child: Icon(Icons.photo_camera_rounded,
                          color: MC.soleil, size: 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(st.name.isEmpty ? 'Sans nom' : st.name,
                style: TextStyle(
                    fontSize: Tx.title,
                    fontWeight: FontWeight.w800,
                    color: MC.ivoire)),
          ),
          Center(
            child: Text(st.phone, style: TextStyle(color: MC.kaki)),
          ),
          const SizedBox(height: 24),
          _tile(Icons.edit_rounded, L10n.t('edit_name'),
              () => _editName(context)),
          _tile(Icons.public_rounded, L10n.t('rates_by_dest'),
              () => _showRates(context)),
          //Inviter tes proches — carte dorée bien visible
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Rd.md)),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: MC.degrade,
                  borderRadius: BorderRadius.circular(Rd.md),
                ),
                child: ListTile(
                  leading:
                      Icon(Icons.favorite_rounded, color: MC.onAccent),
                  title: Text(L10n.t('invite'),
                      style: TextStyle(
                          color: MC.onAccent,
                          fontSize: Tx.bodyLg,
                          fontWeight: FontWeight.w800)),
                  subtitle: Text(L10n.t('invite_sub'),
                      style: TextStyle(
                          color: MC.onAccent.withValues(alpha: .85),
                          fontSize: Tx.label)),
                  trailing:
                      Icon(Icons.chevron_right_rounded, color: MC.onAccent),
                  onTap: () => _showReferral(context),
            ),
              ),
            ),
          ),
          _tile(
              Icons.lock_rounded,
              pinSet ? '${L10n.t('pin_title')} · activé' : L10n.t('pin_set'),
              () => _managePin(context)),
          const SizedBox(height: 14),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: MC.rouge),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Rd.md)),
            ),
            onPressed: () => st.logout(),
            child: Text(L10n.t('logout'),
                style: TextStyle(color: MC.rouge, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// ⋮ Réglages : ouvre le hub unique (apparence, langue, notifications,
  /// sécurité). Il n'y a plus deux endroits qui changent les mêmes réglages.
  void _openSettings(BuildContext context) {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  // Audit a11y/UI : un ListTile posé sur un DecoratedBox opaque masque son
  // fond d'encre (ripple) — Flutter lève une assertion et l'utilisateur ne
  // voit aucun retour au toucher. On peint donc la surface avec un `Material`,
  // qui sert d'ancêtre d'encre ET porte le fond.
  Widget _tile(IconData icon, String label, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: MC.nuit2,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Rd.md)),
          child: ListTile(
          leading:
              Icon(icon, color: onTap == null ? MC.kaki : MC.soleil, size: 22),
          title: Text(label,
              style: TextStyle(
                  color: onTap == null ? MC.kaki : MC.ivoire,
                  fontSize: Tx.body,
                  fontWeight: FontWeight.w600)),
          trailing: onTap == null
              ? null
              : Icon(Icons.chevron_right_rounded, color: MC.kaki),
          onTap: onTap,
        ),
        ),
      );

  ///Choisir une photo dans la galerie, compressée puis envoyée au serveur :
  /// elle s'affichera chez tes proches quand ils t'appellent.
  Future<void> _changePhoto(BuildContext context) async {
    final st = context.read<AppState>();
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 300 * 1024) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('Photo trop lourde, choisis-en une autre'),
              backgroundColor: MC.rouge));
        }
        return;
      }
      final dataUri = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      await st.api.updateAvatar(dataUri);
      await st.refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Photo de profil mise à jour'),
            backgroundColor: MC.savane));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e)), backgroundColor: MC.rouge));
      }
    }
  }

  void _editName(BuildContext context) {
    final st = context.read<AppState>();
    final ctrl = TextEditingController(text: st.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.nuit2,
        title: Text('Mon nom', style: TextStyle(color: MC.ivoire)),
        content:
            TextField(controller: ctrl, style: TextStyle(color: MC.ivoire)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Annuler', style: TextStyle(color: MC.kaki))),
          TextButton(
            onPressed: () async {
              await st.api.updateName(ctrl.text.trim());
              await st.refresh();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Enregistrer', style: TextStyle(color: MC.soleil)),
          ),
        ],
      ),
    );
  }

  ///Feuille parrainage : code + stats + copie en 1 geste
  void _showReferral(BuildContext context) async {
    final st = context.read<AppState>();
    final r = await st.api.referral();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.nuit2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icône professionnelle du programme de parrainage
            Container(
              width: 52,
              height: 52,
              decoration:
                  BoxDecoration(gradient: MC.degrade, shape: BoxShape.circle),
              child: Icon(Icons.card_giftcard_rounded,
                  color: MC.onAccent, size: 26),
            ),
            const SizedBox(height: 12),
            Text(L10n.t('referral_title'),
                style: TextStyle(
                    fontSize: Tx.title,
                    fontWeight: FontWeight.w800,
                    color: MC.ivoire)),
            const SizedBox(height: 8),
            Text(L10n.t('referral_body'),
                textAlign: TextAlign.center,
                style: TextStyle(color: MC.sable, fontSize: Tx.label, height: 1.5)),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              decoration: BoxDecoration(
                gradient: MC.degrade,
                borderRadius: BorderRadius.circular(Rd.md),
              ),
              child: Text(r['code'] ?? '…',
                  style: TextStyle(
                      fontSize: Tx.headline,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: MC.onAccent)),
            ),
            const SizedBox(height: 10),
            Text(
                '${r['filleuls']} ${L10n.t('referral_stats')} ${fmtMoney(r['earned_cents'] ?? 0)}',
                style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
            const SizedBox(height: 16),
            //Partage riche : message complet prêt pour WhatsApp
            MboteButton(
              label: L10n.t('share_invite'),
              onTap: () async {
                final msg = L10n.t('invite_message')
                    .replaceAll('%CODE%', r['code'] ?? '');
                await Share.share(msg, subject: 'MboteCall');
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: MC.soleil),
                padding: const EdgeInsets.symmetric(vertical: 13),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Rd.md)),
              ),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: r['code'] ?? ''));
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(L10n.t('copied')),
                      backgroundColor: MC.savane));
                }
              },
              child: Text(L10n.t('copy'),
                  style:
                      TextStyle(color: MC.soleil, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  ///Gestion du code PIN : activer / changer / désactiver
  void _managePin(BuildContext context) {
    if (!pinSet) {
      // Activation : choisir + confirmer un code
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PinScreen(
            setup: true,
            onSuccess: () {
              Navigator.pop(context);
              setState(() => pinSet = true);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(L10n.t('pin_saved')),
                  backgroundColor: MC.savane));
            },
          ),
        ),
      );
      return;
    }
    // Déjà activé : changer ou désactiver (après vérification du code actuel)
    final st0 = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.nuit2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L10n.t('pin_title'),
                style: TextStyle(
                    fontSize: Tx.title,
                    fontWeight: FontWeight.w800,
                    color: MC.ivoire)),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.sync_rounded, color: MC.soleil),
              title: Text(L10n.t('pin_change'),
                  style: TextStyle(
                      color: MC.ivoire,
                      fontSize: Tx.bodyLg,
                      fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                _verifyThen(() {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PinScreen(
                        setup: true,
                        onSuccess: () {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(L10n.t('pin_saved')),
                              backgroundColor: MC.savane));
                        },
                      ),
                    ),
                  );
                });
              },
            ),
            ListTile(
              leading: Icon(Icons.lock_open_rounded, color: MC.rouge),
              title: Text(L10n.t('pin_off'),
                  style: TextStyle(
                      color: MC.rouge,
                      fontSize: Tx.bodyLg,
                      fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                final messenger = ScaffoldMessenger.of(context);
                _verifyThen(() async {
                  await Pin.remove();
                  if (!mounted) return;
                  setState(() => pinSet = false);
                  messenger.showSnackBar(SnackBar(
                      content: Text(L10n.t('pin_removed')),
                      backgroundColor: MC.nuit3));
                });
              },
            ),
            //PIN oublié alors que l'app est ouverte ?
            // → réinitialisation par SMS (sans connaître l'ancien code)
            ListTile(
              leading: Icon(Icons.sms_rounded, color: MC.soleil),
              title: Text(L10n.t('pin_forgot'),
                  style: TextStyle(
                      color: MC.ivoire,
                      fontSize: Tx.bodyLg,
                      fontWeight: FontWeight.w600)),
              subtitle: Text('SMS · ${st0.phone}',
                  style: TextStyle(color: MC.kaki, fontSize: Tx.label)),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await resetPinBySms(context);
                if (ok && mounted) setState(() => pinSet = false);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Demande le code actuel avant une action sensible
  void _verifyThen(VoidCallback onVerified) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PinScreen(
          onSuccess: () {
            Navigator.pop(context);
            onVerified();
          },
        ),
      ),
    );
  }

  void _showRates(BuildContext context) async {
    final st = context.read<AppState>();
    final rates = await st.api.allRates();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.nuit2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Text('Tarifs par destination',
              style: TextStyle(
                  fontSize: Tx.title, fontWeight: FontWeight.w800, color: MC.ivoire)),
          const SizedBox(height: 12),
          ...rates.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Icon(Icons.public_rounded, size: 16, color: MC.kaki),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(r['destination'],
                          style: TextStyle(color: MC.ivoire, fontSize: Tx.body)),
                    ),
                    Text(
                        '${(r['price_per_min_cents'] / 100).toStringAsFixed(2)} \$/min',
                        style: TextStyle(
                            color: MC.soleil,
                            fontWeight: FontWeight.w700,
                            fontSize: Tx.label)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
