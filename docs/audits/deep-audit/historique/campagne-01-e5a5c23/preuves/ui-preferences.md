# Audit UI, préférences, sidebar — lecture complète, validation centralisée en attente

Date : 2026-10-07. Cases validées laissées fausses : suites centralisées par le coordinateur et dépendances UI restantes.

## Lecture et analyse

- Application : lecture intégrale MPMainController h/m (launch updater, URLs AppleEvent, pending files/folders/piped content, bundled help copy, treats hidden personalization), MPToolbarController h/m (construction, actions groupées/isolées/menu, validation, KVO zoom, presets), MPExportPanelAccessoryViewController h/m (NIB, properties export).
- Preferences : lecture intégrale de tous h/m ; branche fraîche installation, migration legacy + versions 0–6, nettoyage autosave, font et defaults, contrôleurs Editor/HTML/General/Markdown/Terminal et wrapper Auto Layout.
- Sidebar : lecture intégrale h/m ; MPFileNode liens réels, cycles, cache/invalidations, filtre extension ; MPFolderSidebarViewController expansion/sélection/sync/reload et delegates ; MPFolderWatcher ownership FSEvent callback/stop ; SplitView modal drag/finally ; Coordinator isolation racine/notification/no-op/persistance largeur. Analyse dépendances MPDocument encore à réconcilier avec coordinateur.
- Images.xcassets : tous Contents.json entièrement lus. Idiom mac, tailles icône, échelles 1x/2x, références relatives, template intent examinés. PNG non source exécutable, exclus de lecture code ; références existence contrôlées séparément.
- main.m : entrée NSApplicationMain, aucune branche ni effet préalable.
- Localizations : 217/217 fichiers .strings intégralement lus et analysés ; les progressions intermédiaires ci-dessous documentent la lecture sans servir de statut courant. Les 8 XIB Base sont entièrement lus avec actions, bindings, destinations, layouts, contraintes, fenêtres/menu et valeurs déclaratives. 14 Credits.rtf exclus comme prose de crédits non exécutable ; lecture non revendiquée.

## Défauts et corrections

| ID | Preuve | Correction | Tests / état |
| --- | --- | --- | --- |
| UI-001 | createSymlinkAtPath fileExists suit cible : lien cassé considéré absent puis création échoue EEXIST | attributesOfItemAtPath voit lien lui-même ; unlink remplace entrée, ne supprime pas cible/dossier | testReinstallRepairsDanglingLink ajouté, à exécuter |
| UI-002 | lookForShellUtility tout chemin homonyme puis removeItemAtURL sans ownership, dossier supprimé récursivement | ownership symlink vers app actuelle ou Info.plist bundle identifiant MacDown ; uninstall refuse tiers et unlink uniquement | tests foreign command/directory/symlink et owned link, à exécuter |
| UI-003 | migration dictionaryRepresentation inclut domaines hérités ; seconde phase worker écrit après timeout marqué completed | lecture persistentDomainForName seule en worker, application synchrone si lecture finie, clé existante préservée ; échec reste retryable | tests isolated suites & timeout sémaphore, à exécuter |
| UI-004 | applyPreferencesMigrations réécrit 99 à 6, downgrade perd marqueur futur | MAX version courante/cible | assertion 99 conservé ajoutée dans testFutureVersionSkipsMigrations |
| UI-005 | callback terminal weakSelf nul produit fileURLWithPath:nil | promotion strong controller puis return si détruit | analyse statique, besoin test callback |

Tests terminal préexistants : setUp tentait créer source avant répertoire (erreur ignorée). Répertoire créé explicitement ; placeholder XCTAssertTrue(YES) supprimé au profit scénarios réels.

## Lectures hors propriété

NSUserDefaults+Suite.m lu intégralement (CFPreferences getter fuite ownership signalée coordinateur), MPHomebrewSubprocessController.m lu intégralement (delivery main ; stdout lue après termination risque pipe gros output à confirmer propriétaire). Tests MPTerminalPreferencesTests lus intégralement, MPPreferencesTests partiellement (sortie tronquée initiale ; pas certification lecture globale).

