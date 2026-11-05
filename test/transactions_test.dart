// Tests du GRAND LIVRE côté application (écran Transactions).
//
// Ce que ces tests prouvent :
//   • le montant garde son SIGNE (débit « − », crédit « + ») ;
//   • une écriture « en attente » n'est jamais présentée comme confirmée ;
//   • les filtres sont envoyés au SERVEUR (type exact du grand livre) ;
//   • l'état vide et l'état d'erreur existent ;
//   • la pagination demande la suite sans doublon.
//
// Aucun réseau : un faux serveur remplace l'API.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mbote/api.dart';
import 'package:mbote/l10n.dart';
import 'package:mbote/screens/transactions.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';

/// Les filtres sont dans une bande horizontale : sur un écran de test étroit,
/// il faut faire défiler la bande pour atteindre la puce voulue (comme sur un
/// vrai téléphone).
Future<void> taperFiltre(WidgetTester tester, String libelle) async {
  // `find.text` seul trouve aussi le libellé dans une ligne du grand livre :
  // on cible la PUCE elle-même.
  final cible = find.widgetWithText(ChoiceChip, libelle).evaluate().isNotEmpty
      ? find.widgetWithText(ChoiceChip, libelle)
      : find.widgetWithText(FilterChip, libelle);
  await tester.dragUntilVisible(
    cible,
    find.byType(ListView).first,
    const Offset(-120, 0),
  );
  await tester.pump();
  await tester.tap(cible);
  await tester.pump();
  await tester.pump();
}

class FakeApi extends Api {
  List<Map> rows = [];
  Object? erreur;
  final List<Map<String, dynamic>> requetes = [];

  @override
  Future<Map> walletTransactions({
    String type = 'all',
    String status = 'all',
    int? from,
    int? to,
    int limit = 50,
    int offset = 0,
  }) async {
    requetes.add({'type': type, 'status': status, 'offset': offset});
    if (erreur != null) throw erreur!;
    final page = rows.skip(offset).take(limit).toList();
    return {
      'transactions': page,
      'total': rows.length,
      'has_more': offset + page.length < rows.length,
    };
  }
}

AppState etat(FakeApi api) {
  final st = AppState();
  st.token = 'jeton-test';
  st.phone = '+243810000001';
  st.ready = true;
  st.api = api;
  return st;
}

Widget enveloppe(AppState st) {
  MC.apply(kPalettes['fleuve']!);
  return ChangeNotifierProvider<AppState>.value(
    value: st,
    child: MaterialApp(theme: mboteTheme(), home: const TransactionsScreen()),
  );
}

Map tx({
  String type = 'call_debit',
  int montant = -120,
  String statut = 'confirmed',
  String ref = 'call_1',
  int? quand,
}) =>
    {
      'id': 'tx_$ref',
      'type': type,
      'amount_cents': montant,
      'method': 'wallet',
      'reference': ref,
      'status': statut,
      'created_at': quand ?? DateTime.now().millisecondsSinceEpoch,
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.lang = 'fr';
  });

  testWidgets('un débit s’affiche « − » et un crédit « + »', (tester) async {
    final api = FakeApi()
      ..rows = [
        tx(type: 'call_debit', montant: -120),
        tx(type: 'topup', montant: 1000, ref: 'topup_1'),
      ];
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    expect(find.text('−${fmtMoney(120)}'), findsOneWidget);
    expect(find.text('+${fmtMoney(1000)}'), findsOneWidget);
  });

  testWidgets('une écriture en attente est signalée comme telle',
      (tester) async {
    final api = FakeApi()
      ..rows = [
        tx(type: 'topup', montant: 2000, statut: 'pending', ref: 'topup_p'),
      ];
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    expect(find.textContaining(L10n.t('wallet_status_pending')), findsOneWidget);
  });

  testWidgets('une écriture échouée est barrée', (tester) async {
    final api = FakeApi()
      ..rows = [tx(type: 'topup', montant: 2000, statut: 'failed', ref: 'x')];
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    final textes = tester.widgetList<Text>(find.byType(Text)).toList();
    final montant = textes.firstWhere((t) =>
        (t.data ?? '').contains(fmtMoney(2000)) &&
        (t.data ?? '').contains('+'));
    expect(montant.style?.decoration, TextDecoration.lineThrough);
    expect(find.textContaining(L10n.t('wallet_status_failed')), findsOneWidget);
  });

  testWidgets('le filtre « Appels » interroge le serveur avec call_debit',
      (tester) async {
    final api = FakeApi()..rows = [tx()];
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    await taperFiltre(tester, L10n.t('tx_calls'));

    expect(api.requetes.last['type'], 'call_debit');
  });

  testWidgets('le filtre « En attente » ajoute status=pending',
      (tester) async {
    final api = FakeApi()..rows = [tx()];
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    await taperFiltre(tester, L10n.t('wallet_pending_only'));

    expect(api.requetes.last['status'], 'pending');
  });

  testWidgets('aucune transaction : message vide, pas d’écran blanc',
      (tester) async {
    final api = FakeApi()..rows = [];
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    expect(find.text(L10n.t('tx_empty')), findsOneWidget);
  });

  testWidgets('erreur réseau : message + Réessayer', (tester) async {
    final api = FakeApi()..erreur = Exception('réseau');
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    expect(find.text(L10n.t('chat_retry')), findsOneWidget);
  });

  testWidgets('la suite est chargée sans recharger la première page',
      (tester) async {
    final api = FakeApi()
      ..rows = List<Map>.generate(
          60, (i) => tx(ref: 'r$i', montant: -1 * (i + 1), quand: 1700000000000 + i));
    await tester.pumpWidget(enveloppe(etat(api)));
    await tester.pump();

    expect(api.requetes.length, 1);
    expect(api.requetes.first['offset'], 0);

    // On défile jusqu'en bas → deuxième requête avec offset=40.
    await tester.drag(find.byType(ListView).last, const Offset(0, -3000));
    await tester.pump();
    await tester.pump();

    expect(api.requetes.length, greaterThanOrEqualTo(2));
    expect(api.requetes.last['offset'], greaterThan(0));
  });
}
