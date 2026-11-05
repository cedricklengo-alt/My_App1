import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Sélecteur de réactions façon Facebook (8 réactions), affiché au-dessus
/// du bouton « J'aime » (appui long).
class ReactionPicker {
  static const types = ['like', 'love', 'haha', 'wow', 'sad', 'angry', 'care', 'solidarity'];

  static const _icons = {
    'like': Icons.thumb_up_alt_rounded,
    'love': Icons.favorite_rounded,
    'haha': Icons.sentiment_very_satisfied_rounded,
    'wow': Icons.auto_awesome_rounded,
    'sad': Icons.sentiment_dissatisfied_rounded,
    'angry': Icons.mood_bad_rounded,
    'care': Icons.volunteer_activism_rounded,
    'solidarity': Icons.handshake_rounded,
  };

  static final _colors = {
    'like': const Color(0xFF1877F2),
    'love': const Color(0xFFF25268),
    'haha': const Color(0xFFF7B125),
    'wow': const Color(0xFFF7B125),
    'sad': const Color(0xFFF7B125),
    'angry': const Color(0xFFE9710F),
    'care': const Color(0xFFF25268),
    'solidarity': const Color(0xFF45BD62),
  };

  static IconData iconOf(String type) => _icons[type] ?? Icons.thumb_up_alt_rounded;
  static Color colorOf(String type) => _colors[type] ?? const Color(0xFF1877F2);

  /// Affiche la barre de réactions ancrée sous [globalPosition] (bouton J'aime).
  static Future<String?> show(BuildContext context, Offset globalPosition, {String? current}) {
    HapticFeedback.selectionClick();
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx - 20,
        globalPosition.dy - 64,
        MediaQuery.of(context).size.width - globalPosition.dx - 20,
        MediaQuery.of(context).size.height - globalPosition.dy,
      ),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      items: types
          .map((t) => PopupMenuItem<String>(
                value: t,
                height: 48,
                child: Center(
                  child: Icon(iconOf(t),
                      color: t == current ? colorOf(t) : colorOf(t),
                      size: t == current ? 32 : 28),
                ),
              ))
          .toList(),
    );
  }
}
