// lib/models/post.dart
// Modèles du fil Mbote : publications (posts) + statuts (stories).
//
//Les couleurs/thèmes vivants sont dans `theme.dart` ; ici, uniquement des
// données. Chaque modèle sait se construire depuis la réponse de l'API
// (`fromJson`) — c'est ce qui rend le fil réellement branché au backend.

import 'dart:convert';

import 'social.dart';

//───────────────────────────────────────────
// Enums
//───────────────────────────────────────────

enum PostType { photo, clip, texte, event }

enum PostOrigine { rdc, diaspora }

enum PostDuree { h24, permanent }

enum PostVisibilite { contacts, communaute, public }

PostType postTypeFrom(Object? v) => switch ('$v') {
      'photo' => PostType.photo,
      'clip' => PostType.clip,
      'event' => PostType.event,
      _ => PostType.texte,
    };

PostOrigine postOrigineFrom(Object? v) =>
    '$v' == 'diaspora' ? PostOrigine.diaspora : PostOrigine.rdc;

PostDuree postDureeFrom(Object? v) =>
    '$v' == 'h24' ? PostDuree.h24 : PostDuree.permanent;

/// L'API renvoie « communauté » (accentué) ; on tolère les deux écritures.
PostVisibilite postVisibiliteFrom(Object? v) => switch ('$v') {
      'public' => PostVisibilite.public,
      'communauté' || 'communaute' => PostVisibilite.communaute,
      _ => PostVisibilite.contacts,
    };

String postVisibiliteToApi(PostVisibilite v) => switch (v) {
      PostVisibilite.public => 'public',
      // Valeur canonique SANS accent : c'est celle que le serveur enregistre.
      // (Il accepte encore « communauté », mais l'écrire ainsi évite toute
      // question d'encodage Unicode.)
      PostVisibilite.communaute => 'communaute',
      PostVisibilite.contacts => 'contacts',
    };

String postTypeToApi(PostType t) => switch (t) {
      PostType.photo => 'photo',
      PostType.clip => 'clip',
      PostType.texte => 'texte',
      PostType.event => 'event',
    };

//───────────────────────────────────────────
// Publication
//───────────────────────────────────────────

class Post {
  final String id;
  final String authorId;
  final String authorName;
  final String? authorAvatar;

  /// Numéro de l'auteur — fourni par l'API **seulement** s'il est dans mes
  /// contacts (ou s'il s'agit de moi). C'est ce qui alimente « Appeler ».
  final String? authorPhone;

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
  final bool liked;
  final PostDuree duree;
  final PostVisibilite visibilite;
  final PostOrigine origine;

  /// Personnes mentionnées (@pseudo) : permet d'ouvrir leur profil.
  final List<Mention> mentionsListe;

  /// Hashtags de cette publication que je suis : le fil les met en avant.
  final List<String> tagsSuivis;

  /// Pourquoi cette publication remonte dans « Pour toi » (hashtag suivi,
  /// auteur suivi) — affiché comme explication, jamais comme décoration.
  final String? raison;

  /// Lien public de la publication (`https://…/p/<id>`), fourni par le
  /// serveur. C'est ce lien que l'on copie ou que l'on envoie vers une autre
  /// application (WhatsApp, Facebook, SMS…).
  final String? partageUrl;

  /// Nombre de fois que cette publication a été partagée.
  final int partages;

  /// Miniature de la vidéo, capturée par le serveur à l'envoi du fichier.
  /// `null` pour une photo, un texte ou une vidéo publiée avant les miniatures.
  final String? thumbUrl;

  /// Nombre de lectures (une seule par personne, la vue de l'auteur exclue).
  final int vues;

  /// Mots-clés de la publication (`#kinshasa` → `kinshasa`), calculés par le
  /// serveur. Ils alimentent les tendances et le filtrage par mot-clé.
  final List<String> tags;

  /// Je suis l'auteur de cet auteur-ci (bouton « Suivre »).
  final bool suivi;

  /// Cette publication est-elle la mienne ? Le serveur le dit explicitement,
  /// ce qui évite de comparer des identifiants côté affichage.
  final bool aMoi;

  const Post({
    required this.id,
    required this.authorId,
    required this.authorName,
    this.authorAvatar,
    this.authorPhone,
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
    this.liked = false,
    this.duree = PostDuree.permanent,
    this.visibilite = PostVisibilite.contacts,
    this.origine = PostOrigine.rdc,
    this.thumbUrl,
    this.partageUrl,
    this.partages = 0,
    this.mentionsListe = const [],
    this.tagsSuivis = const [],
    this.raison,
    this.vues = 0,
    this.tags = const [],
    this.suivi = false,
    this.aMoi = false,
  });

