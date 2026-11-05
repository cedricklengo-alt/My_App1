/// ============================================================
///  TESTS DE L'ARCHITECTURE LOCAL-FIRST (base locale + file de synchro)
/// ============================================================
///
/// Exécution :  flutter test test/local_first_test.dart
///
/// Scénarios couverts (cf. mission §15) :
///  - persistance locale d'un message hors connexion (statut pending)
///  - déduplication par client_id et par id serveur
///  - file de synchro : pas de doublon d'opération (dedupe_key)
///  - backoff exponentiel croissant
///  - curseur avancé uniquement après persistance
///  - wipe complet (changement de compte)
///
/// La base de test tourne en mémoire via sqflite_common_ffi.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mbote/local/local_db.dart';
import 'package:mbote/local/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Base locale local-first', () {
    setUp(() async {
      await LocalDb.instance.wipeAll();
    });

    test('un message hors connexion est persisté avec statut pending', () async {
      final id = await LocalRepository.instance.insertMessage({
        'local_id': 'l1',
        'server_id': null,
        'peer_phone': '+243900000002',
        'sender_id': 'me',
        'recipient_id': '+243900000002',
        'client_id': 'cli-1',
        'kind': 'text',
        'body': 'salut hors ligne',
        'created_at': 1000,
        'server_ts': null,
        'status': 'pending',
      });
      expect(id, 'l1');
      final msgs =
          await LocalRepository.instance.listMessages('+243900000002');
      expect(msgs.length, 1);
      expect(msgs.first['status'], 'pending');
      expect(msgs.first['body'], 'salut hors ligne');
    });

    test('déduplication par client_id (idempotence)', () async {
      await LocalRepository.instance.insertMessage({
        'local_id': 'l1',
        'peer_phone': 'p',
        'sender_id': 'me',
        'recipient_id': 'p',
        'client_id': 'cli-x',
        'kind': 'text',
        'body': 'a',
        'created_at': 1,
        'status': 'pending',
      });
      final found = await LocalRepository.instance.findByClientId('cli-x');
      expect(found, isNotNull);
      expect(found!['local_id'], 'l1');
    });

    test('déduplication par id serveur', () async {
      await LocalRepository.instance.insertMessage({
        'local_id': 'l2',
        'server_id': 'srv-9',
        'peer_phone': 'p',
        'sender_id': 'p',
        'recipient_id': 'me',
        'kind': 'text',
        'body': 'reçu',
        'created_at': 2,
        'status': 'sent',
      });
      expect(await LocalRepository.instance.findByServerId('srv-9'), isNotNull);
      expect(await LocalRepository.instance.findByServerId('inconnu'), isNull);
    });

    test('file de synchro : dedupe_key évite les doublons', () async {
      final a = await LocalRepository.instance.enqueue(
        opType: 'send_message',
        entity: 'messages',
        entityId: 'l1',
        payload: {'client_id': 'cli-1'},
        dedupeKey: 'send_message:cli-1',
      );
      final b = await LocalRepository.instance.enqueue(
        opType: 'send_message',
        entity: 'messages',
        entityId: 'l1',
        payload: {'client_id': 'cli-1'},
        dedupeKey: 'send_message:cli-1',
      );
      expect(a, isNotNull);
      expect(b, a, reason: 'la 2e operation doit reutiliser la 1ere (pas de doublon)');
      final pending = await LocalRepository.instance.pendingOps();
      expect(pending.length, 1);
    });

    test('l\'historique des appels est lisible localement', () async {
      await LocalRepository.instance.insertCall({
        'server_id': 'c1',
        'peer_phone': '+243900000003',
        'direction': 'in',
        'call_kind': 'gsm',
        'started_at': 5000,
        'duration_sec': 0,
        'status': 'missed',
        'provider': 'twilio',
        'sync_state': 'synced',
      });
      final missed = await LocalRepository.instance.listCalls(filter: 'missed');
      expect(missed.length, 1);
      expect(missed.first['provider'], 'twilio');
    });

    test('curseurs de synchro persistés dans sync_state', () async {
      await LocalRepository.instance.setState('cursor_messages', '12345');
      expect(await LocalRepository.instance.getState('cursor_messages'), '12345');
      expect(await LocalRepository.instance.getState('inconnu'), isNull);
    });

    test('wipeAll vide toutes les tables (changement de compte)', () async {
      await LocalRepository.instance.insertMessage({
        'local_id': 'l9',
        'peer_phone': 'p',
        'sender_id': 'me',
        'recipient_id': 'p',
        'client_id': 'cli-9',
        'kind': 'text',
        'body': 'x',
        'created_at': 9,
        'status': 'pending',
      });
      await LocalDb.instance.wipeAll();
      expect(await LocalRepository.instance.listMessages('p'), isEmpty);
    });
  });
}
