# Reprise — MPDocument

## Périmètre réellement relu

MPDocument.h intégral (52 lignes) et MPDocument.m hérité intégral (5273 lignes) lus par plages contiguës 1–650, 651–1300, 1301–1950, 1951–2600, 2601–3250, 3251–3900, 3901–4550, 4551–5273, sans sortie tronquée. Deux lignes nouvelles de setupEditor relues après correction flags ; les autres lignes de MPDocument sont identiques au snapshot hérité. La déclaration testing et les quatre nouveaux tests Lifecycle ont été relus à leur création ; MPExternalChangeReloadTests intégral avant modifications puis tous nouveaux hunks relus. MPRenderDeferralTests intégral. Lifecycle/IO/Style/Scroll/Checkbox : sections nécessaires examinées seulement ; une sortie cumulative tronquée n'est pas utilisée pour certifier ces fichiers entiers.

Dépendances : MPRenderer.h et MPResourceWatcherSet.m entiers ; MPRenderer.m 655–900 pour pipeline async/snapshot/publish/render/export, sections highlighter parseText et extensions + grammaire footnotes. Préférences/Sidebar/éditeur et YAML déjà entièrement examinés dans reprise-ui. Les sources rendering/PDF et build ont leur propriétaire d'audit distinct ; leurs preuves ne sont pas remplacées par une recherche de symboles.

## Tous les blocs examinés et contrats

Helpers inline et catégories NSURL/WebView/Preferences : flags extension/render cohérents, égalité nil-safe, préférences éditeur observées, catégories locales sans pipeline alternatif. DOM anchor JS : filtre éléments invisibles/script/style, décode fragments, occurrences conservées et ambiguïtés rejetées ; pipeline PDF relu, injection dans composant propriétaire PDF, sauvegarde temporaire puis replace atomique.

Accessors/init/nib : contenu chargé avant éditeur conservé, titres six comptes et sélection, fonts/throttle, ratio/zoom defaults, enregistrement KVO et notifications. Sidebar : canonicalisation root, installation avant nib, sync largeur/visibility sous ownership coordinator, activation existing vs nouveau document, erreurs propagées. Chargement/reload/close/save : sélection et viewport préservés/borne, générations protègent callbacks anciens, delegates détachés et watchers arrêtés au close, unsafe URL save bypass volontaire pour volume nonlocal, erreurs UTF8 et données avant nib prises en compte.

UI validation/actions : pane collapse ne masque pas le dernier pane, restore ratio, menus autosave/invisibles/zoom/sidebar. TextView : indent/newline/autocomplete/Backspace/SmartHome, typed attributes et undo. WebView : ressources MathJax locales, delegates limités mainFrame, navigation user/nonuser exécutables/scope gardés, copyHTML différé, context reload. Renderer : données/flags/délégation, DOM replacement vs reload full, jeton checkbox renouvelé, scripts/head et diagrammes, MathJax completion generations, ressources watcher coalescées.

Notifications/KVO : word count sélection vs totaux, transitions sync panes, resize/fullscreen/live scroll owners, thèmes et zoom. Exports et markup : fresh render queue FIFO, writeHTML atomique/erreur, PDF pending/annulation/callback ownership, headings/emphasis/links/images/table insertion, lists/blockquote/indent. Font/style/insets : extensions highlighter, baseline/style reset, tab4 espaces, width bounds, substitutions et editorOnRight. Scroll : classifier fences/ATX/setext/images/paragraphs/listes, align LCS/fallback, monotonic coordinates, interpolation, scroll-to-cursor et reverse, panescollapse. Checkbox : autorisation token, index ASCII/overflow, source snapshot/offset exact, edit1 caractère undoable, parse pipeline partagé avec renderer. External watcher : same-file prompt, dirty guards, coalescing et génération, reload file date snapshot, SaveAs/close protégés. Zoom shared : niveaux uniques et stepping/caps.

