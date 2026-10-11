# Preuve de lecture et d’analyse : renderer du commit fusionné

Périmètre : commit `dbc6b23`, ajout de `HTMLForMarkdownSnapshot:` et interactions nécessaires du renderer. Date : 9 octobre 2026. Aucun changement de production nécessaire après examen ; deux tests de caractérisation ajoutés. Ce lot ne certifie pas tout Quick Look, le patch C ou le document : leurs dépendances nécessaires ont été examinées.

## Versions lues

| Fichier | Lecture intégrale | SHA-256 | Analyse | Validation |
| --- | --- | --- | --- | --- |
| `MacDown/Code/Document/MPRenderer.h` | 1–84 | `897256ea8bb4616dec80592c49c7e02c82bc1ad42f3a43f7c34cc23f213cba6d` | Terminée | À vérifier par suite native |
| `MacDown/Code/Document/MPRenderer.m` | 1–250, 251–500, 501–750, 751–953 | `cd6b9a332b52f2a160d9c530d59c1fae3246642fa01679953d8c827cafb418e2` | Terminée | À vérifier par suite native |
| `MacDownTests/MPMarkdownRenderingTests.m` | Version finale : 1–330, 331–660, 661–990, 991–fin, sorties non tronquées | `44f669b2b84c7a39c8b606798e90b6feedd0a79a3a31de9a6e24cbf97e1460a1` | Terminée | Tests ajoutés non encore exécutés dans ce lot |

Dépendances lues intégralement pour vérifier les contrats : `MPRendererTestHelpers.h/.m`, `MPMarkdownPreprocessor.h` (329 lignes), `MPAsset.m`, `hoedown_html_patch.h/.c` (616 lignes C), `MPQuickLookRenderer.m` (376 lignes), template `default.handlebars`. Sections du document suivies : datasource/delegate, déclenchement des options, export HTML après rendu, appels des probes et de la transaction de mise en forme. La lecture de ces dépendances n’équivaut pas à une certification globale indépendante.

## Relevé des fonctions et branches

- URLs Extensions/Prism : ressources bundled, recherche minifiée puis non minifiée, extras et dépendances ; langues normalisées, alias remplacés dans classe CSS, registre propre à chaque résultat. La carte de dépendances chargée une seule fois reste immuable. Aucun registre de langues du renderer vivant n’est touché pendant un snapshot.
- `MPHTMLFromMarkdown` : preprocessing partagé, durée de vie explicite des tokens UTF-8 pendant Hoedown, création/destruction document/buffers, branche SmartyPants, rendu TOC indépendant avec slugs propres et échappement de template regex, callouts et retrait des marqueurs task. Profondeur de nesting limitée par constante partagée.
- `MPGetHTML` et échappements : titre échappé, head applicatif distinct du body Markdown, assets selon mode demandé. Le snapshot rend seulement le body ; il ne prépare aucune page WebView ni aucun script. Le template fourni conserve la CSP avant le body. Les politiques preview et Quick Look ont des variations légitimes (Quick Look bloque scripts et réseau), non deux pipelines concurrents d’édition.
- Création/free des renderers C : contexte de parse local, registres slugs distincts pour body/TOC, checkbox index local, offsets et tokens locaux ; absence de pointeur vers un état mutable publié dans les callbacks. Les pointeurs restent vivants pendant la parse synchrone.
- Accesseurs CSS/scripts : style, highlighting, numéros de lignes, accessoire, task/table, Mermaid/Graphviz indépendants de Prism et MathJax. Export incorpore les ressources pertinentes et laisse le CDN MathJax en lien ; aucune option du popup n’est exportée par ce renderer.
- Initialisation/checkbox offsets : file série et collections propres à l’instance ; mode headless passe par la même parse. `parseResultForMarkdown:options:` capture source d’origine, décale les offsets après front matter, retourne ses propres HTML/langues/checkboxes/token sans publier.
- `HTMLForMarkdownSnapshot:` : utilise les options courantes via `parseOptions`, renvoie le HTML du résultat local. N’écrit ni génération, ni rendu publié, ni source/offset/token des checkboxes, ni préférences de rendu, ni file d’opérations. Les prototypes candidats peuvent contenir des langues différentes sans changer les ressources du document vivant.
- Parse asynchrone : capture Markdown/options sur main, annule les opérations précédentes ; cancellation avant/après parse, génération contrôlée avant publication et lors de readiness polling. Readiness ne bloque pas le main thread ; délai borné. Entrée synchrone headless invalide également les anciennes opérations. Les appels applicatifs de snapshot sont sur le main ; aucune garantie nouvelle d’accès concurrent aux propriétés du delegate n’est introduite.
- Invalidation parse/rendu : extensions/SmartyPants/TOC/front matter séparés des styles/diagrammes/accessoires ; flags renderer mis à jour dans le consommateur Document. Les options temporairement changées par une transaction sont relues par chaque snapshot ; le mapping source/DOM doit donc être vérifié par le Document, examiné dans le lot correspondant.
- `render` : head CSP/token, wrapping, ressources, cache-busting seulement si base URL et timestamps, livraison delegate et mémorisation des options courantes ; aucun chemin de snapshot ne l’appelle.
- Timestamps et export : ajout/suppression local, export consomme `currentHtml` et `currentLanguages` publiés. Le Document diffère l’export jusqu’au rendu courant, afin de ne pas publier un ancien body. Quick Look consomme la même compatibilité de preprocessing/patch C mais ne reçoit pas l’API d’édition ni de snapshot.

