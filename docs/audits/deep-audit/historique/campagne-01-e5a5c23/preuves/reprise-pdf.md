# Reprise PDF — 7 octobre 2026

Cette note complète `pdf-anchors.md`, sans remplacer ses preuves historiques.

## Lecture et analyse

`MPPDFAnchorInjector.h` (74 lignes) et `.m` (351 lignes) lus intégralement à la reprise. `MPPDFAnchorInjectorTests.m` lu intégralement, puis version finale relue en plages contiguës 1–400, 401–800, 801–1200, 1201–fin après modification. La constante JavaScript, `readAnchorLinks:headings:` et le consommateur `postProcessExportedPDFAtURL:` de `MPDocument.m` ont été examinés comme dépendances ; cela ne certifie pas le reste de MPDocument.

| Fichier | SHA-256 analysé | Lecture | Analyse | Validation |
| --- | --- | --- | --- | --- |
| `MacDown/Code/Document/MPPDFAnchorInjector.h` | `558508dae940e858e83675149f6f271dae75b3d84ffca106abf506543c09ba40` | intégrale | intégrale | en attente des contrôles centralisés |
| `MacDown/Code/Document/MPPDFAnchorInjector.m` | `b8f20104ec80990652b864742864fd0b6e6662cf8c6986cbae67027d78a6e590` | intégrale | intégrale | en attente des contrôles centralisés |
| `MacDownTests/MPPDFAnchorInjectorTests.m` | `0797c602b0dc58c08542e703ab72a3376753279e98f14bd3da1d37eddc4b7294` | intégrale finale | intégrale | en attente des contrôles centralisés |

Symboles et branches examinés : deux factories et leurs propriétés copiées ; chaîne vide ; snapshot immédiat PDFSelection/pages/bounds ; document absent/vide ; dictionnaire de slugs avec premier titre ; needles distinctes et erreurs PDFKit ; comptage et avancement par texte ; sélection explicite avec cardinalité et index borné ; contrat TOC-only ; destination inconnue/absente ; pages canoniques ; construction annotation/action et isolation d'un lien défectueux. Aucun code obfusqué constaté dans ces fichiers. Coût : une recherche PDF par texte distinct, snapshots limités à leurs résultats ; aucune recherche répétée par lien.

## REPRISE-PDF-01 — texte invisible dupliqué dans la fixture

Le contrôle initial `/tmp/macdown-audit-reprise-tests.log` exécute 59 tests, avec 5 assertions échouées dans un seul test, `testInlineLinkAfterHeadingTargetsEarlierHeading`. Sa première assertion constate **3 occurrences PDF recherchables pour 2 items dessinés**. Les quatre suivantes découlent du refus légitime de l'injecteur lorsque la cardinalité attendue 2 diffère du PDF 3.

Cause identifiée : `MPPDFTestPrintView.drawRect:` réémet tous les items à chaque passe de page, y compris hors du rectangle à dessiner. Le clipping visuel ne garantit pas que le texte émis hors page disparaisse de son flux PDF recherchable. Correction : n'émettre `drawAtPoint:` que si le rectangle de texte intersecte `dirtyRect`. L'impression AppKit et la recherche PDFKit restent réelles ; aucun mock, aucun filtrage a posteriori des résultats, assertion exacte 2 conservée. Cause proposée à confirmer par la relance réelle centralisée.

Le même test vérifie désormais la persistance : PDF annoté sérialisé, rouvert avec PDFKit, action GoTo relue et destination vers la page et le point du titre antérieur. Les contrôles de type/count précèdent les lectures dépendantes ; un échec reste un échec et n'est pas remplacé par une assertion sur `nil`.

État : **corrigé à vérifier**. Aucun Xcode lancé par cet agent, pour préserver la sérialisation des contrôles orchestrés.

## Seconde passe et hypothèses restantes

