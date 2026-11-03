// Tests unitaires des modèles du fil : mapping API → objets Dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:mbote/models/post.dart';

void main() {
  group('Post.fromJson', () {
    test('mappe une publication texte complète', () {
      final p = Post.fromJson({
        'id': 'po_1',
        'user_id': 'u1',
        'author_name': 'Mama Lola',
        'author_avatar': 'https://exemple.cd/a.jpg',
        'author_phone': '+243810000001',
        'type': 'texte',
        'texte': 'Makemba ya sika',
        'ville': 'Kinshasa',
        'likes': 12,
        'comments': 3,
        'liked': 1,
        'visibilite': 'public',
        'origine': 'rdc',
        'duree': 'permanent',
        'created_at': 1767225600000,
      });

      expect(p.id, 'po_1');
      expect(p.authorName, 'Mama Lola');
      expect(p.authorPhone, '+243810000001');
      expect(p.isContact, isTrue);
      expect(p.canCall, isTrue);
      expect(p.type, PostType.texte);
      expect(p.likes, 12);
      expect(p.comments, 3);
      expect(p.liked, isTrue);
      expect(p.visibilite, PostVisibilite.public);
      expect(p.createdAt.millisecondsSinceEpoch, 1767225600000);
      expect(p.ville, 'Kinshasa');
    });

    test('convertit les tags JSON en liste', () {
      final p = Post.fromJson({
        'id': 'po_2',
        'type': 'event',
        'event_title': 'Concert',
        'event_tags': '["musique","kin","rumba"]',
        'created_at': 1767225600000,
      });
      expect(p.eventTags, ['musique', 'kin', 'rumba']);
      expect(p.type, PostType.event);
      expect(p.eventTitle, 'Concert');
    });

    test('accepte les tags déjà en liste', () {
      final p = Post.fromJson({
        'id': 'po_3',
        'event_tags': ['a', 'b']
      });
      expect(p.eventTags, ['a', 'b']);
    });

    test('tolère l’accent de « communauté » et son absence', () {
      expect(postVisibiliteFrom('communauté'), PostVisibilite.communaute);
      expect(postVisibiliteFrom('communaute'), PostVisibilite.communaute);
      expect(postVisibiliteFrom('public'), PostVisibilite.public);
      expect(postVisibiliteFrom('contacts'), PostVisibilite.contacts);
      expect(postVisibiliteFrom('n’importe quoi'), PostVisibilite.contacts);
    });

    test('numéro absent → pas de bouton Appeler', () {
      final p = Post.fromJson({'id': 'po_4', 'author_phone': null});
      expect(p.canCall, isFalse);
    });

    test('chaîne vide de numéro → traitée comme absente', () {
      final p = Post.fromJson({'id': 'po_5', 'author_phone': '   '});
      expect(p.authorPhone, isNull);
      expect(p.canCall, isFalse);
    });

    test('date d’événement (epoch ms) → DateTime', () {
      final p = Post.fromJson({
        'id': 'po_6',
        'type': 'event',
        'event_date': 1767225600000,
      });
      expect(p.eventDate, isNotNull);
      expect(p.eventDate!.millisecondsSinceEpoch, 1767225600000);
    });

    test('champs manquants → valeurs par défaut sûres', () {
      final p = Post.fromJson({'id': 'po_7'});
      expect(p.texte, isNull);
      expect(p.likes, 0);
      expect(p.liked, isFalse);
      expect(p.eventTags, isEmpty);
      expect(p.type, PostType.texte);
    });

    test('durée de clip formatée', () {
      final p = Post.fromJson({'id': 'po_8', 'type': 'clip', 'clip_sec': 102});
      expect(p.clipDureeLabel, '1:42');
      expect(
          Post.fromJson({'id': 'po_9', 'clip_sec': null}).clipDureeLabel, '');
    });

    test('âge lisible', () {
      final now = DateTime.now();
      Post at(Duration d) => Post(
            id: 'x',
            authorId: 'u',
            authorName: 'n',
            type: PostType.texte,
            createdAt: now.subtract(d),
          );
      expect(at(const Duration(seconds: 5)).age, "à l'instant");
      expect(at(const Duration(minutes: 5)).age, '5 min');
      expect(at(const Duration(hours: 3)).age, '3 h');
      expect(at(const Duration(days: 1)).age, 'hier');
      expect(at(const Duration(days: 3)).age, '3 j');
    });

    test('copyWith ne touche que les compteurs', () {
      final p =
          Post.fromJson({'id': 'po_10', 'likes': 4, 'liked': 0, 'texte': 'x'});
      final q = p.copyWith(liked: true, likes: 5);
      expect(q.liked, isTrue);
      expect(q.likes, 5);
      expect(q.texte, 'x');
      expect(q.id, p.id);
    });
  });

  group('StoryGroup', () {
    Story story(String id, String user, {bool seen = false, int offsetH = 0}) =>
        Story(
          id: id,
          userId: user,
          authorName: user == 'me' ? 'Moi' : 'Auteur $user',
          createdAt: DateTime(2026, 1, 1).add(Duration(hours: offsetH)),
          seen: seen,
        );

    test('regroupe par auteur et place « moi » en premier', () {
      final groups = StoryGroup.group([
        story('s1', 'a', offsetH: 2),
        story('s2', 'b', offsetH: 3),
        story('s3', 'a', offsetH: 1),
        story('s4', 'me', offsetH: 0, seen: true),
      ], myUserId: 'me');

      expect(groups.length, 3);
      expect(groups.first.isMe, isTrue);
      expect(groups.first.userId, 'me');
      final a = groups.firstWhere((g) => g.userId == 'a');
      expect(a.stories.map((s) => s.id), ['s3', 's1']); // tri chronologique
    });

    test('non vus avant les vus', () {
      final groups = StoryGroup.group([
        story('s1', 'vue', seen: true, offsetH: 5),
        story('s2', 'neuve', seen: false, offsetH: 1),
      ]);
      expect(groups.first.userId, 'neuve');
      expect(groups.first.hasUnseen, isTrue);
      expect(groups.last.allSeen, isTrue);
    });
  });
}