Aucun code obfusqué trouvé dans MPDocument, aucun legacy supprimé. Le classifier de références sert la géométrie, le parseur Hoedown sert le rendu ; le toggle checkbox utilise désormais les offsets du même renderer. DOM replacement et reload complet sont deux stratégies de publication nécessaires selon ressources/scripts, avec finishPreviewRender commun pour exporter seulement après completion.

## Défaut nouveau confirmé : extension notes inversée

setupEditor initialisait pmh_EXT_NOTES puis effaçait ce bit lorsque extensionFootnotes était activée. MPPreferences.extensionFlags fait l'inverse pour renderer, enum pmh_EXT_NOTES vaut bit0 et la grammaire conditionne Note/NoteReference sur EXT(pmh_EXT_NOTES). Correction minimale : partir de NONE, OR NOTES si préférence activée ; préserver OR MATH sous MathJax+dollar.

Régression testEditorFootnoteParsingFollowsPreferenceAndPreservesMath : huit combinaisons notes/math/dollar, vrai HGMarkdownHighlighter.parseText. La référence `Text[^*note*].` est opaque quand notes activées ; sans notes son contenu est une emphase Markdown. L'oracle initial pmh_NOTE était erroné car la grammaire ne crée jamais d'éléments NOTE : run7 a donné quatre échecs. Cet oracle a été remplacé après probe réel clang du pmh_parser.c généré, sans changer le parser : sans NOTES élément pmh_EMPH offsets6–12, avec NOTES absent. Le test vérifie ce comportement et le bit MATH indépendant, restaure les préférences et désactive le vrai highlighter. Résultat Xcode final encore attendu.

## Échec Discard de la suite complète

Log full : testDiscardReloadsFromDisk attendait reloadCount1 mais créait un document sans fileURL. Guard inherited promptURL refuse de recharger si URL a changé ; nil ne répond pas égal à nil. En application external change ne traite que fileURL.fileURL. Correction de précondition test : vrai fichier temporaire. Deux régressions ajoutées : Discard après SaveAs ne recharge pas nouveau fichier ; Discard après close ne recharge pas. Aucun guard production affaibli. `/tmp/macdown-audit-reprise-tests7.log` : ExternalChangeReload 31/31 réussis, nouveaux scénarios compris.

## Couverture des petites corrections héritées

- Underline : vraie action MPDocument + NSTextView produit `_text_` si extension active, `<u>text</u>` sinon ; vrai MPRenderer confirme `<u>` et absence `<em>` dans les deux modes.
- Backspace sélection : vraie commande NSTextView doCommandBySelector deleteBackward, sélection de `]` dans `[]` laisse `[` ; l'ancien auto-pair supprimerait les deux caractères.
- SmartHome : vrai NSLayoutManager sur `  😀` et caret à fin UTF16 doit déplacer le caret au premier caractère non whitespace position2. Conversion char→glyph évite plage basée sur compteur UTF16.

Ces trois tests utilisent les composants déterminants réels, dans Lifecycle existant, sans nouvel ajout au projet. Déclaration privée parseMarkdown: ajoutée dans category testing après diagnostic erreur compilation full2 ; production inchangée. Dernier résultat central restant.

## Plan de commits restant et snapshots

Root a déjà committé print callback, lazy IO, UTF8 et checkbox/renderer partagé. Fichier source divisé en snapshots cumulés, base immuable HEAD a859d8672a970fda7649b9069a80defeceb019ff ; `/tmp/macdown-document-commits/manifest.json` donne chemins et SHA. Toutes étapes recomposées donnent exactement workspace final, assertion du script réussie. Aucun staging/commit par cet agent.

