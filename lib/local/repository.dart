import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'local_db.dart';

/// ============================================================
///  REPOSITORY LOCAL-FIRST
/// ============================================================
///
/// Règle fondamentale : l'UI lit TOUJOURS ici (base locale) et observe
/// les changements via [stream]. Le réseau n'intervient que dans
/// [SyncService] (arrière-plan). Un serveur vide ou une erreur réseau
/// ne vide JAMAIS les données locales.
class LocalRepository {
  LocalRepository._();
  static final LocalRepository instance = LocalRepository._();

  final _threadsCtrl =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final _msgCtrl =
      StreamController<String>.broadcast(); // émet peer_phone modifié
  final _callsCtrl =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  /// Flux réactifs exposés à l'UI.
  Stream<List<Map<String, dynamic>>> threadsStream() async* {
    yield await listThreads();
    yield* _threadsCtrl.stream;
  }

  Stream<String> messagesChanged() => _msgCtrl.stream;
  Stream<List<Map<String, dynamic>>> callsStream() async* {
    yield await listCalls();
    yield* _callsCtrl.stream;
  }

  // ---------------------------------------------------------------
  //  CONVERSATIONS
  // ---------------------------------------------------------------

  Future<List<Map<String, dynamic>>> listThreads() async {
    final db = await LocalDb.instance.db;
    return db.query(
      'conversations',
      where: 'hidden = 0',
      orderBy: 'pinned DESC, last_at DESC',
    );
  }

