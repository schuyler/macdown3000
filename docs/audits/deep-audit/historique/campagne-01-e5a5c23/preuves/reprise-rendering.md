# Reprise intégrale du rendu — 2026-10-07

Périmètre attribué : renderer application, renderer Quick Look, préprocesseur commun, callbacks Hoedown et contrôleur Quick Look, avec leurs tests et fixtures. Sources lues intégralement, fonctions et branches examinées ; aucune case de validation finale n'est attribuée par cette note. L'exécution Xcode est centralisée par l'agent principal. La suite complète finale a réussi (1416 tests, 0 échec) ; cela ne certifie pas les autres gates de livraison ni le reste du dépôt.

## Parcours et contrats

Application : MPDocument → MPRenderer.parseOptions → parseResultForMarkdown → préprocesseur → Hoedown/callbacks → publication HTML/langages/offsets source/token → preview ou export. Les options et texte sont capturés avant travail différé ; les générations empêchent une publication périmée. Les offsets UTF-16 d'origine restent alignés malgré normalisation CRLF et insertion de lignes/markers.

Quick Look : PreviewViewController (lecture fichier, propagation des erreurs et annulation) → MPQuickLookRenderer → même préprocesseur et callbacks Hoedown → styles embarqués/HTML sous CSP → WKWebView. Le rendu Quick Look garde ses variantes légitimes : pas de scripts, ressources distantes bloquées, checkboxes désactivées. Les anciennes fonctions de prétraitement et les copies de slug/blockcode Quick Look ont été retirées et leurs appelants remplacés ; aucun fallback runtime parallèle ne subsiste dans ces fichiers.

Symboles examinés : création/libération des renderers, mapping des langages/dépendances, options SmartyPants/frontmatter/TOC/extensions, readiness/générations/annulation, scripts/styles/cache-busting, URLs/assets/export ; scan de lignes/fences/quotes/listes/inline/backticks/références et markers/offsets ; callbacks blockcode/listitem/header/table_header/toc_header, UTF-8/slug/entités/tag remplacés ; lecture fichier/encodage/styles/wrapping/erreurs Quick Look ; lecture via renderer, identité des navigations et complétion/annulation du contrôleur Quick Look. Le contrôleur final ne contient ni sémaphore/deadline ni appel explicite startAccessingSecurityScopedResource ; le grant du fichier fourni par le host natif Quick Look reste à vérifier dans ce host.

## Corrections héritées réexaminées

- Pipeline Markdown commun : ancienne transformation regex injectait une ligne vide devant un tiret de code Objective-C, après certaines clôtures de fences et U+200B dans `]:`. Le scan contextuel et markers retirés lors du rendu conservent le contenu littéral. Tests app/QL couvrent listes, références, crochets et fence non fermée.
- Mapping des checkboxes : état local par renderer, markers avec positions source UTF-16, suppression des markers en sortie, rendu non interactif Quick Look. Consommateur MPDocument examiné par l'agent principal.
- Rendu différé : attente bornée non bloquante sur main queue et invalidation des résultats antérieurs ; tests chargement jamais terminé, rendu immédiat, requête concurrente plus récente.
- Info de fence : attribut `data-information` échappé HTML, test d'injection. Trimming des tâches : lecture sur l'indice final réel et limite `size > offset`, conservation des fermetures de paragraphes ; ancien décalage inspectait un autre octet et laissait des LF parasites.
- MathJax : préférence suivie dans les ressources du rendu, test activation/désactivation.
- PreviewViewController : correction de libération/annulation avec tests dédiée, commit séparé par l'agent principal.

## Nouveaux défauts confirmés

