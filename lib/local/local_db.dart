import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// ============================================================
///  BASE DE DONNÉES LOCALE — MboteCall (architecture Local-First)
/// ============================================================
///
/// La base locale est la SOURCE D'AFFICHAGE de l'application :
///   UI → Repository → Base locale (sqflite)
/// Le réseau n'est utilisé qu'en arrière-plan pour synchroniser.
///
/// Schéma (version 1) :
///   - conversations : un fil par correspondant (téléphone peer)
///   - messages      : texte / image / vidéo / audio / fichier / voix
///   - calls         : historique des appels (app↔app et app→GSM/Twilio)
///   - media         : pièces jointes (métadonnées + chemin local)
///   - sync_queue    : opérations en attente de synchronisation
///   - sync_state    : curseurs et état global de synchro (clé/valeur)
///
/// Aucune donnée sensible (mot de passe, secret Twilio, clé API, jeton
/// de paiement) n'est jamais stockée ici.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  static const int schemaVersion = 1;
  Database? _db;

  Future<Database> get db async {
    final d = _db;
    if (d != null && d.isOpen) return d;
    return _open();
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'mbote_local.db');
    final db = await openDatabase(
      path,
      version: schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      singleInstance: true,
    );
    _db = db;
    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // ---- Conversations -------------------------------------------------
    batch.execute('''
      CREATE TABLE conversations (
        peer_phone     TEXT PRIMARY KEY,          -- identifiant stable du fil
        peer_name      TEXT NOT NULL DEFAULT '',
        last_body      TEXT NOT NULL DEFAULT '',
        last_kind      TEXT NOT NULL DEFAULT 'text',
        last_at        INTEGER NOT NULL DEFAULT 0, -- ms epoch
        unread_count   INTEGER NOT NULL DEFAULT 0,
        pinned         INTEGER NOT NULL DEFAULT 0,
        archived       INTEGER NOT NULL DEFAULT 0,
        hidden         INTEGER NOT NULL DEFAULT 0, -- supprimée « pour moi »
        last_sync_at   INTEGER NOT NULL DEFAULT 0,
        sync_state     TEXT NOT NULL DEFAULT 'ok'  -- ok | pending | error
      )
    ''');

    // ---- Messages ------------------------------------------------------
    batch.execute('''
      CREATE TABLE messages (
        local_id       TEXT PRIMARY KEY,           -- UUID généré côté client
        server_id      TEXT,                       -- null tant que le serveur n'a pas répondu
        peer_phone     TEXT NOT NULL,              -- fil auquel appartient le message
        sender_id      TEXT NOT NULL,              -- id serveur de l'expéditeur
        recipient_id   TEXT NOT NULL,
        client_id      TEXT,                       -- idempotence (unique côté serveur)
        kind           TEXT NOT NULL DEFAULT 'text', -- text|image|video|audio|voice|file
        body           TEXT NOT NULL DEFAULT '',
        translation    TEXT,
        media_id       TEXT,                       -- FK media.id (nullable)
        created_at     INTEGER NOT NULL,           -- ms epoch (création locale)
        server_ts      INTEGER,                    -- ms epoch (horodatage serveur)
        status         TEXT NOT NULL DEFAULT 'pending',
        -- pending | sending | sent | delivered | read | failed
        deleted_me     INTEGER NOT NULL DEFAULT 0,
        deleted_all    INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute(
        'CREATE UNIQUE INDEX idx_messages_client ON messages(client_id) '
        'WHERE client_id IS NOT NULL');
    batch.execute(
        'CREATE INDEX idx_messages_peer ON messages(peer_phone, created_at)');
    batch.execute(
        'CREATE UNIQUE INDEX idx_messages_server ON messages(server_id) '
        'WHERE server_id IS NOT NULL');

    // ---- Historique des appels -----------------------------------------
    batch.execute('''
      CREATE TABLE calls (
        local_id       TEXT PRIMARY KEY,
        server_id      TEXT,
        peer_phone     TEXT NOT NULL DEFAULT '',   -- correspondant (ou numéro GSM)
        peer_name      TEXT NOT NULL DEFAULT '',
        direction      TEXT NOT NULL DEFAULT 'out', -- in | out
        call_kind      TEXT NOT NULL DEFAULT 'app', -- app | gsm (Twilio)
        started_at     INTEGER NOT NULL,
        duration_sec   INTEGER NOT NULL DEFAULT 0,
        status         TEXT NOT NULL DEFAULT 'pending',
        -- pending | completed | missed | refused | failed | canceled
        provider       TEXT NOT NULL DEFAULT '',   -- ex. 'twilio' pour le GSM
        billed_sec     INTEGER NOT NULL DEFAULT 0,
        cost_cents     INTEGER NOT NULL DEFAULT 0,
        sync_state     TEXT NOT NULL DEFAULT 'synced' -- synced | pending | error
      )
    ''');
    batch.execute(
        'CREATE INDEX idx_calls_started ON calls(started_at DESC)');
    batch.execute(
        'CREATE UNIQUE INDEX idx_calls_server ON calls(server_id) '
        'WHERE server_id IS NOT NULL');

    // ---- Médias (métadonnées ; les octets vivent dans le système de
    //      fichiers privé de l'app, cf. MediaStore) ----------------------
    batch.execute('''
      CREATE TABLE media (
        id             TEXT PRIMARY KEY,           -- id serveur du message média, ou UUID local
        message_local_id TEXT,                     -- FK messages.local_id
        mime           TEXT NOT NULL DEFAULT '',
        file_name      TEXT NOT NULL DEFAULT '',
        size_bytes     INTEGER NOT NULL DEFAULT 0,
        local_path     TEXT,                       -- null = pas encore téléchargé
        remote_url     TEXT NOT NULL DEFAULT '',
        thumb_path     TEXT,
        sha256         TEXT,
        download_state TEXT NOT NULL DEFAULT 'none', -- none | downloading | done | failed
        upload_state   TEXT NOT NULL DEFAULT 'none', -- none | pending | uploading | done | failed
        created_at     INTEGER NOT NULL
      )
    ''');

    // ---- File de synchronisation (opérations sortantes) ----------------
    batch.execute('''
      CREATE TABLE sync_queue (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        op_type        TEXT NOT NULL,              -- send_message | send_media | delete_message | mark_read | log_call | upload_media | reconcile_wallet
        entity         TEXT NOT NULL,              -- table concernée
        entity_id      TEXT NOT NULL,              -- local_id de l'entité
        payload        TEXT NOT NULL DEFAULT '{}', -- JSON minimal
        dedupe_key     TEXT,                       -- évite les doublons de file
        created_at     INTEGER NOT NULL,
        attempts       INTEGER NOT NULL DEFAULT 0,
        next_attempt   INTEGER NOT NULL DEFAULT 0,
        last_error     TEXT NOT NULL DEFAULT '',
        status         TEXT NOT NULL DEFAULT 'pending'
        -- pending | running | done | failed_definitive
      )
    ''');
    batch.execute(
        'CREATE UNIQUE INDEX idx_queue_dedupe ON sync_queue(dedupe_key) '
        'WHERE dedupe_key IS NOT NULL');
    batch.execute(
        'CREATE INDEX idx_queue_next ON sync_queue(status, next_attempt)');

    // ---- État de synchronisation (clé / valeur) ------------------------
    batch.execute('''
      CREATE TABLE sync_state (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL DEFAULT ''
      )
    ''');

    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    // Migrations contrôlées et documentées. Aucune suppression de données.
    for (var v = oldV + 1; v <= newV; v++) {
      switch (v) {
        case 1:
          break; // schéma initial
      }
    }
  }

  /// Vide TOUTES les données locales (déconnexion avec suppression, ou
  /// changement de compte). Appelé explicitement, jamais automatiquement.
  Future<void> wipeAll() async {
    final d = await db;
    final batch = d.batch();
    for (final t in [
      'messages',
      'conversations',
      'calls',
      'media',
      'sync_queue',
      'sync_state',
    ]) {
      batch.delete(t);
    }
    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    final d = _db;
    _db = null;
    if (d != null && d.isOpen) await d.close();
  }
}
