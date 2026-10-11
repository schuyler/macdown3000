# Relecture complète — conversion des titres dans le texte source

Date : 2026-10-09. Extension de périmètre confirmée depuis le consommateur `MPDocument` : le bouton Texte normal doit effectivement supprimer le statut de titre dans la source. Lecture et analyse achevées ; certification de livraison en attente des gates finales natives/UI du parent. Aucun commit, installation ou push effectué par ce lot.

## Versions et lectures intégrales

| Fichier | Lecture finale non tronquée | SHA-256 |
| --- | --- | --- |
| `MacDown/Code/Extension/NSTextView+Autocomplete.h` | 1–40 | `9412de885b8ff167500177ee83787e485eed5cd4d1ea2de781f4ea3d15ef40e2` |
| `MacDown/Code/Extension/NSTextView+Autocomplete.m` | 1–250, 251–500, 501–805 | `2e6d7472c314e9f24f4236f1f5398cb92e2e3021e8f7162e5767af209c07da4f` |
| `MacDownTests/MPUtilityTests.m` | 1–250, 251–500, 501–750, 751–1000, 1001–1137 | `9eeb1a1f7622d435cb8f79d2eaffbc55e30a5fcf8f33ab8b31dbe78fb88b5429` |

Les versions initiales du helper (39/729 lignes) et des tests (999 lignes) ont aussi été lues intégralement avant correction. Les plages finales ci-dessus ont été relues après les dernières modifications, sans hériter de la lecture initiale.

## Défaut confirmé et cause

L'ancien helper ne retirait que les préfixes ATX par regex `^(#+ )*`, indépendamment de la syntaxe réellement interprétée. `Title\n====` restait titre, `# Title ###` exposait le suffixe, les conversions de niveau conservaient le soulignement Setext. Les opérations coupaient uniquement sur LF. Ces problèmes existaient avant cette correction et sont reproduits en tests natifs RED : `queue-boundaries-green-source-headings-red.log`, 1 test source, 17 assertions en échec, restauration des préférences confirmée par le parent.

La conversion doit aussi préserver le sens du contenu : `# - Title`, `# # Title`, `# 1. Title` ne doivent pas devenir liste/titre, et `# Title\n---` ne doit pas fabriquer un nouveau titre Setext. RED avant correction : `source-headings-literals-red.log`, 1 test, 17 assertions en échec. Le correctif traite ces variantes de la même cause métier, pas un second pipeline.

## Implémentation et contrats

- Une seule API `makeHeaderForSelectedLinesWithLevel:renderMarkdown:`. Les sept consommateurs H1–H6/Texte normal fournissent le snapshot du renderer du document, avec ses options effectives. Tous les usages et déclarations ont été recherchés par `rg`; aucun ancien sélecteur dynamique ni référence nib/resources trouvé. Ancienne signature retirée.
- Énumération physique des lignes conservant exactement LF/CRLF, EOF vide et limites UTF-16. Un probe du document complet contient les candidats balisés et passe par le parser applicatif réel ; aucun renderer temporaire aux options supposées.
- ATX reconnu seulement si le marqueur injecté appartient réellement au début du corps d'un titre. Setext exige un rendu local unique de titre ET un marqueur en fin du corps dans le document complet : contexte fences, HTML et voisinage conservé. Un snapshot absent provoque un abandon avant mutation.
- Le suffixe ATX suit la règle Hoedown : hashes terminaux, puis espaces avant ceux-ci. Les hashes suivis d'espaces sont du contenu littéral. Une attente initiale du test sur `### Title ###  ` a été corrigée après confrontation au parser réel : Hoedown produit `Title ###`, et la conversion conserve ce contenu.
- Pour Texte normal, le contenu doit réellement devenir un unique paragraphe. Échappement Markdown minimal d'un marqueur initial seulement si la parse prouve sa nécessité, puis reparsing du paragraphe. Aucun HTML ajouté. Une ligne vide sépare un voisin ressemblant à Setext si sa proximité transformerait le texte converti. Une conversion non prouvée reste inchangée.
- Remplacement atomique `insertText:replacementRange:` ; mapping des deux bornes sélectionnées tenant compte de préfixes, suffixes, ligne Setext retirée, slash ajouté et newline conservée. Undo/redo natifs vérifiés par les tests. Une conversion sans changement ne crée pas d'édition.

