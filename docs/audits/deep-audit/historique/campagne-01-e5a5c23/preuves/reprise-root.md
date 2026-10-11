# Reprise coordonnée — 7 octobre 2026

Demande explicite : reprendre l’audit et créer un commit distinct par correction. Le suivi précédent confirme le périmètre MacDown (aucun app/database). Aucun push, déploiement ou installation de l’application. Bilan-arret.md reste la photographie historique de l’arrêt précédent. Le présent audit reste en cours ; aucune validation finale générale n’est acquise.

## Lecture et analyse effectuées par le coordinateur

Relus intégralement : MPUtilities.h/m (574 lignes m, deux plages contiguës), FileURLInlining.m, NSDocumentController+Document.m, NSPasteboard+Types.m, NSString+Lookup.m, NSUserDefaults+Suite.m, NSTextView+Autocomplete.h/m (732 lignes m, trois plages), MPMainController.m (deux plages), MPHTMLResourceURLs.m, MPURLSecurityPolicy.m, MPFileWatcher.m, MPResourceWatcherSet.m, mermaid.init.js, updateHeaderLocations.js. Les empreintes enregistrées correspondent à ces versions effectivement lues. La lecture des autres fichiers utiles/tests est tracée dans les notes des surfaces ; aucune lecture complète de MPDocument final n’est déduite de ses hunks.

- Utilities : résolution ressources/thèmes et ordre override, helpers caractères, JavaScript→JSON UTF8/ownership/erreurs, dossiers temporaires privés/exclusifs, archives bundled, historique des hashes stock et prune limité par nom+empreinte. Les maps cachées restent réellement consommées, preuve editor-utilities ; aucun retrait legacy arbitraire.
- Clipboard et document creation : filtres protocoles, nil/empty, clipping plist typé, erreurs et refus écrasement avant création document ; sources d’entrée MainController/Editor suivies.
- Autocomplete : paires/smart-quotes/IME, wrapping/deletion, espaces/indentation/désindentation, liste/blockquote/indent continuation, marqueurs entiers et mapping sélection, titres et lignes blanches, mapped image privée. Les trois actions de document ont été migrées dans le même commit que le contrat marker-only. Les autres deltas MPDocument demandent encore relecture finale.
- Resources/watchers : attributs src/href, URLs relatives/file/remote/fragment et entity decoding, conservation query et remplacement t ; génération par chemin et identité des sources empêchent ancien retry après retrait/re-add. Lifecycle cancel ferme fd. Tests réels vnode requis et exécutés ci-dessous.
- JS : erreur Mermaid textContent et renouvellement DOM pendant Promise ; image standalone tient compte du texte voisin et anchor wrapper. Les tests adaptateur ne certifient pas les internals Mermaid fournisseur.

## Commits et traçabilité

Chaque correction est isolée dans Git avec son ID dans le message lorsque l’ID historique existe. Les tests partagés sont préparés dans l’index par méthodes/scénarios sans écraser le fichier de travail. Des commits de test séparés corrigent les fixtures découvertes à la reprise et n’affaiblissent pas le contrat : domaine persistant destination (registerDefaults est hérité), ligne réelle de dossier (NSURL de directory de fixture avait slash distinct), shortcut déclaré (AppKit adapte le clavier).

`git log --oneline 962df74..HEAD` fournit les commits exacts. Notes métier/causes/tests : editor-utilities.md, ui-preferences.md et nouvelles notes reprise-build/ui/pdf/PEG/rendering. Les nouvelles corrections sont séparées des versions héritées par snapshots de blobs dans /tmp, sans réinitialiser l’arbre partagé.

## Contrôles centralisés exécutés

Toutes commandes XCTest utilisent `xcodebuild test -workspace 'MacDown 3000.xcworkspace' -scheme MacDown -derivedDataPath build/DerivedData -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120`, avec `-only-testing` par classe/méthode ci-dessous. Xcode26.2, macOS local, hôte Debug. Aucun appel au smoke helper CI sur les préférences locales.

