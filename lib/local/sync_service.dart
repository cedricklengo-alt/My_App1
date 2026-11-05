import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../api.dart';
import 'local_db.dart';
import 'repository.dart';
import 'media_store.dart';

/// ============================================================
///  SERVICE DE SYNCHRONISATION — MboteCall
/// ============================================================
///
/// Responsabilités :
///  1. Traiter la file persistante [sync_queue] (envoi des messages en
///     attente, médias, appels, lectures) avec backoff exponentiel + jitter.
///  2. Tirer les nouveautés du serveur (messages reçus hors ligne, fils,
///     appels, solde) via des curseurs stockés dans [sync_state].
///  3. Télécharger les médias à la demande et les garder consultables
///     hors connexion (via [MediaStore]).
///
/// Garanties :
///  - idempotence (client_id côté serveur + dedupe_key côté file) ;
///  - reprise après interruption (curseur enregistré APRÈS persistance) ;
///  - aucune perte silencieuse : échec définitif → statut 'failed', jamais
///    supprimé automatiquement de la file.
class SyncService {
  SyncService({required Api api, this.repo = const _DefaultRepo()}) : _api = api;
  Api _api;
  Api get api => _api;
  final dynamic repo; // LocalRepository (typé dynamiquement pour les tests)

  static final SyncService instance = SyncService(api: Api());

  /// Branche l'API réelle (avec jeton) sur le singleton utilisé par l'UI.
  void attach(Api a) => _api = a;

  final _online = StreamController<bool>.broadcast();
  Stream<bool> get onlineStream => _online.stream;
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Timer? _queueTimer;
  Timer? _pollTimer;
  StreamSubscription? _connSub;
  bool _running = false;

  static const int maxAttempts = 12;
  static const int baseBackoffMs = 2000;
  static const int maxBackoffMs = 15 * 60 * 1000; // 15 min max

  // ---------------------------------------------------------------
  //  DÉMARRAGE
  // ---------------------------------------------------------------

