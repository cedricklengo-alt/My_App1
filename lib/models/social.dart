// lib/models/social.dart
// MODÈLES SOCIAUX — hashtags, personnes mentionnables, notifications.
//
// Les mêmes objets servent à la page d'un hashtag, aux tendances, aux
// suggestions de l'éditeur, à la recherche universelle et à la boîte de
// réception : une seule définition évite les conversions approximatives d'un
// écran à l'autre.

/// Un hashtag tel que la plateforme le connaît.
class Hashtag {
  final String tag; // clé : sans #, sans accent, en minuscules
  final int publications;
  final int abonnes;
  final int engagement;

  /// -1 (recule) à 1 (explose) : évolution des dernières 24 heures.
  final double croissance;

  /// Fait partie des tendances (du volume, récent, ne recule pas).
  final bool tendance;

  /// Je suis ce hashtag.
  final bool suivi;

  const Hashtag({
    required this.tag,
    this.publications = 0,
    this.abonnes = 0,
    this.engagement = 0,
    this.croissance = 0,
    this.tendance = false,
    this.suivi = false,
  });

  factory Hashtag.fromJson(Map j) => Hashtag(
        tag: '${j['tag'] ?? j['nom'] ?? ''}',
        publications: (j['publications'] as num?)?.toInt() ?? 0,
        abonnes: (j['abonnes'] as num?)?.toInt() ?? 0,
        engagement: (j['engagement'] as num?)?.toInt() ?? 0,
        croissance: (j['croissance'] as num?)?.toDouble() ?? 0,
        tendance: j['tendance'] == 1 || j['tendance'] == true,
        suivi: j['suivi'] == 1 || j['suivi'] == true,
      );

  /// Écriture affichable : « #MboteCall ».
  String get libelle => '#$tag';

  /// « 12 publications » — jamais « 1 publications ».
  String get volume =>
      publications <= 1 ? '$publications publication' : '$publications publications';

  Hashtag copyWith({bool? suivi, int? abonnes, int? publications}) => Hashtag(
        tag: tag,
        publications: publications ?? this.publications,
        abonnes: abonnes ?? this.abonnes,
        engagement: engagement,
        croissance: croissance,
        tendance: tendance,
        suivi: suivi ?? this.suivi,
      );
}

/// Une personne : suggestion de mention, résultat de recherche, auteur.
class Personne {
  final String id;
  final String name;
  final String? handle;
  final String? avatar;
  final String? country;

  /// Présente dans mon répertoire téléphonique.
  final bool contact;

  /// Je suis déjà cette personne.
  final bool suivi;

  const Personne({
    required this.id,
    required this.name,
    this.handle,
    this.avatar,
    this.country,
    this.contact = false,
    this.suivi = false,
  });

  factory Personne.fromJson(Map j) => Personne(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        handle: (j['handle'] as String?)?.trim().isEmpty ?? true ? null : j['handle'] as String,
        avatar: (j['avatar'] as String?)?.trim().isEmpty ?? true ? null : j['avatar'] as String,
        country: j['country'] as String?,
        contact: j['contact'] == 1 || j['contact'] == true,
        suivi: j['suivi'] == 1 || j['suivi'] == true,
      );

  /// « @cedricklengo » quand l'identifiant existe, sinon le nom.
  String get mention => handle != null ? '@$handle' : name;
}

/// Une mention telle qu'elle apparaît dans un contenu : identifiant + nom,
/// pour ouvrir le profil du bon côté.
class Mention {
  final String id;
  final String handle;
  final String name;
  final String? avatar;

  const Mention({
    required this.id,
    required this.handle,
    required this.name,
    this.avatar,
  });

  factory Mention.fromJson(Map j) => Mention(
        id: '${j['id'] ?? j['user_id'] ?? ''}',
        handle: '${j['handle'] ?? j['cle'] ?? ''}',
        name: '${j['name'] ?? ''}',
        avatar: j['avatar'] as String?,
      );
}

/// Élément de la boîte de réception.
/// NOTIFICATION D'INTERACTION — j'aime, commentaire, réponse, mention,
/// partage.
///
/// Le texte affiché vient du serveur (`message`) : il porte le regroupement
/// (« Patrick, Junior et 16 autres personnes ont aimé votre publication »),
/// qui ne peut pas être recalculé sans la liste complète des auteurs. Le client
/// ne fabrique une phrase qu'en dernier recours, si le serveur est plus ancien
/// que l'application.
class NotificationSociale {
  final String id;
  final String type; // post_like | comment | comment_reply | mention | share | follow
  final String? postId;
  final String? commentId;
  final String? sourceType; // post | comment | story
  final String texte;
  final bool lu;
  final DateTime createdAt;

  /// Auteur du dernier geste (avatar de la ligne).
  final Personne? expediteur;

  /// Nombre d'auteurs pour les notifications regroupées (1 pour les autres).
  final int nbActeurs;

  /// Les auteurs connus, du plus récent au plus ancien (bandeau d'avatars).
  final List<Personne> acteurs;

  /// Phrase prête à afficher, calculée par le serveur.
  final String message;

  const NotificationSociale({
    required this.id,
    required this.type,
    required this.createdAt,
    this.postId,
    this.commentId,
    this.sourceType,
    this.texte = '',
    this.lu = false,
    this.expediteur,
    this.nbActeurs = 1,
    this.acteurs = const [],
    this.message = '',
  });