| ID | Portée / preuve | Résultat réel | Limite |
| --- | --- | --- | --- |
| R1 | MPUtilityTests + MPPDFAnchorInjectorTests ; /tmp/macdown-audit-reprise-tests.log | exit65 ; 59 tests, 5 assertions dans un seul test PDF ; 44 Utility réussis | Échec PDF confirmé, fixture corrigée ensuite ; source YAML encore antérieure aux nouvelles clés |
| R2 | PDF + URLSecurityPolicy + MainControllerMenu ; /tmp/macdown-audit-reprise-tests2.log | exit65 ; 37 tests, 1 échec menu ; 15 PDF et 17 URLSecurity réussis | PDF fixture dirtyRect vérifiée ; roundtrip ajouté ensuite |
| R3 | Preferences, Terminal, Sidebar, PreferencesResizability, HTMLResourceURLs, ResourceWatcherSet, PDF ; /tmp/macdown-audit-reprise-tests3.log | exit65 ; 179 tests, 2 échecs de fixtures dans tests nouveaux migration/sidebar | Autres classes réussies, dont PDF roundtrip et watchers réels ; fixtures révisées |
| R4 | MainControllerMenu + deux méthodes migration/sidebar échouées ; /tmp/macdown-audit-reprise-tests4.log | exit0 ; 7 tests réussis | Suites de livraison complètes restent à exécuter |
| R5 | Utility + Terminal + deux nouvelles méthodes headings app/QL ; /tmp/macdown-audit-reprise-tests5.log | exit65 ; build échoué, aucune validation de test | Macro XCTAssert et virgule Objective-C corrigées ; relance R6 en cours |
| R6 | Utility + Terminal + RendererState + QuickLookRenderer ; /tmp/macdown-audit-reprise-tests6.log | en cours | Consigner compte/code après fin réelle |
| JS | node MacDownTests/JavaScript/mermaid-init.test.js ; node MacDownTests/JavaScript/header-locations.test.js | exit0, deux Mermaid + quatre classifications | DOM adaptateur contrôlé ; fournisseur SVG non exercé |
| Portable | CLI/BuildTools/version/workflow/website/pluriels | résultats précis dans reprise-build.md et reprise-ui.md | Environnements isolés ; API GitHub/GUI/signatures distantes non exécutées |

Les xcresult sont conservés dans build/DerivedData/Logs/Test ; les logs /tmp ne constituent pas des artefacts pérennes du dépôt. Les nouvelles sources peuvent rouvrir un résultat précédent ; aucun succès d’un ancien lot ne certifie les deltas suivants.

## Points de reprise ouverts

- Finir commit des corrections héritées rendering/MPDocument/PDF/PEG/project et localisations, puis nouvelles corrections avec leurs régressions.
- Relecture intégrale finale MPDocument, carte des parcours et seconde passe des consommateurs (dont ordre DOM/PDF, liens multipage, UTF8/NUL, scopes et rendu frais). Le highlighter initial inverse extensionFootnotes (pmh_EXT_NOTES vs NONE), signal statique à confirmer avec test.
- Consolider les preuves sources nouvelles et SHA divergents ; réconcilier tous fichiers source, exclusions et nouveaux fichiers. Un test PDF accidentellement inscrit dans inventaire principal est retiré des compteurs et reste tracé dans les notes PDF.
- Suites complètes, builds propres Debug/Release/universal et gates applicables restent non exécutés sur le code final. Aucune affirmation « prêt à livrer ».

## R7 — Relecture projet et contrôle des regressions

Lecture intégrale du projet Xcode : plages contiguës 1–120, 121–300, 301–450, 451–600, 601–800, 801–1200, 1201–1600, 1601–2000, 2001–2400, 2401–2891. Les sorties tronquées préalables ne sont pas comptabilisées. Examen objets sources/headers/resources, dépendances cibles/subprojects, shell phases/entrées/sorties, variants localisés, SDK/debug/release/test flags, frameworks et embedding. Groupes référencent parfois les mêmes sources sous deux IDs : buildfiles sélectionnent une seule unité par cible ; aucun second pipeline runtime déduit de ces doublons d'affichage. Ancienne référence PAPreferences dans groupe Frameworks sans buildfile actif conservée : aucun changement spéculatif. Génération partagée MacDownResources ordonne styles/Prism avant application et Core sans cycle app→extension→Core→app. Copie Core purge ressources précédentes. Contrôle final clean Debug/Release et bundles encore ouvert.

