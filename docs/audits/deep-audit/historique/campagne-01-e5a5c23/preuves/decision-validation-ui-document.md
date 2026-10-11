# Décisions manuelles finales UI, Document, éditeur et YAML — 2026-10-07

Décision prise fichier par fichier après lecture et analyse, sans promotion automatique par SHA. Cette note remplace les réserves historiques « XCTest/build/UI restant » des preuves reprise-ui.md et reprise-document.md pour les fichiers explicitement ci-dessous. Elle ne modifie pas l’inventaire principal ; root applique les décisions.

Preuves communes : `/tmp/macdown-audit-final-full-tests.log` : 1427 tests, zéro échec ; `/tmp/macdown-audit-final-debug.log` et `/tmp/macdown-audit-final-release.log` : constructions propres universelles arm64/x86_64 réussies. `/tmp/macdown-audit-ui-acceptance2.log` : les quatre vrais cas UI ont été exécutés et réussissent, xcresult 21-30-11. L’échec d’initialisation UI historique ne reste donc plus ouvert. Cette gate UI ne prétend pas tester seule toutes les préférences : leurs contrats sont couverts par lectures, tests ciblés/consommateurs et builds.

## Fichiers de production : décision Validé

| Chemin | Preuves déterminantes et décision |
| --- | --- |
| MacDown/Code/Preferences/MPEditorPreferencesViewController.h | Lecture entière reprise-ui ; contrats contrôleur/bindings, tests préférences/resize et composants éditeur, builds/UI réussis. Validé. |
| MacDown/Code/Preferences/MPEditorPreferencesViewController.m | Même lecture et analyse de toutes branches ; préférences et substitutions consommées par éditeur réel. Validé. |
| MacDown/Code/Preferences/MPGeneralPreferencesViewController.h | Lecture entière reprise-ui, contrats contrôleur/bindings et tests préférences/resize ; builds/UI. Validé. |
| MacDown/Code/Preferences/MPGeneralPreferencesViewController.m | Lecture entière ; persistance et observers réconciliés avec MPPreferences ; suite préférences/resize. Validé. |
| MacDown/Code/Preferences/MPHtmlPreferencesViewController.h | Lecture entière reprise-ui, contrôleur/bindings et tests préférences/resize/rendu. Validé. |
| MacDown/Code/Preferences/MPHtmlPreferencesViewController.m | Lecture entière ; diagrammes indépendants de syntax highlighting vérifiés et vrai Mermaid consommé par Document. Validé. |
| MacDown/Code/Preferences/MPMarkdownPreferencesViewController.h | Lecture entière reprise-ui, interfaces concordantes avec contrôleur/rendu. Validé. |
| MacDown/Code/Preferences/MPMarkdownPreferencesViewController.m | Lecture entière ; flags consommés dans renderer et parser, tests Markdown et huit combinaisons flags Document réussis. Validé. |
| MacDown/Code/Preferences/MPPreferences.h | Lecture entière reprise-ui ; API publique/persistance et consommateurs réconciliés, MPPreferencesTests et Core réussis. Validé. |
| MacDown/Code/Preferences/MPPreferences.m | Lecture entière ; migrations, domaine/timeout/retry, conservation version future testés ; preuves preferences et Core sandbox root, build final. Validé. |
| MacDown/Code/Preferences/MPPreferencesViewController.h | Lecture entière reprise-ui ; interface et resize/selection contrôleurs vérifiés. Validé. |
| MacDown/Code/Preferences/MPPreferencesViewController.m | Lecture entière ; MPPreferencesViewControllerResizabilityTests réussis, resources/bindings construits et UI réussie. Validé. |
| MacDown/Code/Preferences/MPTerminalPreferencesViewController.h | Lecture entière reprise-ui ; interface conforme au composant exercé par MPTerminalPreferencesTests. Validé. |
| MacDown/Code/Preferences/MPTerminalPreferencesViewController.m | Lecture entière finale ; ownership symlinks, liens cassés, entrée étrangère et callback après vraie destruction couverts ; Terminal 19/19 et suite finale. Validé. |
| MacDown/Code/Sidebar/MPFileNode.h | Lecture entière reprise-ui ; interface résolutions/nœuds et MPFileNodeTests réussis. Validé. |
| MacDown/Code/Sidebar/MPFileNode.m | Lecture entière ; cycles/résolution/tri/type étudiés, MPFileNodeTests et consommateurs sidebar réussis. Validé. |
| MacDown/Code/Sidebar/MPFolderSidebarViewController.h | Lecture entière reprise-ui ; contrat activation/délégation testé. Validé. |
| MacDown/Code/Sidebar/MPFolderSidebarViewController.m | Lecture entière ; Return dossier .md refusé, fichiers activés, sélection/reload/stop étudiés ; MPFolderSidebarViewControllerTests verts. Validé. |
| MacDown/Code/Sidebar/MPFolderWatcher.h | Lecture entière reprise-ui ; contrat watch/stop conforme à implémentation et consommateurs. Validé. |
| MacDown/Code/Sidebar/MPFolderWatcher.m | Lecture entière ; events/callback séparé/stop réexaminés, MPFolderWatcherTests réels réussis. Validé. |
| MacDown/Code/Sidebar/MPSidebarSplitView.h | Lecture entière reprise-ui ; propriété drag et contrats split testés. Validé. |
| MacDown/Code/Sidebar/MPSidebarSplitView.m | Lecture entière ; drag/resize/collapse étudiés avec contrôleur ; MPSidebarSplitViewTests réussis. Validé. |
| MacDown/Code/Sidebar/MPSidebarSyncCoordinator.h | Lecture entière reprise-ui ; contrat racine/source/width/visibility cohérent. Validé. |
| MacDown/Code/Sidebar/MPSidebarSyncCoordinator.m | Lecture entière sans troncature retenue ; stockage/synchronisation entre tabs analysés, MPSidebarSyncCoordinatorTests réussis. Validé. |
| MacDown/Code/View/MPEditorView.h | Lecture entière reprise-ui ; géométrie/clipboard/substitutions consommateurs vérifiés. Validé. |
| MacDown/Code/View/MPEditorView.m | Lecture entière ; plages glyphes/Unicode et collage échappé testés, MPEditorViewPasteboardTests/SubstitutionTests/MPUtilityTests réussis ; builds/UI. Validé. |
| Dependency/YAML-framework/YAMLSerialization.h | Lecture entière reprise-ui ; API publique lecteur/writer/mutabilité et consommateurs front matter vérifiés. Validé. |
| Dependency/YAML-framework/YAMLSerialization.m | Lecture entière finale ; vrais LibYAML/M13, rouge 12/15 puis vert 15/15 pour clés collections ; erreur YAMLString préservée ; MPUtilityTests verts dans suite finale. Validé. |
| MacDown/Code/Document/MPDocument.h | Lecture entière, preuve reprise-document ; interfaces/actions réconciliées avec source entière, suites Document/UI/build. Validé. |
| MacDown/Code/Document/MPDocument.m | Relecture finale intégrale des 5367 lignes, SHA a6623063…4939 stable avant/après ; reprise-document, navigation HTTP rouge réelle puis régression verte, head rapide/Mermaid, save/watch/close/scroll/actions et PDF natif ; suite finale 1427/0, UI4/4 et builds propres universels. Validé. |
| MacDown/Localization/ru-RU.lproj/Localizable.strings | Lecture entière finale reprise-ui ; six listes/règle 7, vrais JJPluralForm 360 contrôles quatre locales, consommateur totaux/sélection, packaging localisations du produit contrôlé root. Validé. |
| MacDown/Localization/uk.lproj/Localizable.strings | Lecture entière finale reprise-ui ; mêmes contrôles règle 7 ; vrai bundle et titres/formes consommés root. Validé. |
| MacDown/Localization/cs.lproj/Localizable.strings | Lecture entière finale reprise-ui ; six listes/règle 8, oracle cardinal indépendant avec vrai JJPluralForm, consommateur et packaging. Validé. |
| MacDown/Localization/sk.lproj/Localizable.strings | Lecture entière finale reprise-ui ; mêmes contrôles règle 8, consommateur et packaging. Validé. |

