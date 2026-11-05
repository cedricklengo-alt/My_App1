///Petites fonctions pures de la messagerie (dates, tailles, durées,
/// numéros). Isolées ici pour être **testables sans serveur ni écran**.
///
/// Toutes les dates du serveur sont en **millisecondes** (0 = « jamais »).
library;

/// Date d'un horodatage en millisecondes (0 ou négatif → `null`).
DateTime? chatDate(Object? raw) {
  final ms = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}'.trim());
  if (ms == null || ms <= 0) {
    // Certaines réponses peuvent déjà contenir une date ISO.
    final s = '${raw ?? ''}'.trim();
    if (s.isEmpty || s == '0' || s == 'null') return null;
    return DateTime.tryParse(s);
  }
  return DateTime.fromMillisecondsSinceEpoch(ms);
}

/// « 14:32 » (heure locale), ou une chaîne vide si la date est absente.
String chatClock(Object? raw) {
  final d = chatDate(raw)?.toLocal();
  if (d == null) return '';
  return '${_two(d.hour)}:${_two(d.minute)}';
}

/// Étiquette de jour d'une conversation : « Aujourd'hui », « Hier », « 12/10/2026 ».
String chatDayLabel(
  Object? raw, {
  required String today,
  required String yesterday,
}) {
  final d = chatDate(raw)?.toLocal();
  if (d == null) return '';
  final diff = _dayDiff(d);
  if (diff == 0) return today;
  if (diff == 1) return yesterday;
  return '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

/// Version courte pour la liste : heure si aujourd'hui, « Hier », sinon la date.
String chatListTime(
  Object? raw, {
  required String yesterday,
  required String daysAgo, // contient %s (nombre de jours)
}) {
  final d = chatDate(raw)?.toLocal();
  if (d == null) return '';
  final diff = _dayDiff(d);
  if (diff == 0) return chatClock(raw);
  if (diff == 1) return yesterday;
  if (diff < 7) return daysAgo.replaceAll('%s', '$diff');
  return '${_two(d.day)}/${_two(d.month)}';
}

/// « maintenant », « vu à 14:32 », « vu hier à 14:32 » ou « hors ligne ».
String chatLastSeen(
  Object? raw, {
  required String now,
  required String at,
  required String yesterdayAt,
  required String offline,
}) {
  final d = chatDate(raw)?.toLocal();
  if (d == null) return offline;
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 2) return now;
  final hhmm = '${_two(d.hour)}:${_two(d.minute)}';
  if (_dayDiff(d) == 0) return at.replaceAll('%s', hhmm);
  if (_dayDiff(d) == 1) return yesterdayAt.replaceAll('%s', hhmm);
  return offline;
}

/// « 0:07 » / « 1:05 » pour une note vocale.
String chatDuration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  return '${s ~/ 60}:${_two(s % 60)}';
}

/// « 812 o », « 3 Ko », « 1.5 Mo ».
String chatSize(Object? raw) {
  final b = raw is num ? raw.toInt() : (int.tryParse('${raw ?? 0}') ?? 0);
  if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} Mo';
  if (b >= 1024) return '${(b / 1024).round()} Ko';
  return '$b o';
}

/// Deux numéros désignent-ils la même personne ? (formats +243…/00243…/espaces)
bool samePeerPhone(Object? a, Object? b) {
  final x = _digits('${a ?? ''}');
  final y = _digits('${b ?? ''}');
  if (x.isEmpty || y.isEmpty) return false;
  if (x == y) return true;
  // On compare aussi les 9 derniers chiffres (numéro national).
  if (x.length >= 9 && y.length >= 9) {
    return x.substring(x.length - 9) == y.substring(y.length - 9);
  }
  return false;
}

/// Initiales d'un nom : « Alice Mbote » → « AM », « Bob » → « BO ».
String chatInitials(String name) {
  final clean = name.trim();
  if (clean.isEmpty) return '?';
  final parts = clean.split(RegExp(r'\s+'));
  String take(String s, int n) => String.fromCharCodes(s.runes.take(n));
  if (parts.length == 1) return take(parts.first, 2).toUpperCase();
  return (take(parts.first, 1) + take(parts.last, 1)).toUpperCase();
}

// interne ────────────────────────────────────────────

String _two(int v) => v.toString().padLeft(2, '0');

String _digits(String s) =>
    s.replaceAll(RegExp(r'[^0-9]'), '').replaceFirst(RegExp(r'^00'), '');

int _dayDiff(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  return today.difference(day).inDays;
}
