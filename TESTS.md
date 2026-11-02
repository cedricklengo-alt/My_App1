# ✅ Tests du fil de publication — MboteCall

Tout ce qui concerne l'onglet **Accueil** (fil + statuts) est couvert par des
tests **exécutables**. Aucun test ne dépend d'un téléphone ni d'Internet.

```bash
# 1. Backend (46 vérifications, lance son propre serveur sur le port 4788)
cd mbote-backend && npm install && node test/feed.test.js

# 2. Application Flutter (29 tests)
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
Backend  : 46 réussis, 0 échec
Flutter  : 29 tests, All tests passed!   (6 s)
Analyse  : 0 erreur, 0 avertissement, 2 infos (dépréciations Firebase Messaging
           dans lib/push.dart : getToken → register, onTokenRefresh → onRegistered)
```
