# 🏠 Architecture Local-First / Offline-First — MboteCall

## 1. Architecture découverte (audit)

| Couche | Technologie réelle |
|---|---|
| Framework | **Flutter / Dart** (pas Android natif) — Material, Provider |
| État global | `lib/state.dart` (`AppState` ChangeNotifier) |
| Réseau | `lib/api.dart` (http), temps réel WebSocket `lib/rtc.dart`, push Firebase |
| Persistance AVANT | `shared_preferences` uniquement (token + réglages) — **aucune base locale** |
| Backend | Node.js / Express modulaire (`mbote-backend`), SQLite (`better-sqlite3`) ou PostgreSQL |
| Messagerie | `/api/messages/threads`, `/with/:phone`, `/send` (idempotent via `client_id`), `/send-media` |
| Appels | `/api/calls/history`, Twilio (GSM) + WebRTC (app↔app) |
| Paiements | FlexPaie / PayPay (webhooks côté serveur uniquement) |

## 2. Principe implémenté

```
UI → Écran → LocalRepository → Base locale (sqflite)   ← source d'AFFICHAGE
                              ↘ SyncService → API → serveur  ← arrière-plan uniquement
```

- Les écrans lisent **toujours** la base locale (jamais de spinner bloquant hors ligne).
- Un serveur vide/erreur ne vide **jamais** les données locales.
- Envoi d'un message : UUID local + persistance + opération en file (`sync_queue`) **atomique**, puis envoi si online.
- Retour d'Internet → `connectivity_plus` déclenche `flushQueue()` + `pullServerState()` (curseurs `cursor_messages`, `cursor_calls`).

## 3. Fichiers créés

| Fichier | Rôle |
|---|---|
| `lib/local/local_db.dart` | Schéma sqflite v1 + migrations + `wipeAll()` |
| `lib/local/repository.dart` | Accès local-first + flux réactifs + file de synchro |
| `lib/local/sync_service.dart` | File d'attente, backoff exponentiel + jitter, synchro entrante par curseur |
| `lib/local/media_store.dart` | Médias dans le répertoire privé, téléchargement à la demande, cache |
| `lib/local/local_first.dart` | Façade utilisée par les écrans (sendText/sendMedia/logCall hors ligne) |
| `test/local_first_test.dart` | Tests unitaires de la base locale (sqflite FFI) |
| `ARCHITECTURE-OFFLINE.md` | Ce document |

## 4. Fichiers modifiés

| Fichier | Modification |
|---|---|
| `pubspec.yaml` | + `sqflite`, `connectivity_plus`, `uuid` (+ `sqflite_common_ffi` en dev) |
| `lib/api.dart` | + `messagesSince()`, `rawGet()`, `history(since:)`, `sendMessage(kind:)` |
| `lib/state.dart` | démarrage de `SyncService` à l'ouverture, arrêt au logout, `wipeLocalDataOnAccountSwitch()` |
| `lib/screens/chats.dart` | liste des fils : **locale d'abord**, réseau en complément |
| `lib/screens/chat.dart` | messages : **local d'abord** ; envoi persisté localement + en file |
| `lib/screens/history.dart` | historique des appels : **local d'abord**, filtres compatibles |
| `lib/screens/shell.dart` | bandeau discret « Hors ligne — données locales » |

## 5. Schéma base locale (v1)

- `conversations` (PK `peer_phone`) : dernier message, non-lus, épinglé/archivé, `sync_state`
- `messages` (PK `local_id` UUID, `server_id` nullable UNIQUE, `client_id` UNIQUE) : kind, body, média, statuts `pending/sending/sent/delivered/read/failed`
- `calls` (PK `local_id`, `server_id` UNIQUE) : direction, kind app/gsm, durée, statut, provider
- `media` : métadonnées + `local_path` + états download/upload
- `sync_queue` : op_type, entity, payload JSON, `dedupe_key` UNIQUE, attempts, next_attempt (backoff), status
- `sync_state` : curseurs (`cursor_messages`, `cursor_calls`, `last_sync_ok`)

## 6. Nouveaux contrats API (backend)

| Endpoint | Contrat |
|---|---|
| `GET /api/messages/since?since=<ms>&limit=200` | messages (envoyés/reçus) avec `created_at > since`, tri ASC, `has_more`, champs `peer_phone`, `client_id`, `sender_id`, `recipient_id` |
| `GET /api/calls/history?...&since=<ms>` | filtre `started_at > since` ajouté |

