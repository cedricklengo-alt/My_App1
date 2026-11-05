import 'dart:io';
import 'package:uuid/uuid.dart';
import '../api.dart';
import '../prefs.dart';
import 'repository.dart';
import 'sync_service.dart';
import 'media_store.dart';

/// ============================================================
///  FAÇADE LOCAL-FIRST — point d'entrée utilisé par les écrans
/// ============================================================
///
/// Les écrans appellent ici au lieu d'appeler l'API directement :
///  - la lecture vient TOUJOURS de la base locale (jamais de spinner
///    bloquant quand Internet est absent) ;
///  - l'envoi écrit localement d'abord (statut « pending »), enfile une
///    opération de synchro, puis tente l'envoi si le réseau est là.
class LocalFirst {
  LocalFirst({required this.api, this.sync});
  final Api api;
  final SyncService? sync;

  SyncService get _sync => sync ?? SyncService(api: api);
  static const _uuid = Uuid();

  // ---------------------------------------------------------------
  //  LECTURE (locale d'abord, réseau en complément)
  // ---------------------------------------------------------------

  /// Liste des fils : locale immédiatement. Si online, le SyncService
  /// met à jour en arrière-plan (pullServerState).
  Stream<List<Map<String, dynamic>>> threads() =>
      LocalRepository.instance.threadsStream();

  /// Messages d'un fil : depuis la base locale. Si online et que le fil
  /// n'a jamais été synchronisé, on tire la conversation complète.
  Future<List<Map<String, dynamic>>> conversation(String peer,
      {int? before}) async {
    final local =
        await LocalRepository.instance.listMessages(peer, before: before);
    if (_sync.isOnline) {
      // Synchro de rattrapage en arrière-plan (ne bloque pas l'affichage).
      _sync.pullServerState();
    }
    return local;
  }

  /// Historique des appels : base locale uniquement (fonctionne hors ligne).
  Stream<List<Map<String, dynamic>>> calls({String filter = 'all'}) async* {
    yield await LocalRepository.instance.listCalls(filter: filter);
  }

  // ---------------------------------------------------------------
  //  ENVOI (écriture locale d'abord, synchro ensuite)
  // ---------------------------------------------------------------

  /// Envoie un message texte — fonctionne HORS CONNEXION.
  /// Retourne le message local (statut pending si offline).
  Future<Map<String, dynamic>> sendText(String peer, String text) async {
    final clientId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final msg = {
      'local_id': _uuid.v4(),
      'server_id': null,
      'peer_phone': peer,
      'sender_id': 'me',
      'recipient_id': peer,
      'client_id': clientId,
      'kind': 'text',
      'body': text,
      'created_at': now,
      'server_ts': null,
      'status': _sync.isOnline ? 'sending' : 'pending',
    };
    // 1. Persistance locale (source d'affichage immédiate).
    await LocalRepository.instance.insertMessage(msg);
    // 2. Opération persistante (transaction atomique avec l'étape 1 via
    //    la même base) — dédupliquée par client_id.
    await LocalRepository.instance.enqueue(
      opType: 'send_message',
      entity: 'messages',
      entityId: msg['local_id'] as String,
      payload: {
        'peer': peer,
        'body': text,
        'kind': 'text',
        'client_id': clientId,
      },
      dedupeKey: 'send_message:$clientId',
    );
    // 3. Tentative immédiate si online.
    if (_sync.isOnline) {
      await _sync.flushQueue();
      final reloaded = await LocalRepository.instance.listMessages(peer);
      return reloaded.lastWhere((m) => m['local_id'] == msg['local_id'],
          orElse: () => msg);
    }
    return msg;
  }

  /// Envoie un média (image/vidéo/fichier/voix) — file d'attente hors ligne.
  Future<Map<String, dynamic>> sendMedia(
      String peer, File file, String kind) async {
    final clientId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final mediaId = _uuid.v4();
    final msg = {
      'local_id': _uuid.v4(),
      'server_id': null,
      'peer_phone': peer,
      'sender_id': 'me',
      'recipient_id': peer,
      'client_id': clientId,
      'kind': kind,
      'body': '',
      'media_id': mediaId,
      'created_at': now,
      'server_ts': null,
      'status': _sync.isOnline ? 'sending' : 'pending',
    };
    await LocalRepository.instance.insertMessage(msg);
    // Copie du fichier dans le répertoire privé (disponible hors ligne
    // immédiatement pour l'expéditeur).
    await MediaStore.instance.register(
      id: mediaId,
      messageLocalId: msg['local_id'] as String,
      mime: _mimeOf(file.path),
      fileName: file.path.split('/').last,
      sizeBytes: await file.length(),
      uploadState: 'pending',
    );
    await LocalRepository.instance.enqueue(
      opType: 'send_media',
      entity: 'messages',
      entityId: msg['local_id'] as String,
      payload: {
        'peer': peer,
        'kind': kind,
        'client_id': clientId,
        'file_path': file.path,
        'mime': _mimeOf(file.path),
      },
      dedupeKey: 'send_media:$clientId',
    );
    if (_sync.isOnline) await _sync.flushQueue();
    return msg;
  }

