// lib/screens/call_sheet.dart
// Fiche d'appel affichée quand on touche « Appeler » depuis une publication,
// un contact ou une conversation.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'call.dart';

/// Ouvre la fiche d'appel pour [phone].
/// [name] est le nom affiché (facultatif).
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

  @override
  Widget build(BuildContext context) {
    final display = (name ?? '').trim().isEmpty ? phone : name!.trim();
    final initial = display.isNotEmpty ? display[0].toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(
        color: MC.nuit2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Poignée
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: MC.nuit3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Identité
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MC.nuit3,
                  border: Border.all(
                      color: MC.soleil.withValues(alpha: .45), width: 2),
                  image: (avatar != null && avatar!.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(avatar!),
                          fit: BoxFit.cover,
                          onError: (_, __) {},
                        )
                      : null,
                ),
                child: (avatar == null || avatar!.isEmpty)
                    ? Center(
                        child: Text(
                          initial,
                          style: TextStyle(
                            color: MC.soleil,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 10),
              Text(
                display,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MC.ivoire,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                phone,
                style: TextStyle(color: MC.kaki, fontSize: 12),
              ),
              const SizedBox(height: 20),

              // 🎙️ Appel MboteCall (voix sur Internet)
              _Option(
                icon: Icons.call_rounded,
                color: MC.savane,
                title: 'Appel MboteCall',
                subtitle: 'Voix sur Internet — gratuit entre comptes Mbote',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CallScreen(to: phone, displayName: name),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),

              // 📋 Copier le numéro (repli si l'appel échoue)
              _Option(
                icon: Icons.copy_rounded,
                color: MC.soleil,
                title: 'Copier le numéro',
                subtitle: phone,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: phone));
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Numéro copié : $phone')),
                  );
                },
              ),
              const SizedBox(height: 14),

              // Annuler
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Annuler',
                  style: TextStyle(color: MC.kaki, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Option({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MC.nuit3,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: .16),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: MC.ivoire,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: MC.kaki, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: MC.kaki, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