  Future<void> start() async {
    // État initial de la connectivité.
    try {
      final r = await Connectivity().checkConnectivity();
      _setOnline(r != ConnectivityResult.none);
    } catch (_) {}
    _connSub = Connectivity().onConnectivityChanged.listen((r) {
      final online = r != ConnectivityResult.none;
      _setOnline(online);
      if (online) {
        // Retour d'Internet : synchro immédiate de rattrapage.
        unawaited(flushQueue());
        unawaited(pullServerState());
      }
    });
    // Boucle de la file (toutes les 15 s si des opérations attendent).
    _queueTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isOnline) unawaited(flushQueue());
    });
    // Tirage périodique (file de secours si le temps réel/push manque).
    _pollTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_isOnline) unawaited(pullServerState());
    });
    if (_isOnline) {
      unawaited(pullServerState());
      unawaited(flushQueue());
    }
  }

  void _setOnline(bool v) {
    if (_isOnline == v) return;
    _isOnline = v;
    _online.add(v);
  }

  void stop() {
    _queueTimer?.cancel();
    _pollTimer?.cancel();
    _connSub?.cancel();
  }

  // ---------------------------------------------------------------
  //  FILE SORTANTE
  // ---------------------------------------------------------------

  /// Traite les opérations en attente. Jamais deux exécutions simultanées.
  Future<void> flushQueue() async {
    if (_running || !_isOnline) return;
    _running = true;
    try {
      while (true) {
        final ops = await repo.pendingOps();
        if (ops.isEmpty) break;
        var progressed = false;
        for (final op in ops) {
          if (!_isOnline) break;
          progressed = true;
          await _processOp(op);
        }
        if (!progressed) break;
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _processOp(Map<String, dynamic> op) async {
    final id = op['id'] as int;
    final type = op['op_type'] as String;
    final entityId = op['entity_id'] as String;
    final payload =
        jsonDecode((op['payload'] as String).isEmpty ? '{}' : op['payload'] as String)
            as Map<String, dynamic>;
    await repo.updateOp(id, {'status': 'running'});
    try {
      switch (type) {
        case 'send_message':
          await _sendMessageOp(entityId, payload);
          break;
        case 'send_media':
          await _sendMediaOp(entityId, payload);
          break;
        case 'delete_message':
          await api.deleteMessageForAll(entityId);
          break;
        case 'mark_read':
          await api.markConversationRead(entityId);
          break;
        case 'log_call':
          await _logCallOp(payload);
          break;
        case 'dial_later':
          // Rappel programmé : envoyé au serveur dès que possible.
          await api.dialLater(
            payload['target_phone'] as String,
            targetName: payload['target_name'] as String?,
            scheduledAt: (payload['scheduled_at'] as num).toInt(),
            tzOffset: (payload['tz_offset'] as num?)?.toInt() ?? 0,
          );
          break;
        case 'presence_reminder':
          // 🔔 Rappel « reviens en ligne » : activé/annulé côté serveur.
          if (payload['on'] == true) {
            await api.setPresenceReminder(payload['target_phone'] as String);
          } else {
            await api.deletePresenceReminder(payload['target_phone'] as String);
          }
          break;
        case 'upload_media':
          await MediaStore.instance.upload(entityId, api);
          break;
        default:
          throw UnimplementedError('op $type');
      }
      await repo.updateOp(id, {'status': 'done'});
    } on ApiException catch (e) {
      await _handleFailure(id, op, e.code == 'offline' || e.code == 'timeout'
          ? _isRetryable(e)
          : _isRetryable(e), e.message);
    } catch (e) {
      await _handleFailure(id, op, _isRetryable(e), '$e');
    }
  }

  bool _isRetryable(Object e) {
    if (e is ApiException) {
      // Erreurs réseau = retentable ; 4xx métier = définitif.
      return e.code == 'offline' || e.code == 'timeout' || e.code == null;
    }
    if (e is SocketException) return true;
    return false;
  }

  Future<void> _handleFailure(
      int id, Map<String, dynamic> op, bool retryable, String message) async {
    final attempts = (op['attempts'] as int? ?? 0) + 1;
    if (!retryable || attempts >= maxAttempts) {
      // Échec définitif : on CONSERVE l'opération (pas de perte silencieuse)
      // et on marque le message correspondant en échec pour l'UI.
      await repo.updateOp(id, {
        'status': 'failed_definitive',
        'attempts': attempts,
        'last_error': message,
      });
      if (op['entity'] == 'messages') {
        await repo.updateMessage(op['entity_id'] as String, {'status': 'failed'});
      }
      return;
    }
    final backoff = _backoff(attempts);
    await repo.updateOp(id, {
      'status': 'pending',
      'attempts': attempts,
      'next_attempt': DateTime.now().millisecondsSinceEpoch + backoff,
      'last_error': message,
    });
  }

  /// Backoff exponentiel avec jitter (évite les tentatives simultanées).
  int _backoff(int attempts) {
    final exp = baseBackoffMs * (1 << (attempts - 1));
    final capped = exp > maxBackoffMs ? maxBackoffMs : exp;
    final jitter = Random().nextInt(capped ~/ 2);
    return capped + jitter;
  }

  Future<void> _sendMessageOp(String localId, Map<String, dynamic> payload) async {
    // Déduplication : si le serveur a déjà ce client_id, on récupère la ligne.
    final clientId = payload['client_id'] as String;
    final existing = await repo.findByClientId(clientId);
    if (existing != null && existing['server_id'] != null) {
      return; // déjà envoyé et confirmé
    }
    final row = await api.sendMessage(
      payload['peer'] as String,
      payload['body'] as String,
      clientId: clientId,
      kind: payload['kind'] as String? ?? 'text',
    );
    await repo.updateMessage(localId, {
      'server_id': '${row['id']}',
      'status': 'sent',
      'server_ts': row['created_at'] is int
          ? row['created_at'] as int
          : DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _sendMediaOp(String localId, Map<String, dynamic> payload) async {
    final clientId = payload['client_id'] as String;
    final existing = await repo.findByClientId(clientId);
    if (existing != null && existing['server_id'] != null) return;
    final f = File(payload['file_path'] as String);
    final bytes = await f.readAsBytes();
    final name = f.path.split('/').last;
    final row = await api.sendMessageMedia(
      payload['peer'] as String,
      bytes: bytes,
      kind: payload['kind'] as String,
      mime: payload['mime'] as String? ?? 'application/octet-stream',
      name: name,
      clientId: clientId,
    );
    await repo.updateMessage(localId, {
      'server_id': '${row['id']}',
      'status': 'sent',
    });
  }

  Future<void> _logCallOp(Map<String, dynamic> payload) async {
    // L'historique d'appels est en lecture seule côté client : le serveur
    // est la source de vérité. On pousse juste l'évènement « appel reçu ».
    if (payload['direction'] == 'in') {
      await api.logIncoming(payload['from'] as String,
          (payload['billed_sec'] as num?)?.toInt() ?? 0);
    }
  }

  // ---------------------------------------------------------------
  //  TIRAGE SERVEUR (entrantes)
  // ---------------------------------------------------------------

  /// Récupère les nouveautés depuis le dernier curseur. Idempotent :
  /// le curseur n'avance qu'après persistance réussie.
  Future<void> pullServerState() async {
    if (!_isOnline) return;
    try {
      await _pullThreads();
      await _pullMessagesSince();
      await _pullCallsSince();
      await repo.setState('last_sync_ok',
          DateTime.now().millisecondsSinceEpoch.toString());
    } on ApiException catch (e) {
      if (e.code == 'offline') return; // on retentera à la reconnexion
      rethrow;
    }
  }

  Future<void> _pullThreads() async {
    final threads = await api.messageThreads();
    for (final t in threads) {
      final peer = '${t['peer_phone'] ?? t['phone'] ?? ''}';
      if (peer.isEmpty) continue;
      final db = await LocalDb.instance.db;
      final existing = await db.query('conversations',
          columns: ['unread_count', 'pinned', 'archived', 'hidden'],
          where: 'peer_phone=?',
          whereArgs: [peer]);
      await db.insert(
        'conversations',
        {
          'peer_phone': peer,
          'peer_name': '${t['peer_name'] ?? t['name'] ?? peer}',
          'last_body': '${t['last_body'] ?? ''}',
          'last_kind': '${t['last_kind'] ?? 'text'}',
          'last_at': (t['last_at'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
          'unread_count':
              existing.isEmpty ? (t['unread'] ?? 0) as int : existing.first['unread_count'] as int,
          'pinned': existing.isEmpty ? 0 : existing.first['pinned'] as int,
          'archived': existing.isEmpty ? 0 : existing.first['archived'] as int,
          'hidden': existing.isEmpty ? 0 : existing.first['hidden'] as int,
          'last_sync_at': DateTime.now().millisecondsSinceEpoch,
          'sync_state': 'ok',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await repo.refreshThreads();
  }

  Future<void> _pullMessagesSince() async {
    final sinceStr = await repo.getState('cursor_messages');
    final since = sinceStr == null ? 0 : int.tryParse(sinceStr) ?? 0;
    final r = await api.messagesSince(since);
    final items = (r['items'] as List? ?? []).cast<Map<String, dynamic>>();
    int maxTs = since;
    for (final m in items) {
      final serverId = '${m['id']}';
      // Déduplication par id serveur puis par client_id.
      if (await repo.findByServerId(serverId) != null) continue;
      final clientId = m['client_id']?.toString();
      if (clientId != null && clientId.isNotEmpty) {
        final byClient = await repo.findByClientId(clientId);
        if (byClient != null) {
          // Le serveur confirme notre envoi : on raccorde l'id serveur.
          await repo.updateMessage(byClient['local_id'] as String, {
            'server_id': serverId,
            'status': _serverStatusToLocal(m['status']),
            'server_ts': (m['created_at'] as num?)?.toInt(),
          });
          continue;
        }
      }
      final peer = m['peer_phone'] as String;
      await repo.insertMessage({
        'server_id': serverId,
        'peer_phone': peer,
        'sender_id': '${m['sender_id'] ?? m['from_id'] ?? ''}',
        'recipient_id': '${m['recipient_id'] ?? m['to_id'] ?? ''}',
        'client_id': clientId,
        'kind': m['kind'] ?? 'text',
        'body': m['body'] ?? '',
        'translation': m['translation'],
        'created_at': (m['created_at'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        'server_ts': (m['created_at'] as num?)?.toInt(),
        'status': _serverStatusToLocal(m['status']),
      });
      final ts = (m['created_at'] as num?)?.toInt() ?? 0;
      if (ts > maxTs) maxTs = ts;
    }
    // Curseur avancé UNIQUEMENT après persistance de tout le lot.
    if (items.isNotEmpty) await repo.setState('cursor_messages', '$maxTs');
  }

  Future<void> _pullCallsSince() async {
    final sinceStr = await repo.getState('cursor_calls');
    final since = sinceStr == null ? 0 : int.tryParse(sinceStr) ?? 0;
    final r = await api.history(limit: 200, since: since);
    final items = (r['items'] as List? ?? r['calls'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    int maxTs = since;
    for (final c in items) {
      final serverId = '${c['id']}';
      final db = await LocalDb.instance.db;
      final exists = await db.query('calls',
          columns: ['local_id'], where: 'server_id=?', whereArgs: [serverId], limit: 1);
      if (exists.isNotEmpty) continue; // déduplication
      await repo.insertCall({
        'server_id': serverId,
        'peer_phone': '${c['callee'] ?? c['peer_phone'] ?? ''}',
        'peer_name': '${c['peer_name'] ?? ''}',
        'direction': c['direction'] ?? 'out',
        'call_kind': (c['destination'] != null) ? 'gsm' : 'app',
        'started_at': (c['started_at'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        'duration_sec': (c['billed_sec'] as num?)?.toInt() ?? 0,
        'status': _callStatusToLocal(c['status']),
        'provider': (c['destination'] != null) ? 'twilio' : '',
        'billed_sec': (c['billed_sec'] as num?)?.toInt() ?? 0,
        'cost_cents': (c['cost_cents'] as num?)?.toInt() ?? 0,
        'sync_state': 'synced',
      });
      final ts = (c['started_at'] as num?)?.toInt() ?? 0;
      if (ts > maxTs) maxTs = ts;
    }
    if (items.isNotEmpty) await repo.setState('cursor_calls', '$maxTs');
  }

  String _serverStatusToLocal(Object? s) {
    switch ('$s') {
      case 'sent': return 'sent';
      case 'delivered': return 'delivered';
      case 'read': return 'read';
      case 'failed': return 'failed';
      default: return 'sent';
    }
  }

  String _callStatusToLocal(Object? s) {
    switch ('$s') {
      case 'completed':
      case 'answered': return 'completed';
      case 'missed':
      case 'no_answer': return 'missed';
      case 'busy':
      case 'refused': return 'refused';
      case 'failed': return 'failed';
      case 'canceled': return 'canceled';
      default: return 'pending';
    }
  }
}

class _DefaultRepo {
  const _DefaultRepo();
  // Façade vers le singleton pour permettre l'injection en test.
  Future<List<Map<String, dynamic>>> pendingOps({int limit = 20}) =>
      LocalRepository.instance.pendingOps(limit: limit);
  Future<void> updateOp(int id, Map<String, dynamic> patch) =>
      LocalRepository.instance.updateOp(id, patch);
  Future<void> updateMessage(String localId, Map<String, dynamic> patch) =>
      LocalRepository.instance.updateMessage(localId, patch);
  Future<Map<String, dynamic>?> findByServerId(String id) =>
      LocalRepository.instance.findByServerId(id);
  Future<Map<String, dynamic>?> findByClientId(String id) =>
      LocalRepository.instance.findByClientId(id);
  Future<void> insertMessage(Map<String, dynamic> m) =>
      LocalRepository.instance.insertMessage(m);
  Future<void> insertCall(Map<String, dynamic> c) =>
      LocalRepository.instance.insertCall(c);
  Future<void> setState(String k, String v) =>
      LocalRepository.instance.setState(k, v);
  Future<String?> getState(String k) => LocalRepository.instance.getState(k);
  Future<void> refreshThreads() async {
    await LocalRepository.instance.listThreads();
  }
}