| Identifiant | Cause et correction | Non-régression |
|---|---|---|
| R-IDs | Des titres distincts ou répétés partageaient un id DOM. Registry par parse avec suffixes et réservation de chaque slug ; registry distincte pour TOC et même callback pour body/TOC/QL. | titres répétés, collision avec suffixe existant, fallback section, reset parse, href correspondants app/QL ; test C/C++ et golden syntax |
| R-fence | Fences dans conteneurs restaient actives après sortie quote/liste ; info valide contenant un seul backtick rejetée ; triple tilde dans info accepté alors que Hoedown refuse ; indentation clôture non conforme au parser. | six scénarios app/QL, reproduction rouge/verte standalone avec Hoedown installé |
| R-NUL | Décodage C-string tronquait body et TOC au premier octet NUL valide dans NSString. | conversion explicite bytes/length, paragraphe et titre après NUL, TOC complet |
| R-TOC | TOC utilisé comme replacement template interprétait dollars/backslashes du titre. | escapedTemplateForString, labels littéraux $5 et C:\path dans titre/TOC |
| R-entity-overflow | Accumulation uint32 des entités numériques débordait ; `&#4294967456;` devenait 160 et une ligne de header visible était supprimée. | garde avant multiplication, decimal et hex oversized, présence thead/cellule/body app/QL |

## Diagnostic des anciens attendus

Suite complète `/tmp/macdown-audit-reprise-full-tests.log` : 1408 tests, 8 échecs. Sept concernaient ce périmètre ; un relève du reload externe (agent principal).

Corrections manuelles minimales des fixtures, jamais de régénération globale : `code-languages.html` enlève uniquement le LF initial absent du code source Objective-C ; `regression-issue36.html` enlève uniquement le LF terminal ajouté par ancien prétraitement (la règle renderer retire déjà le LF terminal normal pour Prism) ; `regression-issue37.html` enlève uniquement cinq U+200B absents du code source ; `task-lists.html` et `mixed-complex.html` enlèvent uniquement les LF immédiatement avant `</li>` qui provenaient du trimming décalé, sans toucher texte/check/indices/imbrication ; `syntax-highlighting-languages.html` remplace uniquement id C++ `c` par `c-1`. L'ancien test exigeant deux ids identiques C/C++ est remplacé par des assertions exactes sur les deux destinations et l'unicité de c.

QL nestedquote oracle : la préférence autolink transforme l'URL texte en `<a>`, le test examine la structure de paragraphe `[id]: ` et conservation du contenu plutôt qu'imposer une URL non liée. La réalité du conteneur et absence de marker restent vérifiées.

## Vérifications et limites

- Harness compilé avec clang/Foundation, `Pods/hoedown/src/*.c` et callback production ; logs `/tmp/macdown-render-harness/latest.log` et `/tmp/macdown-render-harness/numeric-fixed.log`. Scénarios fences avant/après, collisions de titres, et tableau overflow reproduits.
- Xcode ciblé par agent principal : PDF tests2/test3 verts ; rendering tests6 avait un oracle QL autolink erroné corrigé depuis. Les sept échecs complets sont expliqués ci-dessus. Contrôle complet final orchestré : `/tmp/macdown-audit-reprise-full-tests3.log`, **1416 tests, 0 échec**, incluant IDs/fences/NUL/TOC/overflow et goldens corrigés. Les gates de livraison restent orchestrés par le coordinateur.
- `git diff --check` périmètre changements récent réussi.
- Le slug garde son contrat existant (Latin-1 lowercased, autres scripts/emoji conservés) ; aucune prétention de parité totale github-slugger. Les liens fragment explicitement écrits vers un ancien id gardent la première occurrence ; TOC généré distingue les suivantes.
- Les variations JS/ressources entre application et Quick Look sont délibérées. Aucun fichier non lu ne doit être certifié à partir du seul succès des tests.

## Empreintes de la version examinée

Révision de référence au moment de la note : `f93bcb7340edf09aac41062bd7e488643f45f86a`, avec modifications locales et staging/commits orchestrés indépendamment.

