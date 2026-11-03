// lib/state/notifs.dart
// CENTRE DE NOTIFICATIONS — état partagé et rafraîchissement « temps réel ».
//
// L'application n'utilise pas Firestore : le temps réel se fait par
// interrogation courte du serveur (25 s), complétée par trois accélérateurs :
//   • rafraîchissement immédiat au retour de l'application au premier plan ;
//   • rafraîchissement immédiat après une action de l'utilisateur (il vient de
//     commenter, de publier : le compteur doit suivre) ;
//   • pause complète quand l'application est en arrière-plan — inutile de
//     consommer de la data kinoise pour un écran éteint.
//
// Le compteur et la liste vivent ici, pas dans les écrans : la pastille de
// l'en-tête et la page de notifications affichent donc toujours la même valeur.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api.dart';
import '../models/social.dart';

class NotifsCtl extends ChangeNotifier with WidgetsBindingObserver {
  NotifsCtl(this.api);

  final Api api;

  /// Intervalle d'interrogation quand l'application est visible.
  static const Duration intervalle = Duration(seconds: 25);

  List<NotificationSociale> items = const [];
  int nonLues = 0;
  bool charge = false;
  String? erreur;
  bool? _next; // vrai s'il reste des pages

  Timer? _minuteur;
  bool _actif = false;
  bool _disposed = false;

  bool get aPlus => _next == true;

  /// Démarre le suivi (une seule fois, idempotent).
  void demarrer() {
    if (_actif) return;
    _actif = true;
    WidgetsBinding.instance.addObserver(this);
    rafraichirBadge();
    _minuteur = Timer.periodic(intervalle, (_) => rafraichirBadge());
  }

  /// Arrête le suivi et libère le minuteur.
  void arreter() {
    _actif = false;
    _minuteur?.cancel();
    _minuteur = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _actif) {
      rafraichirBadge();
      if (_minuteur == null || !_minuteur!.isActive) {
        _minuteur = Timer.periodic(intervalle, (_) => rafraichirBadge());
      }
    } else if (state == AppLifecycleState.paused) {
      _minuteur?.cancel();
      _minuteur = null;
    }
  }

  /// Met à jour le badge seul : c'est l'appel périodique, il doit rester
  /// minuscule (une ligne de JSON).
  Future<void> rafraichirBadge() async {
    if (_disposed) return;
    try {
      final n = await api.notificationsNonLues();
      if (_disposed) return;
      if (n != nonLues) {
        nonLues = n;
        notifyListeners();
      }
    } catch (_) {
      // Un badge muet vaut mieux qu'une erreur à l'écran.
    }
  }

  /// Charge (ou recharge) la première page.
  Future<void> charger({bool silencieux = false}) async {
    if (_disposed) return;
    if (!silencieux) {
      charge = true;
      erreur = null;
      notifyListeners();
    }
    try {
      final r = await api.notifications(limite: 40);
      if (_disposed) return;
      items = ((r['notifications'] as List?) ?? const [])
          .map((e) => NotificationSociale.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      nonLues = (r['non_lues'] as num?)?.toInt() ?? 0;
      _next = r['next'] != null;
      charge = false;
      erreur = null;
    } catch (e) {
      if (_disposed) return;
      charge = false;
      erreur = friendlyError(e);
    }
    notifyListeners();
  }

  /// Page suivante (curseur `created_at`).
  Future<void> chargerPlus() async {
    if (!aPlus || items.isEmpty || _disposed) return;
    try {
      final r = await api.notifications(before: items.last.createdAt.millisecondsSinceEpoch, limite: 40);
      if (_disposed) return;
      final suite = ((r['notifications'] as List?) ?? const [])
          .map((e) => NotificationSociale.fromJson(Map<String, dynamic>.from(e as Map)));
      items = [...items, ...suite];
      _next = r['next'] != null;
      notifyListeners();
    } catch (_) {/* on retentera au prochain geste */}
  }

  /// Marque une notification lue, localement d'abord : l'écran ne doit pas
  /// attendre le réseau pour cesser de la surligner.
  Future<void> marquerLue(NotificationSociale n) async {
    if (n.lu) return;
    items = items.map((e) => e.id == n.id ? e.copyWith(lu: true) : e).toList();
    nonLues = nonLues > 0 ? nonLues - 1 : 0;
    notifyListeners();
    try {
      await api.marquerNotificationLue(n.id);
    } catch (_) {/* sera réessayé au prochain chargement */}
  }

  /// Tout marquer comme lu.
  Future<void> toutLire() async {
    items = items.map((e) => e.copyWith(lu: true)).toList();
    nonLues = 0;
    notifyListeners();
    try {
      await api.marquerNotificationsLues();
    } catch (_) {/* idem */}
  }

  @override
  void dispose() {
    _disposed = true;
    arreter();
    super.dispose();
  }
}