  /// Auteur dans mes contacts → l'API m'a donné son numéro.
  bool get isContact => authorPhone != null;

  /// Je peux appeler l'auteur depuis la carte.
  bool get canCall => authorPhone != null;

  factory Post.fromJson(Map<String, dynamic> j) {
    final createdMs = (j['created_at'] as num?)?.toInt();
    final eventMs = (j['event_date'] as num?)?.toInt();
    return Post(
      id: '${j['id']}',
      authorId: '${j['user_id'] ?? ''}',
      authorName: (j['author_name'] ?? '').toString(),
      authorAvatar: (j['author_avatar'] as String?)?.trim().isEmpty ?? true
          ? null
          : j['author_avatar'] as String,
      authorPhone: (j['author_phone'] as String?)?.trim().isEmpty ?? true
          ? null
          : j['author_phone'] as String,
      type: postTypeFrom(j['type']),
      createdAt: createdMs == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(createdMs),
      texte: j['texte'] as String?,
      mediaUrl: (j['media_url'] as String?)?.trim().isEmpty ?? true
          ? null
          : j['media_url'] as String,
      eventTitle: j['event_title'] as String?,
      eventDate:
          eventMs == null ? null : DateTime.fromMillisecondsSinceEpoch(eventMs),
      eventLieu: j['event_lieu'] as String?,
      eventTags: _parseTags(j['event_tags']),
      clipDureeSeconds: (j['clip_sec'] as num?)?.toInt(),
      ville: (j['ville'] as String?)?.trim().isEmpty ?? true
          ? null
          : j['ville'] as String,
      likes: (j['likes'] as num?)?.toInt() ?? 0,
      comments: (j['comments'] as num?)?.toInt() ?? 0,
      liked: (j['liked'] as num?)?.toInt() == 1,
      duree: postDureeFrom(j['duree']),
      visibilite: postVisibiliteFrom(j['visibilite']),
      origine: postOrigineFrom(j['origine']),
      thumbUrl: (j['thumb_url'] as String?)?.trim().isEmpty ?? true
          ? null
          : j['thumb_url'] as String,
      partageUrl: (j['share_url'] as String?)?.trim().isEmpty ?? true
          ? null
          : j['share_url'] as String,
      // Le serveur nomme le compteur `partages` ; `shares` est l'ancien nom
      // de colonne, accepté par prudence.
      partages: (j['partages'] as num?)?.toInt() ??
          (j['shares'] as num?)?.toInt() ??
          0,
      mentionsListe: ((j['mentions'] as List?) ?? const [])
          .map((e) => Mention.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      tagsSuivis: ((j['tags_suivis'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(),
      raison: j['raison'] as String?,
      vues: (j['vues'] as num?)?.toInt() ?? 0,
      tags: (j['tags'] as List?)?.map((e) => '$e').toList(growable: false) ??
          const [],
      // Le serveur renvoie 1/0 (SQLite) ou true/false (PostgreSQL).
      suivi: j['suivi'] == 1 || j['suivi'] == true,
      aMoi: j['a_moi'] == 1 || j['a_moi'] == true,
    );
  }

  /// `event_tags` arrive en chaîne JSON (`["kin","musique"]`) ou déjà en liste.
  static List<String> _parseTags(Object? raw) {
    if (raw == null) return const [];
    if (raw is List) return raw.map((e) => '$e').toList(growable: false);
    final s = '$raw'.trim();
    if (s.isEmpty) return const [];
    try {
      final decoded = jsonDecode(s);
      if (decoded is List) {
        return decoded.map((e) => '$e').toList(growable: false);
      }
    } catch (_) {/* pas du JSON : on retombe sur le découpage brut */}
    return s
        .split(',')
        .map((e) => e.replaceAll(RegExp(r'[\[\]"]'), '').trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  Post copyWith({
    int? likes,
    int? comments,
    bool? liked,
    int? vues,
    bool? suivi,
    String? thumbUrl,
    int? partages,
    List<Mention>? mentionsListe,
    List<String>? tagsSuivis,
    String? raison,
    PostVisibilite? visibilite,
  }) =>
      Post(
        id: id,
        authorId: authorId,
        authorName: authorName,
        authorAvatar: authorAvatar,
        authorPhone: authorPhone,
        type: type,
        createdAt: createdAt,
        texte: texte,
        mediaUrl: mediaUrl,
        eventTitle: eventTitle,
        eventDate: eventDate,
        eventLieu: eventLieu,
        eventTags: eventTags,
        clipDureeSeconds: clipDureeSeconds,
        ville: ville,
        likes: likes ?? this.likes,
        comments: comments ?? this.comments,
        liked: liked ?? this.liked,
        duree: duree,
        visibilite: visibilite ?? this.visibilite,
        origine: origine,
        thumbUrl: thumbUrl ?? this.thumbUrl,
        partageUrl: partageUrl,
        partages: partages ?? this.partages,
        mentionsListe: mentionsListe ?? this.mentionsListe,
        tagsSuivis: tagsSuivis ?? this.tagsSuivis,
        raison: raison ?? this.raison,
        vues: vues ?? this.vues,
        tags: tags,
        suivi: suivi ?? this.suivi,
        aMoi: aMoi,
      );

  /// Temps écoulé lisible (ex. « à l'instant », « 2 min », « 3 h », « hier »).
  String get age {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return "à l'instant";
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    if (diff.inDays == 1) return 'hier';
    if (diff.inDays < 7) return '${diff.inDays} j';
    return '${(diff.inDays / 7).floor()} sem';
  }

  /// Durée de clip formatée (ex. « 1:42 »).
  String get clipDureeLabel {
    final s0 = clipDureeSeconds;
    if (s0 == null || s0 <= 0) return '';
    final m = s0 ~/ 60;
    final s = s0 % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

//───────────────────────────────────────────
// Statuts (stories)
//───────────────────────────────────────────

class Story {
  final String id;
  final String userId;
  final String authorName;
  final String? avatar;
  final String? mediaUrl;
  final String? texte;
  final DateTime createdAt;
  final bool seen;

  const Story({
    required this.id,
    required this.userId,
    required this.authorName,
    this.avatar,
    this.mediaUrl,
    this.texte,
    required this.createdAt,
    this.seen = false,
  });

  factory Story.fromJson(Map<String, dynamic> j) => Story(
        id: '${j['id']}',
        userId: '${j['user_id'] ?? ''}',
        authorName: (j['author_name'] ?? '').toString(),
        avatar: (j['author_avatar'] as String?)?.trim().isEmpty ?? true
            ? null
            : j['author_avatar'] as String,
        mediaUrl: (j['media_url'] as String?)?.trim().isEmpty ?? true
            ? null
            : j['media_url'] as String,
        texte: j['texte'] as String?,
        createdAt: (j['created_at'] as num?) == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(
                (j['created_at'] as num).toInt()),
        seen: (j['seen'] as num?)?.toInt() == 1,
      );

  Story copyWith({bool? seen}) => Story(
        id: id,
        userId: userId,
        authorName: authorName,
        avatar: avatar,
        mediaUrl: mediaUrl,
        texte: texte,
        createdAt: createdAt,
        seen: seen ?? this.seen,
      );
}

/// Toutes les stories d'un même auteur (une pastille dans la bande).
class StoryGroup {
  final String userId;
  final String authorName;
  final String? avatar;
  final List<Story> stories;
  final bool isMe;

  StoryGroup({
    required this.userId,
    required this.authorName,
    this.avatar,
    required this.stories,
    this.isMe = false,
  });

  bool get allSeen => stories.isNotEmpty && stories.every((s) => s.seen);
  bool get hasUnseen => stories.any((s) => !s.seen);

  /// Regroupe une liste plate (renvoyée par l'API) par auteur.
  /// Non vus d'abord, puis les plus récens.
  static List<StoryGroup> group(List<Story> flat, {String? myUserId}) {
    final byUser = <String, List<Story>>{};
    for (final s in flat) {
      byUser.putIfAbsent(s.userId, () => []).add(s);
    }
    final groups = byUser.entries.map((e) {
      final list = List<Story>.from(e.value)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return StoryGroup(
        userId: e.key,
        authorName: list.first.authorName,
        avatar: list.first.avatar,
        stories: list,
        isMe: myUserId != null && e.key == myUserId,
      );
    }).toList();

    // Moi d'abord (comme WhatsApp), puis non vus, puis les autres.
    groups.sort((a, b) {
      if (a.isMe != b.isMe) return a.isMe ? -1 : 1;
      if (a.hasUnseen != b.hasUnseen) return a.hasUnseen ? -1 : 1;
      final la = a.stories
          .map((s) => s.createdAt)
          .reduce((x, y) => x.isAfter(y) ? x : y);
      final lb = b.stories
          .map((s) => s.createdAt)
          .reduce((x, y) => x.isAfter(y) ? x : y);
      return lb.compareTo(la);
    });
    return groups;
  }
}
