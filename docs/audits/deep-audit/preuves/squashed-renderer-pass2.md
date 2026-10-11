# Renderer — nouvelle lecture indépendante, passe 2

Date : 9 octobre 2026. Nouvelle lecture complète demandée du code fusionné, sans réutiliser une ancienne case « lu ». Aucun fichier source ni index modifié pendant cette passe.

## Lecture complète actuelle

| Fichier | Plages effectivement relues, sorties non tronquées | SHA-256 actuel | Résultat |
| --- | --- | --- | --- |
| `MacDown/Code/Document/MPRenderer.h` | 1–84 | `897256ea8bb4616dec80592c49c7e02c82bc1ad42f3a43f7c34cc23f213cba6d` | Lu, analysé |
| `MacDown/Code/Document/MPRenderer.m` | 1–250, 251–500, 501–750, 751–953 | `cd6b9a332b52f2a160d9c530d59c1fae3246642fa01679953d8c827cafb418e2` | Lu, analysé |
| `MacDownTests/MPMarkdownRenderingTests.m` | 1–330, 331–660, 661–990, 991–1310 | `44f669b2b84c7a39c8b606798e90b6feedd0a79a3a31de9a6e24cbf97e1460a1` | Lu, analysé ; 2 tests ciblés verts |

Les empreintes sont identiques à la passe précédente, mais la présente lecture a bien été refaite. Les helpers de tests h/m ont également été relus intégralement. Les consommateurs actuellement modifiés ont été suivis : `installPreviewEditor` contrôle la source publiée, le token bridge/meta et l’URL du document avant de mapper ; chaque probe passe par `HTMLForMarkdownSnapshot`. `userDefaultsDidChange` propage les flags renderer avant parse. Les conversions bloc emploient également les snapshots pour distinguer titres setext et règles horizontales. La passe ne prétend pas lire entièrement MPDocument, attribué au lot Document.

## Fonctions et branches revérifiées

1. API h : flags, weak datasource/delegate, propriétés checkbox read-only, parse immédiate/différée, invalidation préférences, snapshot/export, timestamps et deux options delegate facultatives. Aucune nouvelle publication implicite de snapshot dans ce contrat.
2. Helpers URLs : Extensions, Prism minifié/non minifié, extras et dépendances. `add_to_languages` réordonne chaque langue après ses dépendances ; `language_addition` normalise les alias depuis la carte bundled chargée via `dispatch_once`, ajoute au registre local reçu et renvoie son buffer propre. Une langue non bundled n’est pas exécutée depuis un chemin arbitraire par le snapshot.
3. Parse C et preprocessing : HTML et TOC utilisent des renderers/contextes séparés ; flags/extensions/SmartyPants/front matter sont transmis ; durée de vie des tokens explicite, buffers/documents libérés ; template regex TOC échappé, callouts terminés et marqueurs tasks retirés. Chaque snapshot a ses propres slugs/langues/checkbox offsets et UUID.
4. Template/escape/CSP : titre échappé, head et body distincts, policies générées seulement pour le preview publié ; snapshot retourne du body uniquement. Assets CSS/scripts prennent leurs modes explicites. Les contraintes réseau/scripts du preview ne se substituent pas à la validation native du pont d’édition.
5. Construction/free/init : callbacks patchés cohérents, chaque champ extra initialisé, contexte conservé pendant parse, queue série et collections d’instance propres. Checkbox offsets headless traverse la même parse locale.
6. Accesseurs ressources : styles de base, Prism/line numbers/accessory, MathJax, Mermaid, Graphviz, tâches/table et styles export/print ; variantes liées aux options et ordre CSS examinés. Le registre de langues publié est utilisé lors du rendu/export ; le snapshot ne le remplace pas.
7. Parse asynchrone : capture main, cancellation avant/après parse, génération vérifiée au main avant publication, polling readiness non bloquant et borné. Entrées now/later, nil weak renderer et nouvelle génération examinées. Snapshot n’annule ni ne publie d’opération et ne perturbe donc pas une parse normale en attente.
8. Options et publication : parseOptions relit toutes les options parse ainsi que rendererFlags ; parseResult décale les offsets source après front matter et renvoie des copies ; publishParseResult seul attribue HTML/source/token/offsets/langues/options publiées. parseMarkdown synchrone invalide les anciennes opérations avant publication.
9. Invalidation/render : égalité nil-safe pour thèmes, wrapping facultatif protégé par respondsToSelector, changements de diagrammes/styles/accessoires déclenchent render ; CSP/checkbox token/wrapping puis ressources avant delegate ; cache-busting uniquement avec timestamps et baseURL. Les options publiées restent séparées de celles utilisées par les prototypes.
10. Timestamps/export : chemins nil ignorés, clear explicite ; styles/highlighting indépendants, scripts diagrammes/math hors highlighting, export.css dernier, titre vide admis. Export utilise currentHtml publié et n’incorpore pas les snapshots candidats. Le consommateur Document attend un rendu courant avant écriture.
11. Tests finaux : helpers golden et branche regeneration inchangés, tests Markdown standard/lists/code/tasks/Unicode/CRLF/TOC/slugs/limites Hoedown/underline/callouts revus ; sauvegarde/restauration de l’option underline dans finally, datasource/delegate réinitialisés par test. Les 2 nouveaux tests gardent Hoedown/preprocessor/assets réels et contrôlent des sorties consommées, pas un nom de méthode privée.

