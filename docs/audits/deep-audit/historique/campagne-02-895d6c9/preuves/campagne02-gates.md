# Gates finales — campagne 02

Sources finales : R04 `723ef22`, D02 `f5870f5`. Les corrections applicatives sont committées ; les empreintes des preuves correspondent aux versions intégralement relues. Environnement local macOS 26 / Xcode 26.2, tests exécutés arm64. Les résultats de campagne 01 ne remplacent aucun contrôle de cette campagne.

| Contrôle | Résultat réel | Preuve |
| --- | --- | --- |
| Suite XCTest complète finale | 1436 tests, 0 échec, sortie 0 | /tmp/macdown-campaign02-final-full-tests-green2.log ; xcresult 23-46-51 |
| Scripting et consumer CLI ciblés | 49 tests, 0 échec, sortie 0 | /tmp/macdown-campaign02-scripting-green2.log ; A2-D02.md |
| XCUITest scheme MacDownUITests | 4 tests, 0 échec, sortie 0 | /tmp/macdown-campaign02-final-ui-tests-green.log ; xcresult 23-49-23 |
| Debug universel | BUILD SUCCEEDED, sortie 0 ; app/CLI/extension arm64+x86_64 | /tmp/macdown-campaign02-final-debug-build.log |
| Release universel | BUILD SUCCEEDED, sortie 0 ; app/CLI/extension arm64+x86_64 | /tmp/macdown-campaign02-final-release-build.log |
| Identité réellement embarquée | App/extension/CLI Debug et Release : 3000.0.7-rc.1.post188, build1599 | campagne02-build-identities.json : plist, CLI --version et lipo effectifs |
| Scripts/empty-suite/version/release/packaging/PEG/YAML/heading print | Huit runners, sorties 0 | /tmp/macdown-campaign02-build-contracts.log |
| Accessoire code/TOC/QL tokens/indentation/géométrie/pluriels et JS init/header | Huit runners, sorties 0 ; contrôles affectés réexécutés après R04 | /tmp/macdown-campaign02-regressions.log ; A2-R04.md |
| Queue CLI réelle interprocess | 320 demandes consommées une fois dans cette exécution ; refus/stockage/stdin vérifiés | /tmp/macdown-campaign02-command-queue.log |
| Contraste code Quick Look | Huit navigations WK, 24 PRE ; highlighting et line-numbers activés/désactivés, deux styles | /tmp/macdown-campaign02-r04-green.log |
| Mermaid adapter après R04 | Trois scénarios verts, dont deux frères PRE+CODE et remplacement body | /tmp/macdown-campaign02-r04-mermaid-js.log ; runner JS committé |
| Sandbox préférences | Lecture autorisée/refusée, écriture partagée refusée | /tmp/macdown-campaign02-sandbox-preferences.log |
| Sandbox assets | USER autorisé, BUNDLE fallback, frontières lecture/écriture préservées | /tmp/macdown-campaign02-sandbox-assets.log |
| Adapters DOM applicatifs | Table drag/reset/reinit, tasklist navigation, vrai Viz et bridge MathJax : sorties 0 | campagne02-adapters-native.json |
| Ressources UI/locales compilées | 217 tables, 5184 clés, 0 erreur ; 8 nibs et 43 assets attendus | campagne02-ui-bundle.json ; campagne02-ui-assets.json |
| Markdown lint configuré | Sortie 0 sur les cinq documents configurés | /tmp/macdown-campaign02-markdownlint.log |
| PDF code print après R04 | Six NSPrintOperations, PDF écrits et rouverts ; pixels/texte avant-après identiques avec Prism | campagne02-code-print-native.json |
| PDF strict sur MPDocument final | Douze contrôles verts, sortie 0 ; writeToURL/initWithURL, GoTo page/point, RGBA et restore | campagne02-pdf-native.json ; /tmp/macdown-campaign02-final-pdf.log |
| Quick Look provider natif final | Host sortie 0, provider exact observé, capture inspectée : code lisible sur fond sombre | campagne02-quicklook-native.json ; campagne02-quicklook-native.png |
| Réconciliation physique | 482 présents ; aucun manquant/divergent/inconnu/symlink propre | campagne02-reconciliation.json |

