// lib/widgets/feed/story_bar.dart
// Bande de statuts (24 h) — style WhatsApp, identité Kinshasa.
//
// Les statuts viennent de `GET /api/feed/stories` et sont regroupés par auteur
// (`StoryGroup.group`). Le premier rond est toujours « Mon statut » : il permet
// d'ajouter une photo ou d'ouvrir la sienne.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/post.dart';
import '../../design.dart';
import '../../l10n.dart';
import '../../theme.dart';

class StoryBar extends StatelessWidget {
  final List<StoryGroup> groups;
  final String? myAvatar;
  final void Function(StoryGroup) onGroupTap;
  final void Function(StoryGroup? myGroup) onMyTap;

  const StoryBar({
    super.key,
    required this.groups,
    required this.onGroupTap,
    required this.onMyTap,
    this.myAvatar,
  });

  StoryGroup? get _mine {
    for (final g in groups) {
      if (g.isMe) return g;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    final others = groups.where((g) => !g.isMe).toList();

    // Hauteur calculée, pas figée : à 200 % de taille de texte le libellé
    // sous l'avatar dépasse les 96 px et le contenu se retrouve rogné
    // (WCAG 2.2 · 1.4.4). On ajoute donc la hauteur réelle d'une ligne.
    final facteur = MediaQuery.textScalerOf(context).scale(1.0);
    final hauteurLibelle = Tx.caption * 1.45 * facteur;
    return SizedBox(
      height: 62 + 5 + hauteurLibelle + 12,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: others.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return _StoryItem(
              label: 'Mon statut',
              avatar: myAvatar,
              initials: 'Moi',
              ring: mine != null && mine.hasUnseen,
              seen: mine != null && mine.allSeen,
              addBadge: true,
              onTap: () {
                HapticFeedback.selectionClick();
                onMyTap(mine);
              },
            );
          }
          final g = others[i - 1];
          return _StoryItem(
            label: g.authorName.split(' ').first,
            avatar: g.avatar,
            initials: g.authorName,
            ring: g.hasUnseen,
            seen: g.allSeen,
            onTap: () {
              HapticFeedback.selectionClick();
              onGroupTap(g);
            },
          );
        },
      ),
    );
  }
}

class _StoryItem extends StatelessWidget {
  final String label;
  final String? avatar;
  final String initials;
  final bool ring;
  final bool seen;
  final bool addBadge;
  final VoidCallback onTap;

  const _StoryItem({
    required this.label,
    this.avatar,
    required this.initials,
    required this.ring,
    required this.seen,
    required this.onTap,
    this.addBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: addBadge
          ? L10n.t('story_mine')
          : L10n.t('story_of').replaceAll('%s', label),
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 68,
          margin: const EdgeInsets.only(right: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 62,
                height: 62,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: ring ? MC.degrade : null,
                        color: ring ? null : MC.nuit3,
                      ),
                      padding: const EdgeInsets.all(2.5),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: MC.nuit2,
                        ),
                        padding: const EdgeInsets.all(2),
                        child: ClipOval(
                            child: _Avatar(url: avatar, name: initials)),
                      ),
                    ),
                    if (addBadge)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: MC.soleil,
                            border: Border.all(color: MC.nuit, width: 2),
                          ),
                          child:
                              Icon(Icons.add_rounded, size: 14, color: MC.nuit),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: seen && !addBadge ? MC.kaki : MC.sable,
                  fontSize: Tx.caption,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  const _Avatar({this.url, required this.name});

  String get _initialsLabel {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
    final s = parts.map((w) => w[0].toUpperCase()).join();
    return s.isEmpty ? '?' : s;
  }

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return Image.network(
        url!,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        cacheWidth: 200,
        errorBuilder: (_, __, ___) => _Initials(text: _initialsLabel),
      );
    }
    return _Initials(text: _initialsLabel);
  }
}

class _Initials extends StatelessWidget {
  final String text;
  const _Initials({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MC.nuit3,
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: MC.soleil,
          fontSize: Tx.subtitle,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
