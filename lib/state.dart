import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'push.dart';
import 'rtc.dart';

/// État global de l'application (session, solde, contacts).
class AppState extends ChangeNotifier {
  final Api api = Api();

  String? token;
  String? id; // identifiant serveur (pour « mon statut » dans le fil)
  String name = '';
  String phone = '';
  String? avatar; // 📷 data-URI de la photo de profil
  int balanceCents = 0;
  List contacts = [];
  bool ready = false;

  bool get loggedIn => token != null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token');
    api.token = token;
    if (token != null) {
      try {
        await refresh();
        _connectRealtime();
      } catch (_) {
        await logout(); // token expiré
      }
    }
    ready = true;
    notifyListeners();
  }

  Future<void> onLoggedIn(String tk, Map user, int balance) async {
    token = tk;
    api.token = tk;
    id = user['id']?.toString();
    name = user['name'] ?? '';
    phone = user['phone'] ?? '';
    avatar = user['avatar'];
    balanceCents = balance;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', tk);
    await loadContacts();
    _connectRealtime();
    notifyListeners();
  }

  /// 🔌 Ouvre le canal temps réel (appels entrants) et enregistre le jeton
  /// push. Sans ces deux appels l'app ne PEUT PAS recevoir d'appel :
  /// le serveur n'a personne à qui annoncer l'appel, et ne peut pas réveiller
  /// le téléphone quand l'app est fermée.
  void _connectRealtime() {
    final tk = token;
    if (tk == null) return;
    Rtc.connect(tk);
    Push.register(api); // en arrière-plan : ne bloque jamais l'ouverture
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
    token = null;
    id = null;
    api.token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    notifyListeners();
  }
}