| Étape | Correction | Hunks précis |
| --- | --- | --- |
| 01 | lifetime-watchers | documentClosed/fileWatchGeneration, setup différé/close, didProduce closed guard, stop/start generation, coalescing, promptURL, snapshot mtime avant read |
| 02 | checkbox-token résiduel B | propagation du nouveau token au meta DOM pendant remplacement body ; à rattacher correction B déjà committée |
| 03 | pdf-pending | property, garde dès save panel, libération cancel/close/didPrint ; dépend close01 |
| 04 | save-generation | property, ++ sur write et clear flag seulement si dernière save |
| 05 | fresh-render | previewRenderGeneration/awaiting, callback generation, mainFrame delegates/finishPreviewRender/error, completion MathJax et nonMathJax, performAfterRender toujours demandé ; MPRenderDeferralTests déjà commités root A |
| 06 | resource-coalescing | property et callback resourceWatcherSet async main, identité/closed guard |
| 07 | head-refresh | property head, comparaison scripts normalise token, full reload head/diagrammes, invalidate head |
| 08 | html-write | write atomique et propagation erreur |
| 09 | scroll-memory | allocation bornée LCS ≤8MiB, fast identical et fallback monotonic |
| 10 | scroll-bounds | visible-height guards, signed index compare et clamp coordinates forward/cursor/reverse |
| 11 | underline | extension active markup sinon balise u ; test dédié |
| 12 | selected-backspace | garde !selectedRange.length ; test dédié |
| 13 | glyph-smart-home | deux conversions glyphRangeForCharacterRange ; test dédié |
| 14 | footnotes nouveau | correction flags deux lignes ; test parser huit combinaisons |
| 15 | print-comment résiduel | commentaire convention callback, pas nouveau défaut ; rattacher ancien commit print |

Snapshots Lifecycle tests-01-underline, tests-02-selected-backspace, tests-03-glyph-smart-home, tests-04-footnotes sont cumulés indépendamment, dernier exactement workspace. Snapshot original héritage complet conservé avant nouveaux changements : `/tmp/macdown-document-inherited.m` SHA15dc67aebb85ada717967653ec4bd16360737e930c4007da28a68718e225e427 ; Lifecycle inherited b79c88d261864b55aa271744912cfb2b7decc05cf2cc7045f26dde0d4089f62e ; External inherited165d95b7b7ca204002e384ff9e538e79113d4af3ea456dabaed0f7e3604abc03.

## Empreintes et statut

| Source | SHA-256 version examinée | Lecture | Analyse | Validation globale |
| --- | --- | --- | --- | --- |
| MPDocument.m | 255fa0e18a12763d3a409a90ac92b2e537f1aa38c4a445a49683337c42b50374 | entière5273 + hunk flags relu | entière | ouverte |
| MPDocument.h | f70d0155da4792f9f0a49dbdb8edb98f4d49474d819e016a05ad417f747bb485 | entière | entière | ouverte |
| MPExternalChangeReloadTests.m | 45e4664a2b9fca1e4053b7a21927504f849e7773dd75afec42fa1b7e2f4707fe | entière + hunks finaux | scénarios concernés | ciblée31/31 ; globale ouverte |
| MPDocumentLifecycleTests.m | bceb48c8a625a91bb4a52d9e75f66d3bc3a217295a2727313e619cbe1e6d39d8 | partielle explicite | nouveaux tests et héritage concernés | ouverte |

Git diff --check du périmètre corrigé réussi. Suite globale full1408 avec8échecs antérieure à nouveaux tests : un test External corrigé, sept fixtures rendering/syntax confiées propriétaire rendering. Aucun fichier certifié livré par seul hash/grep. Xcode centralisé root, tests finaux/package/smoke restent gates de livraison.

## Gate XCTest finale reçue

`/tmp/macdown-audit-reprise-full-tests3.log` : suite All tests réussie, 1416 tests, 0 échec, 18,551 secondes. Les quatre nouveaux tests Lifecycle (footnotes8combinaisons, underline, selectedBackspace, SmartHome) passent réellement, de même que deux tests de rendu/toggle underline apportés par propriétaire rendering et les scénarios External. La version de test finale ci-dessus est celle exercée. L'échec d'oracle run7 et l'erreur de déclaration full2 sont résolus, pas ignorés. Source stable pour builds clean/root ; validation livraison reste distincte des contrôles tests (clean builds/package/smoke encore root).

## Régressions renforcées sur cinq corrections déjà commitées