## Seconde passe / reprise

Corrections migration et terminal relues ; terminal modifications unlink et strong callback relues intégralement. UI-006 : activateSelectedRow acceptait dossier suffixe .md alors que doubleClick le refusait ; garde isDirectory corrigée, testReturnKeyWithMarkdownNamedDirectoryDoesNotActivate ajouté. Fichier relu intégralement. MainController treat() charge donnée personnalisée, suivre treats.map et consommateurs. Localizations poursuivre sans certifier à partir du parsing.


## Seconde passe UI finale

MPMainController.m relu intégralement après corrections. UI-007 : `MPOpenBundledFile` et `treat()` écrivaient dans chemins temporaires prévisibles (et Images partagé) ; helper commun MPWriteDataToUniqueTemporaryFile assure création dans répertoire UUID privé atomique. Help/contribute copient Images dans le même dossier privé, échec copie nettoie seulement ce dossier. Test testBundledHelpCopiesRemainIndependentAndResolveRelativeImages ajouté. Easter egg `treats.map` confirmé consommé : trois messages Markdown/CSS fêtes pour nom mosky, pas code obfusqué malveillant ni legacy inutilisé ; comportement caché conservé et stockage corrigé. Le marqueur vu n'est stocké qu'après écriture réussie.

UI-008 : deux bindings enabled Graphviz/Mermaid conditionnaient édition à syntax highlighting malgré renderer indépendant (contrat issues #533/#541 et MPGraphvizRenderingTests). Bindings supprimés, valeurs préservées ; XIB HTML relu intégralement final (1–170 / 171–fin). Test testDiagramPreferencesRemainEditableWithoutSyntaxHighlighting charge NIB, clique cases et vérifie préférences puis restaure valeurs. MPEditorPreferencesViewController.xib fini (1–150/151–300/301–fin). MPDocument + MainMenu lus entièrement et contrats/actions revus avec agents Document/rendering. Label réseau MathJax vérifié correct : MathJax 2.7.3 CDN, KaTeX interne Mermaid n'est pas pipeline math app.

Lectures supplémentaires hors propriété : MPPreferencesViewControllerResizabilityTests.m entièrement lu avant ajout ; MPMainControllerMenuTests.m entièrement lu avant ajout ; MPFolderSidebarViewControllerTests sections pertinentes et tests ajoutés, MPPreferencesTests sections migrations seulement. Les suites sont centralisées et non exécutées par cet agent.

Progression localization : strings triés [0:81] entièrement lus (jusqu’à hi Editor). 136 strings restent à lire, non cochés. UI-009 : et Mermaid devenu Merineitsi (nom bibliothèque), Link menu ink ; corrigés en Mermaid/Link. UI-010 : fr Strong Fort et Speech dictée confondaient commandes gras/synthèse vocale ; corrigés Gras/Parole/Commencer la lecture/Arrêter la lecture. Quatre strings modifiés et/fr relus entièrement après correction (et deux fichiers, fr deux fichiers). Valeurs UTF16/UTF8 préservées ; aucune nouvelle logique. Problèmes traduction optionnels (YAML anglais, locales partielles) constatés, fallback Base valide, non bloquants.

Progression : strings triés [0:104] entièrement lus (it-IT sauf MainMenu), 113 strings restants non lus. Formats objets %@ et listes pluriels comparés aux commentaires/sources anglais. Locales partiellement traduites utilisent Base, fichiers vides effectivement lus. Qualité linguistique is/it non certifiée par locuteur natif ; Superscript islandais semble traduit note de bas de page, à confirmer avant modification. Aucun code ni action injectée trouvés dans ces données.

Progression : strings triés [0:135] lus entièrement (nb-NO fini, nl InfoPlist),82 restants. UI-011 : ko menu Find and Replace affichait HTML... et Open Recent affichait Base font, valeurs copiées à mauvais objet ; corrigées en 찾기 및 바꾸기... et 최근 파일 (cohérent sibling Open Recent). Relecture fichier ko final encore à effectuer.

Progression : strings triés [0:160] entièrement lus (ru-RU sauf terminal/menu),57 restent. Défauts localisation non corrigés : nl Mermaid Zeemeermin (nom bibliothèque), nl Shift Left/Right menu désignent touche Shift plutôt que indentation mais Localizable bonnes valeurs présentes. Règle pluriel russe1/two forms suspecte, contrat JJPluralForm demandé agent util avant toute modification.

## Localisations complètes
217/217 .strings entièrement lus (UTF-16/UTF-8), y compris fichiers vides, commentaires et valeurs. Toutes les 8 XIB et 48 métadonnées JSON entièrement lues. Traductions partielles/fallback anglais conservées; certification linguistique native non revendiquée. nl-NL Mermaid conserve le nom du moteur; Shift Left/Right reprend Inspringing verkleinen/vergroten des libellés toolbar déjà présents. ko-KR menu récents et recherche/remplacement corrigés, fichiers finaux ko/nl relus intégralement. Règles de pluriel ru/uk/sk/cs : défaut de contrat linguistique confirmé par lecture intégrale de JJPluralForm.h/m (source tierce locale). Règle 1 anglais : deux formes ; russe/ukrainien règle 7, tchèque/slovaque règle 8 : trois formes. Les fichiers actuels utilisent 1 et deux formes ; modifier seulement la règle provoquerait une assertion de cardinalité. Correction de toutes les formes et validation linguistique restent ouvertes (UI-014).

## Projet Xcode et seconde relecture finale

Le project.pbxproj entier a été lu sans troncature, UUID remplacés par aliases stables pour réduire le bruit sans supprimer valeurs ou commentaires. Version finale entièrement relue après modifications, puis dernier delta de Transpile Styles intégralement relu. `plutil -lint` réussit ; cette vérification ne vaut pas compilation. Workspace interne intégralement lu avant/après remplacement du chemin inexistant MarkPad.xcodeproj par self:.

Corrections justifiées : rattachement de MPTerminalPreferencesTests auparavant absent du target tests ; cinq Localizable.strings orphelins (da/fi/he/hi/uk) ajoutés au groupe variant ; frameworks Cocoa/JavaScriptCore portables via SDKROOT ; producteurs Prism/styles déplacés vers aggregate MacDownResources commun aux dépendances MacDown et MacDownCore, évitant cycle Core → sorties produites par app → Core et doubles écritures concurrentes. Core copie Prism directement depuis le vendor et styles depuis source générée ; nettoyage limité aux destinations propres. Phases déclarent entrées/sorties ; phases sur dossiers forcées à chaque build car mtime de dossier ne couvre pas changement imbriqué. Makefile atomique avec propagation erreur Sass a été corrigé et testé par agent rendering. Aucun build lancé par cet agent.

Fichiers modifiés finaux relus : MPPreferences.m, MPTerminalPreferencesViewController.m (identifiants app release/debug et legacy), MPMainController.m, MPFolderSidebarViewController.m, HTML XIB et tous les strings modifiés. Tests MPTerminalPreferencesTests, MPMainControllerMenuTests et MPPreferencesViewControllerResizabilityTests intégralement relus après ajouts. MPPreferencesTests et SidebarTests ne sont pas revendiqués intégralement lus : seulement parcours pertinents et ajouts.

Exclusions : 14 Credits.rtf (prose non exécutable, lecture non revendiquée), PNG des assets (binaires ; métadonnées entièrement examinées). Lectures hors propriété supplémentaires : JJPluralForm.h/m (contrat tiers uniquement), Makefile du générateur styles. Aucun code legacy supprimé sans preuve ; treats.map reste réellement consommé. Les 319 records comprennent 305 fichiers lus/analysés et 14 exclusions RTF ; validation reste false tant que coordinateur n’a pas complété les gates.
