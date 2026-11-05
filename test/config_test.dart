// Tests de la configuration réseau et des messages d'erreur : ce sont les
// rouages qui décident « à quel serveur on parle » et « quoi afficher quand
// ça casse ». Un bug ici casse tout le fil.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mbote/api.dart';
import 'package:mbote/config.dart';
import 'package:mbote/theme.dart';

void main() {
  setUp(Config.reset);
  tearDown(Config.reset);

  group('Config', () {
    test('apiBase se surcharge à l’exécution puis se réinitialise', () {
      final prod = Config.apiBase;
      Config.apiBase = 'http://127.0.0.1:4790/api';
      expect(Config.apiBase, 'http://127.0.0.1:4790/api');
      Config.reset();
      expect(Config.apiBase, prod);
      expect(prod, contains('/api'));
    });

    test('wsUrl : https → wss, http → ws, /api retiré', () {
      Config.apiBase = 'https://exemple.cd/api';
      expect(Config.wsUrl, 'wss://exemple.cd/ws');
      Config.apiBase = 'http://127.0.0.1:4000/api';
      expect(Config.wsUrl, 'ws://127.0.0.1:4000/ws');
    });
  });

  group('friendlyError', () {
    test('aucun jargon technique ne fuit vers l’écran', () {
      expect(
          friendlyError(const SocketException('boom')), contains('connexion'));
      expect(friendlyError(TimeoutException('trop long')),
          contains('trop de temps'));
      expect(friendlyError(ApiException('Numéro invalide', 'bad_phone')),
          'Numéro invalide');
      expect(friendlyError(StateError('x')), contains('réessaie'));
      for (final msg in [
        friendlyError(const SocketException('x')),
        friendlyError(StateError('x')),
      ]) {
        expect(msg, isNot(contains('Exception')));
        expect(msg, isNot(contains('Socket')));
      }
    });
  });

  group('types MIME des envois', () {
    test('images et vidéos reconnues par le serveur', () {
      expect(Api.mimeForPath('/tmp/a.JPG'), 'image/jpeg');
      expect(Api.mimeForPath('/tmp/a.jpeg'), 'image/jpeg');
      expect(Api.mimeForPath('/tmp/a.png'), 'image/png');
      expect(Api.mimeForPath('/tmp/a.webp'), 'image/webp');
      expect(Api.mimeForPath('/tmp/a.mp4'), 'video/mp4');
      expect(Api.mimeForPath('/tmp/a.mov'), 'video/quicktime');
    });

    test('jamais application/octet-stream (refusé par le serveur)', () {
      expect(Api.mimeForPath('/tmp/sans-extension'), startsWith('image/'));
      expect(Api.mimeForPath('/tmp/bizarre.zzz'), startsWith('image/'));
    });
  });

  group('thèmes', () {
    test('changer de thème change réellement les couleurs actives', () {
      MC.apply(kPalettes['kin']!);
      final accentKin = MC.soleil;
      expect(MC.degrade.colors.first, accentKin);

      final autre = kPalettes.entries.firstWhere((e) => e.key != 'kin');
      MC.apply(autre.value);
      expect(MC.soleil, autre.value.accent);
      expect(MC.soleil, isNot(accentKin));

      MC.apply(kPalettes['kin']!); // on remet l'état par défaut
    });
  });
}