| Fichier | SHA-256 |
|---|---|
| `MacDown/Code/Document/MPRenderer.h` | `45e93c4fd1c078842d10fdc835fbbc71f4f247709c6c468d9d53755a6eff1d4e` |
| `MacDown/Code/Document/MPRenderer.m` | `a939696a43b801dd5f59e28a731865c24b6bdf3ec092f5c997ae65667370ecff` |
| `MacDownCore/MPQuickLookRenderer.h` | `8624df9faeb328e0c4ae1e3ad5ac82da4487fd9697dec3495849a90681908400` |
| `MacDownCore/MPQuickLookRenderer.m` | `f7637311c6c552fe5e0143790a7a83c3b229ff03fe5d07adfb833071e99b4bd5` |
| `MacDownCore/MPMarkdownPreprocessor.h` | `ed5e8e88ac2b0daf36d5907a8c676c51da858470f08858cc5370ee879adb65cf` |
| `MacDownQuickLook/PreviewViewController.m` | `6fad5f1905f4566f9a6e77c6b4436fcb815669020f8490b14d60f5c02765f76d` |
| `MacDown/Code/Extension/hoedown_html_patch.h` | `763870f5ef85caee5a24198c1493f4f8da72690bb434e4415085eec579221d84` |
| `MacDown/Code/Extension/hoedown_html_patch.c` | `12676962fcb7f21e22b57c361ff28a010d5f8581bf51e80ce031d072913259bf` |
| `MacDownTests/MPRendererStateTests.m` | `008e205f58ab1184ae9cef2f1ce8e8d7469c9c59db81bbb70dbc9403cb7cda6f` |
| `MacDownTests/MPQuickLookRendererTests.m` | `f9c5f0bcf40463d89702191567fec7ce4cb138fa2b9ebaf3551aa77893022fc9` |
| `MacDownTests/MPRendererEdgeCaseTests.m` | `786214242466832b180648aaee41085e46df00a8fdf91cf1bea5feea85b90af3` |
| `MacDownTests/MPMarkdownRenderingTests.m` | `cc3237ee1da3a99745f70599d6563fa6e5b83e3a802a51bcf111fa86a2b8aded` |
| `MacDownTests/MPSyntaxHighlightingTests.m` | `3e984c711b1d87b7a43d0390f37aaf37903650108500968f1533b314ac170b75` |
| `MacDownTests/MPPreviewViewControllerTests.m` | `de815e9ac055c6c57313a8845c0d077b35d564a6add20e349c89e6f847a045d3` |


## Décision manuelle finale par fichier — gates finaux 2026-10-07

Les lectures intégrales précédentes et leurs analyses des fonctions/branches demeurent la base de ces décisions ; les SHA servent seulement à identifier la continuité des versions. Le renderer Core modifié par RA01 a été relu intégralement dans sa version finale 372 lignes, y compris home getpwuid_r, priorité/fallback des deux ressources, options/Hoedown, CSP, encodages et nettoyage. Controller h/m, préférences h/m, umbrella/plists et entitlements ont aussi été relus intégralement lors de cette décision. Aucun nouveau source ni build exécuté par cet agent.

Gates consommés : `/tmp/macdown-audit-final-full-tests.log`, 1427/0, dont MPQuickLookRendererTests 64/0 (véritable CoreRenderer), MPPreviewViewControllerTests 9/0 (WKWebView substitué, limite ci-dessous), ainsi que les tests app/Hoedown ; Debug et Release clean universels 0 selon reprise-root. Le sandbox signé ad hoc RA01 consomme le véritable renderMarkdown non vide et les CSS user/bundle ; RS01 consomme CFPreferences réellement et vérifie le refus d’écriture. Ces preuves n’équivalent pas à un lancement du host Finder.

