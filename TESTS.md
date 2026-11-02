# ✅ Tests — MboteCall (fil, statuts, appels et discussions)

Tout ce qui concerne l'onglet **Accueil** (fil + statuts), les **appels**
(audio, vidéo, groupe), l'onglet **Discussions** (textes, photos, fichiers,
notes vocales traduites, accusés de lecture) **et la navigation** (4 onglets +
menu « ··· ») est couvert par des tests **exécutables**. Aucun test ne
dépend d'un téléphone, d'un micro, d'une caméra ni d'Internet.

```bash
# 1. Backend — fil (56 vérifications, serveur sur le port 4788)
cd mbote-backend && npm install && node test/feed.test.js

# 1 bis. Backend — appels (41 vérifications WebSocket réelles, port 4789)
node test/calls.test.js

# 1 ter. Backend — discussions (81 vérifications, port 4791)
node test/messages.test.js

# 2. Application Flutter (78 tests)
cd My_App1
flutter pub get
flutter test
```

> ⚠️ **Si `flutter test` échoue avec « The Dart compiler exited unexpectedly »
> ou reste bloqué plusieurs minutes** : le dossier temporaire est plein.
> `flutter` compile dans `$TMPDIR`. Chez nous `/tmp` fait 992 Mo et se remplit
> vite :
> ```bash
> export TMPDIR=/var/tmp   # disque normal, 20 Go libres
> ```

## Les 8 fichiers de test

| Fichier | Ce qu'il prouve | Tests |
|---|---|---|
| `test/feed_model_test.dart` | `Post.fromJson` / `Story` / `StoryGroup` : champs, valeurs par défaut, tags JSON ou liste, accent « communauté », numéro masqué, âge lisible, groupement des statuts | 14 |
| `test/config_test.dart` | `Config.apiBase` surchargeable, `wsUrl` (https→wss), `friendlyError` (aucun jargon à l'écran), types MIME des envois, changement de thème | 6 |
| `test/feed_screen_test.dart` | Interface complète avec un faux serveur : chargement, erreur + réessai, j'aime optimiste + réconciliation, échec du j'aime → retour arrière, fil vide, pagination au défilement, publication d'un texte, commentaires | 8 |
| `test/feed_integration_test.dart` | **Bout en bout, vraies requêtes HTTP** vers un vrai `mbote-backend` lancé par le test : OTP, contacts, publication, fil, numéro de l'auteur, j'aime, commentaire, visibilité « contacts » vs inconnu, pagination par curseur, statuts + « vu », envoi de fichier servi en retour, événement (date/lieu/mots-clés) | 1 parcours de 40+ assertions |
| `test/chats_test.dart` | Onglet **Discussions** avec un faux serveur : liste (aperçu, « Vous : », non-lus, présence, recherche, « écrit… », appui long), bulles, ✓/✓✓ lu, note vocale + traduction, fichier, envoi optimiste, échec → « Réessayer », et **temps réel** (`lu`, `supprimé`, nouveau message) | 22 |
| `test/shell_test.dart` | **Navigation** : les 4 onglets affichent leur écran, re-taper recharge, pastille des appels manqués, historique reçu/passé/sans réponse, filtres, erreur réseau, menu « ··· » complet (portefeuille, clavier, déconnexion confirmée, à propos) | 12 |
| `test/compile_all_test.dart` | Importe **les 37 fichiers de `lib/`** : preuve que toute l'application compile (le compilateur doit tout résoudre) | 1 |

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
Backend fil       : 56 réussis, 0 échec
Backend appels    : 41 réussis, 0 échec   (WebSocket réels : offre/réponse/refus,
                                           drapeau vidéo, salle de groupe, historique
                                           entrant/sortant/manqué/vidéo)
Backend messages  : 81 réussis, 0 échec   (envoi, fils, lecture, médias, notes
                                           vocales, suppression, temps réel)
Flutter           : 78 tests, All tests passed!   (18 s)
Analyse         : 0 erreur, 0 avertissement, 2 infos (dépréciations Firebase
                  Messaging dans lib/push.dart)
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
