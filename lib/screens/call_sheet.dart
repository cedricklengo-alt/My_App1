// lib/screens/call_sheet.dart
// Fiche d'appel affichée quand on touche « Appeler » depuis une publication,
// un contact ou une conversation.
//
// UI : trois boutons **flottants à icône seule** (téléphone, caméra, groupe).
// Aucun libellé visible ; chaque bouton porte un `tooltip` et une étiquette
// d'accessibilité, donc l'explication n'est jamais perdue.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../design.dart';
import '../state.dart';
import '../theme.dart';
import '../local/local_first.dart';
import '../widgets/avatar.dart';
import '../widgets/floating_choice.dart';
import 'call.dart';
import 'group_call.dart';

/// Ouvre la fiche d'appel pour [phone].
/// [name] est le nom affiché (facultatif), [avatar] sa photo (facultative).
Future<void> showCallModeSheet(
  BuildContext context,
  String phone, {
  String? name,
  String? avatar,
}) {
  final clean = phone.trim();
  if (clean.isEmpty) {
    return Future.value();
  }
  HapticFeedback.mediumImpact();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _CallModeSheet(phone: clean, name: name, avatar: avatar),
  );
}

class _CallModeSheet extends StatelessWidget {
  final String phone;
  final String? name;
  final String? avatar;

  const _CallModeSheet({required this.phone, this.name, this.avatar});

  /// Ouvre l'écran d'appel correspondant, en refermant la fiche.
  void _appeler(BuildContext context, {bool video = false}) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(to: phone, displayName: name, video: video),
      ),
    );
  }

  /// Appel de groupe : on demande d'abord audio ou vidéo (deux boutons
  /// flottants), puis on ouvre la salle avec ce contact déjà invité.
  Future<void> _appelerGroupe(BuildContext context) async {
    final video = await _askGroupVideo(context);
    if (video == null || !context.mounted) return;
    Navigator.pop(context);
    startGroupCall(
      context,
      video: video,
      invites: [
        {'name': name, 'phone': phone},
      ],
    );
  }

  Future<void> _copier(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Numéro copié : $phone')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final display = (name ?? '').trim().isEmpty ? phone : name!.trim();

    return Container(
      decoration: BoxDecoration(
        color: MC.nuit2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Rd.lg)),
        border: Border(top: BorderSide(color: MC.ligne)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.x5, Sp.x3, Sp.x5, Sp.x5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Poignée de la feuille
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: Sp.x5),
                decoration: BoxDecoration(
                  color: MC.ligne,
                  borderRadius: BorderRadius.circular(Rd.xs),
                ),
              ),
              // Identité : avatar carré arrondi, nom, numéro
              MboteAvatar(
                name: display,
                size: 72,
                accent: true,
                image: (avatar != null && avatar!.isNotEmpty)
                    ? NetworkImage(avatar!)
                    : null,
              ),
              const SizedBox(height: Sp.x3),
              Text(
                display,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: MC.ivoire,
                  fontSize: Tx.subtitle,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                phone,
                style: TextStyle(color: MC.kaki, fontSize: Tx.label),
              ),
              const SizedBox(height: Sp.x6),

 // Les trois façons d'appeler : icônes seules, couleurs
              //    porteuses de sens (vert = voix, sable = vidéo, corail = groupe).
              FloatingChoiceRow(
                children: [
                  FloatingChoice(
                    icon: Icons.call_rounded,
                    color: MC.savane,
                    label: 'Appel audio',
                    hint: 'Voix sur Internet — gratuit entre comptes MboteCall',
                    onTap: () => _appeler(context),
                  ),
                  FloatingChoice(
                    icon: Icons.videocam_rounded,
                    color: MC.soleil,
                    label: 'Appel vidéo',
                    hint: 'Caméra et micro — gratuit entre comptes MboteCall',
                    onTap: () => _appeler(context, video: true),
                  ),
                  FloatingChoice(
                    icon: Icons.groups_rounded,
                    color: MC.braise,
                    label: 'Appel de groupe',
                    hint: 'MboteCall Famille — jusqu’à 4 personnes',
                    onTap: () => _appelerGroupe(context),
                  ),
                ],
              ),
              const SizedBox(height: Sp.x5),

 // Actions secondaires, plus petites, sans aplat plein.
              FloatingChoiceRow(
                gap: Sp.x4,
                children: [
                  FloatingChoice(
                    icon: Icons.copy_rounded,
                    color: MC.sable,
                    label: 'Copier le numéro',
                    hint: phone,
                    size: 48,
                    outlined: true,
                    onTap: () => _copier(context),
                  ),
                  FloatingChoice(
                    icon: Icons.close_rounded,
                    color: MC.kaki,
                    label: 'Fermer',
                    size: 48,
                    outlined: true,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Choix audio / vidéo avant de lancer l'appel de groupe : deux boutons
/// flottants, eux aussi sans texte visible.
Future<bool?> _askGroupVideo(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: MC.nuit2,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(Rd.lg)),
      side: BorderSide(color: MC.ligne),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.x5, Sp.x4, Sp.x5, Sp.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Appel de groupe',
              style: TextStyle(
                color: MC.ivoire,
                fontSize: Tx.subtitle,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: Sp.x1),
            Text(
              'MboteCall Famille — jusqu’à 4 personnes',
              style: TextStyle(color: MC.kaki, fontSize: Tx.label),
            ),
            const SizedBox(height: Sp.x6),
            FloatingChoiceRow(
              children: [
                FloatingChoice(
                  icon: Icons.call_rounded,
                  color: MC.savane,
                  label: 'Groupe en audio',
                  hint: 'Voix seule — idéal en 3G',
                  onTap: () => Navigator.pop(ctx, false),
                ),
                FloatingChoice(
                  icon: Icons.videocam_rounded,
                  color: MC.soleil,
                  label: 'Groupe en vidéo',
                  hint: 'Caméra et micro — jusqu’à 4 personnes',
                  onTap: () => Navigator.pop(ctx, true),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