- Le runtime MPDocument construit toujours les modèles avec indices explicites ; la compatibilité TOC-only est utilisée par les fixtures historiques, pas par l'export actuel. Elle est un contrat documenté, pas un repli après refus de cardinalité : la branche explicite fait `continue` sans retomber sur l'heuristique.
- Les liens vers des titres antérieurs et les répétitions de prose ne doivent jamais être interprétés comme une TOC. Les tests explicites couvrent ces cas, ainsi que l'exclusion indépendante d'une source/destination dont la cardinalité diffère.
- L'égalité des cardinalités ne prouve pas à elle seule l'égalité de l'ordre DOM/PDF. Une feuille d'impression qui réordonne visuellement les mêmes textes constitue une hypothèse déterminante à éprouver au niveau WebView/export ; elle a été signalée au coordinateur. Ne pas annoncer une garantie pour tout CSS arbitraire.
- Les selections multi-page ne sont représentées que par leur première page ; la prise en charge d'un lien long à cheval sur deux pages n'est pas démontrée par les fixtures courtes actuelles. Cette limite préexistante doit rester visible lors de la validation du flux complet.

Prochaine action : contrôle ciblé inline puis suite PDF centralisés, inscription des résultats réels, résolution de l'hypothèse d'ordre avant validation globale du flux.

## Seconde passe export réel — défaut d'ordre confirmé

Les lots PDF ciblés et la suite complète finale `/tmp/macdown-audit-reprise-full-tests3.log` (1416 tests, 0 échec) ont réussi. La correction de fixture et le roundtrip de persistance sont donc vérifiés. Cela ne résout pas les limites suivantes découvertes hors des fixtures initiales.

Reproduction supplémentaire : compilateur clang/AppKit/WebKit/JavaScriptCore/PDFKit, production `MPPDFAnchorInjector.m`, JavaScript d'extraction exact de MPDocument, WebFrameView.printOperationWithPrintInfo → NSPrintOperation → PDFKit. Source/log `/tmp/macdown-pdf-order-harness.m` et `.log`. HTML : h2 Target suivi de a Target, conteneur `display:flex; flex-direction:column-reverse`. DOM heading index0/link index1, cardinalité2 ; PDF trouve deux matches dans ordre visuel inversé. L'annotation ajoutée se trouve sur le titre et vise le lien. **Défaut confirmé et non corrigé à ce stade** ; validation du flux suspendue, pas un simple avertissement CSS.

Le même consumer WebView émet déjà une annotation native Link au rectangle correct du lien interne, mais sans URL/action ni named destination pour `#target` (même avec baseURL file et ancre `a[name]`). Avec une URL synthétique absolue, il conserve URL/action et geometry. Une ancre vide positionnée absolument, top/left:auto et dimension1px au début du titre produit également une annotation native URL au point du titre sans glyphes ni modification du flux normal. Reproduction `/tmp/macdown-pdf-marker-harness.m` / `.log` / `/tmp/macdown-pdf-marker.pdf`.

Approche en investigation : transporter les identités de sources/destinations dans ces annotations natives puis convertir en GoTo, nettoyer les marqueurs et restaurer le DOM après impression. Elle traite ordre CSS, source fractionnée, répétitions et différence media print sans déduire les positions PDF depuis des coordinates DOM. Les styles structurels sensibles à l'insertion d'un enfant doivent être vérifiés avant adoption.

Autre preuve : texte de lien normalisé `First Last` ne retrouve pas le PDF dont le texte contient `First\nLast` ; la recherche PDFKit actuelle ne couvre donc pas un lien multi-ligne de manière démontrée. Les essais de sauts de page internes au lien ont donné un PDF incomplet pour Last et ne constituent pas encore une reproduction valide du cas multi-page ; conserver cette distinction.

## Seconde passe : identités natives et export atomique (en cours de validation)