MPDocumentLifecycleTests.m final (1333 lignes) relu entièrement par plages contiguës 1–500, 501–1000 et 1001–1550, dernière plage jusqu’à @end ; aucune sortie tronquée retenue. SHA-256 b414d741094b13916b469cfca2f235629713576e5c7b7345229af725a57870d0. Cette lecture entière remplace le statut de lecture partielle du tableau précédent pour cette version seule. Les tests Style/HTMLExport ont été consultés pour leurs scénarios concernés sans certification entière.

Les tests précédents des cinq comportements étaient absents ou insuffisants (export no-throw, write NSString hors action de production, miroir local des flags head, watcher composant sans callback Document). Cinq tests exercent désormais les composants déterminants réels :

| Correction source déjà commitée | Nouveau test | Comportement observé |
| --- | --- | --- |
| a976430 — PDF pending | testPDFExportAllowsOnePendingPanelAndCanRetryAfterCancellation | Deux appels à l’action n’ouvrent qu’un panel ; annulation autorise une nouvelle tentative. Seule la frontière panel AppKit est contrôlée. |
| f74d97f — save generation | testAnEarlierSaveTimerCannotReloadWhileTheLatestSaveIsProtected | Deux vraies écritures NSDocument espacées de 0,3 s ; une modification disque externe ne remplace pas le contenu pendant la protection de la seconde sauvegarde, puis recharge réellement une fois cette protection expirée. |
| f49e6a3 — head refresh | testChangedHeadScriptsReloadAndUnchangedHeadPreservesJavaScriptState | Vrai WebView/JSContext : un script head changé est exécuté ; un head inchangé préserve l’état JS et remplace réellement le body. |
| 727682c — resource coalescing | testResourceWatcherBurstPublishesOnceAndAnOldWatcherSetCannotPublish | Vrais MPResourceWatcherSet, MPRenderer et MPDocument : plusieurs ressources initiales produisent une publication, leurs URL reçoivent leur timestamp, un set retiré n’en produit aucune. |
| 845d901 — HTML write | testHTMLExportReportsWriteFailureAfterRealRenderAndPreservesExistingFile | Vraie action export, parse/rendu/WebView puis écriture vers un dossier : erreur effectivement présentée et fichier existant préservé. Panel et présentation UI de l’erreur sont les seules frontières contrôlées. |

MPDocumentExportAuditProbe observe la publication puis appelle super ; il ne remplace ni parseur, ni renderer, ni règles d’écriture. Les préférences globales et l’IMP NSSavePanel.savePanel sont restaurés dans @finally. Import JavaScriptCore explicite ajouté après le premier échec de compilation dû à une forward declaration JSContext ; cet échec n’est pas compté comme résultat runtime.

`/tmp/macdown-audit-lifecycle-more2.log` et xcresult `Test-MacDown-2026.10.07_20-37-00-+0200.xcresult` : 47 tests Lifecycle, 0 échec, 4,513 s (4,538 s suite). Root a effectué Xcode. L’agent n’a exécuté aucun Xcode, staging ou commit. Cinq snapshots cumulatifs indépendants pour commits de tests, support commun au premier : `/tmp/macdown-document-more-tests/manifest.json`, base da6bc871fddca31715248675afefc02c88ab2d17. Le cinquième est strictement identique au workspace final ; assertion de recomposition et diff --check réussis.

Rouge/vert PDF supplémentaire : `/tmp/macdown-pdf-panel-regression.py` extrait sans modification la méthode exportPdf: avant et après a976430 et compile avec Cocoa/ARC. Le récepteur est un vrai NSDocument ; la factory du panel est la seule frontière contrôlée, aucune impression exécutée. Avant : 3 contrôles, 2 échecs (deuxième panel ouvert, puis troisième au retry) ; après : 3 contrôles, 0 échec. Logs `/tmp/macdown-pdf-panel-regression/red.log` et `green.log`. C’est une isolation de la méthode exacte, pas une certification de l’ancienne application complète. Les quatre autres tests ont une preuve verte dans la vraie application ; aucune exécution historique rouge n’est revendiquée pour eux.

## Seconde passe critique après commits