## Invariants et contrôles

| Contrat | Preuve / test | Résultat du lot |
| --- | --- | --- |
| Les probes ne remplacent pas le preview ou l’export vivant, ni ses ressources Prism | `testMarkdownSnapshotsDoNotPublishOrChangeLivePreviewAndExportResources` : document JavaScript/tasks publié, snapshots vide/Python/callout/nil ; HTML live et export comparés, page rendue après probes identique, langue Python absente | Ajouté ; exécution native centralisée à effectuer |
| Source, token et offsets de checkboxes du document vivant restent cohérents | Même test : comparaison des trois propriétés après chaque probe et publication de page contrôlée | Ajouté ; exécution native centralisée à effectuer |
| Snapshot utilise les options courantes sans publier celles-ci | `testMarkdownSnapshotUsesCurrentParseOptionsWithoutReplacingPublishedState` : front matter/TOC/underline/strike activés puis désactivés ; attentes HTML opposées et HTML publié inchangé | Ajouté ; exécution native centralisée à effectuer |
| Composant dont dépend la garantie réel | Les tests invoquent MPRenderer/Hoedown/preprocessor/assets effectifs ; seul le delegate/datasource transportant les options et réception de page est un adaptateur de test | Conception vérifiée ; suite requise |
| Diff valide | `git diff --check` | Réussi, code 0 |

Les suites précédentes ne servent pas à valider les nouveaux tests. Le parent sérialise les suites natives et UI dans le coffre qui restaure les préférences de l’utilisateur. Aucun xcodebuild, push, installation ou changement de données réelles exécuté par ce lot.

## Seconde passe critique

Réexamen : effets indirects du preprocessing à tokens aléatoires, cache statique des aliases Prism, registres slugs/checkboxes, lifetime des contextes C, options changeant pendant les probes, cancellation des opérations précédentes et consommation finale export. Les tokens aléatoires sont retirés du body ou conservés dans un résultat local non publié ; les registres mutables sont propres à chaque parse ; les structures statiques sont initialisées via `dispatch_once`. Les probes n’incrémentent pas la génération et n’annulent pas la parse légitime en attente. Le pipeline async et l’entrée synchrone partagent `parseResultForMarkdown` ; seul le snapshot contourne volontairement publication, pas les règles de parse.

Aucun défaut confirmé propre à ce parcours découvert. Ce constat ne garantit pas l’absence de bugs imaginables. Validation encore ouverte tant que les tests ci-dessus et les contrôles d’intégration du parent ne sont pas réussis sur les empreintes finales.

## Mise à jour des preuves natives (campagne actuelle)

Les deux tests de caractérisation ci-dessus ont été exécutés avec le renderer réel et ont réussi : `build/SquashedPreviewAudit/native-red.log`, lignes 3906–3911, 2 tests, 0 échec, 0,012 s. Le journal complet termine avec un échec des tests Document ciblés et ne constitue donc pas une validation intégrale. La relecture indépendante et les empreintes finales du renderer sont consignées dans `squashed-renderer-pass2.md`. Validation de livraison encore soumise aux suites natives et UI finales centralisées.