Défaut confirmé : un conteneur `flex-direction:column-reverse` inverse l’ordre physique du titre et du lien sans changer leurs occurrences DOM. La recherche textuelle précédente annotait le titre et ciblait le lien. Un lien réparti sur plusieurs pages perdait également ses rectangles hors de la première page trouvée. Reproductions réelles WebView/NSPrintOperation/PDFKit : `/tmp/macdown-pdf-order-harness.log`, `/tmp/macdown-pdf-longlink-harness.log`.

La correction remplace entièrement les modèles/recherches d’occurrences par une représentation temporaire portant des URL de session natives. Les cibles restent les titres h1–h6 avec ID, contrat de l’ancien extracteur ; le premier ID DOM gagne en cas de doublon raw HTML. Les liens externes ne changent pas, un fragment inconnu conserve son annotation native sans action.

Deux impressions privées servent un seul pipeline : l’original conserve exactement l’apparence imprimée ; la seconde transporte l’identité des sources et destinations par les annotations natives du moteur. Le PDF secondaire n’est jamais publié. Les GoTo ciblent les pages canoniques de l’original et sont appliqués seulement après vérification de la pagination, des pages et des rectangles sources (tolérance 0,1 point). Des rectangles identiques ambigus sont refusés au lieu d’être associés par ordre. Le PDF original est publié par écriture atomique après succès ; les deux fichiers temporaires sont supprimés dans tous les callbacks.

Le DOM de la seconde passe restaure ses règles CSSOM, attributs et marqueurs dans un finally. Les changements d’appartenance aux sélecteurs induits par le marqueur ou le href sont conservés par des règles CSSOM temporaires gardant spécificité, ordre, media scopes, %, calc() et var(). `attr(href)` simple est remplacé par le fragment initial dans les déclarations concernées. L’original assure la conservation des couleurs :visited. Une feuille inaccessible ou un sélecteur que le moteur ne peut traiter provoque un échec visible, sans écraser un PDF existant. Aucune garantie de support universel des syntaxes CSS futures n’est revendiquée.

Le snapshot inclut outerHTML et CSSRules, la génération du rendu, l’identité du WebView et de son JSContext, et l’état de fermeture. Il est vérifié avant la préparation et après restauration ; la représentation préparée est aussi vérifiée juste avant/après son impression. Un changement abort la publication. La fermeture/erreur de chargement conserve le stash pendant l’impression afin que le callback nettoie ses fichiers.

Preuves autonomes, compilation clang ARC avec frameworks AppKit/WebKit/JavaScriptCore/PDFKit et moteur de production :

- `/tmp/macdown-native-production-harness.log` : baseURL file, 1 GoTo après sérialisation/relecture, pixels identiques à l’original, DOM et snapshot CSSOM restaurés exactement.
- `/tmp/macdown-native-sibling-harness.log` : `h2:has(a)+p`, 1 GoTo, pixels identiques, restauration exacte.
- `/tmp/macdown-native-fluid-harness.log` : largeur relative 75 %, bordure/font du lien sous papier 420 px différent du viewport 600 px ; transfert sans désaccord et pixels identiques.
- `/tmp/macdown-native-attrhref-harness.log` : `a::after{content:attr(href)}`, transfert sans désaccord et pixels identiques.
- `/tmp/macdown-native-multipage-harness.log` : 4 pages, 3 rectangles source des pages 0/1/2, 3 GoTo vers la page canonique 3 après relecture ; deux impressions et transfert en 0,056 s sur cette machine, hors chargement HTML. La page ne contenant que le titre n’a pas de rectangle source.

18 tests XCTest réels ajoutés/migrés dans MPPDFAnchorInjectorTests, encore à exécuter par l’orchestrateur : reverse, multi-page, texte répété/slug encodé, doublons raw, inconnus/externes, annulation et préservation d’un fichier existant, erreur de publication et nettoyage, marqueurs malformés, géométrie contradictoire/ambiguë, nil, changements génération/DOM/CSSOM/fermeture et pixels CSS. La suite full3 antérieure ne certifie pas cette nouvelle correction. Inventaire PDF laissé non validé jusqu’aux nouveaux résultats.

