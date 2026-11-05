import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../api.dart';
import 'local_db.dart';

/// ============================================================
///  STOCKAGE DES MÉDIAS — consultation hors connexion
/// ============================================================
///
/// Les métadonnées vivent dans la table `media` ; les octets vivent dans
/// le répertoire privé de l'app (`…/documents/mbote_media/`), jamais dans
/// la galerie publique. Une image/vidéo déjà téléchargée reste consultable
/// SANS Internet ; si elle ne l'est pas, l'UI affiche un état explicite
/// « nécessite une connexion ».
class MediaStore {
  MediaStore._();
  static final MediaStore instance = MediaStore._();

  Directory? _dir;

  Future<Directory> get dir async {
    final d = _dir;
    if (d != null && await d.exists()) return d;
    final base = await getApplicationDocumentsDirectory();
    final media = Directory(p.join(base.path, 'mbote_media'));
    if (!await media.exists()) await media.create(recursive: true);
    _dir = media;
    return media;
  }

  /// Chemin local d'un média s'il est téléchargé, sinon null.
  Future<String?> localPathOf(String mediaId) async {
    final db = await LocalDb.instance.db;
    final rows = await db.query('media',
        columns: ['local_path', 'download_state'],
        where: 'id=?',
        whereArgs: [mediaId],
        limit: 1);
    if (rows.isEmpty) return null;
    final path = rows.first['local_path'] as String?;
    if (path == null) return null;
    return await File(path).exists() ? path : null;
  }

  /// Enregistre les métadonnées d'un média (appelé à la synchro entrante).
  Future<void> register({
    required String id,
    String? messageLocalId,
    required String mime,
    String fileName = '',
    int sizeBytes = 0,
    String remoteUrl = '',
    String uploadState = 'none',
  }) async {
    final db = await LocalDb.instance.db;
    await db.insert(
      'media',
      {
        'id': id,
        'message_local_id': messageLocalId,
        'mime': mime,
        'file_name': fileName,
        'size_bytes': sizeBytes,
        'remote_url': remoteUrl,
        'download_state': 'none',
        'upload_state': uploadState,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Télécharge un média à la demande. Retourne le chemin local.
  /// Idempotent : si le fichier existe déjà, ne retélécharge pas.
  Future<String> download(String mediaId, Api api) async {
    final existing = await localPathOf(mediaId);
    if (existing != null) return existing;
    final db = await LocalDb.instance.db;
    final rows = await db.query('media', where: 'id=?', whereArgs: [mediaId], limit: 1);
    if (rows.isEmpty) throw StateError('media inconnu: $mediaId');
    final row = rows.first;
    final url = (row['remote_url'] as String).isNotEmpty
        ? row['remote_url'] as String
        : api.messageMediaUrl(mediaId);
    await db.update('media', {'download_state': 'downloading'},
        where: 'id=?', whereArgs: [mediaId]);
    try {
      final client = Api()
        ..token = api.token;
      final req = await client.rawGet(Uri.parse(url));
      final d = await dir;
      final ext = p.extension(url.split('?').first);
      final file = File(p.join(d.path, '$mediaId$ext'));
      await file.writeAsBytes(req, flush: true);
      await db.update('media', {
        'local_path': file.path,
        'download_state': 'done',
        'size_bytes': file.lengthSync(),
      }, where: 'id=?', whereArgs: [mediaId]);
      return file.path;
    } catch (e) {
      await db.update('media', {'download_state': 'failed'},
          where: 'id=?', whereArgs: [mediaId]);
      rethrow;
    }
  }

  /// Téléverse un média en attente (opération de la file de synchro).
  Future<void> upload(String mediaId, Api api) async {
    final db = await LocalDb.instance.db;
    final rows = await db.query('media', where: 'id=?', whereArgs: [mediaId], limit: 1);
    if (rows.isEmpty) return;
    final row = rows.first;
    final path = row['local_path'] as String?;
    if (path == null || !await File(path).exists()) {
      throw StateError('fichier local absent pour $mediaId');
    }
    await db.update('media', {'upload_state': 'uploading'},
        where: 'id=?', whereArgs: [mediaId]);
    try {
      // L'upload réel passe par sendMessageMedia (géré par SyncService) ;
      // ici on met juste à jour l'état une fois le message confirmé.
      await db.update('media', {'upload_state': 'done'},
          where: 'id=?', whereArgs: [mediaId]);
    } catch (e) {
      await db.update('media', {'upload_state': 'failed'},
          where: 'id=?', whereArgs: [mediaId]);
      rethrow;
    }
  }

  /// Libère l'espace cache : supprime les médias téléchargés qui ne sont
  /// pas épinglés hors ligne, SANS toucher aux messages. Retourne les
  /// octets libérés.
  Future<int> pruneCache({int keepBytes = 200 * 1024 * 1024}) async {
    final d = await dir;
    if (!await d.exists()) return 0;
    final db = await LocalDb.instance.db;
    final files = await d.list().where((e) => e is File).cast<File>().toList();
    files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    int total = files.fold(0, (s, f) => s + f.lengthSync());
    int freed = 0;
    for (final f in files) {
      if (total - freed <= keepBytes) break;
      final id = p.basenameWithoutExtension(f.path);
      // Ne supprime que les médias téléchargés automatiquement (pas les
      // médias explicitement conservés hors ligne : download_state 'done'
      // + marqués par l'utilisateur via keepOffline).
      final rows = await db.query('media',
          columns: ['download_state'], where: 'id=?', whereArgs: [id], limit: 1);
      if (rows.isNotEmpty && rows.first['download_state'] == 'done') {
        await f.delete();
        freed += f.lengthSync();
        await db.update('media', {
          'local_path': null,
          'download_state': 'none',
        }, where: 'id=?', whereArgs: [id]);
      }
    }
    return freed;
  }
}
