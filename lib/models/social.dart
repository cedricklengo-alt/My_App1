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
class NotificationSociale {
  final String id;
  final String type; // mention
  final String? postId;
  final String? commentId;
  final String? sourceType; // post | comment | story
  final String texte;
  final bool lu;
  final DateTime createdAt;
  final Personne? expediteur;

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
  });

  factory NotificationSociale.fromJson(Map j) {
    final exp = j['expediteur'];
    return NotificationSociale(
      id: '${j['id'] ?? ''}',
      type: '${j['type'] ?? 'mention'}',
      postId: j['post_id'] as String?,
      commentId: j['comment_id'] as String?,
      sourceType: j['source_type'] as String?,
      texte: '${j['texte'] ?? ''}',
      lu: j['lu'] == 1 || j['lu'] == true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (j['created_at'] as num?)?.toInt() ?? 0),
      expediteur: exp is Map ? Personne.fromJson(exp) : null,
    );
  }

  /// Phrase affichée dans la liste, sans emoji.
  String get resume {
    final qui = expediteur?.name.isNotEmpty == true ? expediteur!.name : 'Quelqu’un';
    final ou = switch (sourceType) {
      'comment' => 'dans un commentaire',
      'story' => 'dans un statut',
      _ => 'dans une publication',
    };
    return '$qui t’a mentionné $ou';
  }
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