  factory NotificationSociale.fromJson(Map j) => NotificationSociale(
        id: '${j['id'] ?? ''}',
        type: '${j['type'] ?? 'mention'}',
        postId: j['post_id'] as String?,
        commentId: j['comment_id'] as String?,
        sourceType: j['source_type'] as String?,
        texte: '${j['texte'] ?? ''}',
        lu: j['lu'] == 1 || j['lu'] == true,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (j['created_at'] as num?)?.toInt() ?? 0),
        expediteur:
            j['expediteur'] is Map ? Personne.fromJson(j['expediteur'] as Map) : null,
        nbActeurs: (j['nb_acteurs'] as num?)?.toInt() ?? 1,
        acteurs: ((j['acteurs'] as List?) ?? const [])
            .map((e) => Personne.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        message: '${j['message'] ?? ''}',
      );

  NotificationSociale copyWith({bool? lu}) => NotificationSociale(
        id: id,
        type: type,
        createdAt: createdAt,
        postId: postId,
        commentId: commentId,
        sourceType: sourceType,
        texte: texte,
        lu: lu ?? this.lu,
        expediteur: expediteur,
        nbActeurs: nbActeurs,
        acteurs: acteurs,
        message: message,
      );

  /// Vrai si la notification concerne un j'aime ou un partage (regroupables).
  bool get estGroupee => nbActeurs > 1;

  /// Phrase affichée : celle du serveur, sinon une phrase de repli par type.
  String get resume {
    if (message.isNotEmpty) return message;
    final qui = expediteur?.name.isNotEmpty == true ? expediteur!.name : 'Quelqu’un';
    return switch (type) {
      'post_like' => '$qui a aimé votre publication',
      'comment' => '$qui a commenté votre publication',
      'comment_reply' => '$qui a répondu à votre commentaire',
      'share' => '$qui a partagé votre publication',
      'follow' => '$qui vous suit maintenant',
      _ => switch (sourceType) {
          'comment' => '$qui vous a mentionné dans un commentaire',
          'story' => '$qui vous a mentionné dans un statut',
          _ => '$qui vous a mentionné dans une publication',
        },
    };
  }

  /// Compte rendu court pour l'accessibilité et l'infobulle.
  String get nature => switch (type) {
        'post_like' => 'J’aime',
        'comment' => 'Commentaire',
        'comment_reply' => 'Réponse',
        'share' => 'Partage',
        'follow' => 'Abonnement',
        _ => 'Mention',
      };

  /// Les types qui ouvrent une publication.
  bool get aUnePublication => postId != null && postId!.isNotEmpty;
}

/// Tranche horaire d'une notification : c'est le découpage demandé par le
/// centre de notifications (Aujourd'hui / Cette semaine / Plus anciennes).
enum TrancheNotifs { aujourdhui, semaine, anciennes }

TrancheNotifs trancheDe(DateTime t, {DateTime? maintenant}) {
  final now = maintenant ?? DateTime.now();
  final debutJour = DateTime(now.year, now.month, now.day);
  if (!t.isBefore(debutJour)) return TrancheNotifs.aujourdhui;
  if (now.difference(t).inDays < 7) return TrancheNotifs.semaine;
  return TrancheNotifs.anciennes;
}

/// Résultat groupé de la recherche universelle.
class ResultatsRecherche {
  final String q;

  /// « hashtags », « personnes » ou « tout » : la barre a compris l'intention.
  final String portee;
  final List<Personne> personnes;
  final List<Hashtag> hashtags;
  final List<Map> publications;
  final List<Map> statuts;
  final List<Map> evenements;
  final int total;

  const ResultatsRecherche({
    required this.q,
    this.portee = 'tout',
    this.personnes = const [],
    this.hashtags = const [],
    this.publications = const [],
    this.statuts = const [],
    this.evenements = const [],
    this.total = 0,
  });

  factory ResultatsRecherche.fromJson(Map j) => ResultatsRecherche(
        q: '${j['q'] ?? ''}',
        portee: '${j['portee'] ?? 'tout'}',
        personnes: ((j['personnes'] as List?) ?? const [])
            .map((e) => Personne.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        hashtags: ((j['hashtags'] as List?) ?? const [])
            .map((e) => Hashtag.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        publications: ((j['publications'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        statuts: ((j['statuts'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        evenements: ((j['evenements'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        total: (j['total'] as num?)?.toInt() ?? 0,
      );

  bool get vide =>
      personnes.isEmpty && hashtags.isEmpty && publications.isEmpty && statuts.isEmpty;
}

/// Statistiques personnelles des mentions.
class AnalytiqueMentions {
  final int recues;
  final int recues24h;
  final int envoyees;
  final int porteeVues;
  final int porteeLikes;

  const AnalytiqueMentions({
    this.recues = 0,
    this.recues24h = 0,
    this.envoyees = 0,
    this.porteeVues = 0,
    this.porteeLikes = 0,
  });

  factory AnalytiqueMentions.fromJson(Map j) {
    final portee = j['portee'];
    return AnalytiqueMentions(
      recues: (j['recues'] as num?)?.toInt() ?? 0,
      recues24h: (j['recues_24h'] as num?)?.toInt() ?? 0,
      envoyees: (j['envoyees'] as num?)?.toInt() ?? 0,
      porteeVues: portee is Map ? (portee['vues'] as num?)?.toInt() ?? 0 : 0,
      porteeLikes: portee is Map ? (portee['likes'] as num?)?.toInt() ?? 0 : 0,
    );
  }
}