## Relevé de toutes les autres fonctions et branches

L'ensemble de l'extension a été examiné : tableau de paires et quotes Unicode ; `substringInRange` (bornes/prefix/suffix, strong vs emphasis) ; tabulation par colonne et IME sentinel ; dispatch insert simple/remplacement et wrapping ; autoquote/macOS/markedText/paires/skip fermeture ; wrapping simple/markup/strike ; suppression de paire et bornes ; désindentation par espaces et colonne ; toggle inline et conservation sélection ; toggle bloc regex, marqueurs complets, ajout/retrait et mapping ; indentation et dernier composant vide ; désindentation tabs/espaces et bornes ; contenu image mappé/statique/tempfile ; liste vide/nonvide, bullet/number/increment/réutilisation de marqueur ; continuation quote/réutilisation ; continuation indentation. Aucun nouveau défaut confirmé dans les parcours fusionnés de ces fonctions à la relecture finale.

Les 1137 lignes de tests ont été relues : fixtures temporaires, thèmes/styles/pruning/hash, JavaScript/Unicode, clipboard/files/frontmatter, édition/selection/undo, YAML/aliases/stream close/mutabilité, styleparser, URL paste et géométrie. Les nouveaux tests utilisent NSTextView/AppKit et MPRenderer/Hoedown effectifs ; mockdelegate transporte uniquement les options.

Dépendances consultées : renderer audité intégralement séparément ; parser Hoedown `is_atxheader`, `is_headerline`, `parse_atxheader`, `parse_paragraph` dans `Pods/hoedown/src/document.c`. Avec SPACE_HEADERS, Hoedown accepte l'espace ASCII après hashes, pas une tabulation ; les tests préservent `#\tTitle` et sept hashes sans espace dans ce mode. Sans cette option, sept hashes peuvent légitimement être H6 avec un hash contenu. La logique de `parse_paragraph` limite un Setext à la dernière ligne du paragraphe précédent : aucun retrait des lignes de prose antérieures.

## Tests et seconde passe

Six tests source ciblés ont réussi dans `source-headings-final-green-autosave-red.log` : 0 échec, 0,146 s. Le test de volume a converti 1000 titres/19890 unités UTF-16 en 0,122475 s : 1 parse du document complet + 1000 snapshots de contenu courts. Assertions sur source complète, rendu sans H2, caractères Unicode, sélection et bornes ; aucune assertion de seuil temporel arbitraire. Le log général reste RED pour le test autosave indépendant du Document.

La seconde passe a identifié un risque introduit dans l'implémentation intermédiaire : un `<h1>` HTML contenant un texte suivi de `====` pouvait satisfaire un marqueur simplement présent dans le corps. Le helper final exige le marqueur terminal et le test littéral comporte ce cas. Deux autres cas demandés en revue (sept hashes et tabulation avec SPACE_HEADERS) ont été ajoutés sans changer la regex après vérification de la grammaire Hoedown. Ces derniers ajouts et le fail-fast snapshot nil requièrent le nouveau gate natif final ; les verts précédents ne certifient pas cette empreinte.

Aucun défaut confirmé encore ouvert dans ce lot à la fin de la lecture. Validation globale, vérification des consommateurs Document et commit de la cause unique centralisés par le parent.


## Gate final ciblé

`pass2-final-targets-green.log` : six tests Utility et le test réel draft/sauvegarde, **7 réussis, 0 échec**, 2,217 s, XCTest `Test-MacDown-2026.10.09_01-06-35-+0200.xcresult`. Les derniers cas HTML littéral, tabulation/sept hashes et snapshot absent sont inclus ; préférences restaurées. Correction de cause unique commitée par root dans `ee253cc`. Suites et build de clôture référencés séparément dans `squashed-cloture.md`.


## Validation de livraison après les lectures

Les attentes de contrôles mentionnées plus haut décrivent l'état au moment des lectures. Clôture du parent : **1 471 XCTest, 13 XCUITest, 65 contrats CLI réussis**, syntaxe JS correcte et Release universel signé localement vérifié. Aucun changement de source depuis la version finale intégralement relue. Validation dans le périmètre vérifié, commandes/empreintes/limites dans [la clôture](squashed-cloture.md) et [verification.json](squashed-verification.json).