Suite complète `/tmp/macdown-audit-reprise-full-tests.log` : 1 408 tests, 8 échecs (7 rendus/fixtures, 1 test reload sans fileURL). Aucune validation globale. Contrôle R7 ciblé `/tmp/macdown-audit-reprise-tests7.log` : ExternalChangeReload 31/31 réussi après précondition et scénarios Save As/close ; nouveau test footnotes en échec (4 assertions), diagnostic en cours.

- `MacDown 3000.xcodeproj/project.pbxproj` SHA-256 `852cce645681a4d471680d8c2e8001e73a2f1d1a9f6c1517ed6b695aa3654dd9` : lu/analyse intégral, validation ouverte.

- `MacDown 3000.xcodeproj/project.xcworkspace/contents.xcworkspacedata` SHA-256 `7f3b00b5c3fdb45242d7b87e1e5c4e25d1fa8129a16c94295ecc4e8ea2235c5f` : lu/analyse intégral, validation ouverte.

## R8 — Suite globale réussie

`xcodebuild test -workspace 'MacDown 3000.xcworkspace' -scheme MacDown -derivedDataPath build/DerivedData -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120` : exit0, 1 416 tests / 0 échec, 18,551s. Log `/tmp/macdown-audit-reprise-full-tests3.log`, résultat `build/DerivedData/Logs/Test/Test-MacDown-2026.10.07_20-23-52-+0200.xcresult`. Suite précédente full2 n'a pas exécuté de tests : compilation du nouveau test Lifecycle échouait faute de déclaration privée de parseMarkdown ; déclaration category ajoutée puis full3 passé. Le premier oracle footnote pmh_NOTE était erroné : règle grammar ne remplit pas ce type. Oracle final observe l'analyse réelle d'une référence note contenant une emphase ; aucune modification du parser pour satisfaire le test.

Vrai NSBundle du produit Debug : `/tmp/macdown-localization-bundle-contracts 'build/DerivedData/Build/Products/Debug/MacDown 3000.app'` réussi, domaines da/fi/he/hi/uk trouvés ; titres traduits et formes 1/2/5 consommées par JJPluralForm réel.

Core/QL headers/plists/prefs/entitlements relus intégralement. Point ouvert QL preference sandbox : extension sandbox lit suite application sans app group ni exception shared-preference ; la documentation Apple UserDefaults init(suiteName:) exige une entitlement adéquate pour accéder à un autre domaine. Vérification isolée sandbox en préparation ; le résultat des tests unitaires unsandboxed ne prouve pas cet accès. Sources primaires : https://developer.apple.com/documentation/foundation/userdefaults/init%28suitename%3A%29 et https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html .

Build propre universel Debug en cours dans `build/AuditDebug`, Release à suivre. Validation globale encore ouverte.

## R9 — validations complémentaires et état actuel