Le premier ciblé `/tmp/macdown-audit-native-pdf-tests.log` a exposé une variante native réelle : les fragments inconnus et `#tar%20get` deviennent des URL natives (`file:///tmp/document.md#tar%20get`) au lieu d’annotations sans action. La correction associe également ces sources lorsque leur fragment décodé correspond à la cible, avec le même contrôle de rectangle unique. Preuve autonome `/tmp/macdown-native-encoded-harness.log` : 1 GoTo, externe inchangé, pixels/DOM/CSSOM identiques. `/tmp/macdown-native-percent-harness.log` vérifie en plus le décodage unique de `#tar%2520get` vers un ID littéral `tar%20get`. Les nouveaux résultats XCTest restent requis.

Relecture finale intégrale des fichiers PDF h/m/tests (18 tests) et de toutes les méthodes/constants PDF modifiées de MPDocument, SHA256 figés pour la relecture globale de MPDocument par l’agent UI :

| Fichier | SHA256 |
| --- | --- |
| MPPDFAnchorInjector.h | `7dbaa29df89ed7405bb15a3471f5bdd75b7486a5b2558f60a826caa4430c5593` |
| MPPDFAnchorInjector.m | `902c57b2cb6354a651e0b981a49bfee390ae89fc1e003d0d1a71bd343c2ed5a0` |
| MPPDFAnchorInjectorTests.m | `203e83c2b39796a2f2f9ac66b86bc1f8be8c1591027aea2fa548ecf7777b0a73` |
| MPDocument.m | `ff3f342e561293aba00c5a0fca60719622f68e267f9e3cfafc5885acf2ff9f2e` |

Validation ciblée finale du gel SHA ci-dessus : `/tmp/macdown-audit-native-pdf-tests2.log`, **130 tests réussis, 0 échec**, dont les **18 tests MPPDFAnchorInjectorTests réussis, 0 échec** (0,225 s). `git diff --check` propre. La suite globale et les gates finaux restent à exécuter par l’orchestrateur après les autres corrections du dépôt.

## Correction distincte : export sans ancres

Un export sans `a[href^="#"]` non vide n’a besoin d’aucune préparation CSSOM. Il publie désormais l’original atomiquement avec les mêmes contrôles de snapshot, au lieu de créer des marqueurs et d’effectuer une deuxième impression inutiles. Le test consommateur supplémentaire `testNoAnchorsExportsOriginalWithActuallyInaccessibleCrossOriginCSS` sert une CSS réelle sur HTTP localhost, depuis un document HTML de base HTTP sur un autre port : font 26px et couleur rouge sont réellement appliquées, mais CSSRules lève SecurityError. Le PDF sans ancres doit néanmoins être publié, relu par PDFKit, conserver son titre et les pixels de l’original. Serveur éphémère loopback uniquement, send partiel traité, timeouts et refus des syscalls observables par les assertions de consommation CSS.

Probe de portée avec ancres : `/tmp/macdown-native-crossorigin-file-harness.log` confirme que le Legacy WebView chargé avec baseURL **file** accède déjà aux CSSRules HTTP : 4 règles, 1 GoTo, pixels identiques. Le même résultat existe avec base nil. `/tmp/macdown-native-crossorigin-http-harness.log` confirme la limite distincte d’un document de base HTTP : SecurityError JS, API publique native DOMCSSStyleSheet.cssRules inaccessible (nil/length0), alors que WebDataSource.subresources contient les 149 bytes exactement chargés. Aucune sécurité WebKit désactivée, API privée, refetch ou parser CSS additionnel introduit : reconstituer ces bytes inline changerait les URLs relatives/imports sans correction sûre.