Pour ces 34 fichiers, aucun défaut confirmé restant ni contrat réellement indispensable non vérifié n’empêche la validation code. Signature Developer ID, notarisation et publication ne sont pas des préconditions de leur validation code. Les différences OS externes et volumes FUSE réels non disponibles restent des limites explicites, pas un défaut nouvellement introduit ni un motif artificiel de certification impossible.

## Tests et ressources hors production : décisions bornées

Validé pour les deux fichiers de régression pluriels effectivement entièrement relus : `MacDownTests/Localization/PluralCountRegression.m` et `MacDownTests/Localization/test_plural_counts.sh` ; rouge/vert réels, composants déterminants non substitués, nettoyage temporaire vérifié.

Les fichiers entièrement relus dans la reprise et réellement exécutés peuvent être validés : `MacDownTests/MPTerminalPreferencesTests.m`, `MacDownTests/MPPreferencesTests.m`, `MacDownTests/MPSelectionCountTests.m`, ainsi que les tests Sidebar dont la lecture entière est consignée dans reprise-ui.md. Pour `MacDownTests/MPDocumentLifecycleTests.m`, la lecture entière initiale puis les hunks de renforcements finaux (PDF panel/save/head/resources/write failure/Mermaid/navigation) et la réussite intégrée justifient Validé ; aucune simulation du déterminant renderer/WebView/parser ajoutée pour ces scénarios.