Relus en lecture seule : close/writeToURL/writeSafelyToURL/dataOfType, callback resourceWatcherSet, actions copyHtml/exportHtml/exportPdf (hors extraction liens PDF confiée à l’autre agent), performAfterRender/invokeRenderCompletionHandlers, start/stop/handle/process/prompt/reload watchers. MPResourceWatcherSet.m intégral relu ; références de ces méthodes recherchées dans production et tests pour vérifier l’absence de second chemin legacy. Génération des sauvegardes, protection SaveAs/close, invalidation des réarmements et lecture atomique avant réinitialisation dirty cohérentes. Deux voies de reload (silencieux et réponse Discard) convergent vers reloadFromDisk ; les exports convergent vers performAfterRender. Aucun nouveau défaut certain confirmé, aucun code supprimé ni source production modifiée par cet agent pendant cette passe. La modification PDF simultanée de MPDocument relève de sa preuve dédiée ; le SHA précédent n’est pas présenté comme empreinte du fichier après cette modification. Validation livraison/package/smoke reste centralisée chez root.

Commits de renforcement réalisés ensuite par root (un scénario par commit, sans réécrire les corrections source) : PDF 1d9fe2b, sauvegardes 8c80554, head 21828e9, ressources a841445, erreur HTML 40d1bf6.

Le run UI acceptance `/tmp/macdown-audit-ui-acceptance.log` a échoué à l’initialisation automation avant les cas (timeout 60 s ; DevToolsSecurity developer disabled selon diagnostic root). Aucun résultat fonctionnel UI n’en est déduit, aucune configuration d’autorisation modifiée. Cette limite appartient aux gates centrales de livraison, séparées des 47 tests Lifecycle effectivement exécutés.

## Vérification du candidat Mermaid async / consommation différée

Source mermaid.init.js relue entière : init async, await mermaid.render, puis substitution du pre avec le SVG. didFinishLoadForFrame et callback de completion MPDocument relus : la gate explicite concerne MathJax. Cette différence constitue un candidat à vérifier, pas une preuve de course ; la queue microtask JavaScript peut finir avant le callback natif. Aucun correctif production appliqué.

Probe Cocoa/WebView compilé avec clang, fichiers Mermaid 11.x réellement embarqués, aucune Promise temporisée/remplacée : huit flowcharts puis huit types (flowchart, sequence, state, class, gantt, pie, journey, mindmap). À didFinishLoad puis dans l’opération NSOperationQueue.mainQueue reproduisant la planification production : 8 SVG, 0 .language-mermaid restant. Résultats `/tmp/macdown-mermaid-timing.log` et `/tmp/macdown-mermaid-timing-mixed.log`, probe `/tmp/macdown-mermaid-timing.m`. Ces scénarios ne reproduisent pas le candidat. La bibliothèque minifiée n’est pas certifiée relue entière par ces recherches.

Test intégré ajouté : testDeferredConsumerSeesCompletedRealMermaidDiagrams, Document/renderer/WebView et scripts réels, huit types dans un seul document, performAfterRender mesure 8 SVG enfants directs du body et aucune source/erreur ; deux passes MathJax désactivé/activé. Ce test n’emploie aucune substitution de Promise ou de renderer. Snapshot avant ajout `/tmp/macdown-lifecycle-before-mermaid.m`, SHA final du test cbf4c0655400744d615dd9de9a8aace3f15dd1f4c63cbbe95aafcf33ac0d2983. Hunk entier et déclaration testing relus ; le reste est identique à la version 1333 lignes déjà lue. Exécution intégrée centralisée root encore attendue ; statut candidat non confirmé.

Probe MathJax activé supplémentaire : `/tmp/macdown-mermaid-math-timing.m` compile aussi le vrai MPMathJaxListener.m, charge config/init et MathJax locaux, puis mesure le DOM au callback réel End. Huit types de diagrams déjà remplacés (8 SVG, 0 source) à didFinishLoad et au End 0,23 s plus tard. `/tmp/macdown-mermaid-math-timing.log` : exit 0. Aucun hook de Promise ni temps artificiel. Candidat non reproduit dans les trois probes ; le test intégré reste le contrôle de la consommation réelle Document/renderer.