- Suite complète avant refonte PDF native : 1 416 tests, zéro échec, exit0 ; `/tmp/macdown-audit-reprise-full-tests3.log`, xcresult `build/DerivedData/Logs/Test/Test-MacDown-2026.10.07_20-23-52-+0200.xcresult`. Cette réussite ne certifie pas les sources PDF modifiées ensuite.
- Builds propres Debug et Release : arm64 et x86_64, exit0, produits `build/AuditDebug` et `build/AuditRelease`. Warning Release de versions extension/app divergentes confirmé, correction `c91b9f9` à contrôler sur le prochain produit réel. Signature de distribution non exécutée.
- Sandbox réel corrigé dans `6e8d0db` ; essais signés ad hoc, CFPreferences réellement consommé, lecture autorisée/refus écriture. Voir reprise-quicklook-sandbox.md pour nettoyage et portée.
- 47 tests Lifecycle passent après ajout de cinq assertions de parcours consommateur, `/tmp/macdown-audit-lifecycle-more2.log`, xcresult 20-37-00 ; premier essai arrêté à compilation faute d’import JSContext, réparé avant exécution.
- Lint configuré CI : `npx --yes --package markdownlint-cli markdownlint README.md CHANGELOG.md CONTRIBUTING.md MacDown/Resources/help.md MacDown/Resources/contribute.md`, exit0, `/tmp/macdown-audit-markdownlint.log`. Dépendance exécutée dans le cache npm, aucune installation globale ni modification du dépôt.
- Réconciliation physique : chaque racine de l’inventaire parcourue récursivement, fichiers cachés compris, `os.walk(...,followlinks=False)`, exclusions tiers/build appliquées et `Tools/GitHub-style-generator/node_modules` (dépendances installées) exclu explicitement. Aucun fichier absent de l’inventaire ou de sa liste d’exclusions, aucun fichier inventorié disparu, aucun lien symbolique. Nouveaux tests et preuves restent hors compte du code applicatif. À répéter après dernières créations source PDF éventuelles.
- Seconde passe sécurité URL : MPURLSecurityPolicy.m et MPHTMLResourceURLs.m entièrement relus. Résolution composant final/symlinks et frontière slash protègent la portée des ouvertures ; POSIX/UTI protègent les exécutables. MPGetDataMap consomme seulement les archives `.map` du bundle, pas une archive de document importé. Pas de finding démontré pour ces chemins ; ne pas transformer la dépréciation de l’API d’archive en faille non prouvée.
- Traductions restantes commités séparément après comparaison des IDs aux actions XIB (reading, bold, indent, find, recent documents, Mermaid). Tous les `.strings` modifiés passent `plutil -lint`. Aide frontmatter et extension `.style` corrigées chacune dans un commit.

Gates encore ouverts : pipeline PDF natif et réouverture après export, version paquet finale, tests UI, suite complète après dernières corrections, seconde passe globale et validation finale des empreintes.

### R10 — gate UI tenté, blocage environnement confirmé

`xcodebuild test -scheme MacDownUITests`, `/tmp/macdown-audit-ui-acceptance.log`, xcresult `build/DerivedData/Logs/Test/Test-MacDownUITests-2026.10.07_20-39-10-+0200.xcresult`, exit65. Compilation/liaison et lancement runner réussis ; aucune des quatre fonctions de test UI n’a démarré. XCTest signale `Timed out while enabling automation mode.` après60s. `DevToolsSecurity -status` indique `Developer mode is currently disabled.` : condition environnement distincte d’un défaut application, sans établir que ce réglage est la seule cause. Pas de permission système élargie, pas de contournement, pas de fake succès. La suite UI reste non validée ; xcresult compte seulement l’échec d’initialisation du runner.

Le smoke script CI réinitialise explicitement les domaines de préférences utilisateur et exige `GITHUB_ACTIONS=true`. Il n’est pas exécuté en forgeant ce flag sur le poste utilisateur. Ses tests de migration isolés sont verts, mais ne certifient pas le lancement/migration réel sur un runner propre. Ne pas classer le script CI comme legacy : workflows smoke/release le consomment.

## R11 — contrats autonomes reliés à CI

Les tests natifs ajoutés pendant l’audit vivaient hors target XCTest. Le workflow test les exécute désormais explicitement avant la suite Xcode, dans chaque matrice macOS14/26, avec timeout5min et arrêt immédiat sur erreur. Une seule étape, mêmes scripts qu’exercés pendant l’audit, pas de mock ajouté pour la CI. Aucun appel de publication/signature distribution.

Exécutés de nouveau localement : scripts_tests7scénarios, stall_empty_suite, version_tests, packaging_version_tests, peg_contracts UBSAN, print_colors6titres/PDFKit, mermaid-init2 et header-locations4 : tous exit0. preferences_tests Sandbox signé a déjà passé avant son commit6e8d0db ; pas de répétition inutile du test créant des conteneurs macOS. YAML workflow chargé par Ruby, git diff --check vert. Le job GitHub distant n’a pas été lancé ; ces contrôles locaux ne certifient pas les deux OS distants.