Pas de certification de lecture entière nouvelle par cet agent pour `MacDownTests/MPUtilityTests.m` : seules sections YAML/éditeur et infrastructures nécessaires relues, même si la suite entière réussit. Root peut utiliser sa propre lecture intégrale comme complément. Même restriction pour les XIB et les autres locales historiques : leurs corrections/consommateurs ont été vérifiés ici, mais une nouvelle lecture intégrale de toutes ces ressources n’est pas revendiquée. Leur décision finale doit s’appuyer sur le propriétaire de leur preuve historique, pas sur le succès d’un build seul.

## Complément Graphviz réellement consommé — gate clôturée

Sonde demandée après la première décision : `/tmp/macdown-graphviz-document-probe.m`, compilée en harness de diagnostic injecté dans le vrai binaire Debug final. Utilise MPDocument, MPRenderer, MPEditorView et WebView réels ainsi que les ressources Viz/viz.init.js réellement incluses par le renderer. Aucun remplacement de renderer, Promise, Viz ni callback du document. Les préférences partagées modifiées par la sonde sont sauvegardées et restaurées avant sortie ; pas de changement source ni nouveau test redondant.

Les six moteurs **déclarés** par viz.init.js sont testés ensemble : dot, neato, fdp, osage, twopi, circo. Observation directement au callback du vrai `performAfterRender`, une passe MathJax OFF puis une passe ON : **6 SVG, 0 code source Graphviz restant, Viz=function**, dans chacune des deux passes. `/tmp/macdown-graphviz-document-probe.log` : exit 0, FINAL failures=0. Les déclarations ne comprennent pas sfdp ; aucun contrat supplémentaire n’est inventé.

Cette preuve clôt la réserve « Graphviz complet, gate séparée » pour les consommateurs Document/préférences de mon lot. Les décisions Validé des 34 chemins ci-dessus restent définitives, aucun contrat indispensable restant pour ces fichiers. La validation du fichier viz.init.js et des ressources Viz elles-mêmes reste la décision de leur propriétaire RR sur sa propre lecture complète, à laquelle cette preuve réelle de consommation peut être rattachée.