## Relecture intégrale de MPDocument final après gel strict PDF

La première tentative de relecture a rencontré des changements concurrents (début SHA 7df036fc…, fin 9a571785…) et n’est pas utilisée pour certifier l’empreinte finale. Après confirmation du gel par root et pdf_review : snapshot immuable `/tmp/macdown-document-final-frozen.m`, SHA-256 **ff3f342e561293aba00c5a0fca60719622f68e267f9e3cfafc5885acf2ff9f2e**, 5351 lignes. Lecture entière à nouveau, plages contiguës 1–700, 701–1400, 1401–2100, 2101–2800, 2801–3500, 3501–4200, 4201–4900, 4901–5351, sans troncature dans les lectures retenues. Une tentative groupée 701–2100 tronquée a été rejetée puis les deux plages ont été relues séparément en totalité. SHA workspace vérifié après lecture, identique au snapshot et au SHA du gel annoncé. Ce statut remplace l’ancienne empreinte Document pour cette version finale.

Analyse entière réconciliée avec les contrats plus haut. Nouvelles interactions impression réexaminées : snapshot DOM + CSSOM avant première impression et avant/après seconde impression metadata, même WebView/context/génération ; original préservé, publication atomique seulement après résolution ; mediaStyle print et session CSSOM restaurés en @finally ; cleanup des deux fichiers temporaires et des références fortes au callback ; close/didFailLoad préservent le stash lorsqu’une impression est active pour permettre ce nettoyage ; un document fermé ne passe plus la validation snapshot. NSInvocation callback reste équilibré bridge_retained/bridge_transfer et reçoit document/success/context corrects. Les générations des callbacks preview et save/watchers ainsi que les consommateurs export ont été réexaminés. Aucun nouveau défaut certain confirmé dans cette passe. Aucun source production modifié par cet agent. Analyse PDF complète et régressions natives restent dans la preuve propriétaire PDF. Validation de livraison distincte et résultats ciblés de la version gelée encore attendus.

Le ciblé antérieur `/tmp/macdown-audit-native-pdf-tests.log` a exécuté 128 tests avec 6 assertions en échec : 4 assertions d’un scénario fragment PDF corrigé par propriétaire PDF, et 2 assertions de notre oracle Mermaid `body > svg`. Diagnostic de ce dernier : le vrai hoedown_patch_render_blockcode conserve un div autour du pre ; Mermaid remplace le pre et le SVG reste dans ce wrapper. L’oracle top-level était faux, les deux contrôles sources Mermaid restantes valaient déjà 0. Correction du test seule : compter les SVG id mermaid_ sans ancêtre temporaire div id dmermaid_, en gardant zéro source et zéro erreur au consommateur. Probe avec wrappers réels et oracle corrigé réussit (8 SVG/0 sources), `/tmp/macdown-mermaid-wrapped-timing.log`. SHA Lifecycle final corrigé : 4cd566db5e4135a8c40142bbbb56e05b5fc79b1e1c4ee06adce9d1db68f7b296. Hunk final relu, diff --check réussi. Le candidat Mermaid n’est pas déclaré confirmé à partir de ces échecs d’oracle.

## Navigation réelle et gel final après zéro ancres PDF

Défaut confirmé avant correction : navigation HTTP non initiée par un clic utilisateur autorisée par la vraie policy WebKit ; les caches currentHeadContent/currentBaseUrl demeurent ceux de la publication Markdown. Le remplacement body réutilisait le head distant, même après performAfterRender. Reproduction sur le vrai binaire Debug avec injection d’un harness de diagnostic, vrais MPDocument/MPRenderer/WebView et serveur HTTP loopback : `/tmp/macdown-navigation-probe.m`, `/tmp/macdown-navigation-red.log`. Initial base et request file:///tmp/macdown-navigation-local.md ; page HTTP ensuite observée avec meta remote-marker ; au consommateur différé, le h1 « Returned Markdown » était frais mais base HTTP et head distant persistaient. Cette trace est la preuve rouge du défaut de production, pas une exécution XCTest historique.