Lecture intégrale finale du workflow test affiché sans troncature, chaque déclencheur, job, timeout, permission, step et branchediagnostic examiné. SHA-256 `9501da350496f41e13090b35dec33eda2afdd15f2963316ebf57b17aaba2683b`.

Produit Debug real : deux plists application/extension portent CFBundleVersion1570 et shortversion3000.0.7-rc.1.post159 ; ValidateEmbeddedBinary exécuté sans avertissementversion. Signature ad hoc extension vérifiée strictement ; entitlement réel embarqué contient domaineexactread-only. Xcode injecte des exceptions supplémentaires dans ses produits de test, distinctes de la politique source et du test Sandbox autonome. Release final à contrôler après correction PDF.

## R12 — derniers correctifs prouvés et commits

RA01 `0c80850` : consumer Core réellement sandboxé consomme les CSS de styles et Prism ; résolution du home réel et droits exacts en lecture. Les flags du fixture non vide sont constants pour isoler toutes les préférences ; h1 et CSS vérifiés. Voir reprise-quicklook-assets.md. Build workspace scheme MacDownQuickLook Release universel exit0 (`/tmp/macdown-audit-quicklook-release2.log`) et signature extension/framework vérifiée `codesign --verify --strict --deep`. Les entitlements embarqués montrent les seuls dossiers sources Styles et Prism/themes en read-only + exact domaineprefs. Signature ad hoc locale, pas distribution Developer ID. Le premier essai -project/-target ne construisait pas les Pods : erreur de contexte build, réparée en workspace/scheme, pas défaut source. Scheme extension construit aussi le host : pas certification des sources PDF alors intermédiaires.

PDF natif `e2845a7` : représente l'original intact et une seconde impression d'identités, puis transfère les GoTo sur les pages canoniques originales. Les deux représentations appartiennent à une seule opération export, pas deux règles de matching. Abandon atomique si géométrie, générations, DOM ou CSSOM divergent ; fermeture/annulation nettoient, fichiers existants préservés. Le matcher texte/ordre et ses modèles supprimés après migration de leur unique consommateur et des tests. Core et rendu app conservent le préprocesseur commun, variations JavaScript QuickLook délibérément désactivées.

Ciblé1 :128tests,6assertions échouées. Deux venaient de l'oracle Mermaid supposant SVG enfant direct de body malgré le wrapper Hoedown, sans bug de production : corrigé pour exclure conteneurs temporaires et compter vrais SVG. Quatre venaient d'un vrai refus PDF avec fragments encodés/inconnus : WebKit peut produire une URL native avec fragment plutôt qu'actionnil ; fix du resolver conservant géométrie exacte et unicité.

Ciblé2 `/tmp/macdown-audit-native-pdf-tests2.log`, xcresult `build/DerivedData/Logs/Test/Test-MacDown-2026.10.07_21-06-46-+0200.xcresult` :130tests zéroéchec, PDF18/18, Lifecycle48/48 (consommation Mermaid réelle huit diagrammes MathJax OFF/ON), CoreRenderer64/64. Mermaid `24b2e48` est une régression de consommation, aucun correctif spéculatif appliqué. Tests standalone de CSS layout/multipage documentés propriétaire PDF. Seconde passe a rouvert l'absence d'ancres avec CSS inaccessible : court-circuit et probe cross-origin en cours, pas case Validé.

Lecture finale complète root : `MacDown/Code/Document/MPPDFAnchorInjector.h`, SHA-256 `7dbaa29df89ed7405bb15a3471f5bdd75b7486a5b2558f60a826caa4430c5593`. Implémentation resolver intégralement affichée sans troncature, nullable/errors/rectangles/fragment decoding/canonicalpages et atomicvalidation examinés ; workflow entier relu après dernière commande assets_tests et YAML chargé.