| Fichier | Décision proposée | Contrat et preuves spécifiques |
| --- | --- | --- |
| MacDown/Code/Document/MPRenderer.h | Validable | API parsing/options/publication et ressources cohérente avec tous consommateurs MPDocument ; compilation deux architectures et tests app réels. |
| MacDown/Code/Document/MPRenderer.m | Validable | Snapshot/générations async, HTML/langages/offsets source, TOC/resources/options, corps NUL, literal templates ; application/WebView/Mermaid/PDF consommés par tests et gates app UI. Aucun pipeline Markdown divergent conservé. |
| MacDownCore/MPMarkdownPreprocessor.h | Validable | Scan commun conteneurs/fences/inline/références, tokens/offsets source UTF-16 ; fixtures app/QL, rouges standalone puis verts, suite finale. |
| MacDown/Code/Extension/hoedown_html_patch.h | Validable | Contrat opaque par parse, callbacks/task markers/slugs partagé des deux moteurs ; deux compilations/consommateurs et tests communs. |
| MacDown/Code/Extension/hoedown_html_patch.c | Validable | Blockcode/info escaped, listes/tables/TOC, entités bornées et IDs uniques/reset ; invariants Hoedown/app/Core64/goldens et tests C consommateurs. |
| MacDownCore/MPQuickLookRenderer.h | Validable | API Markdown/string/URL/error réelle appelée par Core64, contrôleur et harness sandbox signé. |
| MacDownCore/MPQuickLookRenderer.m | Validable | Markdown/encodages/CSP/styles, shared callbacks et priorité user/bundle ; Core64 + RA01 véritable renderer sandbox, fallback et refus écritures ; aucune exécution script ou ressource distante revendiquée. Version finale SHA ac4f7b… consignée en RA01. |
| MacDownCore/MPQuickLookPreferences.h | Validable | Interface defaults/flags/diagram-disabled consommée par renderer réel et tests préférences. |
| MacDownCore/MPQuickLookPreferences.m | Validable | Valeurs/domaines/types/defaults/flags et restrictions diagrams ; tests getters + RS01 lecture réelle CFPreferences/AppSandbox, refus write et valeur intacte. |
| MacDownCore/MacDownCore.h | Validable | Umbrella export des deux APIs et symboles version ; consommateurs Core/compilation framework et clean builds universels. |
| MacDownCore/Info.plist | Validable | Métadonnées framework substituées dans le produit, framework embarqué résolu/compilé ; clean builds et packaging contrôlés. |
| MacDownQuickLook/MacDownQuickLook.entitlements | Validable pour sa politique | Domaine exact read-only et deux dossiers exacts read-only réellement imposés en sandbox ; refus voisins/écritures, entitlement embarqué et signature ad hoc contrôlés. La signature de distribution n’est pas exécutée. |
| MacDownQuickLook/PreviewViewController.h | Validable après preuve native R15 | Conformances publiques compilées et tests interface/lifecycle réussis ; QLPreviewView natif active le contrôleur final UUID isolé, WK load/finish/paint réels (reprise-quicklook-natif.md). |
| MacDownQuickLook/PreviewViewController.m | Validable après preuve native R15 | Navigation identity, one-shot complétion/remplacement/annulation, JavaScript désactivé et policy étudiés. Les 9 tests substituent MPTestWKWebView, complétés maintenant par contexte extension natif, grant du fichier synthétique et WebContent82847 load/finish/paint. Aucune inspection visuelle/Finder direct revendiquée. |
| MacDownQuickLook/Info.plist | Validable après preuve native R15 | Point com.apple.quicklook.preview/principalClass/UTI/extensions et versions du produit cohérents/compilés, activation de cette extension vérifiée sous identité/UTI uniques avec le host public QLPreviewView ; sélection de l’identité utilisateur dans Finder non modifiée. |

Cette proposition ne coche aucune ligne automatiquement. La décision finale d’inventaire revient au coordinateur. Le lot rendu/Core est validable dans ses contrats consommés ; le contrat natif Quick Look est désormais couvert par reprise-quicklook-natif.md (R15), avec limites capture visuelle/Finder direct/distribution explicitement conservées. Les 12 fichiers Rendering/Core/politique et les 3 fichiers QL controller/info sont donc proposés validables après décisions manuelles sur chaque contrat, pas automatiquement par empreinte.