Correction isolée commit **984b8b3** : avant remplacement body, comparer aussi l’URL de la request réellement chargée au baseURL rendu. En cas de navigation vers une autre page, le pipeline existant recharge le document complet, donc head/scripts et base locale reviennent avant consommation. Aucune interdiction globale HTTP ni second pipeline d’export. Une variation de fragment peut provoquer un rechargement complet supplémentaire, sans compromettre le contrat de fraîcheur. Test `testDeferredConsumerRestoresLocalHeadAndBaseAfterHTTPNavigation` : serveur TCP loopback réel, policy/delegates Document réels, identité du head distant réellement attendue, puis base locale/head checkbox rétablis et h1 frais au callback performAfterRender. Pas de renderer simulé ni DOM inventé comme preuve.

**Gel et lecture finale actuels** : MPDocument.m 5367 lignes, snapshot immuable `/tmp/macdown-document-navigation-final.m`, SHA-256 **a6623063fc819f9c81fbadc9a6f753dc13f387ff055f6b2fd525fcbd260d4939**. Lecture intégrale finale des plages contiguës 1–700, 701–1400, 1401–2100, 2101–2800, 2801–3500, 3501–4200, 4201–4900, 4901–5367 ; aucune sortie tronquée dans ces huit lectures retenues. Empreinte workspace avant/après identique au snapshot. Inclut le court-circuit export PDF sans ancres **bae35a9** et la correction navigation, et remplace toutes les empreintes précédentes pour le statut courant. MPDocument.h déjà lu entièrement, SHA f70d0155da4792f9f0a49dbdb8edb98f4d49474d819e016a05ad417f747bb485.

Analyse intégrale : caches head/base/styles, callbacks main-frame/génération/MathJax, pending renders/handlers et consommateurs frais ; deux passes PDF, snapshots DOM+CSSOM, restauration CSSOM/mediaStyle, zéro ancres, fermeture pendant impression et didFailLoad ; sauvegardes superposées/générations, remplacement inode/Save As/reload/prompts différés ; mutations/undo/autocomplete, footnotes, référence-scroll LCS et bornes. Les interactions nouvelles gardent un seul pipeline renderer et l’export lit l’aperçu complet fraîchement republié après navigation. Aucun autre défaut certain constaté dans cette passe. Pas de suppression legacy sans preuve.

**Validation finale intégrée**, centralisée par root : `/tmp/macdown-audit-final-full-tests.log`, xcresult 21-24-38, exit 0, **1427 tests, zéro échec, 24.654 s**. Navigation passe (1.032 s) ; `testChangedHeadScriptsReloadAndUnchangedHeadPreservesJavaScriptState` passe (2.124 s), attestant aussi maintien du remplacement rapide avec head inchangé ; Mermaid consommateur réel passe (0.551 s), huit SVG après rendu, zéro source et erreur, MathJax OFF/ON. Le candidat Mermaid est donc non reproduit, aucun correctif production artificiel ajouté. SHA Lifecycle courant : 9eed359446bb7b3344d3a5207d0c2a7183e94dc4d6133b53d3f1ce6c98351a3f. Les constructions universelles propres Debug/Release sont pilotées par root, statut indépendant de cette lecture et de la suite.

Complément final Graphviz : vrai binaire Debug final, Document/renderer/WebView réels et scripts inclus via renderer, six moteurs déclarés dot/neato/fdp/osage/twopi/circo. À chaque vrai callback performAfterRender, MathJax OFF puis ON, 6 SVG et zéro source restante ; exit 0, `/tmp/macdown-graphviz-document-probe.log`. Préférences sauvegardées/restaurées, aucun composant déterminant substitué, aucune source modifiée. La réserve de consommation Graphviz est clôturée, Mermaid également confirmé vert par suite intégrée. Décisions manuelles détaillées, 34 chemins production Validé : `decision-validation-ui-document.md`. Builds finaux propres universels Debug/Release et quatre tests UI réussis centralisés root ne laissent plus la validation application historique ouverte pour ces chemins ; signature/notarisation/publication n’est pas assimilée à un contrat code non vérifié.
