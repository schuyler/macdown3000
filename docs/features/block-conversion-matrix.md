# Matrice des conversions de blocs — 9 octobre 2026

## Couverture

Les tests sont dans `MacDownTests/MPDocumentLifecycleTests.m` :

- `testEveryEditableBlockConvertsToEveryBlockDestination` : **736 couples**, soit **32 sélections sources × 23 destinations**. Chaque couple est effectivement exécuté, y compris les conversions vers le même type.
- `testAllBlockSourcesRefuseDisabledDestinationsWithoutChangingSourceOrSelection` : **96 refus**, soit les mêmes 32 sélections × tâches/code/équation lorsque la syntaxe correspondante est désactivée.
- `testPreviewOrderedListWritesSequentialSourceNumbers` : vraie WebView, sélection des cinq lignes du signalement, conversion via le pont du visualiseur, Markdown exact `1.` à `5.`, cinq éléments rendus, voisin conservé. Compare aussi les options réelles du menu à la couverture de la matrice pour détecter une future option oubliée.
- `testOrderedListConversionWritesSequentialNumbersAndPreservesSelection` : douze lignes CRLF, passage de `9.` à `10.`, source exacte, bornes de sélection exactes et second clic sans changement.

| Sources et destinations | Précisions |
| --- | --- |
| Texte normal | Paragraphe |
| Titres H1 à H6 | H5/H6 sont pris en charge par le moteur ; le menu propose H1 à H4. |
| Listes à puces, numérotées, tâches | Syntaxe existante retirée avant application du type cible ; vrai rendu Hoedown. |
| Citation et code clôturé | Code littéral avec ses plages et frontières UTF-16 ; conversion code → code également couverte. |
| Callouts note/tip/warning/important/caution | Deux sélections par type : contenu et titre. L'autre partie doit être conservée. |
| Dépliant simple et titres dépliants H1 à H4 | Deux sélections par type : contenu et titre ; structure details/summary et niveau du titre contrôlés. |
| Équation | Destination supplémentaire, avec garde de désactivation. La matrice ne fabrique pas de sélection dans une équation générée par MathJax. |

Les 22 types éditables incluent les deux niveaux de titres internes supplémentaires. Les dix variantes de callouts/dépliants ont chacune deux sélections, ce qui donne 32 sources distinctes. L'équation porte le nombre de destinations à 23.

## Invariants

Chaque conversion doit être acceptée par le véritable endpoint natif, produire le bloc demandé, conserver le texte sélectionné une seule fois, conserver le titre/contenu non sélectionné d'un conteneur, préserver les voisins avant/après et ne pas générer de HTML dans la source. Les anciens délimiteurs de callout doivent disparaître lorsque la destination n'est plus un conteneur. Les tâches doivent produire une case ; les titres dépliants doivent avoir le niveau demandé. Chaque refus doit laisser la source et la sélection identiques.

Le parseur Markdown, le validateur des sélections et la transaction sont réels. Pour isoler les conversions, les tests fournissent les plages littérales du DOM à partir des fixtures, comme les tests de bloc existants. Le rendu est analysé comme XML après normalisation des seules balises void `input` des fixtures : le mode HTML tidy aplatissait les balises HTML5 aside/details/summary et produisait de faux échecs.

Cela constitue une matrice de contrats du moteur, pas 736 gestes de souris. Le scénario de numérotation et la parité barre/menu utilisent une vraie WebView. Le test d'interface de sélection mixte signalé dans `list-toolbar-parity.md` reste hors de cette validation ; il n'est pas présenté comme corrigé. Le rendu visuel des équations par MathJax n'est pas certifié par ces assertions de structure et de délimiteurs.

## Numérotation du Markdown

Le moteur écrivait un préfixe constant `1. ` sur chaque ligne. Markdown l'autorise, mais la source n'affichait pas les numéros successifs souhaités. Le commit `030d485` utilise désormais un compteur pour les lignes réellement converties et la longueur du préfixe réel pour restaurer la sélection, y compris à partir du dixième élément. Les boutons et le menu partagent ce comportement.

## Preuves locales

- `build/ListToolbarUnification/numbering-red.log` : reproduction avant correction.
- `build/ListToolbarUnification/numbering-verified.log` : six tests ciblés, sans échec.
- `build/ListToolbarUnification/conversion-matrix-accepted.log` : quatre tests regroupant les 736 conversions, 96 refus et deux scénarios de numérotation, sans échec.
- `build/ListToolbarUnification/matrix-artifacts/exercised-conversions.json` : export XCTest des 736 couples ; unicité, dimensions 32 × 23 et exhaustivité de chaque ligne vérifiées.
- `build/ListToolbarUnification/numbering-matrix-native-full.log` : **1506 tests natifs, 0 échec**, `TEST SUCCEEDED`. Les 736 conversions et 96 refus font partie de ces tests ; ils ne sont pas ajoutés au total XCTest.

Les sessions sont sérialisées dans le coffre de préférences, avec restauration vérifiée après chaque session terminée. Aucun push n'est demandé pour cette livraison.
