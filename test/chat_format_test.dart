// Tests UNITAIRES de la messagerie : formats de date, taille, durée, numéros.
// Aucun écran, aucun réseau — on vérifie la logique qui produit ce que
// l'utilisateur lit dans les bulles et dans la liste.
import 'package:flutter_test/flutter_test.dart';

import 'package:mbote/chat_format.dart';

int msOf(DateTime d) => d.millisecondsSinceEpoch;

void main() {
  group('Dates', () {
    test('0 et les valeurs absurdes ne produisent pas de date', () {
      expect(chatDate(0), isNull);
      expect(chatDate(null), isNull);
      expect(chatDate(''), isNull);
      expect(chatDate(-5), isNull);
    });

    test('une date ISO reste lisible (anciens messages)', () {
      final iso = DateTime(2026, 10, 12, 9, 5).toIso8601String();
      expect(chatDate(iso), isNotNull);
      expect(chatClock(iso), '09:05');
    });

    test('l’heure est sur deux chiffres', () {
      expect(chatClock(msOf(DateTime(2026, 3, 4, 7, 8))), '07:08');
      expect(chatClock(msOf(DateTime(2026, 3, 4, 23, 59))), '23:59');
    });

    test('le jour se dit aujourd’hui / hier / en toutes lettres', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 11, 30);
      final hier = today.subtract(const Duration(days: 1));
      final vieux = DateTime(2026, 1, 2, 8, 0);

      expect(
        chatDayLabel(msOf(today), today: 'Aujourd’hui', yesterday: 'Hier'),
        'Aujourd’hui',
      );
      expect(
        chatDayLabel(msOf(hier), today: 'Aujourd’hui', yesterday: 'Hier'),
        'Hier',
      );
      expect(
        chatDayLabel(msOf(vieux), today: 'Aujourd’hui', yesterday: 'Hier'),
        '02/01/2026',
      );
    });

    test('la liste montre l’heure, « Hier », « Il y a 3 j », puis la date', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 16, 42);
      final hier = today.subtract(const Duration(days: 1));
      final troisJours = today.subtract(const Duration(days: 3));
      final mois = today.subtract(const Duration(days: 40));

      String f(DateTime d) => chatListTime(msOf(d),
          yesterday: 'Hier', daysAgo: 'Il y a %s j');

      expect(f(today), '16:42');
      expect(f(hier), 'Hier');
      expect(f(troisJours), 'Il y a 3 j');
      expect(f(mois), matches(RegExp(r'^\d{2}/\d{2}$')));
    });

    test('« vu à … », « vu hier à … », « hors ligne »', () {
      String vu(Object? v) => chatLastSeen(v,
          now: 'à l’instant',
          at: 'vu à %s',
          yesterdayAt: 'vu hier à %s',
          offline: 'hors ligne');

      final maintenant = DateTime.now().subtract(const Duration(seconds: 20));
      final hier = DateTime.now()
          .subtract(const Duration(days: 1))
          .copyWith(hour: 9, minute: 5, second: 0, millisecond: 0);

      expect(vu(msOf(maintenant)), 'à l’instant');
      expect(vu(msOf(hier)), 'vu hier à 09:05');
      expect(vu(0), 'hors ligne');
      expect(vu(null), 'hors ligne');
    });
  });

  group('Durées et tailles', () {
    test('durée d’une note vocale', () {
      expect(chatDuration(0), '0:00');
      expect(chatDuration(7), '0:07');
      expect(chatDuration(65), '1:05');
      expect(chatDuration(-3), '0:00');
    });

    test('taille d’un fichier', () {
      expect(chatSize(0), '0 o');
      expect(chatSize(812), '812 o');
      expect(chatSize(2048), '2 Ko');
      expect(chatSize(1572864), '1.5 Mo');
      expect(chatSize('2048'), '2 Ko');
      expect(chatSize(null), '0 o');
    });
  });

  group('Numéros', () {
    test('deux écritures du même numéro se reconnaissent', () {
      expect(samePeerPhone('+243810000002', '+243810000002'), isTrue);
      expect(samePeerPhone('+243 810 000 002', '+243810000002'), isTrue);
      expect(samePeerPhone('00243810000002', '+243810000002'), isTrue);
      expect(samePeerPhone('0810000002', '+243810000002'), isTrue,
          reason: 'numéro national à 9 chiffres');
    });

    test('deux personnes différentes ne se confondent pas', () {
      expect(samePeerPhone('+243810000001', '+243810000002'), isFalse);
      expect(samePeerPhone('', '+243810000002'), isFalse);
      expect(samePeerPhone(null, null), isFalse);
    });
  });

  group('Initiales', () {
    test('nom complet, prénom seul, vide', () {
      expect(chatInitials('Alice Mbote'), 'AM');
      expect(chatInitials('Bob'), 'BO');
      expect(chatInitials('  '), '?');
      expect(chatInitials('kabeya  mwamba  '), 'KM');
    });
  });
}
