// Preuve de COMPILATION : ce fichier importe **tout** `lib/`.
//
// Le compilateur Dart doit résoudre l'intégralité de l'application (écrans,
// widgets, modèles, services, appels WebRTC). Si un seul fichier casse, ce test
// échoue au chargement — c'est un « build » complet sans SDK Android.
//
//   flutter test test/compile_all_test.dart
// ignore_for_file: unused_import
import 'package:flutter_test/flutter_test.dart';

import 'package:mbote/api.dart';
import 'package:mbote/config.dart';
import 'package:mbote/group_call.dart';
import 'package:mbote/l10n.dart';
import 'package:mbote/main.dart';
import 'package:mbote/models/post.dart';
import 'package:mbote/pin.dart';
import 'package:mbote/prefs.dart';
import 'package:mbote/push.dart';
import 'package:mbote/rtc.dart';
import 'package:mbote/screens/airtime.dart';
import 'package:mbote/screens/call.dart';
import 'package:mbote/screens/call_sheet.dart';
import 'package:mbote/screens/chat.dart';
import 'package:mbote/screens/chats.dart';
import 'package:mbote/screens/contacts.dart';
import 'package:mbote/screens/favorites.dart';
import 'package:mbote/screens/feed_screen.dart';
import 'package:mbote/screens/group_call.dart';
import 'package:mbote/screens/history.dart';
import 'package:mbote/screens/home.dart';
import 'package:mbote/screens/incoming_call.dart';
import 'package:mbote/screens/keypad.dart';
import 'package:mbote/screens/login.dart';
import 'package:mbote/screens/lokota.dart';
import 'package:mbote/screens/onboarding.dart';
import 'package:mbote/screens/packages.dart';
import 'package:mbote/screens/profile.dart';
import 'package:mbote/screens/shell.dart';
import 'package:mbote/screens/topup.dart';
import 'package:mbote/screens/transfer.dart';
import 'package:mbote/state.dart';
import 'package:mbote/tabs.dart';
import 'package:mbote/theme.dart';
import 'package:mbote/widgets/feed/media_view.dart';
import 'package:mbote/widgets/feed/post_card.dart';
import 'package:mbote/widgets/feed/story_bar.dart';

void main() {
  test("toute l'application compile", () {
    expect(true, isTrue);
  });
}