Flux applicatif lu : rendererBaseURL et didProduceHTMLOutput dérivent la base de self.fileURL ou htmlDefaultDirectoryUrl (défaut NSHomeDirectory en URL file), puis previewSafeBaseURL ; le print passe par performAfterRender. Hypothèse de navigation HTTP secondaire transmise à l’agent UI : la policy permet une navigation non initiée par clic, et aucun didStartProvisionalLoadForFrame ne remet à zéro les caches de head/base/ready ; l’agent vérifie que le rendu frais ne conserve pas un head HTTP lors du remplacement body. Ce flux n’est pas certifié tant que sa preuve n’est pas reçue.

Gel suivant pour la correction zéro ancres, deux sources seulement : MPDocument.m SHA256 `cbce4479149065fbf6811801f7204c5b9ae0dfd46e00a34a93c144e90736bcb0`, MPPDFAnchorInjectorTests.m SHA256 `5a40ac2efe81fc88f8fefdcfbc11c65ee789e849f425c7da2dce22647b60fcf5`. 19 tests PDF ; ciblé demandé à l’orchestrateur, résultat encore requis. Diff --check propre.

Le premier ciblé zéro ancres a trouvé une course de fixture : readyState complete + une feuille existent encore dans l’ancien document immédiatement après loadHTMLString. Les trois assertions CSS restent inchangées ; l’attente vérifie désormais le meta `cross-origin-css-fixture` propre au nouveau HTML avant CSS/ready. Nouveau SHA tests : `eaa7d20884cd151a04a66378ec151ae5dd726ba95bd73d586f978754efd1ebff`. MPDocument inchangé pour cette réparation.

Ciblé réparé `/tmp/macdown-audit-zero-anchor-tests2.log` : **19 tests PDF réussis, 0 échec** (0,337 s), dont le cas CSS inaccessible sans ancres en 0,026 s ; xcresult `build/DerivedData/Logs/Test/Test-MacDown-2026.10.07_21-20-48-+0200.xcresult`. Correction autonome committée par l’orchestrateur : `bae35a9`, après le pipeline natif `e2845a7`. Relecture finale intégrale réexécutée de MPPDFAnchorInjector.h, MPPDFAnchorInjector.m et de chaque ligne/fonction des 19 tests de MPPDFAnchorInjectorTests.m (SHA `eaa7d20884cd151a04a66378ec151ae5dd726ba95bd73d586f978754efd1ebff`). Aucun défaut confirmé restant dans ce sous-périmètre ; le flux navigation/rendu de MPDocument reste sous la responsabilité de l’agent UI et les gates globaux sous celle de l’orchestrateur.


## Verdict manuel final des deux sources PDF

- MPPDFAnchorInjector.h : **validable**. API de transfert sur original/metadata, nil/no-op et NSError géométrie explicites, interface consommée par MPDocument et tests réels, compilations propres Debug/Release arm64/x86_64.
- MPPDFAnchorInjector.m : **validable**. Chaque fonction/ligne relue : grammaire index exacte/overflow, rectangle borné à 0,1 point, cardinalité/rotation/media box, destination canonique du document original, premier titre DOM, association géométrique unique et fragment décodé, validation préalable avant actions. PDF19/0 après sérialisation/réouverture, pixels, multipage et refus/cancel/cleanup ; full1427/0 et clean builds universels final root. Aucun source PDF changé depuis les empreintes finales relevées ; aucune recherche textuelle/ordre runtime conservée. Les limites de contexte HTTP externe ont été traitées séparément par N01 de l’agent UI (984b8b3), dont le gate global consomme le retour au Markdown local.

Les tests PDF définitifs (19 fonctions + serveur fixture et tous helpers) ont été relus intégralement au SHA eaa7d208… après réparation de la course readyState ; leur validation ciblée réelle est documentée plus haut. Cette décision manuelle ne coche aucune ligne de l’inventaire automatiquement.