  String _mimeOf(String path) {
    final ext = path.toLowerCase().split('.').last;
    return switch (ext) {
      'jpg' || 'jpeg' || 'png' || 'webp' || 'gif' => 'image/$ext',
      'mp4' || 'mov' => 'video/$ext',
      'mp3' || 'm4a' || 'aac' || 'ogg' => 'audio/$ext',
      'pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };
  }

  /// Journalise un appel localement (consultable hors connexion) et enfile
  /// la synchro si le serveur doit le recevoir.
  Future<void> logCall({
    required String peer,
    required String direction, // in | out
    required String callKind,  // app | gsm
    required int startedAt,
    int durationSec = 0,
    String status = 'pending',
    String provider = '',
  }) async {
    final localId = await LocalRepository.instance.insertCall({
      'server_id': null,
      'peer_phone': peer,
      'direction': direction,
      'call_kind': callKind,
      'started_at': startedAt,
      'duration_sec': durationSec,
      'status': status,
      'provider': provider,
      'sync_state': 'pending',
    });
    if (direction == 'in') {
      await LocalRepository.instance.enqueue(
        opType: 'log_call',
        entity: 'calls',
        entityId: localId,
        payload: {'direction': 'in', 'from': peer, 'billed_sec': durationSec},
        dedupeKey: 'log_call:$localId',
      );
    }
    if (_sync.isOnline) await _sync.flushQueue();
  }

  /// Marque une conversation comme lue (local immédiat + synchro).
  Future<void> markRead(String peer) async {
    await LocalRepository.instance.setUnread(peer, 0);
    await LocalRepository.instance.enqueue(
      opType: 'mark_read',
      entity: 'conversations',
      entityId: peer,
      payload: {},
      dedupeKey: 'mark_read:$peer:${DateTime.now().millisecondsSinceEpoch ~/ 60000}',
    );
    if (_sync.isOnline) await _sync.flushQueue();
  }

  /// Supprime un message « pour tout le monde » (expéditeur) — file d'attente.
  Future<void> deleteForAll(String serverId, String localId) async {
    await LocalRepository.instance.updateMessage(localId, {
      'deleted_all': 1,
      'status': 'failed', // masqué localement en attendant confirmation
    });
    await LocalRepository.instance.enqueue(
      opType: 'delete_message',
      entity: 'messages',
      entityId: serverId,
      payload: {},
      dedupeKey: 'delete:$serverId',
    );
    if (_sync.isOnline) await _sync.flushQueue();
  }

  /// Programme un rappel « appeler plus tard » — persisté localement et
  /// envoyé au serveur dès le retour de la connexion (file de synchro).
  Future<void> scheduleCallLater(String phone,
      {String? name, required DateTime at}) async {
    final key = 'dial_later:$phone:${at.millisecondsSinceEpoch}';
    await LocalRepository.instance.enqueue(
      opType: 'dial_later',
      entity: 'calls',
      entityId: key,
      payload: {
        'target_phone': phone,
        'target_name': name ?? '',
        'scheduled_at': at.millisecondsSinceEpoch,
        'tz_offset': DateTime.now().timeZoneOffset.inMinutes,
      },
      dedupeKey: key,
    );
    if (_sync.isOnline) await _sync.flushQueue();
  }

  /// 🔔 Active/annule le rappel de présence « <phone> revient en ligne ».
  ///
  /// 🏠 LOCAL-FIRST : l'état est d'abord écrit localement (affichage
  /// immédiat, même hors connexion), puis l'opération est mise en file et
  /// envoyée au serveur dès la reconnexion.
  Future<void> rappelEnLigne(String phone,
      {required bool on, String? name}) async {
    await RappelLigne.setActive(phone, on);
    final key = 'presence_reminder:$phone:$on';
    await LocalRepository.instance.enqueue(
      opType: 'presence_reminder',
      entity: 'contacts',
      entityId: key,
      payload: {
        'target_phone': phone,
        'target_name': name ?? '',
        'on': on,
      },
      dedupeKey: key,
    );
    if (_sync.isOnline) await _sync.flushQueue();
  }

  /// Numéros fréquents depuis l'historique LOCAL (fonctionne hors ligne).
  Future<List<Map<String, dynamic>>> recentNumbers({int limit = 8}) =>
      LocalRepository.instance.recentNumbers(limit: limit);

  /// Télécharge un média à la demande (consultation hors ligne ensuite).
  Future<String> downloadMedia(String mediaId) =>
      MediaStore.instance.download(mediaId, api);

  /// Chemin local d'un média déjà téléchargé (null = nécessite Internet).
  Future<String?> offlineMediaPath(String mediaId) =>
      MediaStore.instance.localPathOf(mediaId);
}
