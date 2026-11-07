// lib/telecom.dart
// PONT TELECOM/VOIP — canaux natifs Android (voir MainActivity.kt).
//
// Permet à l'appel WebRTC (flutter_webrtc) de s'enregistrer auprès du
// Telecom Framework Android (historique système, lockscreen, Android Auto,
// Bluetooth) et de piloter le routage audio professionnel (écouteur / HP /
// Bluetooth SCO, effets AEC/NS/AGC). Sans effet hors Android : chaque appel
// renvoie false / un map vide, jamais d'exception.

import 'package:flutter/services.dart';

class Telecom {
  static const MethodChannel _appel = MethodChannel('mbote/appel');
  static const MethodChannel _audio = MethodChannel('mbote/audio');

  /// Enregistre l'appel auprès du Telecom Framework + démarre le service
  /// foreground (notification CallStyle plein écran sur lockscreen).
  static Future<bool> placeAppel({
    required String callId,
    required String nom,
    required String phone,
    bool video = false,
  }) async {
    try {
      final r = await _appel.invokeMethod<Map>('placeCall', {
        'call_id': callId,
        'nom': nom,
        'phone': phone,
        'video': video,
      });
      return r?['ok'] == true;
    } on PlatformException {
      return false; // natif absent (test, bureau) : l'appel WebRTC continue
    }
  }

  /// Termine l'appel côté Telecom + arrête le service foreground.
  static Future<void> terminerAppel(String callId) async {
    try {
      await _appel.invokeMethod('terminerAppel', {'call_id': callId});
    } on PlatformException {/* natif absent : rien à faire */}
  }

  /// Un appel est-il actif côté Telecom ?
  static Future<bool> appelEnCours() async {
    try {
      final r = await _appel.invokeMethod<Map>('appelEnCours');
      return r?['en_cours'] == true;
    } on PlatformException {
      return false;
    }
  }

  /// Mode appel : audio en MODE_IN_COMMUNICATION, écouteur par défaut.
  static Future<void> modeAppel() async {
    try { await _audio.invokeMethod('modeAppel'); } on PlatformException {}
  }

  /// Haut-parleur on/off (bouton HP de l'écran d'appel).
  static Future<void> hautParleur(bool on) async {
    try { await _audio.invokeMethod('hautParleur', on); } on PlatformException {}
  }

  /// Casque Bluetooth (SCO) on/off.
  static Future<void> bluetooth(bool on) async {
    try { await _audio.invokeMethod('bluetooth', on); } on PlatformException {}
  }

  /// Retour à l'écouteur.
  static Future<void> ecouteur() async {
    try { await _audio.invokeMethod('ecouteur'); } on PlatformException {}
  }

  /// Active AEC + Noise Suppressor + AGC si le matériel les supporte.
  static Future<Map<String, bool>> activerEffets() async {
    try {
      final r = await _audio.invokeMethod<Map>('activerEffets');
      return {
        'aec': r?['aec'] == true,
        'ns': r?['ns'] == true,
        'agc': r?['agc'] == true,
      };
    } on PlatformException {
      return const {'aec': false, 'ns': false, 'agc': false};
    }
  }

  /// Libère les effets audio (fin d'appel).
  static Future<void> libererEffets() async {
    try { await _audio.invokeMethod('libererEffets'); } on PlatformException {}
  }
}