Lecture finale complète root : `MacDown/Code/Document/MPPDFAnchorInjector.m`, SHA-256 `902c57b2cb6354a651e0b981a49bfee390ae89fc1e003d0d1a71bd343c2ed5a0`. Implémentation resolver intégralement affichée sans troncature, nullable/errors/rectangles/fragment decoding/canonicalpages et atomicvalidation examinés ; workflow entier relu après dernière commande assets_tests et YAML chargé.

Lecture finale complète root : `.github/workflows/test.yml`, SHA-256 `1db3bfbcba1fdda2794c019b14b60c3d7a503844494b47c804a2ded1cbe0af86`. Implémentation resolver intégralement affichée sans troncature, nullable/errors/rectangles/fragment decoding/canonicalpages et atomicvalidation examinés ; workflow entier relu après dernière commande assets_tests et YAML chargé.

## R13 — PDF sans ancres et réconciliation physique

Correction autonome `bae35a9` : en absence de fragments internes non vides, publier le PDF original après vérification du snapshot, sans manipuler le CSSOM ni imprimer les métadonnées. Ciblé initial : 19 tests, trois assertions de fixture échouées parce que l'attente voyait l'ancien document. Attente du marqueur propre au nouveau HTML ajoutée, assertions CSS et PDF maintenues. Ciblé final `/tmp/macdown-audit-zero-anchor-tests2.log`, xcresult `build/DerivedData/Logs/Test/Test-MacDown-2026.10.07_21-20-48-+0200.xcresult` : 19 tests, zéro échec, exit0.

Réconciliation physique répétée après les derniers fichiers source : 478 fichiers actifs ; aucun fichier non inventorié dans les racines, aucun disparu, aucun symlink. Les dépendances installées `Tools/GitHub-style-generator/node_modules` sont désormais explicitement enregistrées dans les exclusions de racines ; manifestes et intégration restent couverts. Ce contrôle ne coche aucune lecture ou validation.

Dernier point ouvert indépendant : navigation non initiée par clic dans l'aperçu, caches de head/base comparés au document réellement chargé ; reproduction en cours par UI avant relecture intégrale finale de MPDocument. Aucun verdict global anticipé.

## R14 — contrôles finaux du code 984b8b3

Navigation N01 confirmée avant correction avec le véritable MPDocument/MPRenderer/WebView et HTTP loopback : `/tmp/macdown-navigation-red.log`. Le consumer retrouvait le texte Markdown mais gardait head distant et base HTTP. Le remplacement body exige désormais que l'URL réellement chargée corresponde à la base du rendu. Correction et régression autonome `984b8b3` ; pas de blocage réseau global.

Suite configurée complète : `xcodebuild test -workspace 'MacDown 3000.xcworkspace' -scheme MacDown -derivedDataPath build/DerivedData -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120`, `/tmp/macdown-audit-final-full-tests.log`, xcresult `build/DerivedData/Logs/Test/Test-MacDown-2026.10.07_21-24-38-+0200.xcresult` : **1427 tests réussis, zéro échec**, exit0, 24,654 s de tests. Inclut navigation, head inchangé/rapide, Mermaid, PDF19 et consommateurs Core.

Builds propres finaux : `xcodebuild clean build` workspace/scheme MacDown, configurations Debug puis Release, `ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' CODE_SIGNING_ALLOWED=NO`, derivedDataPath `build/AuditDebug` puis `build/AuditRelease`. Deux exit0 : `/tmp/macdown-audit-final-debug.log` et `/tmp/macdown-audit-final-release.log`. Chaque app et extension embarquée contient x86_64 et arm64 selon lipo. CFBundleVersion1582 et CFBundleShortVersionString3000.0.7-rc.1.post171 identiques app/extension, sans warning de version divergente. Produits sans signature de distribution ; les preuves sandbox signées ad hoc distinctes restent en R12.

Consumer de ressources `/tmp/macdown-localization-bundle-contracts` exercé sur les deux applications finales : da/fi/he/hi/uk, titre et pluriels1/2/5 réussis. CLI des deux produits finaux --help/--version : quatre exit0, version1582/post171 cohérente. Aucun accès stdin/prefs/lancement dans ces options.

