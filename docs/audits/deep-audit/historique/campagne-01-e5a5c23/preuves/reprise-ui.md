# Reprise UI — 2026-10-07

Réutilise `ui-preferences.md`, sans recréer l'inventaire principal. Aucun stage/commit ni Xcode effectué par cet agent. Relecture intégrale effective des 24 fichiers h/m Preferences et Sidebar ; seule sortie Sidebar tronquée concernait la section centrale de MPSidebarSyncCoordinator.m, ensuite relu seul intégralement. Les tests Terminal et Sidebar ont été entièrement relus ; MPPreferencesTests relu en deux plages contiguës 1–640/641–1284. MPSelectionCountTests entièrement lu ; MPDocument.m uniquement section consommateur 640–710, pas revendiqué entièrement lu ici.

## Analyse des corrections héritées et plan de commits

| Correction | Ensemble à committer séparément | Preuve / contrôle restant |
| --- | --- | --- |
| UI-001 liens cassés | Terminal : hunk attributes/fileType/unlink ; tests création du répertoire + testReinstallRepairsDanglingLink | La cible est testée avant unlink ; unlink ne suit pas la cible. XCTest centralisé restant. |
| UI-002 commande étrangère | Terminal : ownership helper/removeOwned, usages lookFor et uninstall ; tests foreign file/directory/link et owned link | Seulement symlink vers bundle actuel ou identifiant connu ; suppression unlink bornée à entrée. XCTest restant. |
| UI-003 migration domaine + timeout | MPPreferences : helper/migration ; MPPreferencesTests catégorie/mock et deux tests ajoutés fin fichier | Worker ne lit que persistentDomain ; seul appelant écrit après semaphore réussi. Choix existant conservé. XCTest restant. |
| UI-004 downgrade | MPPreferences dernier hunk MAX ; assertion marqueur 99 de testFutureVersionSkipsMigrations | Toutes migrations conditionnées currentVersion ; marqueur futur conservé. XCTest restant. |
| UI-005 callback détruit | Terminal : promotion weakSelf/retour et substitutions controller | Retour avant userBinPath et fileURLWithPath. Preuve statique ; test callback non ajouté ici. |
| UI-006 activation dossier .md | Sidebar garde isDirectory ; testReturnKeyWithMarkdownNamedDirectoryDoesNotActivate | Branche Return refuse même dossiers .md comme double click ; delegate sans effet. XCTest restant. |
| UI-008 diagrammes indépendants | HTML XIB bindings enabled supprimés ; MPPreferencesViewControllerResizabilityTests import et testDiagramPreferencesRemainEditableWithoutSyntaxHighlighting | Consommateur renderer est propriété root ; XCTest restant. |
| UI-009/010/011/012 traductions | Commits séparés et/fr/ko/nl selon erreur, zh-Hans et zh-Hant séparés | Analyse diff faite ; reprise ne revendique pas relecture entière de toutes anciennes localisations. Preuve historique ui-preferences conserve lecture ancienne. |
| UI-014 pluriels | Quatre Localizable.strings ru-RU/uk/cs/sk + MacDownTests/Localization/PluralCountRegression.m et test_plural_counts.sh | Corrigé et vérifié formatter réel, 360 contrôles réussis ; bundle final et interface menus à intégrer aux gates root. |

Aucun legacy supprimé. PAPreferences reste adaptation persistante utilisée, migrations historiques restent nécessaires. Les classes de préférences ne créent pas une deuxième implémentation des règles de rendu ; elles persistent des flags consommés par renderer. Dans sidebar Return et double click gardent des comportements légitimement différents pour dossiers (refus vs expand), avec la même règle d'ouverture Markdown.

## UI-014 — preuve et matrice

Contrat : les menus document et sélection affichent des formes cardinales pour des comptes entiers non négatifs. MPDocument.wordCountTitleForKey lit le même Localizable.strings pour règle et six listes de formes puis appelle JJPluralForm. JJPluralForm h/m entièrement lus : règle 7 ru/uk, règle 8 cs/sk, chacune cardinalité 3 ; changer seulement règle provoquerait assertion ou ERR. Les quatre ressources avaient règle 1 et seulement deux formes, d'où `2 слов`, `21 слов`, `2 znaků`, etc.