Les commandes XCTest passent par le vault privé relu `/tmp/macdown-xctest-vault.py --execute --timeout ... -- xcodebuild ...` : sauvegarde CFPreferences, protection ApplicationSupport/cache/savedState/queue, fixture HOME, restauration finale et égalité des préférences vérifiée. Suite complète : workspace `MacDown 3000.xcworkspace`, scheme `MacDown`, destination `platform=macOS,arch=arm64`, ARCHS arm64+x86_64, ONLY_ACTIVE_ARCH=NO, only-testing MacDownTests et watchdog120s. UI : même workspace/destination/architectures, scheme `MacDownUITests`. Les quatre UI tests couvrent launch/editor/frappe/présence preview ; la preuve visuelle du provider est distincte.

## Consommateurs natifs et portée

Le PDF final compile l'injector réel et les deux déclarations JS extraites du MPDocument SHA546d434a. Fixture WebView monopage, deux NSPrintOperations réelles, pixels RGBA originaux immuables capturés AVANT mutation, transfert du lien interne puis `resolved.pdf` écrit et rouvert par URL. Le GoTo persistant vise la bonne page et le point du marqueur ; 1294016 octets de pixels décodés identiques. DOM/CSSOM restaurés et session supprimée. Les gardes multipages, géométrie, générations et publication atomique sont aussi exercées par les suites natives ; la fixture stricte n'est pas présentée comme un unique test de toutes les commandes de menu. L'ancien probe u06tm06z rouvrait une sérialisation en mémoire et comparait des PNG encodés ; il est supersédé par la vraie réouverture disque ss0j95yq.

Quick Look : host réel NSApplication.run, provider UUID issu du Debug final, PID37874 observé au chemin exact de l'extension clonée. Fenêtre17215 active/key/visible, occlusion8194 ; root a inspecté le compositeur12s : titre, gras, code clair sur fond sombre et tableau bordé visibles. Aucun binaire instrumenté ne remplace l'extension. Le champ automatique paintValidated=false laisse l'inspection au réviseur ; manualPaintDecision explicite apporte cette décision. Le probe termine avec code2 uniquement pour les métadonnées du conteneur UUID protégées par macOS : élection remise à default, extension et host désenregistrés, listing final vide. Ce nettoyage est distingué du succès de rendu ; aucune modification des permissions système pour supprimer ces résidus de fixtures.

Scripting : vrai NSScriptSuiteRegistry, NSPropertySpecifier, AppleEvents self sur main thread, document/nibs, notification, rendu naturel, état modifié, sauvegarde littérale, no-op/undo/redo et mode manuel. La terminologie du bundle est également compilée par osacompile puis osadecompile. L'envoi interapplication externe et ses permissions TCC ne sont pas revendiqués. L'isolation des groupes dans la fixture XCTest est explicitée dans A2-D02.md ; les assertions dirty ne sont pas supprimées.

Les dépendances tierces internes ne sont pas certifiées par leurs adapters. MathJax CDN/type­setter et toutes les combinaisons de viewport/style ne sont pas prétendus testés. Aucun déploiement, Developer ID, notarisation ou publication externe n'est réalisé. L'essai exploratoire PEG ASan+UBSan a expiré pendant la génération sans rapport mémoire ; ASan n'est pas déclaré vert. Les contrats UBSan requis ont réussi. Les deux architectures sont compilées ; les suites natives sont exécutées arm64.

## Échecs intermédiaires traités

Les deux premiers runs complets après R04 avaient deux échecs : compteur global de classes doublé, puis avertissement Tidy sur fragment sans DOCTYPE. Les assertions finales examinent deux CODE, leurs parents PRE, leurs textes et leur ordre dans un document HTML complet ; NSError reste contrôlé. Le dernier run1436/0 clôt ces échecs. Un premier essai UI utilisait le scheme MacDown, qui ne contient pas MacDownUITests : sortie70 avant tests, vault restauré ; l'exécution du scheme relu MacDownUITests passe4/0. Aucun de ces essais échoués n'est annoncé vert.

Verdict : aucun contrôle local requis manquant et aucun défaut confirmé ouvert dans les contrats examinés. Les décisions de validation restent manuelles et individuelles ; les résultats, hashes et compteurs constituent leurs preuves, pas un mécanisme automatique de certification.