La gate UI R10 reste échouée avant tout cas. Pas de seconde tentative inchangée ni succès déduit de la suite XCTest. Smoke CI destructif pour préférences personnelles non lancé sur ce poste ; signature Developer ID/notarisation/publication non demandées.

## R15 — validation manuelle d'unités et reprise UI

Tableau de seconde-passe-build-cli.md examiné manuellement après R14 : 35 fichiers PEG/version/générateur CSS/argumentprocessor/configuration statique validés dans leur contrat. Ces décisions n'ont pas été dérivées automatiquement d'une empreinte ou d'une commande verte. Les autres fichiers restent lus et analysés, mais leur validation globale dépend de gates encore ouvertes. Le bootstrap versionné greg/greg.c a été retiré de l'exclusion contradictoire : Makefile normal le compile pour produire le générateur ; seule une cible manuelle peut le régénérer avec un générateur déjà disponible. Aucun changement de source ni de périmètre actif.

Dernier gel : 478 fichiers lus et analysés, SHA actuels correspondant tous aux preuves. Aucun chevauchement record actif/exclusion. Registre de commits actualisé jusqu'à984b8b3.

L'utilisateur a activé le mode développeur après les instructions ; `/usr/sbin/DevToolsSecurity -status` confirme `Developer mode is currently enabled.`. Nouvelle suite MacDownUITests lancée, `/tmp/macdown-audit-ui-acceptance2.log` ; résultat encore attendu. Aucun succès UI anticipé.

Suite UI relancée après activation : `/tmp/macdown-audit-ui-acceptance2.log`, xcresult `build/DerivedData/Logs/Test/Test-MacDownUITests-2026.10.07_21-30-11-+0200.xcresult`, exit0, **4 tests exécutés et réussis, zéro échec**, 15,953 s. Fenêtre au lancement, texte saisi dans l'éditeur, textview et aperçu présents. Le blocage R10 est résolu ; il reste comme trace historique, sans exclure ni ignorer les tests. La réussite ne démontre pas chaque opération manuelle imaginable ni la distribution signée.

## R16 — réconciliation finale de la racine et clôture

Le contrôle récursif des racines a été complété par une liste de tous les fichiers de la racine, cachés compris. `.markdownlint.json` était consulté pour le lint R9 mais absent du tableau initial : il est ajouté explicitement comme configuration active, sans réécrire l’historique des comptes478. Lecture complète finale des20lignes/règles : défauts Markdown activés par défaut, exceptions de style précises et MD024 siblings_only ; syntaxe JSON valide, même fichier consommé par la commande CI exacte qui a réussi. SHA-256 `03709bc90f2e0bf621d3e3801b5807d7e4560572e052730a074a8ffa8969d665`. Il ne baisse aucun seuil de l'audit. Racine finale479fichiers actifs. Les docs/licences/données démo et configuration d'assistant .claude sont maintenant explicitement exclus ; aucun code app/build caché supplémentaire retrouvé. Caches Python des seules sondes supprimés ; aucun source modifié.

Décisions finales manuelles root/UI/build/PDF réconciliées : tous fichiers source lus entièrement, analysés et validés dans leurs contrats locaux avec preuves actuelles. PDF natif et Quick Look ont chacun leur consumer réel ; Quick Look utilise identité/UTI isolées, processus extension→WebContent→load/finish/meaningfulpaint, sans prétendre à une capture lisible ou au Finder utilisateur. Le faux candidat CLI venait d'Unicode et est réfuté par stockage réellement relu entre six processus ; aucune correction spéculative. Graphviz6moteurs et Mermaid8types réellement consommés, MathJaxOFF/ON.

Suites finale1427/0 et UI4/0, builds propres Debug/Release arm64/x86_64, versions app/extension identiques, sandbox réel préférences/CSS, lint et contrats autonomes verts. Aucun défaut confirmé restant ni hypothèse déterminante ouverte dans ce périmètre. Aucun push, installation de l'app sous /Applications, distribution Developer ID, notarisation ou publication effectué ; ces opérations distantes restent non certifiées. Code prêt à livrer dans le périmètre local vérifié, sans garantie d'absence universelle de bugs ni d'exécution sur tous OS/services.