Référence primaire des catégories entières : [Unicode CLDR 48](https://www.unicode.org/cldr/charts/48/supplemental/language_plural_rules.html), russe/ukrainien one/few/many, tchèque/slovaque one/few/other. Les catégories décimales ne concernent pas NSUInteger. Correction six listes par locale, avec accord des adjectifs de sélection et suffixe sans espaces.

| Scénario | Oracle | Résultat |
| --- | --- | --- |
| Compte 0,1,2,4,5 | Forme attendue explicite indépendante des ressources | 4 locales × 6 titres, réussi |
| 11,12,14 et 111,112 | Exception 11–14 pour ru/uk, pluriel cs/sk | réussi |
| 21,22,24,25,101 | Fin de nombre ru/uk vs nombre entier cs/sk | réussi |
| 3 métriques × sélection/totaux | Valeur finale complète incluant chiffre et suffixe | réussi |

Commande `bash MacDownTests/Localization/test_plural_counts.sh` : clang ARC Foundation + vrai Pods/JJPluralForm.m ; isolation dossier temporaire mktemp, trap nettoyage. Aucune base, préférence utilisateur ni service externe touché. Phase rouge réelle avant modification : 360 vérifications, 96 écarts (log /tmp/macdown-plural-red.log). Phase verte après correction : code 0, 360 vérifications, 0 échec. Les quatre ressources finales et les deux fichiers de test ont été intégralement relus après écriture. Aucune simulation du composant de pluriel. Cette régression n'exerce pas le packaging Xcode ni le clic UI ; contrôles centralisés encore nécessaires.

## Seconde passe

Migration : absence de résultat, exception et timeout restent retryables ; aucune écriture tardive par worker. Synchronous writes permettent consommateur même processus ; dépendances CFPreferences traitées par root. Terminal : fichiers/dossiers homonymes refusés à uninstall ; dangling bundle-current link reste reconnu et supprimable sans cible. Sidebar : cycle de liens évité dans MPFileNode, cible resolvedURL utilisée pour activation, selection own URL prioritaire, reload sauvegarde expansion, stop désabonne sync. Concurrence UI attendue main-thread, contexte watcher possède callback séparé, stop supprime handler. Ressources pluriel : six clés présentes dans les quatre locales, nombre de formes cohérent, formatter réel n'affiche ni ERR ni erreur de format.

Statut de reprise : lecture et analyse locale terminées des 24 h/m ; validation application reste ouverte pour dependencies et gates centralisés. Pas de nouvelle certification globale des 217 .strings ou XIB hérités par une simple vérification SHA.

## Empreintes de la version relue

Ces empreintes suivent la lecture effective, ne servent pas à automatiser validation.

| Fichier | SHA-256 lu | Lu | Analysé localement | Validé application |
| --- | --- | --- | --- | --- |
| `MacDown/Code/Preferences/MPEditorPreferencesViewController.h` | `5c9f8399882aaef434e60b3d8d12e21508e1229481f16d84589eae9f77d446e5` | ☑ | ☑ | ☐ |
| `MacDown/Code/Preferences/MPEditorPreferencesViewController.m` | `6b12bf12fe47f7869d202eedf3a7f3c60b100ad81f8b6644440fb8c669c50912` | ☑ | ☑ | ☐ |
| `MacDown/Code/Preferences/MPGeneralPreferencesViewController.h` | `2a7d3a84426c24b3ad157984d3c807d31662fcee7c065105c4a1b42e5ba3a16f` | ☑ | ☑ | ☐ |
| `MacDown/Code/Preferences/MPGeneralPreferencesViewController.m` | `4b16b9ff667f9f412289c10ecb159f63d5b3793e6fda0d0cc320104eca0cc315` | ☑ | ☑ | ☐ |
| `MacDown/Code/Preferences/MPHtmlPreferencesViewController.h` | `9beb7de62cc892f606f664b4c035af9cd2cb20e1e9fa8831a4aa82a51f22460f` | ☑ | ☑ | ☐ |
| `MacDown/Code/Preferences/MPHtmlPreferencesViewController.m` | `c3f923395429ffe52394a7c9c00796f4d97d7c46bb3c1724a935e82bdd4b5900` | ☑ | ☑ | ☐ |
| `MacDown/Code/Preferences/MPMarkdownPreferencesViewController.h` | `8fbbe0a0a5aed665a1827155ab8a45a46bf8c624dd87a395c6ea774871ae7698` | ☑ | ☑ | ☐ |
| `MacDown/Code/Preferences/MPMarkdownPreferencesViewController.m` | `b6a006708edad119f8c658250fd4acdd3dd2a2164cf021b0017329a648701b25` | ☑ | ☑ | ☐ |
| `MacDown/Code/Preferences/MPPreferences.h` | `8f999b55f2382e2cfa70825d28fb37781ec589137a02af4bea55db7a5acf2c1e` | ☑ | ☑ | ☐ |
| `MacDown/Code/Preferences/MPPreferences.m` | `5e8637e4bd6d59791afe9739d8fdb5f5b606b4fc7b922b178ee27c24c722ddf3` | ☑ | ☑ | ☐ |
| `MacDown/Code/Preferences/MPPreferencesViewController.h` | `fc5407141d5bd0fdf4ab70710dfe8b316d2e8c30c27a0ad98efea86e67fa409f` | ☑ | ☑ | ☐ |
| `MacDown/Code/Preferences/MPPreferencesViewController.m` | `640394689721bef425d179c97c55d3753b7bba70bbe4540f37d44ba755dba0ac` | ☑ | ☑ | ☐ |
| `MacDown/Code/Preferences/MPTerminalPreferencesViewController.h` | `585306c57bb4c53dd3792f4fdd3c6f786e96ecd50ee25845938720b8cae47b53` | ☑ | ☑ | ☐ |
| `MacDown/Code/Preferences/MPTerminalPreferencesViewController.m` | `d1fe66fd53262cee2cf70e3358edd7f1126bcb1b66c1496cee86a8b2935313c0` | ☑ | ☑ | ☐ |
| `MacDown/Code/Sidebar/MPFileNode.h` | `40378502625b374bbb0cae180e7fae17437fc8eb894820955dc55429787072d5` | ☑ | ☑ | ☐ |
| `MacDown/Code/Sidebar/MPFileNode.m` | `b86a626856e4ae90fe6b11628e4436aebf24ae661cf043529373fe892e82d172` | ☑ | ☑ | ☐ |
| `MacDown/Code/Sidebar/MPFolderSidebarViewController.h` | `ffb1bab4cc07cba00270c98d5e279b65507ff8d747d6c8f4ffba14ee19f1a851` | ☑ | ☑ | ☐ |
| `MacDown/Code/Sidebar/MPFolderSidebarViewController.m` | `4bdfd6c0e6257f43c0f903b6c7f7299a66a54248ec83bcdafe991014ff39b5d2` | ☑ | ☑ | ☐ |
| `MacDown/Code/Sidebar/MPFolderWatcher.h` | `6fa9aa05202122ada20c665934642dcbf17aa18791edfb9fbbbb7abccb715b85` | ☑ | ☑ | ☐ |
| `MacDown/Code/Sidebar/MPFolderWatcher.m` | `d26a83fe8cd73c655289d53cdbda2d12aa94b0e867ccf809cd59cdacc88d63ad` | ☑ | ☑ | ☐ |
| `MacDown/Code/Sidebar/MPSidebarSplitView.h` | `c9f56a108c5b1bb8ca5c9ae006e4e90e87314b1b15590878bf5126e7b3e5a9b1` | ☑ | ☑ | ☐ |
| `MacDown/Code/Sidebar/MPSidebarSplitView.m` | `5f8f7f2ba07d56cf6071bb10443bbb2ce85fcd10287866ca4e92354f6b376123` | ☑ | ☑ | ☐ |
| `MacDown/Code/Sidebar/MPSidebarSyncCoordinator.h` | `0e30d13c20f13372d96d614f998f251109b4b2a385db720069176431336a3f08` | ☑ | ☑ | ☐ |
| `MacDown/Code/Sidebar/MPSidebarSyncCoordinator.m` | `bfa586bc60ac0695d8c3be05aa50c7198ff786145e0c8863349650240e2bc827` | ☑ | ☑ | ☐ |
| `MacDown/Localization/ru-RU.lproj/Localizable.strings` | `68868adca55eb9f78d1e3acac391d71ecb7269459d8c8d0c358930fb7aad7133` | ☑ | ☑ | ☐ |
| `MacDown/Localization/uk.lproj/Localizable.strings` | `a84ff7f40dfe23bd48ec878dc6e6ae19188a128881502d13945c5539a123cf24` | ☑ | ☑ | ☐ |
| `MacDown/Localization/cs.lproj/Localizable.strings` | `35840357dc96c3507a1b697fc106530d5ea14768e053e506ca66c0f4cc6384fc` | ☑ | ☑ | ☐ |
| `MacDown/Localization/sk.lproj/Localizable.strings` | `01fbebec2b1033ec16618a93fb81be564f4183564f9f546b396a606c99cbfaba` | ☑ | ☑ | ☐ |
| `MacDownTests/Localization/PluralCountRegression.m` | `f459898ba69108d4bf3b6e7caecbe0b364558a0776b7ac4db60b5b67ec154130` | ☑ | ☑ | ☐ |
| `MacDownTests/Localization/test_plural_counts.sh` | `d5bce2afab9e7f1a488d59fa9daef7b02f64856d98f6a4e04c8492db61226a15` | ☑ | ☑ | ☐ |

## Extension de reprise — éditeur, YAML et callback Terminal

Lecture intégrale effective de MPEditorView.h/m et YAMLSerialization.h/m, puis relecture finale intégrale de YAMLSerialization.m après les correctifs ci-dessous. MPTerminalPreferencesTests.m intégralement relu après ajout (sortie tronquée récupérée par lecture ciblée de toutes lignes manquantes). MPUtilityTests : sections YAML/éditeur relues de la ligne 720 à la fin, et infrastructures de streams examinées ; aucune certification nouvelle du fichier de tests entier sur cette seule lecture partielle.

Éditeur : toutes méthodes de scroll, géométrie, drag, paste/copy et propriétés de substitution examinées. Corrections héritées justifiées : boundingRectForGlyphRange reçoit désormais une plage de glyphes issue de glyphRangeForCharacterRange ; échappement Markdown du label avant paste et encodage des parenthèses de destination protègent les liens collés. Les tests geometry avec surrogate pairs/espaces terminaux et paste avec crochet/parenthèse exercent les entrées concernées ; leur exécution XCTest reste centralisée par root.

YAML hérité : fermeture input stream sur succès/erreur, firstObject sans exception sur document vide, décodage UTF-8 par longueur explicite, rejet des aliases cycliques et limite de profondeur, options mutable containers/leaves indépendantes, copie immutable des conteneurs, validation types/cycles du writer, longueur UTF-8 en octets, émission multi-documents, prise en compte des écritures partielles/échouées et libération des documents examinés. Les aliases partagés sont conservés en lecture ; aucune suppression des API deprecated sans preuve des consommateurs. Pas de second parseur introduit.

### Défaut nouveau : clés de collection YAML

Entrées `? [a, b]\n: value\n`, `? {a: b}\n: value\n`, alias de séquence comme clé et séquence contenant mapping comme clé : la version héritée lève NSInvalidArgumentException en essayant d'insérer une valeur nil. Elle copie les clés avant de remplir leurs enfants ; M13OrderedDictionary utilise en plus l'identité NSObject, son copy ne reste pas recherchable par la clé d'origine. Les collections sont des clés YAML autorisées ([spécification YAML 1.2.2, Nodes](https://yaml.org/spec/1.2.2/#3211-nodes)). Le front matter NSString.frontMatter appelle réellement ce parseur, et le renderer appelle frontMatter ; défaut atteignable par contenu document.

Correction : remplir enfants avant parents avec memo des nodes déjà remplis, convertir uniquement les clés de collection en conteneurs Foundation immutables à égalité par valeur, avec memo à identité pour conserver le partage et éviter expansion des aliases pendant cette conversion. Les valeurs M13 ordonnées existantes restent préservées. Nouveau test public testYAMLCollectionKeysArePopulatedBeforeDictionaryCopiesThem couvre quatre entrées et trois combinaisons de mutabilité, lookup et contenu des clés.

Validation indépendante réelle : clang Foundation, YAMLSerialization sans ARC, M13OrderedDictionary avec ARC, les huit sources C LibYAML du Pod réel. Harness `/tmp/macdown-yaml-review/regression.m`, quatre clés × trois options + cycle/empty/alias valides = 15 contrôles. Source héritée snapshot : code 1, 12 échecs (/tmp/macdown-yaml-review/red.log). Source corrigée : code 0, 0 échec (/tmp/macdown-yaml-review/green.log). Le test ne remplace ni parser ni dictionaries. XCTest application restant.

### Défaut nouveau distinct : erreur YAMLString convertie en chaîne vide

Foundation initWithData:nil crée une chaîne vide dans le probe réel, masquant l'échec de YAMLData pour objet non pris en charge. Correction isolée : retour nil immédiat quand YAMLData est nil. Nouveau test testYAMLStringWriterReturnsNilOnSerializationFailure : NSObject non pris en charge avec NSError, nil avec error NULL, succès Unicode et roundtrip. Probe réel avant : chaîne vide + NSError code 6 ; après : nil + même NSError. Le correctif garde l'échec observable dans l'API publique. XCTest application restant.

### UI-005 : régression callback ajoutée

Complément au guard hérité déjà committé : méthode privée detectHomebrewPrefixWithCompletionHandler qui relaie strictement la fonction de discovery existante ; ce seul bord subprocess est substitué dans le test. Le test conserve le vrai completion créé par lookForShellUtility, libère réellement le controller sous ARC/autoreleasepool, vérifie weak nil puis appelle completion avec nil et un préfixe valide. Il vérifie absence de rétention/exception après destruction, sans fake de l'ownership ni construction URL. Aucun sous-processus Homebrew réel lancé par cette régression. La ligne UI-005 du tableau initial est historique : ce test existe désormais, validation XCTest encore attendue.

### Diagnostic menu français (lecture seule)

L'échec tests2 attend backslash et obtient backtick. XIB Base déclare backslash, aucune surcharge de keyEquivalent localisée retrouvée, ni defaults NSUserKeyEquivalents app/global. NSMenuItem.h du SDK AppKit expose allowsAutomaticKeyEquivalentLocalization depuis macOS 12 et documente remapping automatique des touches inaccessibles au clavier courant, activé par défaut pour SDK 12+. Cela explique plausiblement le résultat français sans établir une mauvaise définition du raccourci. Correction proposée à root : isoler dans le test la propriété allowsAutomaticKeyEquivalentLocalization à NO dans @try/@finally, restaurer sa valeur, puis vérifier le raccourci déclaré ; conserver adaptation en production. Probe Cocoa standalone n'a pas reproduit le remapping, donc diagnostic explicitement inféré du SDK et des données observées, sans revendication de reproduction complète. MPMainControllerMenuTests non modifié ici.

### Versions et garanties restantes

Snapshots hérités intacts pour commit séparé : `/tmp/macdown-yaml-inherited.m` SHA `8477db1fbae7bead8ae3b95546941e6d7b2f9703330b4ee5817364b12bc4542e`, `/tmp/macdown-utility-inherited.m` SHA `f5d662a9a855d43bc41f3e3b9fec07068d112154a27489f4b45862053b54b08a`. Ils excluent les deux nouveaux correctifs YAML, permettant de committer héritage puis nouvelles corrections indépendamment. Ni staging ni commit ni exécution Xcode par cet agent. git diff --check du périmètre corrigé réussi.

| Fichier/version finale examinée | SHA-256 | Lecture entière de cette reprise | Validation application |
| --- | --- | --- | --- |
| MacDown/Code/View/MPEditorView.m | 494d6f39eeff530482928d829651df78ae97860aa74840f20dcdee6470121e08 | oui | restante |
| MacDown/Code/View/MPEditorView.h | 515c6983974c0ba35ff0291b45c9595cde6f9f6807f9a5ef186b322ccb7491b5 | oui | restante |
| Dependency/YAML-framework/YAMLSerialization.m | 4c5e7f821e53578a08314efcd490d7758ec19d430a28d830684747863a4929ae | oui | restante ; harness 15/15 |
| Dependency/YAML-framework/YAMLSerialization.h | 68e864d1d3bbd71066a1f4e73f76ed69928004bbca198f89502159a97b8169b3 | oui | restante |
| MacDown/Code/Preferences/MPTerminalPreferencesViewController.m | 1948d8a659461fa84878f7289d7dd46550ebe96aa70fb2c036414b07d3ea6835 | oui ; remplace ancienne empreinte ci-dessus | restante |
| MacDownTests/MPTerminalPreferencesTests.m | e2550bea7ffcfc062a4d5c7599eb489a5b18f47a3dce856964c9e7046ff7ca05 | oui | restante |
| MacDownTests/MPUtilityTests.m | a7e0cf9031790140844957663303b50985a9536e9e282407650199de152f2e3b | partielle, sections concernées explicites | restante |

Aucune case de validation application cochée sur la seule réussite d'un harness ou d'un hash. Attente des résultats Xcode centralisés et couverture de packaging/consommateurs application.

Résultat central reçu ensuite : `/tmp/macdown-audit-reprise-full-tests.log`, Terminal 19/19 et MPUtilityTests 46/46 réussis, incluant callback détruit et nouveaux tests YAML. La suite globale 1408 tests contient 8 échecs sur d'autres classes (external change et fixtures rendering/syntax) ; cette réussite locale ne vaut pas livraison globale. Aucun contrôle de signature/package manuel revendiqué.
