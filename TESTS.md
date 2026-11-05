# ✅ Tests — MboteCall (fil, statuts, appels et discussions)

Tout ce qui concerne l'onglet **Accueil** (fil + statuts), les **appels**
(audio, vidéo, groupe), l'onglet **Discussions** (textes, photos, fichiers,
notes vocales traduites, accusés de lecture) **et la navigation** (4 onglets +
menu « ··· ») est couvert par des tests **exécutables**. Aucun test ne
dépend d'un téléphone, d'un micro, d'une caméra ni d'Internet.

```bash
# 1. Backend — TOUTE la batterie (521 vérifications, 10 fichiers)
cd mbote-backend && npm install && npm test

#   ou fichier par fichier
node test/db_tx.test.js              # 13  atomicité / réentrance des transactions
node test/api_smoke.test.js          # 87  parcours de base + sécurité des jetons
node test/group_signaling.test.js    # 30  signalisation des appels de groupe
node test/feed.test.js               # 56  fil et statuts
node test/calls.test.js              # 41  appels audio/vidéo/groupe (WebSocket réels)
node test/messages.test.js           # 87  discussions, médias, notes vocales
node test/billing_referral.test.js   # 34  facturation, parrainage, blocage de compte
node test/wallet.test.js             # 96  portefeuille, forfaits, GSM, tarifs, promos, console admin
node test/shop.test.js               # 71  boutique, cadeaux, Lokota, invitations, webhooks, ICE
node test/twilio_sms.test.js         # 64  Twilio, SMS, webhooks signés, historique, portefeuille

# 2. Application Flutter (304 tests)
cd My_App1
flutter pub get
flutter test
flutter analyze lib test            # doit afficher « No issues found! »
```

> ⚠️ **Si `flutter test` échoue avec « The Dart compiler exited unexpectedly »
> ou reste bloqué plusieurs minutes** : le dossier temporaire est plein.
> `flutter` compile dans `$TMPDIR`. Chez nous `/tmp` fait 992 Mo et se remplit
> vite :
> ```bash
> export TMPDIR=/var/tmp   # disque normal, 20 Go libres
> ```

## Les 15 fichiers de test

