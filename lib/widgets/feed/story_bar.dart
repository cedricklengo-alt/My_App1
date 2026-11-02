// lib/widgets/feed/story_bar.dart
// Bande de statuts style WhatsApp — design Kinshasa Noir

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/post.dart';
import '../../theme.dart';

class StoryBar extends StatelessWidget {
  final List<StoryContact> stories;
  final void Function(StoryContact) onStoryTap;
  final VoidCallback onAddTap;

  const StoryBar({
    super.key,
    required this.stories,
    required this.onStoryTap,
    required this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: stories.length,
        itemBuilder: (context, i) => _StoryItem(
          story: stories[i],
          onTap: () {
            HapticFeedback.selectionClick();
            if (stories[i].isMe) {
              onAddTap();
            } else {
              onStoryTap(stories[i]);
            }
          },
        ),
      ),
    );
  }
}

class _StoryItem extends StatelessWidget {
  final StoryContact story;
  final VoidCallback onTap;

  const _StoryItem({required this.story, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool unseen = !story.isSeen && !story.isMe;

    return Semantics(
      label: story.isMe ? 'Ajouter un statut' : 'Statut de ${story.name}',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 64,
          margin: const EdgeInsets.only(right: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Anneau gradient (non vu) ou gris (vu/moi)
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: unseen ? MC.degrade : null,
                  color: unseen ? null : MC.nuit3,
                ),
                padding: const EdgeInsets.all(2.5),
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: MC.nuit2,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: story.isMe
                      ? _MeAvatar()
                      : _Avatar(name: story.name, avatar: story.avatar),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                story.isMe ? 'Mon statut' : story.name.split(' ').first,
                style: const TextStyle(
                  color: MC.sable,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: MC.nuit3,
      ),
      child: const Center(
        child: Icon(Icons.add_rounded, color: MC.soleil, size: 26),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String? avatar;

  const _Avatar({required this.name, this.avatar});

  @override
  Widget build(BuildContext context) {
    if (avatar != null) {
      return ClipOval(
        child: Image.network(
          avatar!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _Initials(name: name),
        ),
      );
    }
    return _Initials(name: name);
  }
}

class _Initials extends StatelessWidget {
  final String name;
  const _Initials({required this.name});

  @override
  Widget build(BuildContext context) {
    final initials = name
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: MC.nuit3,
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: MC.soleil,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
