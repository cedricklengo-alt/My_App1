// lib/models/post.dart
// Modèle unifié Mbote Feed — statuts 24h + clips + posts + événements

enum PostType { photo, clip, texte, event }

enum PostOrigine { rdc, diaspora }

enum PostDuree { h24, permanent }

enum PostVisibilite { contacts, communaute, public }

class Post {
  final String id;
  final String authorId;
  final String authorName;
  final String? authorAvatar;
  final PostType type;
  final DateTime createdAt;

  // Contenu
  final String? texte;
  final String? mediaUrl;

  // Événement
  final String? eventTitle;
  final DateTime? eventDate;
  final String? eventLieu;
  final List<String> eventTags;

  // Clip
  final int? clipDureeSeconds;

  // Méta
  final String? ville;
  final int likes;
  final int comments;
  final PostDuree duree;
  final PostVisibilite visibilite;
  final PostOrigine origine;
  final bool isContact;
  bool isSeen;

  Post({
    required this.id,
    required this.authorId,
    required this.authorName,
    this.authorAvatar,
    required this.type,
    required this.createdAt,
    this.texte,
    this.mediaUrl,
    this.eventTitle,
    this.eventDate,
    this.eventLieu,
    this.eventTags = const [],
    this.clipDureeSeconds,
    this.ville,
    this.likes = 0,
    this.comments = 0,
    this.duree = PostDuree.permanent,
    this.visibilite = PostVisibilite.contacts,
    this.origine = PostOrigine.rdc,
    this.isContact = false,
    this.isSeen = false,
  });

  /// Temps écoulé formaté (ex. "2 min", "3 h", "hier")
  String get age {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    if (diff.inDays == 1) return 'hier';
    return '${diff.inDays} j';
  }

  /// Durée clip formatée (ex. "1:42")
  String get clipDureeLabel {
    if (clipDureeSeconds == null) return '';
    final m = clipDureeSeconds! ~/ 60;
    final s = clipDureeSeconds! % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ──────────────────────────────────────────────
// Statuts (story contacts)
// ──────────────────────────────────────────────

class StoryContact {
  final String id;
  final String name;
  final String? avatar;
  bool isSeen;
  final bool isMe;

  StoryContact({
    required this.id,
    required this.name,
    this.avatar,
    this.isSeen = false,
    this.isMe = false,
  });
}

// ──────────────────────────────────────────────
// Données de démo (remplacer par l'API)
// ──────────────────────────────────────────────

final List<StoryContact> demoStories = [
  StoryContact(id: 'me', name: 'Moi', isMe: true),
  StoryContact(id: 'c1', name: 'Mama Lola', isSeen: false),
  StoryContact(id: 'c2', name: 'Junior K.', isSeen: true),
  StoryContact(id: 'c3', name: 'Grâce M.', isSeen: false),
  StoryContact(id: 'c4', name: 'DJ Roots', isSeen: false),
  StoryContact(id: 'c5', name: 'Immo KIN', isSeen: true),
];

final List<Post> demoPosts = [
  Post(
    id: 'p1',
    authorId: 'c1',
    authorName: 'Mama Lola',
    type: PostType.photo,
    createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
    texte: 'Makemba ya sika na marché ya Lemba 🌿',
    ville: 'Kinshasa',
    likes: 47,
    comments: 8,
    origine: PostOrigine.rdc,
    isContact: true,
  ),
  Post(
    id: 'p2',
    authorId: 'c4',
    authorName: 'DJ Roots',
    type: PostType.clip,
    createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    texte: 'Nouveau mix rumba congolaise 🎵🇨🇩',
    clipDureeSeconds: 102,
    ville: 'Bruxelles',
    likes: 213,
    comments: 34,
    origine: PostOrigine.diaspora,
    isContact: true,
  ),
  Post(
    id: 'p3',
    authorId: 'c3',
    authorName: 'Grâce M.',
    type: PostType.texte,
    createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    texte:
        'Oferta ya bana : inscription scolaire ouverte jusqu\'au 30 novembre. '
        'Contactez-moi pour les détails 📚',
    ville: 'Kinshasa',
    likes: 89,
    comments: 17,
    origine: PostOrigine.rdc,
    isContact: false,
    visibilite: PostVisibilite.communaute,
  ),
  Post(
    id: 'p4',
    authorId: 'c5',
    authorName: 'Immo KIN',
    type: PostType.event,
    createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    eventTitle: 'Salon Immobilier Kinshasa 2024',
    eventDate: DateTime(2024, 12, 7, 9, 0),
    eventLieu: 'Palais du Peuple, Kinshasa',
    eventTags: ['immobilier', 'investissement', 'rdc'],
    ville: 'Kinshasa',
    likes: 156,
    comments: 42,
    origine: PostOrigine.rdc,
    isContact: false,
    visibilite: PostVisibilite.public,
  ),
];
