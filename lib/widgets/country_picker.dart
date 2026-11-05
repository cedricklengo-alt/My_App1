import 'package:flutter/material.dart';

import '../countries.dart';
import '../design.dart';
import '../theme.dart';

/// Sélecteur de pays (inscription) : recherche instantanée + liste complète.
///
/// ⚠️ Aucun emoji drapeau affiché (règle design) : le « drapeau » est un badge
/// arrondi portant le code ISO du pays.
Future<Country?> showCountryPicker(BuildContext context, {Country? current}) {
  return showModalBottomSheet<Country>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MC.nuit2,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Rd.lg))),
    builder: (_) => _CountryPickerSheet(current: current),
  );
}

class _CountryPickerSheet extends StatefulWidget {
  final Country? current;
  const _CountryPickerSheet({this.current});
  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final q = TextEditingController();
  List<Country> results = kCountries;

  @override
  void initState() {
    super.initState();
    q.addListener(() => setState(() => results = searchCountries(q.text)));
  }

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: MC.ligne,
                      borderRadius: BorderRadius.circular(Rd.pill))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: q,
                  autofocus: true,
                  style: TextStyle(color: MC.ivoire, fontSize: Tx.bodyLg),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Rechercher un pays ou un indicatif…',
                    hintStyle: TextStyle(color: MC.kaki, fontSize: Tx.body),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: MC.kaki, size: 20),
                    filled: true,
                    fillColor: MC.nuit3,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Rd.pill),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: MC.ligne, indent: 64),
                  itemBuilder: (_, i) {
                    final c = results[i];
                    final sel = c.iso == widget.current?.iso;
                    return ListTile(
                      dense: true,
                      leading: _FlagBadge(iso: c.iso),
                      title: Text(c.name,
                          style: TextStyle(
                              color: sel ? MC.soleil : MC.ivoire,
                              fontSize: Tx.bodyLg,
                              fontWeight:
                                  sel ? FontWeight.w700 : FontWeight.w500)),
                      trailing: Text(c.dial,
                          style: TextStyle(
                              color: sel ? MC.soleil : MC.kaki,
                              fontSize: Tx.body,
                              fontWeight: FontWeight.w700)),
                      onTap: () => Navigator.of(context).pop(c),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vrai drapeau du pays (asset PNG), avec badge ISO en secours si absent.
class _FlagBadge extends StatelessWidget {
  final String iso;
  const _FlagBadge({required this.iso});
  @override
  Widget build(BuildContext context) {
    final path = 'assets/flags/${iso.toLowerCase()}.png';
    return ClipRRect(
      borderRadius: BorderRadius.circular(Rd.xs),
      child: Image.asset(
        path,
        width: 40,
        height: 28,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (_, __, ___) => Container(
          width: 40,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: MC.nuit3,
            borderRadius: BorderRadius.circular(Rd.xs),
          ),
          child: Text(iso,
              style: TextStyle(
                  color: MC.soleil,
                  fontSize: Tx.caption,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .5)),
        ),
      ),
    );
  }
}
