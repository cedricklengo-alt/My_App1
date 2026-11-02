# ✅ Tests — MboteCall (fil, statuts et appels)

Tout ce qui concerne l'onglet **Accueil** (fil + statuts) **et les appels**
(audio, vidéo, groupe) est couvert par des tests **exécutables**. Aucun test ne
dépend d'un téléphone, d'un micro, d'une caméra ni d'Internet.

```bash
# 1. Backend — fil (56 vérifications, serveur sur le port 4788)
cd mbote-backend && npm install && node test/feed.test.js

# 1 bis. Backend — appels (30 vérifications WebSocket réelles, port 4789)
node test/calls.test.js

# 2. Application Flutter (44 tests)
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

## Les 5 fichiers de test

| Fichier | Ce qu'il prouve | Tests |
|---|---|---|
| `test/feed_model_test.dart` | `Post.fromJson` / `Story` / `StoryGroup` : champs, valeurs par défaut, tags JSON ou liste, accent « communauté », numéro masqué, âge lisible, groupement des statuts | 14 |
| `test/config_test.dart` | `Config.apiBase` surchargeable, `wsUrl` (https→wss), `friendlyError` (aucun jargon à l'écran), types MIME des envois, changement de thème | 6 |
| `test/feed_screen_test.dart` | Interface complète avec un faux serveur : chargement, erreur + réessai, j'aime optimiste + réconciliation, échec du j'aime → retour arrière, fil vide, pagination au défilement, publication d'un texte, commentaires | 8 |
| `test/feed_integration_test.dart` | **Bout en bout, vraies requêtes HTTP** vers un vrai `mbote-backend` lancé par le test : OTP, contacts, publication, fil, numéro de l'auteur, j'aime, commentaire, visibilité « contacts » vs inconnu, pagination par curseur, statuts + « vu », envoi de fichier servi en retour, événement (date/lieu/mots-clés) | 1 parcours de 40+ assertions |
| `test/compile_all_test.dart` | Importe **les 31 fichiers de `lib/`** : preuve que toute l'application compile (le compilateur doit tout résoudre) | 1 |

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
Backend fil     : 56 réussis, 0 échec
Backend appels  : 30 réussis, 0 échec   (WebSocket réels : offre/réponse/refus,
                                         drapeau vidéo, salle de groupe, historique)
Flutter         : 44 tests, All tests passed!   (13 s)
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