| Fichier | Ce qu'il prouve | Tests |
|---|---|---|
| `test/feed_model_test.dart` | `Post.fromJson` / `Story` / `StoryGroup` : champs, valeurs par défaut, tags JSON ou liste, accent « communauté », numéro masqué, âge lisible, groupement des statuts | 14 |
| `test/config_test.dart` | `Config.apiBase` surchargeable, `wsUrl` (https→wss), `friendlyError` (aucun jargon à l'écran), types MIME des envois, changement de thème | 6 |
| `test/feed_screen_test.dart` | Interface complète avec un faux serveur : chargement, erreur + réessai, j'aime optimiste + réconciliation, échec du j'aime → retour arrière, fil vide, pagination au défilement, publication d'un texte, commentaires | 8 |
| `test/feed_integration_test.dart` | **Bout en bout, vraies requêtes HTTP** vers un vrai `mbote-backend` lancé par le test : OTP, contacts, publication, fil, numéro de l'auteur, j'aime, commentaire, visibilité « contacts » vs inconnu, pagination par curseur, statuts + « vu », envoi de fichier servi en retour, événement (date/lieu/mots-clés) | 1 parcours de 40+ assertions |
| `test/chats_test.dart` | Onglet **Discussions** avec un faux serveur : liste (aperçu, « Vous : », non-lus, présence, recherche, « écrit… », appui long), bulles, ✓/✓✓ lu, note vocale + traduction, fichier, envoi optimiste, échec → « Réessayer », **temps réel** (`lu`, `reçu`, `supprimé`, nouveau message) et **robustesse** (historique conservé, pastille « nouveaux messages », brouillon, non-lus du fil ouvert) | 27 |
| `test/chat_format_test.dart` | Fonctions pures de la messagerie : dates (aujourd'hui/hier/date), heure, « vu à … », durées, tailles de fichier, comparaison de numéros, initiales | 11 |
| `test/chat_integration_test.dart` | **Bout en bout, vraies requêtes HTTP + vrai WebSocket** vers un vrai `mbote-backend` : envoi, non-lus, accusé de lecture, message reçu en direct, « écrit… », photo téléchargée octet par octet, note vocale écoutée, suppression pour moi / pour tous, pagination | 1 parcours de 25+ assertions |
| `test/shell_test.dart` | **Navigation** : l'onglet 3 s'appelle **« Discussion »** (plus « Messages »), les 4 onglets affichent leur écran, re-taper recharge, pastille des appels manqués, historique reçu/passé/sans réponse, filtres, erreur réseau, menu « ··· » complet (portefeuille, clavier, déconnexion confirmée, à propos) | 12 |
| `test/wallet_test.dart` | **Portefeuille** avec un faux serveur : solde affiché au format monétaire et dans la plus grosse taille de l'échelle (chiffres à largeur fixe), carte solde en **aplat de sable** sans dégradé ni ombre portée, « Recharger » ouvre bien l'écran de recharge, alerte de crédit bas uniquement sous 1 $, promotions du serveur affichées, et **aucun texte sous 11 px** sur l'écran | 6 |
| `test/a11y_test.dart` | **Audit d'accessibilité international** : les **4 guides officiels de Flutter** (`androidTapTargetGuideline` ≥ 48 dp, `iOSTapTargetGuideline` ≥ 44 pt, `labeledTapTargetGuideline` nom accessible WCAG 4.1.2, `textContrastGuideline` ≥ 4.5:1) appliqués à **11 écrans** — portefeuille, discussions, fil, appels, clavier, recharge, navigation, profil, forfaits, connexion, fiche d'appel — puis **reflow WCAG 1.4.4** : 6 écrans testés à **150 % et 200 %** de taille de texte (aucun débordement), et annonce de l'attente (« Chargement… ») aux lecteurs d'écran | 23 |
| `test/compile_all_test.dart` | Importe **les 38 fichiers de `lib/`** : preuve que toute l'application compile (le compilateur doit tout résoudre) | 1 |
| `test/contract_test.dart` | **Contrat app ↔ serveur** lu dans le code source : aucune clé de traduction manquante, fr/ln/sw ont exactement les mêmes clés et aucune traduction vide, la négation lingala « te » toujours placée en fin de phrase, l'onglet **« Discussion »** est nommé pareil dans les trois langues (aucun libellé d'onglet en doublon), et **chaque route HTTP appelée par `Api` existe réellement** dans `mbote-backend/src/modules/*.routes.js` | 7 |
| `test/design_test.dart` | **Système de design** : formule de contraste WCAG (références 21:1 et 4.54:1) ; **21 paires texte/fond × 5 palettes** conformes AA ; le thème « Bleu Nuit » garde un texte sombre sur son accent clair ; l'identité par défaut est « Fleuve Congo » et `MC` lui correspond ; échelle typographique croissante, plancher de **11 px** ; **aucun `fontSize` numérique dans tout `lib/`** (uniquement des jetons `Tx.*`) et les 8 rôles de l'échelle sont réellement utilisés ; **aucune couleur en dur hors `theme.dart`/`design.dart`** ; **aucun `CircleAvatar`** (tout passe par `MboteAvatar`, carré arrondi) ; couleurs de marque et sémantiques distinctes et visibles ; icône blanche du bouton raccrocher ≥ 4.5:1 ; changement de thème complet ; rayons et espacements sur la grille de 4 ; bouton principal de 56 px ; densité tactile ; **garde-fous d'audit** (aucun `IconButton` sans nom accessible, aucune image sans description ni exclusion, aucun `ListTile` sur surface opaque, aucun cercle de chargement muet, libellés de formulaire persistants) | 136 |

### Réglages du test d'intégration

```bash
# Par défaut il cherche le backend dans ../mbote-backend
MBOTE_BACKEND_DIR=/chemin/vers/mbote-backend flutter test test/feed_integration_test.dart
# Port du serveur de test (défaut 4790)
MBOTE_TEST_PORT=4791 flutter test test/feed_integration_test.dart
```

Si le dépôt backend est absent, le test est **ignoré** (pas d'échec).

## Dernier passage complet

```
Backend (npm test) : 457 réussis, 0 échec   (9 fichiers, 54 s)
  db_tx            13   atomicité, sous-transactions, réentrance, concurrence
  api_smoke        29   parcours de base, jetons absents/invalides
  group_signaling  30   salles, invitations, SDP maillés, départ, salle pleine
  feed             56   fil, statuts, j'aime, commentaires, pagination
  calls            41   audio, vidéo, groupe — WebSocket réels
  messages         87   textes, photos, fichiers, notes vocales, temps réel
  billing_referral 34   facturation à la seconde, bonus parrain/filleul, blocage
  wallet           96   solde, recharge, transfert, forfaits, GSM, tarifs,
                        promos, contacts, parrainage, appels programmés, console
  shop             71   commandes, cadeaux, webhooks signés, Lokota, invitations
Flutter            : 270 tests, All tests passed!   (36 s, 15 fichiers)
Analyse            : No issues found!   (0 erreur, 0 avertissement, 0 info)
Accessibilité      : 11 écrans × 4 guides officiels + 6 écrans à 150 %/200 %
                     → 23 tests, aucun échec
```

⚠️ Ce qui **ne peut pas** être testé ici (pas de téléphone, pas de micro ni de
caméra) : la qualité audio/vidéo réelle, l'écho, le passage d'un réseau 4G à un
autre. Tout le reste — signalisation, états, grille, historique, permissions —
est couvert.

## Appels : ce que le test WebSocket vérifie réellement

`node test/calls.test.js` ouvre de vrais clients WebSocket et joue le rôle des
téléphones :

1. **Audio individuel** : offre → sonnerie → réponse → raccrochage.
2. **Vidéo individuel** : le drapeau `video` survit au relais ; le refus aussi.
3. **Groupe** : création de salle par l'hôte ; entrée refusée sans invitation ;
   invitation relayée avec le mode vidéo de la salle ; arrivée annoncée aux
   autres (`group_peer_joined`) ; offres/réponses/candidats maillés ;
   micro coupé diffusé ; départ annoncé ; 5ᵉ personne refusée (4 max).
4. **Historique** : l'appel de groupe est journalisé une seule fois, gratuit,
   avec sa durée.
5. **Garde-fous** : un non-membre ne peut pas injecter de SDP dans la salle.


## Discussions : ce que `node test/messages.test.js` vérifie réellement

Le test lance un vrai serveur et deux vrais comptes, puis joue le rôle des
téléphones — y compris par **WebSocket** :

1. **Envoi texte** : création, `client_id` idempotent (un renvoi après coupure
   ne crée pas de doublon), refus du texte vide, du numéro inconnu, du message
   à soi-même, et de l'appel sans jeton.
2. **Temps réel** : le destinataire reçoit `{type:'msg', kind:'message'}` avec
   l'identifiant, l'expéditeur et l'aperçu ; `{type:'typing'}` est relayé.
3. **Liste des conversations** : aperçu, type, non-lus, état, présence, nom.
4. **Accusés de lecture** : `POST /messages/with/:phone/read` → événement
   `kind:'read'` chez l'expéditeur, statut `read` et date de lecture en base.
5. **Pagination** : 50 messages par page, `has_more`, remontée par `before`,
   aucun doublon, curseur invalide refusé.
6. **Photos** : signature JPEG contrôlée (un faux JPEG est refusé), formats
   limités, taille contrôlée, téléchargement authentifié identique à l'envoi,
   401 sans jeton et 404 pour un tiers.
7. **Fichiers** : PDF accepté, nom conservé dans l'aperçu, type fantaisiste
   refusé.
8. **Notes vocales** : `POST /konversations/send`, `kind:'note'`, durée,
   langues, forme d'onde, aperçu « Note vocale », `played` → événement
   `kind:'played'` chez l'expéditeur, note téléchargeable.
9. **Suppression** : « pour moi » (masqué d'un seul côté), « pour tout le
   monde » (contenu effacé, fichier supprimé du disque, événement `deleted`),
   et refus quand on n'est pas l'auteur.

⚠️ Ce qui **ne peut pas** être testé ici : l'écoute réelle d'une note vocale et
l'appareil photo. La logique (enregistrement, envoi, lecture, traduction) est
couverte ; le micro dépend du téléphone.


## Finition des onglets : ce que `test/shell_test.dart` vérifie

1. **Les 4 onglets** : Accueil (fil), Appels (historique), Messages
   (discussions) — chacun charge son écran et appelle son API.
2. **Re-taper l'onglet actif** recharge son contenu (compteur d'appels API).
3. **Pastille des appels manqués** : 2 appels non décrochés → « 2 » sur
   l'onglet Appels.
4. **Historique** : reçu ✓ vs passé ✓ vs « Sans réponse », durées, filtres par
   catégorie, erreur réseau + « Réessayer », liste vide avec bouton
   « Composer un numéro ».
5. **Menu « ··· »** : toutes les entrées existent (clavier, contacts, favoris,
   portefeuille, profil, paramètres, à propos, déconnexion) ; le portefeuille
   ouvre un vrai écran ; le clavier affiche ses touches ; la déconnexion
   demande confirmation (annuler ne déconnecte pas, confirmer ferme la
   session) ; « À propos » affiche la présentation.


## Correction globale : ce que vérifient les nouveaux tests

### `node test/db_tx.test.js` — le socle (13 vérifications)

Le driver SQLite sérialise toutes les opérations dans une file d'attente. Un
appel `db.get(...)` **à l'intérieur** d'un `db.tx(...)` se remettait dans cette
file, déjà occupée par la transaction : **attente infinie**, et comme la file
est globale, tout le serveur se figeait pour tous les utilisateurs. Le test
appelle volontairement `db.get` / `db.run` / un `db.tx` imbriqué dans une
transaction et impose un délai maximum de 3 s : sans le correctif, il échoue
avec « BLOCAGE ». Il vérifie aussi l'annulation complète (ROLLBACK), les
sous-transactions (SAVEPOINT), 100 débits concurrents sans écriture perdue, et
qu'un solde ne devient jamais négatif sous 30 tentatives simultanées.

### `node test/billing_referral.test.js` — l'argent (34 vérifications)

Un vrai serveur, de vrais appels (le fournisseur démo décroche à 4 s) :
tarif affiché avant l'appel, durée facturée, coût prélevé, **premier appel
facturé d'un filleul → 1 $ pour lui + 1 $ pour le parrain, une seule fois**,
appel MboteCall → MboteCall gratuit, et blocage par l'admin (plus d'appel, plus
de connexion, plus d'appel entrant) puis déblocage.

### `node test/wallet.test.js` — le portefeuille (96 vérifications)

Solde initial (bonus de bienvenue), recharge Mobile Money (débit simulé après
8 s, suivi de statut, isolation entre comptes), transfert entre proches (totaux
conservés, refus du découvert), achat de forfait (débit exact, refus sans
solde), crédit GSM (remboursement si l'opérateur échoue), contacts, profil,
rappels de présence, tarifs, **promos** (la meilleure remise gagne, retour au
tarif normal après désactivation), parrainage, présence, appels programmés,
libellés, et **les neuf onglets de la console admin**.

### `node test/shop.test.js` — la boutique (71 vérifications)

Commande au prix figé, paiement Mobile Money puis **activation du forfait**
(quota, expiration, idempotence), forfait offert à un proche déjà inscrit ou
pas encore, webhook signé (refus sans signature ou avec une mauvaise),
notes vocales traduites (mode privé, renvoi idempotent, non-lus, lecture,
isolation entre tiers), invitations (création, page publique, validation,
réutilisation refusée), serveurs ICE et accusés WebRTC, webhooks de paiement.

---

## 🆕 Ce tour : boutique, portefeuille réel, SMS, historique (app)

| Fichier | Tests | Ce qui est prouvé |
|---|---|---|
| `test/shop_test.dart` | 8 | prix venant du serveur, états vide/erreur, parcours Mobile Money (commande → paiement → **statut vérifié** → activé), paiement refusé (jamais « activé »), carte = URL hébergée sans champ carte, quotas « Mes forfaits » |
| `test/transactions_test.dart` | 8 | montants **signés** (−/+), « en attente » ≠ confirmé, écriture échouée barrée, filtres envoyés au serveur (`type=call_debit`, `status=pending`), pagination sans doublon, états vide/erreur |
| `test/history_test.dart` | 8 | filtres **serveur** (`gsm`, `internet`), recherche différée (3 frappes = 1 requête), fiche d'appel (coût, canal, durée), masquage → route dédiée + rechargement, états vide/erreur |
| `test/sms_test.dart` | 6 | devis avant envoi, **aucun envoi** si tarif manquant (`SMS_RATE_MISSING`) ou fournisseur non prêt, forfait SMS annoncé comme couvert, identifiant d'idempotence transmis |
| `test/wallet_test.dart` | +4 | dépenses du jour/mois telles que le serveur les calcule, alerte pilotée par `low_balance`, résumé indisponible → **aucun chiffre faux**, accès boutique/forfaits |

Règle appliquée partout : **un chiffre affiché vient du serveur**. Si la donnée
manque, l'écran le dit (« Résumé indisponible ») au lieu d'afficher un zéro.

### Backend — `test/twilio_sms.test.js` (64 vérifications)

* « non configuré » (409 + code) ne se confond **jamais** avec « solde 0 » ;
* `validateSignature` **fail-closed** : pas de jeton → webhook refusé ;
* webhook rejoué avec le **même CallSid** → aucun second débit ;
* SMS : aucun débit si `SMS_RATE_MISSING` ou fournisseur absent ;
* historique filtrable (`in/out/missed/internet/gsm`), masquage **sans perte comptable** ;
* `/wallet/summary` cohérent avec le grand livre ; zéro erreur 5xx.
