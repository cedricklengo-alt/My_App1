import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../l10n.dart';
import '../pin.dart';
import '../prefs.dart';

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
                        fontSize: 24,
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
          // 📷 Avatar : photo si définie, sinon initiale · toucher = changer
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
                            gaplessPlayback: true,
                          )
                        : Text(
                            st.name.isNotEmpty ? st.name[0].toUpperCase() : '?',
                            style: TextStyle(
                                fontSize: 34,
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
                    fontSize: 19,
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
          // 💚 Inviter tes proches — carte dorée bien visible
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              gradient: MC.degrade,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: MC.soleil.withValues(alpha: .25),
                    blurRadius: 14,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: ListTile(
              leading: Icon(Icons.favorite_rounded, color: MC.onAccent),
              title: Text(L10n.t('invite'),
                  style: TextStyle(
                      color: MC.onAccent,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
              subtitle: Text(L10n.t('invite_sub'),
                  style: TextStyle(
                      color: MC.onAccent.withValues(alpha: .85), fontSize: 12)),
              trailing: Icon(Icons.chevron_right_rounded, color: MC.onAccent),
              onTap: () => _showReferral(context),
            ),
          ),
          _tile(
              Icons.lock_rounded,
              pinSet ? '${L10n.t('pin_title')} · activé ✅' : L10n.t('pin_set'),
              () => _managePin(context)),
          _tile(Icons.support_agent_rounded, 'Support (bientôt)', null),
          const SizedBox(height: 14),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: MC.rouge),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () => st.logout(),
            child: Text(L10n.t('logout'),
                style: TextStyle(color: MC.rouge, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// ⋮ Paramètres : langue, thème, police, à propos
  void _openSettings(BuildContext context) {
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
            Text(L10n.t('settings'),
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: MC.ivoire)),
            const SizedBox(height: 10),
            ListTile(
              leading: Icon(Icons.translate_rounded, color: MC.soleil),
              title: Text(L10n.t('language'),
                  style: TextStyle(color: MC.ivoire, fontSize: 15)),
              subtitle: Text(L10n.langs[L10n.lang] ?? '',
                  style: TextStyle(color: MC.kaki, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _pickLanguage(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.palette_rounded, color: MC.soleil),
              title: Text(L10n.t('theme_label'),
                  style: TextStyle(color: MC.ivoire, fontSize: 15)),
              subtitle: Text(ThemeCtl.themes[ThemeCtl.theme] ?? '',
                  style: TextStyle(color: MC.kaki, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _pickTheme(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.text_fields_rounded, color: MC.soleil),
              title: Text(L10n.t('font_label'),
                  style: TextStyle(color: MC.ivoire, fontSize: 15)),
              subtitle: Text(ThemeCtl.fonts[ThemeCtl.font] ?? '',
                  style: TextStyle(color: MC.kaki, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _pickFont(context);
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.notifications_active_rounded, color: MC.soleil),
              title: Text(L10n.t('ring_settings'),
                  style: TextStyle(color: MC.ivoire, fontSize: 15)),
              subtitle: Text(_ringName(CallPrefs.ringtone),
                  style: TextStyle(color: MC.kaki, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _pickRingtone(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.info_outline_rounded, color: MC.soleil),
              title: Text(L10n.t('about'),
                  style: TextStyle(color: MC.ivoire, fontSize: 15)),
              onTap: () {
                Navigator.pop(ctx);
                _showAbout(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _ringName(String key) => switch (key) {
        'douce' => L10n.t('ring_soft').split(' — ').first,
        'forte' => L10n.t('ring_loud').split(' — ').first,
        'silencieux' => L10n.t('ring_silent'),
        _ => L10n.t('ring_classic').split(' — ').first,
      };

  /// 🔔 Sonnerie & vibration — toucher une option la fait écouter 2 s
  void _pickRingtone(BuildContext context) {
    final player = FlutterRingtonePlayer();
    Timer? preview;
    void playPreview(String key) {
      preview?.cancel();
      player.stop();
      switch (key) {
        case 'douce':
          player.play(
              android: AndroidSounds.notification,
              ios: IosSounds.triTone,
              looping: true,
              volume: 0.9);
        case 'forte':
          player.playAlarm(looping: true, volume: 1.0);
        case 'silencieux':
          return;
        default:
          player.playRingtone(looping: true, volume: 1.0);
      }
      preview = Timer(const Duration(milliseconds: 2500), () => player.stop());
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: MC.nuit2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.t('ring_settings'),
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: MC.ivoire)),
              const SizedBox(height: 4),
              Text(L10n.t('ring_hint'),
                  style: TextStyle(color: MC.kaki, fontSize: 12.5)),
              const SizedBox(height: 10),
              ...[
                ('classique', Icons.ring_volume_rounded, 'ring_classic'),
                ('douce', Icons.music_note_rounded, 'ring_soft'),
                ('forte', Icons.campaign_rounded, 'ring_loud'),
                ('silencieux', Icons.notifications_off_rounded, 'ring_silent'),
              ].map((o) => ListTile(
                    leading: Icon(o.$2,
                        color:
                            CallPrefs.ringtone == o.$1 ? MC.soleil : MC.kaki),
                    title: Text(L10n.t(o.$3),
                        style: TextStyle(
                            color: MC.ivoire,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600)),
                    trailing: CallPrefs.ringtone == o.$1
                        ? Icon(Icons.check_circle_rounded, color: MC.soleil)
                        : null,
                    onTap: () async {
                      await CallPrefs.setRingtone(o.$1);
                      setSheet(() {});
                      playPreview(o.$1); // 🎧 écoute immédiate
                    },
                  )),
              SwitchListTile(
                value: CallPrefs.vibration,
                activeThumbColor: MC.soleil,
                secondary: Icon(Icons.vibration_rounded,
                    color: CallPrefs.vibration ? MC.soleil : MC.kaki),
                title: Text(L10n.t('vibration'),
                    style: TextStyle(
                        color: MC.ivoire,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600)),
                onChanged: (v) async {
                  await CallPrefs.setVibration(v);
                  setSheet(() {});
                  if (v) HapticFeedback.vibrate(); // 📳 aperçu
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      preview?.cancel();
      player.stop(); // jamais de son qui continue après fermeture
    });
  }

  /// 🎨 Choix du thème (Soleil de Kin, Émeraude, Océan, Bleu Nuit)
  void _pickTheme(BuildContext context) {
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
            Text(L10n.t('theme_label'),
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: MC.ivoire)),
            const SizedBox(height: 12),
            ...ThemeCtl.themes.entries.map((e) {
              final pal = kPalettes[e.key]!;
              return ListTile(
                leading: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [pal.accent, pal.accent2]),
                    border: Border.all(color: pal.nuit3, width: 2),
                  ),
                ),
                title: Text(e.value,
                    style: TextStyle(
                        color: MC.ivoire,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                trailing: ThemeCtl.theme == e.key
                    ? Icon(Icons.check_circle_rounded, color: MC.soleil)
                    : null,
                onTap: () async {
                  await ThemeCtl.setTheme(e.key);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 🔤 Choix de la police
  void _pickFont(BuildContext context) {
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
            Text(L10n.t('font_label'),
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: MC.ivoire)),
            const SizedBox(height: 12),
            ...ThemeCtl.fonts.entries.map((e) => ListTile(
                  title: Text(e.value,
                      style: TextStyle(
                        color: MC.ivoire,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFamily: switch (e.key) {
                          'serif' => 'serif',
                          'condensed' => 'sans-serif-condensed',
                          'mono' => 'monospace',
                          _ => null,
                        },
                      )),
                  trailing: ThemeCtl.font == e.key
                      ? Icon(Icons.check_circle_rounded, color: MC.soleil)
                      : null,
                  onTap: () async {
                    await ThemeCtl.setFont(e.key);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// ℹ️ À propos de l'application
  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.nuit2,
        title: Row(children: [
          ClipOval(
            child: Image.asset('assets/icon/icon_small.png',
                width: 34, height: 34),
          ),
          const SizedBox(width: 10),
          Text('MboteCall', style: TextStyle(color: MC.ivoire)),
        ]),
        content: Text(L10n.t('about_text'),
            style: TextStyle(color: MC.sable, fontSize: 13.5, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('OK', style: TextStyle(color: MC.soleil))),
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String label, VoidCallback? onTap) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
            color: MC.nuit2, borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          leading:
              Icon(icon, color: onTap == null ? MC.kaki : MC.soleil, size: 22),
          title: Text(label,
              style: TextStyle(
                  color: onTap == null ? MC.kaki : MC.ivoire,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600)),
          trailing: onTap == null
              ? null
              : Icon(Icons.chevron_right_rounded, color: MC.kaki),
          onTap: onTap,
        ),
      );

  /// 📷 Choisir une photo dans la galerie, compressée puis envoyée au serveur :
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
            content: const Text('Photo de profil mise à jour 📷'),
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

  /// 🎁 Feuille parrainage : code + stats + copie en 1 geste
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
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: MC.ivoire)),
            const SizedBox(height: 8),
            Text(L10n.t('referral_body'),
                textAlign: TextAlign.center,
                style: TextStyle(color: MC.sable, fontSize: 13.5, height: 1.5)),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              decoration: BoxDecoration(
                gradient: MC.degrade,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(r['code'] ?? '…',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: MC.onAccent)),
            ),
            const SizedBox(height: 10),
            Text(
                '${r['filleuls']} ${L10n.t('referral_stats')} ${fmtMoney(r['earned_cents'] ?? 0)}',
                style: TextStyle(color: MC.kaki, fontSize: 12.5)),
            const SizedBox(height: 16),
            // 📲 Partage riche : message complet prêt pour WhatsApp
            MboteButton(
              label: L10n.t('share_invite'),
              onTap: () async {
                final msg = L10n.t('invite_message')
                    .replaceAll('%CODE%', r['code'] ?? '');
                await Share.share(msg, subject: 'MboteCall 🧡');
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: MC.soleil),
                padding: const EdgeInsets.symmetric(vertical: 13),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
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
              child: Text('📋 ${L10n.t('copy')}',
                  style:
                      TextStyle(color: MC.soleil, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  /// 🔐 Gestion du code PIN : activer / changer / désactiver
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
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: MC.ivoire)),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.sync_rounded, color: MC.soleil),
              title: Text(L10n.t('pin_change'),
                  style: TextStyle(
                      color: MC.ivoire,
                      fontSize: 15,
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
                      fontSize: 15,
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
            // 🆘 PIN oublié alors que l'app est ouverte ?
            // → réinitialisation par SMS (sans connaître l'ancien code)
            ListTile(
              leading: Icon(Icons.sms_rounded, color: MC.soleil),
              title: Text(L10n.t('pin_forgot'),
                  style: TextStyle(
                      color: MC.ivoire,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              subtitle: Text('SMS → ${st0.phone}',
                  style: TextStyle(color: MC.kaki, fontSize: 12)),
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

  /// 🗣️ Sélecteur de langue : français / lingála / kiswahili
  void _pickLanguage(BuildContext context) {
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
            Text(L10n.t('language'),
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: MC.ivoire)),
            const SizedBox(height: 12),
            ...L10n.langs.entries.map((e) => ListTile(
                  title: Text(e.value,
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  trailing: L10n.lang == e.key
                      ? Icon(Icons.check_circle_rounded, color: MC.soleil)
                      : null,
                  onTap: () async {
                    await L10n.setLang(e.key);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                )),
            Divider(color: MC.ligne, height: 18),
            // 📥 Télécharger de nouvelles langues depuis le serveur
            ListTile(
              leading: Icon(Icons.download_rounded, color: MC.savane),
              title: Text(L10n.t('lang_more'),
                  style: TextStyle(
                      color: MC.savane,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(ctx);
                _downloadLanguages(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 📥 Liste des langues disponibles sur le serveur, non encore installées
  void _downloadLanguages(BuildContext context) async {
    final st = context.read<AppState>();
    List available = [];
    try {
      available = await st.api.availableLangs();
    } catch (_) {}
    final newOnes =
        available.where((l) => !L10n.langs.containsKey(l['code'])).toList();
    if (!context.mounted) return;
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
            Text(L10n.t('lang_more'),
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: MC.ivoire)),
            const SizedBox(height: 12),
            if (newOnes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text('✓ Toutes les langues disponibles sont installées',
                    style: TextStyle(color: MC.kaki, fontSize: 13.5)),
              ),
            ...newOnes.map((l) => ListTile(
                  leading: Icon(Icons.language_rounded, color: MC.soleil),
                  title: Text(l['name'],
                      style: TextStyle(
                          color: MC.ivoire,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  trailing: Icon(Icons.download_rounded, color: MC.savane),
                  onTap: () async {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(L10n.t('downloading')),
                        duration: const Duration(seconds: 1)));
                    try {
                      final pack = await st.api.langPack(l['code']);
                      await L10n.install(l['code'], pack['name'],
                          Map<String, String>.from(pack['strings']));
                      await L10n.setLang(l['code']);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(L10n.t('downloaded')),
                            backgroundColor: MC.savane));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(friendlyError(e)),
                            backgroundColor: MC.rouge));
                      }
                    }
                  },
                )),
            const SizedBox(height: 8),
          ],
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
                  fontSize: 19, fontWeight: FontWeight.w800, color: MC.ivoire)),
          const SizedBox(height: 12),
          ...rates.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Text('${r['flag']} ', style: const TextStyle(fontSize: 16)),
                    Expanded(
                      child: Text(r['destination'],
                          style: TextStyle(color: MC.ivoire, fontSize: 14)),
                    ),
                    Text(
                        '${(r['price_per_min_cents'] / 100).toStringAsFixed(2)} \$/min',
                        style: TextStyle(
                            color: MC.soleil,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
