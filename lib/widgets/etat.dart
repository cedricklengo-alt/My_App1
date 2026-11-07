import 'package:flutter/material.dart';

import '../design.dart';
import '../theme.dart';

/// ─────────────────────────────────────────────────────────────
/// États premium : erreur, chargement, succès, vide, hors-ligne…
///
/// Un seul composant pour remplacer les textes bruts (« Erreur »,
/// « Failed ») : icône Material pertinente, titre, sous-titre et
/// bouton de relance facultatif. Aucun emoji dans l'interface.
/// ─────────────────────────────────────────────────────────────

/// Icônes d'état prédéfinies (Material Symbols, jamais d'emoji).
class EtatIcon {
  static const erreur = Icons.error_outline_rounded;
  static const horsLigne = Icons.wifi_off_rounded;
  static const indisponible = Icons.cloud_off_rounded;
  static const vide = Icons.inbox_rounded;
  static const aucunResultat = Icons.search_off_rounded;
  static const succes = Icons.check_circle_rounded;
  static const avertissement = Icons.warning_amber_rounded;
}

/// Grand état centré : icône + titre + sous-titre + action « Réessayer ».
class EtatPage extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String? sousTitre;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Couleur de l'icône (défaut : kaki atténué ; succès → savane, erreur → rouge).
  final Color? couleurIcone;

  const EtatPage({
    super.key,
    required this.icone,
    required this.titre,
    this.sousTitre,
    this.actionLabel,
    this.onAction,
    this.couleurIcone,
  });

  /// États prêts à l'emploi.
  factory EtatPage.erreur({String titre = 'Une erreur est survenue', String? sousTitre, String actionLabel = 'Réessayer', VoidCallback? onAction}) =>
      EtatPage(icone: EtatIcon.erreur, titre: titre, sousTitre: sousTitre, actionLabel: actionLabel, onAction: onAction, couleurIcone: MC.rouge);
  factory EtatPage.horsLigne({VoidCallback? onAction}) =>
      EtatPage(icone: EtatIcon.horsLigne, titre: 'Connexion perdue', sousTitre: 'Vérifiez votre connexion Internet, puis réessayez.', actionLabel: 'Réessayer', onAction: onAction);
  factory EtatPage.indisponible({VoidCallback? onAction}) =>
      EtatPage(icone: EtatIcon.indisponible, titre: 'Service indisponible', sousTitre: 'Nos serveurs ne répondent pas pour le moment.', actionLabel: 'Réessayer', onAction: onAction);
  factory EtatPage.vide(String titre, {String? sousTitre, String? actionLabel, VoidCallback? onAction}) =>
      EtatPage(icone: EtatIcon.vide, titre: titre, sousTitre: sousTitre, actionLabel: actionLabel, onAction: onAction);
  factory EtatPage.aucunResultat(String requete) =>
      EtatPage(icone: EtatIcon.aucunResultat, titre: 'Aucun résultat', sousTitre: 'Aucun résultat pour « $requete ». Essayez un autre mot-clé.');
  factory EtatPage.succes(String titre, {String? sousTitre}) =>
      EtatPage(icone: EtatIcon.succes, titre: titre, sousTitre: sousTitre, couleurIcone: MC.savane);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (couleurIcone ?? MC.kaki).withValues(alpha: .12),
              ),
              child: Icon(icone, size: 36, color: couleurIcone ?? MC.kaki),
            ),
            const SizedBox(height: 16),
            Text(titre,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: MC.ivoire,
                    fontSize: Tx.subtitle,
                    fontWeight: FontWeight.w800)),
            if (sousTitre != null && sousTitre!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(sousTitre!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: MC.kaki, fontSize: Tx.body, height: 1.4)),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: MC.soleil,
                  foregroundColor: MC.onAccent,
                  minimumSize: const Size(0, 48), // cible tactile ≥ 48 dp
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Rd.pill)),
                ),
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(actionLabel!,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Petit état en ligne (dans une liste vide, par ex.) : icône + texte.
class EtatLigne extends StatelessWidget {
  final IconData icone;
  final String texte;
  const EtatLigne({super.key, required this.icone, required this.texte});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icone, size: 20, color: MC.kaki),
          const SizedBox(width: 8),
          Flexible(
            child: Text(texte,
                style: TextStyle(color: MC.kaki, fontSize: Tx.body)),
          ),
        ],
      ),
    );
  }
}