  /// Insère/met à jour un fil à partir d'un message (local ou serveur).
  Future<void> upsertThreadFromMessage(Map<String, dynamic> m) async {
    final db = await LocalDb.instance.db;
    final peer = m['peer_phone'] as String;
    final existing = await db.query('conversations',
        columns: ['peer_phone', 'unread_count'], where: 'peer_phone=?', whereArgs: [peer]);
    final unread = (existing.isEmpty ? 0 : (existing.first['unread_count'] as int)) ;
    await db.insert(
      'conversations',
      {
        'peer_phone': peer,
        'peer_name': m['peer_name'] ?? '',
        'last_body': m['kind'] == 'text' ? (m['body'] ?? '') : _kindLabel(m['kind']),
        'last_kind': m['kind'] ?? 'text',
        'last_at': m['server_ts'] ?? m['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
        'unread_count': unread,
        'pinned': existing.isEmpty ? 0 : (await db.query('conversations',
                columns: ['pinned'], where: 'peer_phone=?', whereArgs: [peer])).first['pinned'],
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _threadsCtrl.add(await listThreads());
  }

  /// Libellé SANS emoji (mission design : les emojis affichés sont remplacés
  /// par des icônes Material à l'endroit de l'affichage — voir chats.dart).
  String _kindLabel(Object? kind) {
    switch (kind) {
      case 'image': return 'Photo';
      case 'video': return 'Vidéo';
      case 'audio': return 'Audio';
      case 'voice': return 'Note vocale';
      case 'file': return 'Fichier';
      default: return '';
    }
  }

  Future<void> setUnread(String peer, int count) async {
    final db = await LocalDb.instance.db;
    await db.update('conversations', {'unread_count': count},
        where: 'peer_phone=?', whereArgs: [peer]);
    _threadsCtrl.add(await listThreads());
  }

  // ---------------------------------------------------------------
  //  MESSAGES
  // ---------------------------------------------------------------

  /// Messages d'un fil, du plus ancien au plus récent (ordre d'affichage).
  Future<List<Map<String, dynamic>>> listMessages(String peer,
      {int limit = 50, int? before}) async {
    final db = await LocalDb.instance.db;
    final args = <Object?>[peer];
    var where = 'peer_phone=? AND deleted_me=0 AND deleted_all=0';
    if (before != null) {
      where += ' AND created_at < ?';
      args.add(before);
    }
    final rows = await db.query('messages',
        where: where, whereArgs: args, orderBy: 'created_at DESC, local_id DESC', limit: limit);
    return rows.reversed.toList();
  }

  /// Enregistre un message localement (transaction atomique avec la file
  /// de synchro quand il s'agit d'un envoi). Retourne le local_id.
  Future<String> insertMessage(Map<String, dynamic> m) async {
    final db = await LocalDb.instance.db;
    final localId = (m['local_id'] as String?) ??
        DateTime.now().millisecondsSinceEpoch.toString() + '_' + (m['client_id'] ?? '');
    m['local_id'] = localId;
    await db.insert('messages', m,
        conflictAlgorithm: ConflictAlgorithm.replace);
    _msgCtrl.add(m['peer_phone'] as String);
    await upsertThreadFromMessage(m);
    return localId;
  }

  /// Met à jour le statut / l'id serveur d'un message (après confirmation).
  Future<void> updateMessage(String localId,
      Map<String, dynamic> patch) async {
    final db = await LocalDb.instance.db;
    await db.update('messages', patch, where: 'local_id=?', whereArgs: [localId]);
    final row = await db.query('messages',
        columns: ['peer_phone'], where: 'local_id=?', whereArgs: [localId]);
    if (row.isNotEmpty) {
      _msgCtrl.add(row.first['peer_phone'] as String);
      final m = await db.query('messages', where: 'local_id=?', whereArgs: [localId]);
      if (m.isNotEmpty) await upsertThreadFromMessage(m.first);
    }
  }

  /// Déduplication : retrouve un message par son id serveur.
  Future<Map<String, dynamic>?> findByServerId(String serverId) async {
    final db = await LocalDb.instance.db;
    final rows = await db.query('messages',
        where: 'server_id=?', whereArgs: [serverId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Déduplication : retrouve un message par client_id (idempotence).
  Future<Map<String, dynamic>?> findByClientId(String clientId) async {
    final db = await LocalDb.instance.db;
    final rows = await db.query('messages',
        where: 'client_id=?', whereArgs: [clientId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  // ---------------------------------------------------------------
  //  APPELS
  // ---------------------------------------------------------------

  Future<List<Map<String, dynamic>>> listCalls({String filter = 'all'}) async {
    final db = await LocalDb.instance.db;
    var where = '';
    final args = <Object?>[];
    switch (filter) {
      case 'in': where = 'direction=?'; args.add('in'); break;
      case 'out': where = 'direction=?'; args.add('out'); break;
      case 'missed':
        where = 'status IN (?,?)'; args.addAll(['missed', 'failed']); break;
      case 'internet': where = 'call_kind=?'; args.add('app'); break;
      case 'gsm': where = 'call_kind=?'; args.add('gsm'); break;
    }
    final rows = await db.query('calls',
        where: where.isEmpty ? null : where,
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'started_at DESC',
        limit: 200);
    return rows;
  }

  Future<String> insertCall(Map<String, dynamic> c) async {
    final db = await LocalDb.instance.db;
    final localId = (c['local_id'] as String?) ??
        'call_${DateTime.now().millisecondsSinceEpoch}_${c.hashCode.abs()}';
    c['local_id'] = localId;
    await db.insert('calls', c, conflictAlgorithm: ConflictAlgorithm.replace);
    _callsCtrl.add(await listCalls());
    return localId;
  }

  Future<void> updateCall(String localId, Map<String, dynamic> patch) async {
    final db = await LocalDb.instance.db;
    await db.update('calls', patch, where: 'local_id=?', whereArgs: [localId]);
    _callsCtrl.add(await listCalls());
  }

  /// Numéros les plus récents depuis l'historique LOCAL (fréquents) :
  /// consultables hors connexion pour le clavier.
  Future<List<Map<String, dynamic>>> recentNumbers({int limit = 8}) async {
    final db = await LocalDb.instance.db;
    return db.rawQuery('''
      SELECT peer_phone AS phone, MAX(peer_name) AS name, MAX(started_at) AS last_at
      FROM calls
      WHERE peer_phone GLOB '+[0-9]*' AND LENGTH(peer_phone) >= 8
      GROUP BY peer_phone
      ORDER BY last_at DESC
      LIMIT ?
    ''', [limit]);
  }

  // ---------------------------------------------------------------
  //  FILE DE SYNCHRONISATION
  // ---------------------------------------------------------------

  /// Ajoute une opération en file. Si une opération identique (même
  /// dedupe_key) existe déjà, elle n'est PAS recréée (idempotence).
  Future<int?> enqueue({
    required String opType,
    required String entity,
    required String entityId,
    Map payload = const {},
    String? dedupeKey,
  }) async {
    final db = await LocalDb.instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (dedupeKey != null) {
      final existing = await db.query('sync_queue',
          columns: ['id'],
          where: 'dedupe_key=? AND status IN (?,?)',
          whereArgs: [dedupeKey, 'pending', 'running'],
          limit: 1);
      if (existing.isNotEmpty) return existing.first['id'] as int;
    }
    return db.insert('sync_queue', {
      'op_type': opType,
      'entity': entity,
      'entity_id': entityId,
      'payload': jsonEncode(payload),
      'dedupe_key': dedupeKey,
      'created_at': now,
      'next_attempt': now,
      'status': 'pending',
    });
  }

  Future<List<Map<String, dynamic>>> pendingOps({int limit = 20}) async {
    final db = await LocalDb.instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.query('sync_queue',
        where: "status IN ('pending','running') AND next_attempt <= ?",
        whereArgs: [now],
        orderBy: 'created_at ASC',
        limit: limit);
  }

  Future<void> updateOp(int id, Map<String, dynamic> patch) async {
    final db = await LocalDb.instance.db;
    await db.update('sync_queue', patch, where: 'id=?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------
  //  ÉTAT DE SYNC (curseurs)
  // ---------------------------------------------------------------

  Future<String?> getState(String key) async {
    final db = await LocalDb.instance.db;
    final rows =
        await db.query('sync_state', where: 'key=?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setState(String key, String value) async {
    final db = await LocalDb.instance.db;
    await db.insert('sync_state', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  void dispose() {
    _threadsCtrl.close();
    _msgCtrl.close();
    _callsCtrl.close();
  }
}
