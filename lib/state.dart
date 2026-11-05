import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'push.dart';
import 'main.dart' show appNavigatorKey;
import 'rtc.dart';
import 'local/local_db.dart';
import 'local/repository.dart';
import 'local/sync_service.dart';

/// État global de l'application (session, solde, contacts).
class AppState extends ChangeNotifier {
  /// Remplaçable par un faux serveur dans les tests d'interface.
  Api api = Api();

  String? token;
  String? id; // identifiant serveur (pour « mon statut » dans le fil)
  String name = '';
  String phone = '';
  String? avatar; //data-URI de la photo de profil
  int balanceCents = 0;
  List contacts = [];
  bool ready = false;

  bool get loggedIn => token != null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token');
    refreshToken = prefs.getString('refresh_token');
    api.token = token;
    // 🏠 LOCAL-FIRST : la base locale s'ouvre TOUJOURS (même hors connexion)
    // pour que l'historique reste consultable sans Internet.
    try {
      await LocalDb.instance.db;
    } catch (_) {}
    if (token != null) {
      // 🔐 Session valide MAIS hors ligne : on NE déconnecte PAS.
      // Seul un rejet explicite du serveur (401 AUTH, même après rotation
      // du refresh token) met fin à la session.
      try {
        await refresh();
      } on ApiException catch (e) {
        if (e.code == 'AUTH') {
          final rt = refreshToken;
          bool rotated = false;
          if (rt != null) {
            try {
              final r = await api.refreshSession(rt);
              token = r['token']?.toString();
              api.token = token;
              refreshToken = r['refresh_token']?.toString();
              final prefs = await SharedPreferences.getInstance();
              if (token != null) await prefs.setString('token', token!);
              if (refreshToken != null) {
                await prefs.setString('refresh_token', refreshToken!);
              }
              await refresh();
              rotated = true;
            } on ApiException catch (e2) {
              if (e2.code == 'AUTH') {
                await logout(); // session expirée côté serveur
                ready = true;
                notifyListeners();
                return;
              }
              // hors ligne pendant la rotation : session locale conservée
            }
          }
          if (!rotated && rt == null) {
            await logout(); // pas de refresh token → session irrécupérable
            ready = true;
            notifyListeners();
            return;
          }
        }
        // code 'offline' / 'timeout' / autre : session locale conservée,
        // la synchro reprendra à la reconnexion (SyncService).
      } catch (_) {
        // Erreur inconnue : on garde la session (architecture local-first).
      }
      _connectRealtime();
      // Démarre la synchro de rattrapage + la file d'attente persistante
      // sur le singleton (le bandeau hors ligne du shell l'observe).
      SyncService.instance.attach(api);
      SyncService.instance.start();
    }
    ready = true;
    notifyListeners();
  }

  String? refreshToken;

  Future<void> onLoggedIn(String tk, Map user, int balance,
      {String? refreshToken}) async {
    token = tk;
    this.refreshToken = refreshToken;
    api.token = tk;
    id = user['id']?.toString();
    name = user['name'] ?? '';
    phone = user['phone'] ?? '';
    avatar = user['avatar'];
    balanceCents = balance;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', tk);
    if (refreshToken != null) await prefs.setString('refresh_token', refreshToken);
    await loadContacts();
    _connectRealtime();
    notifyListeners();
  }

  ///Ouvre le canal temps réel (appels entrants) et enregistre le jeton
  /// push. Sans ces deux appels l'app ne PEUT PAS recevoir d'appel :
  /// le serveur n'a personne à qui annoncer l'appel, et ne peut pas réveiller
  /// le téléphone quand l'app est fermée.
  void _connectRealtime() {
    final tk = token;
    if (tk == null) return;
    Rtc.connect(tk);
    Push.register(api); // en arrière-plan : ne bloque jamais l'ouverture
    Push.initDeepLinks(appNavigatorKey); // deep-linking des notifications
  }

  Future<void> refresh() async {
    final m = await api.me();
    id = m['user']['id']?.toString();
    name = m['user']['name'] ?? '';
    phone = m['user']['phone'] ?? '';
    avatar = m['user']['avatar'];
    balanceCents = m['balance_cents'] ?? 0;
    await loadContacts();
    notifyListeners();
  }

  Future<void> loadContacts() async {
    contacts = await api.contacts();
  }

  void setBalance(int cents) {
    balanceCents = cents;
    notifyListeners();
  }

  Future<void> logout() async {
    Rtc.disconnect(); // ferme le canal temps réel
    SyncService.instance.stop(); // arrête la synchro de fond
    await api.logoutServer(refreshToken); // révoque la session côté serveur
    refreshToken = null;
    token = null;
    id = null;
    api.token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('refresh_token');
    // ⚠️ On NE vide PAS la base locale à la déconnexion : les messages en
    // attente et l'historique restent consultables. Le vidage n'a lieu que
    // sur changement de compte explicite (wipeOnAccountSwitch).
    notifyListeners();
  }

  /// Changement de compte : aucune donnée de l'ancien compte ne doit rester
  /// exposée au nouveau → on vide la base locale (appelé explicitement).
  Future<void> wipeLocalDataOnAccountSwitch() async {
    LocalRepository.instance.dispose();
    await LocalDb.instance.wipeAll();
  }
}