## Preuves actuelles de tests

Dans `build/SquashedPreviewAudit/native-red.log`, lignes 3906–3911 :

- `testMarkdownSnapshotsDoNotPublishOrChangeLivePreviewAndExportResources` : réussi, 0,010 s.
- `testMarkdownSnapshotUsesCurrentParseOptionsWithoutReplacingPublishedState` : réussi, 0,002 s.
- Sous-suite `MPMarkdownRenderingTests` ciblée : **2 tests, 0 échec**.

Le même lancement global finit en sortie 65 : les 3 tests Document visant les défauts alors reproduits échouaient (13 assertions). Cette sortie ne signifie pas réussite de la suite complète. Le coffre signale la restauration des préférences à la ligne 3926. Les deux tests renderer sont réellement verts sur l’empreinte actuelle ; la clôture exige encore les suites finales natives/UI et build centralisés par le parent.

## Seconde passe critique actuelle

Hypothèses réexaminées : options courantes versus DOM vivant, état concurrent de parse, tokens aléatoires de preprocessing, registres slugs/langues et transfert de buffers C, code blocks et callouts dans prototypes, nil/empty Markdown, exports après probes. Les résultats de parse sont locaux jusqu’à publishParseResult, et le snapshot n’appelle pas ce dernier. Les cartes statiques sont immuables après dispatch_once ; les registres mutables/contextes restent propres à chaque parse. La barrière source/token/URL actuelle du Document protège l’installation contre un résultat publié pour un autre état ; les probes comparent le DOM ordonné avant d’exposer une correspondance.

Aucun défaut confirmé supplémentaire dans ce lot. Aucun changement cosmétique, retrait legacy ou refonte ajouté sans cause établie. État : **lecture et analyse complètes ; validation d’intégration finale en attente**, sans promesse d’absence absolue de défauts.


## Validation de livraison après les lectures

Les attentes de contrôles mentionnées plus haut décrivent l'état au moment des lectures. Clôture du parent : **1 471 XCTest, 13 XCUITest, 65 contrats CLI réussis**, syntaxe JS correcte et Release universel signé localement vérifié. Aucun changement de source depuis la version finale intégralement relue. Validation dans le périmètre vérifié, commandes/empreintes/limites dans [la clôture](squashed-cloture.md) et [verification.json](squashed-verification.json).