Tests backend : `node test/sync_since.test.js` → **14/14 ✓**

## 7. Sécurité respectée

- Aucun secret (Twilio, clés API, jetons paiement) dans le client ni dans la file de synchro.
- Paiements/wallet : **jamais** crédités depuis le client ; solde hors ligne affiché comme « dernière valeur synchronisée ».
- `wipeAll()` uniquement sur changement de compte explicite ; la déconnexion simple conserve les données.
- Médias dans le stockage **privé** de l'app, jamais la galerie publique.

## 8. Commandes de test

```bash
# Backend (Node) :
cd mbote-backend
node test/sync_since.test.js      # synchro /since + idempotence
node test/messages.test.js         # régression messagerie (87 ✓)
node test/calls.test.js            # régression appels (41 ✓)

# App Flutter (nécessite le SDK Flutter) :
cd My_App1
flutter pub get
flutter test test/local_first_test.dart   # base locale, dédup, file de synchro
flutter analyze                           # analyse statique
flutter build apk --debug                 # build Android
```

## 8b. Onglet Appels — local-first

| Fonction | Comportement hors connexion |
|---|---|
| **Historique des appels** | Lu dans la table locale `calls` (filtres in/out/missed/internet/gsm) — déjà implémenté mission 1, fonctionne sans Internet |
| **Journalisation** | Chaque appel terminé est écrit localement (`LocalFirst.logCall`) même si le serveur est injoignable, puis réconcilié par curseur (`cursor_calls`) |
| **Clavier — récents** | Les 5 derniers numéros viennent de la base locale (`recentNumbers`) quand le champ est vide |
| **Clavier — tarif** | Hors ligne : « Hors ligne — tarif indisponible » (au lieu d'une ligne vide) |
| **Appeler plus tard** | Bouton 🕐 → intention persistée dans `sync_queue` (op `dial_later`, dédupliquée) → envoyée à `POST /api/dial-later` au retour d'Internet |
| **Nouvel appel réel** | Nécessite impérativement le réseau (affiché via le bandeau « Hors ligne » du shell) |

Test backend du contrat : `node test/dial_later.test.js` → **7/7 ✓**

## 8c. Onglet Appels — refonte UX (mission 2)

- **Lignes d'appels plates** (`_CallTile` refondu) : avatar circulaire avec initiale, nom en gras (rouge si manqué), sous-titre avec icône de direction + type + heure + durée, séparateur fin, bouton « rappeler » vert — inspiré de WhatsApp/Telegram, sans carte ni bordure.
- **En-tête allégé** : titre discret + recherche révélée par icône (plus de champ permanent) + bouton clavier.
- **États** : skeleton sans bordure, erreur réseau avec bouton « Réessayer » (le contenu local déjà affiché n'est jamais vidé).

## 9. Limitations connues (à configurer hors de cet environnement)

- **Le SDK Flutter/Dart n'est pas installé dans cet environnement** : le code Dart a été écrit et vérifié par relecture, mais `flutter test` / `flutter build` doivent être lancés localement. Aucune compilation n'a été exécutée ici.
- WorkManager (tâche persistante Android quand l'app est tuée) : à ajouter en dépendance native si besoin ; la synchro couvre déjà le cas app ouverte + retour d'Internet, et le push FCM réveille l'app pour le temps réel.
- Le serveur de production (Render) doit être redéployé pour exposer `/messages/since` et `since` sur `/calls/history`.

## 10. Procédure de test manuel sur 2 smartphones

1. Téléphone A (Alice) et B (Bob) connectés : A envoie « test » à B → reçu.
2. Couper le WiFi/données de A → bandeau « Hors ligne » → A envoie « hors ligne 1 » → bulle « En attente ».
3. Fermer l'app de A (kill) → rouvrir sans Internet → conversations + historique + « hors ligne 1 » toujours visibles.
4. Rallumer Internet sur A → « hors ligne 1 » passe à « envoyé » automatiquement, B le reçoit.
5. Couper Internet sur B, A envoie « pendant absence » → rallumer B → B récupère le message à la synchro.
6. Ouvrir une photo reçue hors ligne sur B après l'avoir consultée en ligne → toujours visible.
