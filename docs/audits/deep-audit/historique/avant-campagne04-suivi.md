# Deep audit — campagne03, départ de zéro

Statut campagne03 historique : **audit terminé dans sa version examinée**. Suivi ciblé du commit fusionné : **en cours**, voir la section finale. Début : 8 octobre 2026. Baseline `895d6c95b730dd8c98b7eb4b2fdac179c3407c29` ; arbre source propre. Campagne02 archivée dans [historique/campagne-02-895d6c9](historique/campagne-02-895d6c9/suivi.md). Aucun fichier de la nouvelle campagne n'est certifié par l'ancienne revue.

## Périmètre

MacDown est une application Objective-C/C, AppKit/WebKit/JavaScript, Xcode/CocoaPods ; aucun dossier Laravel app/database n'existe. Le périmètre couvre les mêmes racines propres, redécouvertes physiquement : MacDown, MacDownCore, MacDownQuickLook, macdown-cmd, sources propres Dependency, outils, manifests et workflows. Les tests/documentation/fournisseurs/artefacts sont consultés pour les contrats et preuves, avec exclusions explicitement requalifiées. Les deux archives actives ont été intégralement décodées dans cette campagne, avec image et payloads réellement examinés.

| Lot | Fichiers |
| --- | --- |
| root-document | 47 |
| build-cli-peg | 72 |
| ui-locales | 304 |
| rendering-pdf-quicklook | 60 |

## Exclusions de racines à réexaminer

- `Dependency/prism` : Sous-module tiers Prism : interfaces et intégration examinées, code fournisseur hors inventaire propre.
- `MacDown/Resources/Prism` : Assemblage généré depuis Dependency/prism.
- `Pods` : Dépendances CocoaPods installées.
- `build` : Compilations et sauvegardes locales, aucune donnée à auditer.
- `.git` : Métadonnées Git.
- `Tools/GitHub-style-generator/node_modules` : Dépendances npm installées ; manifestes et intégration examinés, code fournisseur hors inventaire propre.
- `.claude` : Configuration/instructions d’un autre assistant ; hors code applicatif et outils build exécutés.
- `assets` : Démonstration Markdown et screenshot du README, données utilisateur de démonstration et non code applicatif.
- `notes` : Documentation technique hors inventaire source.
- `plans` : Documentation de conception et de procédures hors inventaire source.
- `LICENSE` : Licences tierces et application, documentation légale sans code.
- `docs` : Documentation et suivi d’audit, hors inventaire source principal.
- `MacDownTests` : Tests et fixtures examinés pour les preuves, hors inventaire source principal.
- `MacDownUITests` : Tests UI examinés et exécutés pour les preuves, hors inventaire source principal.

## Inventaire exhaustif

| Chemin | SHA de découverte | Lu intégralement | Analysé intégralement | Validé | État | Preuve |
| --- | --- | --- | --- | --- | --- | --- |
| `.envrc.example` | `f8ec968e7ece` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `.github/actions/build-macdown/action.yml` | `b8c590e20b14` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `.github/actions/setup-macdown/action.yml` | `2c727a47459b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `.github/dependabot.yml` | `ae94084f7047` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `.github/workflows/build-release.yml` | `327c09e26f78` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `.github/workflows/markdownlint.yml` | `1e8a20d34f80` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `.github/workflows/release.yml` | `f44f74aa3636` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `.github/workflows/smoke-test.yml` | `961d97bd49db` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `.github/workflows/staple-release.yml` | `6a61c84cc043` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `.github/workflows/test.yml` | `c596922cc088` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `.github/workflows/update-website.yml` | `a9ddacf84f11` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `.gitignore` | `3a2132614cc0` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `.gitmodules` | `69be9ca5f02b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `.markdownlint.json` | `03709bc90f2e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/YAML-framework/YAMLSerialization.h` | `68e864d1d3bb` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/YAML-framework/YAMLSerialization.m` | `982dd82f7b06` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/HGMarkdownHighlighter.h` | `bcaea22152ff` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/HGMarkdownHighlighter.m` | `f7d378231b6e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/HGMarkdownHighlightingStyle.h` | `bbcf8aa4a4c0` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/HGMarkdownHighlightingStyle.m` | `f1fe70f79eee` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/Makefile` | `ba92d8bc7ce5` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/greg/Makefile` | `ed0ae1de9349` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/greg/compile.c` | `5881904b59c4` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/greg/greg.c` | `c673fb8467fc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/greg/greg.g` | `41f4a5493cfe` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/greg/greg.h` | `bcdd2c5dc463` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/greg/tree.c` | `43854b78d4ae` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/peg-markdown-highlight.xcodeproj/project.pbxproj` | `298977daa58b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/peg-markdown-highlight.xcodeproj/project.xcworkspace/contents.xcworkspacedata` | `14212f4d2947` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/pmh_definitions.h` | `3bb4ae80d27f` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/pmh_grammar.leg` | `7295f542e85a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/pmh_parser.h` | `36724d84cf35` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/pmh_parser_foot.c` | `1204e603df3d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/pmh_parser_head.c` | `a91476dcaad2` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/pmh_styleparser.c` | `ffc1ffd453ac` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/pmh_styleparser.h` | `abb30561fb61` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/peg-markdown-highlight/tools/combine_parser_files.sh` | `c64a2e5286b3` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/version/Makefile` | `a657c7f788cd` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Dependency/version/version.xcodeproj/project.pbxproj` | `9b87d0ce64c7` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Gemfile` | `f878fc8d64bc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Gemfile.lock` | `ab1672163bc7` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `MacDown 3000.xcodeproj/project.pbxproj` | `bb83fc2aec27` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `MacDown 3000.xcodeproj/project.xcworkspace/contents.xcworkspacedata` | `7f3b00b5c3fd` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `MacDown 3000.xcodeproj/xcshareddata/xcschemes/MacDown.xcscheme` | `ee6421df4446` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `MacDown 3000.xcodeproj/xcshareddata/xcschemes/MacDownUITests.xcscheme` | `fcd447a2bfaa` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `MacDown 3000.xcworkspace/contents.xcworkspacedata` | `1f2050230d8c` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `MacDown 3000.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` | `dfa0f9bb85b9` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `MacDown 3000.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings` | `c483c4d3281b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `MacDown/Code/Application/MPExportPanelAccessoryViewController.h` | `656b07ee8787` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Application/MPExportPanelAccessoryViewController.m` | `e37f5bc7a153` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Application/MPMainController.h` | `243032702a66` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Application/MPMainController.m` | `888cb2af2d7d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Application/MPToolbarController.h` | `c45bee13d502` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Application/MPToolbarController.m` | `4cf8981f419d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Document/MPAsset.h` | `c1a03ae5c84d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Code/Document/MPAsset.m` | `a4e260bd0ab2` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Code/Document/MPDocument.h` | `f70d0155da47` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Document/MPDocument.m` | `546d434a262c` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Document/MPPDFAnchorInjector.h` | `7dbaa29df89e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Code/Document/MPPDFAnchorInjector.m` | `902c57b2cb63` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Code/Document/MPRenderer.h` | `45e93c4fd1c0` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Code/Document/MPRenderer.m` | `a939696a43b8` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Code/Extension/DOMNode+Text.h` | `748eb6ded390` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/DOMNode+Text.m` | `4005d622d14d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/NSColor+HTML.h` | `ed1b5feb51f0` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/NSColor+HTML.m` | `c97b507bf33b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/NSDocumentController+Document.h` | `502d752bb8dc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/NSDocumentController+Document.m` | `4af8a68681d5` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/NSJSONSerialization+File.h` | `93948eae8346` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/NSJSONSerialization+File.m` | `2408f3ab942a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/NSObject+HTMLTabularize.h` | `1849ce0e2b22` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/NSObject+HTMLTabularize.m` | `1d87c68ca646` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/NSPasteboard+Types.h` | `6d27da2a53fa` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/NSPasteboard+Types.m` | `d61025bbf8f5` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/NSString+Lookup.h` | `8fcb13267c19` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/NSString+Lookup.m` | `9e18ee26f0cf` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/NSTextView+Autocomplete.h` | `ea69f917e5a7` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/NSTextView+Autocomplete.m` | `948afe284ee3` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/NSUserDefaults+Suite.h` | `cac0f676b540` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/NSUserDefaults+Suite.m` | `e0b928949e2a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/WebView+WebViewPrivateHeaders.h` | `f537f69c38a0` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Extension/hoedown_html_patch.c` | `fd8a4612729a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Code/Extension/hoedown_html_patch.h` | `763870f5ef85` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Code/MacDown-Prefix.pch` | `d68c3773ffcf` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Preferences/MPEditorPreferencesViewController.h` | `5c9f8399882a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Preferences/MPEditorPreferencesViewController.m` | `6b12bf12fe47` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Preferences/MPGeneralPreferencesViewController.h` | `2a7d3a84426c` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Preferences/MPGeneralPreferencesViewController.m` | `4b16b9ff667f` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Preferences/MPHtmlPreferencesViewController.h` | `9beb7de62cc8` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Preferences/MPHtmlPreferencesViewController.m` | `c3f923395429` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Preferences/MPMarkdownPreferencesViewController.h` | `8fbbe0a0a5ae` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Preferences/MPMarkdownPreferencesViewController.m` | `b6a006708eda` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Preferences/MPPreferences.h` | `19d1fd4f6fff` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Preferences/MPPreferences.m` | `313dd3a72396` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Preferences/MPPreferencesViewController.h` | `fc5407141d5b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Preferences/MPPreferencesViewController.m` | `640394689721` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Preferences/MPTerminalPreferencesViewController.h` | `585306c57bb4` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Preferences/MPTerminalPreferencesViewController.m` | `1948d8a65946` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Sidebar/MPFileNode.h` | `40378502625b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Sidebar/MPFileNode.m` | `b86a626856e4` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Sidebar/MPFolderSidebarViewController.h` | `ffb1bab4cc07` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Sidebar/MPFolderSidebarViewController.m` | `4bdfd6c0e625` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Sidebar/MPFolderWatcher.h` | `6fa9aa052021` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Sidebar/MPFolderWatcher.m` | `d26a83fe8cd7` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Sidebar/MPSidebarSplitView.h` | `c9f56a108c5b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Sidebar/MPSidebarSplitView.m` | `5f8f7f2ba07d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Sidebar/MPSidebarSyncCoordinator.h` | `0e30d13c20f1` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Sidebar/MPSidebarSyncCoordinator.m` | `bfa586bc60ac` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/Utility/FileURLInlining.h` | `c1696072c1ee` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/FileURLInlining.m` | `8b6cab69f85d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/MPAutosaving.h` | `798fb7bd3f3a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/MPFileWatcher.h` | `07689eb11b45` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/MPFileWatcher.m` | `ee5059ab5cd7` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/MPGlobals.h` | `8ed8632ca58c` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/MPHTMLResourceURLs.h` | `59696bfe884e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/MPHTMLResourceURLs.m` | `ead2d9ccec8a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/MPHomebrewSubprocessController.h` | `eb1e9070b3fe` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/MPHomebrewSubprocessController.m` | `0e7450785408` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/MPMathJaxListener.h` | `91ae4785b093` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/MPMathJaxListener.m` | `818553ca0a3a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/MPResourceWatcherSet.h` | `db6f55e8e1ba` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/MPResourceWatcherSet.m` | `d4663a4990d8` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/MPURLSecurityPolicy.h` | `cff58c6ee4f0` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/MPURLSecurityPolicy.m` | `ae6111380d3d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/MPUtilities.h` | `583fb5ceb495` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/Utility/MPUtilities.m` | `3e05f9cc43cf` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Code/View/MPDocumentSplitView.h` | `625ea83042c7` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/View/MPDocumentSplitView.m` | `a7c8b03e33c9` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/View/MPEditorView.h` | `515c6983974c` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/View/MPEditorView.m` | `a80f4075d2de` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Code/main.m` | `d806c4913d7b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Images.xcassets/AppIcon.appiconset/Contents.json` | `2d55c952e547` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Contents.json` | `972ec1fd4232` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Preferences Icons/Contents.json` | `972ec1fd4232` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Preferences Icons/PreferencesEditor.imageset/Contents.json` | `db68fe085f4b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Preferences Icons/PreferencesGeneral.imageset/Contents.json` | `4437fa77a297` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Preferences Icons/PreferencesMarkdown.imageset/Contents.json` | `92b86b6bd3ed` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Preferences Icons/PreferencesRendering.imageset/Contents.json` | `bb6d2d8f53c0` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Preferences Icons/PreferencesTerminal.imageset/Contents.json` | `4b466f49b984` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/Contents.json` | `972ec1fd4232` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconBlockquote.imageset/Contents.json` | `a145b7675a7d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconBold.imageset/Contents.json` | `41bf3cb94a35` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconComment.imageset/Contents.json` | `189adf35c961` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconCopyHTML.imageset/Contents.json` | `c9ab4cc9bf4a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconEditorAndPreview.imageset/Contents.json` | `370f3fb8c7c9` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconHeading1.imageset/Contents.json` | `04d4084c9fc7` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconHeading2.imageset/Contents.json` | `5317ac258dcf` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconHeading3.imageset/Contents.json` | `6a0629705f23` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconHideEditor.imageset/Contents.json` | `44ffc3693fa1` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconHidePreview.imageset/Contents.json` | `59d89fb85e49` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconHighlight.imageset/Contents.json` | `78fcd02f8026` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconImage.imageset/Contents.json` | `5814d6124059` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconInlineCode.imageset/Contents.json` | `43d65364cf83` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconItalic.imageset/Contents.json` | `3dc3cf7bf3a1` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconLink.imageset/Contents.json` | `66a9c81188d9` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconOrderedList.imageset/Contents.json` | `a2a73d596add` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconShiftLeft.imageset/Contents.json` | `28502d4cf398` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconShiftRight.imageset/Contents.json` | `24b3e2d617c8` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconStrikethrough.imageset/Contents.json` | `e77c50487d11` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconUnderlined.imageset/Contents.json` | `c0be5f16de2b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/Toolbar Icons/ToolbarIconUnorderedList.imageset/Contents.json` | `0e52a063bec8` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/Contents.json` | `972ec1fd4232` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/TouchBarIconBlockquote.imageset/Contents.json` | `4818ccf05ca4` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/TouchBarIconComment.imageset/Contents.json` | `8b4cd66e231a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/TouchBarIconCopyHTML.imageset/Contents.json` | `88108c3b2480` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/TouchBarIconEditorAndPreview.imageset/Contents.json` | `ab8403ee86d7` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/TouchBarIconHeadings.imageset/Contents.json` | `97923d7fee5f` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/TouchBarIconHideEditor.imageset/Contents.json` | `972d73619015` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/TouchBarIconHidePreview.imageset/Contents.json` | `fd0629ddb48d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/TouchBarIconHighlight.imageset/Contents.json` | `db5ed08775e0` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/TouchBarIconImage.imageset/Contents.json` | `95cb5853898b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/TouchBarIconInlineCode.imageset/Contents.json` | `351cc8890128` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/TouchBarIconLink.imageset/Contents.json` | `8a53098a4321` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/TouchBarIconOrderedList.imageset/Contents.json` | `b16b171adfa1` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/TouchBarIconShiftLeft.imageset/Contents.json` | `2546f3fef2a1` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/TouchBarIconShiftRight.imageset/Contents.json` | `8dfa5a1fb64c` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/TouchBarIconStrikethrough.imageset/Contents.json` | `3e19d7de15db` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Images.xcassets/TouchBar Icons/TouchBarIconUnorderedList.imageset/Contents.json` | `dd5a37ede0b9` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/Base.lproj/MPDocument.xib` | `ac4899e95d5a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/Base.lproj/MPEditorPreferencesViewController.xib` | `63ba27c5cabb` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/Base.lproj/MPExportPanelAccessoryViewController.xib` | `d8d09ea196bc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/Base.lproj/MPGeneralPreferencesViewController.xib` | `563948c93c3d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/Base.lproj/MPHtmlPreferencesViewController.xib` | `3f36c0108c13` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/Base.lproj/MPMarkdownPreferencesViewController.xib` | `bccab13b6980` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/Base.lproj/MPTerminalPreferencesViewController.xib` | `b333323b7a06` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/Base.lproj/MainMenu.xib` | `731e44fa814a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ar.lproj/InfoPlist.strings` | `df0f8657ad22` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ar.lproj/Localizable.strings` | `58b8f416a834` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ar.lproj/MPDocument.strings` | `e3b0c44298fc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ar.lproj/MPEditorPreferencesViewController.strings` | `6aac9b0dfe29` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ar.lproj/MPExportPanelAccessoryViewController.strings` | `e3b0c44298fc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ar.lproj/MPGeneralPreferencesViewController.strings` | `43c692936622` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ar.lproj/MPHtmlPreferencesViewController.strings` | `989c6f017fcb` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ar.lproj/MPMarkdownPreferencesViewController.strings` | `ef08e1b174f1` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ar.lproj/MPTerminalPreferencesViewController.strings` | `325b38fffd63` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ar.lproj/MainMenu.strings` | `e3b0c44298fc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/cs.lproj/Localizable.strings` | `35840357dc96` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/cs.lproj/MPDocument.strings` | `77d13ae6ad6e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/cs.lproj/MPEditorPreferencesViewController.strings` | `dc3422797b03` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/cs.lproj/MPExportPanelAccessoryViewController.strings` | `5fa6411ea7a4` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/cs.lproj/MPGeneralPreferencesViewController.strings` | `4a7ed1f06701` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/cs.lproj/MPHtmlPreferencesViewController.strings` | `f2756b964805` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/cs.lproj/MPMarkdownPreferencesViewController.strings` | `9eecfa07f368` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/cs.lproj/MPTerminalPreferencesViewController.strings` | `46f4777460e0` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/cs.lproj/MainMenu.strings` | `74f8f5970a85` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/da-DK.lproj/Localizable.strings` | `2dbb4e4b3246` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/da-DK.lproj/MPDocument.strings` | `661f00f40ef8` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/da-DK.lproj/MPEditorPreferencesViewController.strings` | `4d8ab7b3681f` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/da-DK.lproj/MPExportPanelAccessoryViewController.strings` | `d10cd7f4e6d1` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/da-DK.lproj/MPGeneralPreferencesViewController.strings` | `df99276854c5` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/da-DK.lproj/MPHtmlPreferencesViewController.strings` | `50960a21e6da` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/da-DK.lproj/MPMarkdownPreferencesViewController.strings` | `49ab2f6f01e1` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/da-DK.lproj/MPTerminalPreferencesViewController.strings` | `4f13ac0447fe` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/da-DK.lproj/MainMenu.strings` | `2ccc4edf04d6` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/da.lproj/Localizable.strings` | `1fbe82793907` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/da.lproj/MainMenu.strings` | `c4613839a041` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/de.lproj/InfoPlist.strings` | `df0f8657ad22` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/de.lproj/Localizable.strings` | `0d5cbd7b1af8` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/de.lproj/MPDocument.strings` | `77d13ae6ad6e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/de.lproj/MPEditorPreferencesViewController.strings` | `5e4bc020dc6c` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/de.lproj/MPExportPanelAccessoryViewController.strings` | `aea0a2a42fdc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/de.lproj/MPGeneralPreferencesViewController.strings` | `43cba8a099c4` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/de.lproj/MPHtmlPreferencesViewController.strings` | `c3c651a765c2` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/de.lproj/MPMarkdownPreferencesViewController.strings` | `d88b529df666` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/de.lproj/MPTerminalPreferencesViewController.strings` | `c7b5147b9252` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/de.lproj/MainMenu.strings` | `97bc3e9e956b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/en.lproj/InfoPlist.strings` | `feb5e820d68e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/en.lproj/Localizable.strings` | `6057a201b81b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/es.lproj/InfoPlist.strings` | `fdad9cd80416` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/es.lproj/Localizable.strings` | `3b735be9b95c` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/es.lproj/MPDocument.strings` | `53eb91af71ef` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/es.lproj/MPEditorPreferencesViewController.strings` | `c1a23cfc7b62` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/es.lproj/MPExportPanelAccessoryViewController.strings` | `6788951d9b96` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/es.lproj/MPGeneralPreferencesViewController.strings` | `99d3d9bc434d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/es.lproj/MPHtmlPreferencesViewController.strings` | `05eb988cd145` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/es.lproj/MPMarkdownPreferencesViewController.strings` | `b743eaf4d82e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/es.lproj/MPTerminalPreferencesViewController.strings` | `4c38cc2049eb` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/es.lproj/MainMenu.strings` | `b129f49d084e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/et.lproj/Localizable.strings` | `90e8c7cefa00` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/et.lproj/MPDocument.strings` | `e3b0c44298fc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/et.lproj/MPEditorPreferencesViewController.strings` | `cec21748449d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/et.lproj/MPExportPanelAccessoryViewController.strings` | `9de83922c266` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/et.lproj/MPGeneralPreferencesViewController.strings` | `02c01df21a8e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/et.lproj/MPHtmlPreferencesViewController.strings` | `02ee634b4dbc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/et.lproj/MPMarkdownPreferencesViewController.strings` | `aaee9c6a2338` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/et.lproj/MPTerminalPreferencesViewController.strings` | `0e05dff823f1` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/et.lproj/MainMenu.strings` | `2fde783507f2` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/fi.lproj/Localizable.strings` | `cd4ff5028316` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/fi.lproj/MainMenu.strings` | `42cc431675cd` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/fr.lproj/InfoPlist.strings` | `df0f8657ad22` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/fr.lproj/Localizable.strings` | `8c639198363d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/fr.lproj/MPDocument.strings` | `234472c13bdb` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/fr.lproj/MPEditorPreferencesViewController.strings` | `074001f98791` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/fr.lproj/MPExportPanelAccessoryViewController.strings` | `3d81f3e467ff` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/fr.lproj/MPGeneralPreferencesViewController.strings` | `7294e6b1dc39` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/fr.lproj/MPHtmlPreferencesViewController.strings` | `2bb18bca6529` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/fr.lproj/MPMarkdownPreferencesViewController.strings` | `b4a3d0e7abb0` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/fr.lproj/MPTerminalPreferencesViewController.strings` | `e7d7c0e2846a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/fr.lproj/MainMenu.strings` | `b07946ea0bb6` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/he.lproj/Localizable.strings` | `6a5207a8dd0f` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/he.lproj/MPEditorPreferencesViewController.strings` | `434b042270cc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/he.lproj/MPGeneralPreferencesViewController.strings` | `8e742802f83b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/he.lproj/MPHtmlPreferencesViewController.strings` | `69dc3ebc9ea0` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/he.lproj/MPMarkdownPreferencesViewController.strings` | `58e4bc22cc43` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/he.lproj/MPTerminalPreferencesViewController.strings` | `c2ce1c444126` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/hi.lproj/Localizable.strings` | `055a28a0f519` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/hi.lproj/MPEditorPreferencesViewController.strings` | `529860eabfe4` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/hi.lproj/MPGeneralPreferencesViewController.strings` | `951d58371c2e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/hi.lproj/MPHtmlPreferencesViewController.strings` | `4d9b6c81ebc2` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/hi.lproj/MPMarkdownPreferencesViewController.strings` | `2d4ea129ce35` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/hi.lproj/MPTerminalPreferencesViewController.strings` | `ad51fae53e4e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/is.lproj/InfoPlist.strings` | `df0f8657ad22` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/is.lproj/Localizable.strings` | `7eeabc5a690d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/is.lproj/MPDocument.strings` | `e3b0c44298fc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/is.lproj/MPEditorPreferencesViewController.strings` | `693db64942fe` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/is.lproj/MPExportPanelAccessoryViewController.strings` | `e3b0c44298fc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/is.lproj/MPGeneralPreferencesViewController.strings` | `ceb6a0aa1d5b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/is.lproj/MPHtmlPreferencesViewController.strings` | `f74638f1665e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/is.lproj/MPMarkdownPreferencesViewController.strings` | `2cd40faf4d0d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/is.lproj/MPTerminalPreferencesViewController.strings` | `437f1a4c8014` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/is.lproj/MainMenu.strings` | `c8268c3a1291` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/it-IT.lproj/InfoPlist.strings` | `df0f8657ad22` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/it-IT.lproj/Localizable.strings` | `28a36e295db8` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/it-IT.lproj/MPDocument.strings` | `e3b0c44298fc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/it-IT.lproj/MPEditorPreferencesViewController.strings` | `6c1e968da5b9` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/it-IT.lproj/MPExportPanelAccessoryViewController.strings` | `e30888d3a377` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/it-IT.lproj/MPGeneralPreferencesViewController.strings` | `6b2ffed50489` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/it-IT.lproj/MPHtmlPreferencesViewController.strings` | `51350dfa188f` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/it-IT.lproj/MPMarkdownPreferencesViewController.strings` | `6eaf2544d289` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/it-IT.lproj/MPTerminalPreferencesViewController.strings` | `a8a413d427c5` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/it-IT.lproj/MainMenu.strings` | `31b7dcf0e068` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ja.lproj/InfoPlist.strings` | `df0f8657ad22` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ja.lproj/Localizable.strings` | `35aa3f26eab3` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ja.lproj/MPDocument.strings` | `896e2e4d7fac` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ja.lproj/MPEditorPreferencesViewController.strings` | `c6579561c40a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ja.lproj/MPExportPanelAccessoryViewController.strings` | `f9ebfb561131` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ja.lproj/MPGeneralPreferencesViewController.strings` | `dc438ae1a2c5` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ja.lproj/MPHtmlPreferencesViewController.strings` | `d21df1eb3fd0` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ja.lproj/MPMarkdownPreferencesViewController.strings` | `230493eedbe2` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ja.lproj/MPTerminalPreferencesViewController.strings` | `8d4d2b85ce5b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ja.lproj/MainMenu.strings` | `7a8af1910a61` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ko-KR.lproj/InfoPlist.strings` | `df0f8657ad22` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ko-KR.lproj/Localizable.strings` | `c50cc32c3a32` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ko-KR.lproj/MPDocument.strings` | `e3b0c44298fc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ko-KR.lproj/MPEditorPreferencesViewController.strings` | `40033238b028` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ko-KR.lproj/MPExportPanelAccessoryViewController.strings` | `181aad75e3a8` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ko-KR.lproj/MPGeneralPreferencesViewController.strings` | `f53d0195b3b7` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ko-KR.lproj/MPHtmlPreferencesViewController.strings` | `dee78fab447e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ko-KR.lproj/MPMarkdownPreferencesViewController.strings` | `a7bbb9ebcc72` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ko-KR.lproj/MPTerminalPreferencesViewController.strings` | `bb080e8395f1` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ko-KR.lproj/MainMenu.strings` | `6d5a5d0f2da2` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nb-NO.lproj/Localizable.strings` | `b10f98e62dbb` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nb-NO.lproj/MPDocument.strings` | `661f00f40ef8` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nb-NO.lproj/MPEditorPreferencesViewController.strings` | `f9f9d5e506ca` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nb-NO.lproj/MPExportPanelAccessoryViewController.strings` | `cf22c1463bfd` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nb-NO.lproj/MPGeneralPreferencesViewController.strings` | `9151212cec29` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nb-NO.lproj/MPHtmlPreferencesViewController.strings` | `eb95fed65249` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nb-NO.lproj/MPMarkdownPreferencesViewController.strings` | `818c9a671eed` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nb-NO.lproj/MPTerminalPreferencesViewController.strings` | `4ec7982fd0a3` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nb-NO.lproj/MainMenu.strings` | `3b57f5500508` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nl-NL.lproj/InfoPlist.strings` | `fdad9cd80416` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nl-NL.lproj/Localizable.strings` | `71cdfcefe8a2` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nl-NL.lproj/MPDocument.strings` | `b55fddad29cf` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nl-NL.lproj/MPEditorPreferencesViewController.strings` | `620bfb32c1a3` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nl-NL.lproj/MPExportPanelAccessoryViewController.strings` | `0852735a0254` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nl-NL.lproj/MPGeneralPreferencesViewController.strings` | `7f5d6a8aa957` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nl-NL.lproj/MPHtmlPreferencesViewController.strings` | `e5b853b2c193` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nl-NL.lproj/MPMarkdownPreferencesViewController.strings` | `d371ceb26f10` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nl-NL.lproj/MPTerminalPreferencesViewController.strings` | `f0a714e9ca27` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/nl-NL.lproj/MainMenu.strings` | `cc08d6a1639d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/pt-BR.lproj/InfoPlist.strings` | `df0f8657ad22` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/pt-BR.lproj/Localizable.strings` | `74c2946c2c19` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/pt-BR.lproj/MPDocument.strings` | `53eb91af71ef` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/pt-BR.lproj/MPEditorPreferencesViewController.strings` | `f3a47fdc4575` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/pt-BR.lproj/MPExportPanelAccessoryViewController.strings` | `f39dbd56254f` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/pt-BR.lproj/MPGeneralPreferencesViewController.strings` | `a58ba2f5891f` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/pt-BR.lproj/MPHtmlPreferencesViewController.strings` | `ac50e93130d7` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/pt-BR.lproj/MPMarkdownPreferencesViewController.strings` | `53ffafc65477` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/pt-BR.lproj/MPTerminalPreferencesViewController.strings` | `7baaf07449b7` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/pt-BR.lproj/MainMenu.strings` | `ed748fd0d299` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ru-RU.lproj/Localizable.strings` | `68868adca55e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ru-RU.lproj/MPDocument.strings` | `ebb371a9af64` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ru-RU.lproj/MPEditorPreferencesViewController.strings` | `8da93228df9f` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ru-RU.lproj/MPGeneralPreferencesViewController.strings` | `9507bf17c12e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ru-RU.lproj/MPHtmlPreferencesViewController.strings` | `2fc7cb5b8135` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ru-RU.lproj/MPMarkdownPreferencesViewController.strings` | `5410d9fe6a9e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ru-RU.lproj/MPTerminalPreferencesViewController.strings` | `9f101611d38d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/ru-RU.lproj/MainMenu.strings` | `d63e5ac90489` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sk.lproj/InfoPlist.strings` | `df0f8657ad22` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sk.lproj/Localizable.strings` | `01fbebec2b10` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sk.lproj/MPDocument.strings` | `e3b0c44298fc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sk.lproj/MPEditorPreferencesViewController.strings` | `226be126c609` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sk.lproj/MPExportPanelAccessoryViewController.strings` | `a83d1f38e4ef` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sk.lproj/MPGeneralPreferencesViewController.strings` | `de39fe488104` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sk.lproj/MPHtmlPreferencesViewController.strings` | `0b382c7cba9b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sk.lproj/MPMarkdownPreferencesViewController.strings` | `6269d07eb1ee` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sk.lproj/MPTerminalPreferencesViewController.strings` | `21c9b90634f6` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sk.lproj/MainMenu.strings` | `d0fbef74b1ff` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sv.lproj/InfoPlist.strings` | `df0f8657ad22` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sv.lproj/Localizable.strings` | `ac3110a647b3` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sv.lproj/MPDocument.strings` | `e3b0c44298fc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sv.lproj/MPEditorPreferencesViewController.strings` | `4bcee71f9638` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sv.lproj/MPExportPanelAccessoryViewController.strings` | `e3b0c44298fc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sv.lproj/MPGeneralPreferencesViewController.strings` | `5868c0063dae` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sv.lproj/MPHtmlPreferencesViewController.strings` | `cf8a0f88b969` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sv.lproj/MPMarkdownPreferencesViewController.strings` | `3348650987b1` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sv.lproj/MPTerminalPreferencesViewController.strings` | `e3b0c44298fc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/sv.lproj/MainMenu.strings` | `c8d75d4fa5c9` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/tr.lproj/Localizable.strings` | `1c23dde183a1` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/tr.lproj/MPDocument.strings` | `815060511db9` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/tr.lproj/MPEditorPreferencesViewController.strings` | `4d1629c4844c` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/tr.lproj/MPExportPanelAccessoryViewController.strings` | `e3b0c44298fc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/tr.lproj/MPGeneralPreferencesViewController.strings` | `b9da4d2eef23` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/tr.lproj/MPHtmlPreferencesViewController.strings` | `839a4a4f8130` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/tr.lproj/MPMarkdownPreferencesViewController.strings` | `7160f2e607bc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/tr.lproj/MPTerminalPreferencesViewController.strings` | `75772ca8eefa` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/tr.lproj/MainMenu.strings` | `fd018b1d2d6d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/uk.lproj/Localizable.strings` | `a84ff7f40dfe` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/uk.lproj/MPEditorPreferencesViewController.strings` | `d80ab16b0651` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/uk.lproj/MPGeneralPreferencesViewController.strings` | `3d55949247ea` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/uk.lproj/MPHtmlPreferencesViewController.strings` | `7b4dffc8a972` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/uk.lproj/MPMarkdownPreferencesViewController.strings` | `dd9a57ace594` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/uk.lproj/MPTerminalPreferencesViewController.strings` | `657cdde9ca94` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hans.lproj/InfoPlist.strings` | `d5ba7085d8c5` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hans.lproj/Localizable.strings` | `e015dfd4e881` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hans.lproj/MPDocument.strings` | `20660125f5e9` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hans.lproj/MPEditorPreferencesViewController.strings` | `fbf96c9b3cc4` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hans.lproj/MPExportPanelAccessoryViewController.strings` | `df1b425f1227` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hans.lproj/MPGeneralPreferencesViewController.strings` | `ae626a97ebb1` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hans.lproj/MPHtmlPreferencesViewController.strings` | `e86765eae530` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hans.lproj/MPMarkdownPreferencesViewController.strings` | `92bbcb070a3e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hans.lproj/MPTerminalPreferencesViewController.strings` | `52c00c7f1ab9` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hans.lproj/MainMenu.strings` | `6377fadaaf13` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hant.lproj/InfoPlist.strings` | `df0f8657ad22` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hant.lproj/Localizable.strings` | `a0b66aa86271` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hant.lproj/MPDocument.strings` | `cb70afa03af6` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hant.lproj/MPEditorPreferencesViewController.strings` | `5ae835b35318` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hant.lproj/MPExportPanelAccessoryViewController.strings` | `324816a8e6fc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hant.lproj/MPGeneralPreferencesViewController.strings` | `bbe35625c028` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hant.lproj/MPHtmlPreferencesViewController.strings` | `518a4695f592` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hant.lproj/MPMarkdownPreferencesViewController.strings` | `d121df58ef10` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hant.lproj/MPTerminalPreferencesViewController.strings` | `1663464575c7` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/Localization/zh-Hant.lproj/MainMenu.strings` | `3454158535f0` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-ui.json) |
| `MacDown/MacDown-Info.plist` | `681500c51779` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/MacDown.entitlements` | `62eb40b798da` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Resources/Data/data.map` | `025a921e2605` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Resources/Data/treats.map` | `dba33b7668fc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-root.json) |
| `MacDown/Resources/Extensions/export.css` | `401a13f7ec85` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Extensions/mermaid.forest.css` | `30f7a6778b2c` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Extensions/mermaid.init.js` | `51e9477dfd47` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Extensions/print.css` | `da10026e3d91` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Extensions/show-information.css` | `b6264623da8f` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Extensions/table-resize.js` | `bdd2edb6f2e2` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Extensions/tasklist.js` | `baaec190711e` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Extensions/viz.init.js` | `4284c2771c20` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/MacDown.sdef` | `5643f7986c7f` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/MathJax/init.js` | `c1dba6dd3930` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Styles/Clearness Dark.css` | `f5e84a44a4eb` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Styles/Clearness.css` | `fc407d712394` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Styles/GitHub Tomorrow.css` | `d274836c4802` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Styles/GitHub-2020.css` | `8a193080ed45` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Styles/GitHub.css` | `50b145c3b6ae` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Styles/GitHub2.css` | `d526e3d22730` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Styles/Github2 (dark).css` | `d437fa41d152` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Styles/Gmail.css` | `cf2f35839c87` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Styles/Google Docs.css` | `7305f1bbf768` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Styles/Solarized (Dark).css` | `831c8a7c4159` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Styles/Solarized (Light).css` | `66385e7e1266` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Templates/Default.handlebars` | `3911974b1f3b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/GitHub Dark Default+.style` | `1c871c959cdd` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/GitHub Dark Default.style` | `7ddc20007c5b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/Mou Fresh Air+.style` | `9c7b5281bc57` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/Mou Fresh Air.style` | `7cf14e229256` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/Mou Night+.style` | `29ac097ec816` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/Mou Night.style` | `5f07cfb769df` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/Mou Paper+.style` | `8d2350b0042a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/Mou Paper.style` | `f91490c350a9` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/Solarized (Dark)+.style` | `2fc489c15373` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/Solarized (Dark).style` | `b087429dda9c` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/Solarized (Light)+.style` | `807de1062aad` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/Solarized (Light).style` | `1e62c3734ef4` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/Tomorrow Blue.style` | `090ad9ac160c` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/Tomorrow+.style` | `ed759e275d7a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/Tomorrow.style` | `75c8dc06b2f4` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/Writer+.style` | `732b282bb992` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/Themes/Writer.style` | `1f9c437258f2` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/syntax_highlighting.json` | `048275f9e5a6` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDown/Resources/updateHeaderLocations.js` | `e15be78acc0b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDownCore/Info.plist` | `9c444ac2cdac` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDownCore/MPMarkdownPreprocessor.h` | `ed5e8e88ac2b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDownCore/MPQuickLookPreferences.h` | `26d4c0091d14` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDownCore/MPQuickLookPreferences.m` | `e269e6e827ef` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDownCore/MPQuickLookRenderer.h` | `8624df9faeb3` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDownCore/MPQuickLookRenderer.m` | `7c14e16770e5` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDownCore/MacDownCore.h` | `903651853151` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDownQuickLook/Info.plist` | `59e4ab4e6df8` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDownQuickLook/MacDownQuickLook.entitlements` | `2c615c485eaf` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDownQuickLook/PreviewViewController.h` | `638953029363` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `MacDownQuickLook/PreviewViewController.m` | `6fad5f1905f4` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-render.json) |
| `Podfile` | `285ad31ecf44` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Podfile.lock` | `9a421717ced1` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Tools/GitHub-style-generator/.gitignore` | `ca1838cde9e4` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Tools/GitHub-style-generator/Makefile` | `25ea97722bc0` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Tools/GitHub-style-generator/index.sass` | `876e8f8a34a6` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Tools/GitHub-style-generator/package-lock.json` | `e4e7fe566e70` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Tools/GitHub-style-generator/package.json` | `c40a49e1291c` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Tools/compat.py` | `113a769af85a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Tools/generate_version_header.sh` | `755b872263dc` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Tools/macdown_utils.py` | `2f02ee26ef73` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Tools/release_asset_checksums.py` | `16009b99c665` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Tools/repro-stall.sh` | `a0ee310115f9` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Tools/sign_sparkle.sh` | `63740bc01bd5` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Tools/smoke_launch.sh` | `d8648538634c` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Tools/update_build_number.sh` | `633982df9b4d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Tools/utils.sh` | `6fa173ed0679` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `Tools/verify_sparkle_signature.sh` | `dbf1db97d46b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `macdown-cmd/MPArgumentProcessor.h` | `bcb98b7454a3` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `macdown-cmd/MPArgumentProcessor.m` | `cb12a2c3d28b` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `macdown-cmd/MPCommandInput.h` | `62aeaedd676d` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `macdown-cmd/MPCommandQueue.h` | `4fa62af434ce` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `macdown-cmd/main.m` | `daa47555cc8a` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `scripts/regenerate-golden-files.sh` | `897f221ab3bb` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |
| `setup.sh` | `b6b594c02231` | ☑ | ☑ | ☑ | validé techniquement | [Analyse individuelle](preuves/campagne03-build.json) |

## Parcours et invariants

Parcours reconstruits depuis les sources actuelles et tracés dans les preuves individuelles : documents/IO/undo, rendu/export/PDF, navigation/sandbox, préférences/migrations, queue CLI, ressources/locales/éditeur, Quick Look, build/version/signature/mise à jour. Différences légitimes fastDOM/reload et app/Quick Look examinées ; queue CLI unique, édition automatique corrigée sur insertText. Aucun résultat antérieur utilisé pour certifier ces parcours.

## Défauts et corrections

Sept défauts confirmés et corrigés, documentés dans [commits.md](commits.md) ; un commit distinct par correction, tests de non-régression et relecture entière du fichier final. Git/index et tests Xcode/UI centralisés par root. Les données utilisateur et l'application installée ne servent pas de fixtures.

## Contrôles et critères de livraison

[Clôture, preuves, secondes passes et limites](preuves/campagne03-cloture.md). Toutes les analyses/corrections et gates locales requises sont terminées. Dernière révision source `c0cd3a130785925a81c5c296975b73340a600a9d`. Aucun résultat historique ne certifie cette campagne.

## Compteurs

**483 fichiers actifs, 483 entièrement lus, 483 analysés, 483 validés techniquement.** 120 exclusions individuelles requalifiées et racines fournisseurs/artefacts explicites. Sept corrections, sept commits séparés, aucun défaut technique confirmé ouvert.

## Limites de portée

Validation sur ce macOS/Xcode : tests exécutés arm64, binaires construits arm64/x86_64. Pas d’exécution sur Intel ou matrice macOS14 distante, pas de certification Apple Developer ID/notarisation/publication réelle, pas de certification exhaustive des fournisseurs ni de la grammaire des26langues. Ces limites décrivent le périmètre vérifié ; elles ne sont pas masquées par les cases. Les deux comportements cachés historiques sont documentés dans preuve root, conservés car encore accessibles.


## Première lecture ciblée du commit fusionné dbc6b23 — historique du 9 octobre 2026

État consigné avant la nouvelle passe : **en cours à cet instant, non certifié**. Baseline `dbc6b23fc4b22340972c858756fd09bc2229d33d`, arbre initial propre. Cette extension couvre les cinq fichiers source actifs modifiés ou ajoutés par le commit fusionné, intégralement, et les dépendances nécessaires aux parcours. DOMNode+Text.m est ajouté au périmètre source après confirmation que le compteur inclut les commandes du panneau ; le total actuel est donc six fichiers source. Les validations de campagne03 ci-dessus restent historiques ; elles ne certifient pas cette version. Les tests et documents du commit sont vérifiés séparément, hors compteur source. Aucun déploiement ni push prévu par cet audit.

Racines : `MacDown/Code/Document` (document natif, renderer, transaction source) et `MacDown/Resources/Extensions` (interface JavaScript de l’aperçu). Les autres fichiers du commit sont cinq fichiers de tests et quatre documents/artifact image ; leur liste réelle est rapprochée de `git diff --name-status dbc6b23^ dbc6b23`. Pods/Prism sont fournisseurs, build/.git sont artefacts/métadonnées. Le périmètre est fixé par ce commit ; le rapprochement physique recense 20 fichiers sous ces deux racines, aucun fichier ignoré et aucun lien symbolique. Les fichiers hors commit restent des dépendances ou hors périmètre, sans certification implicite.

### Inventaire de la première lecture ciblée (historique, non certifié)

| Chemin | SHA-256 | Lu | Analysé | Validé | État / preuves |
| --- | --- | --- | --- | --- | --- |
| `MacDown/Code/Document/MPDocument.m` | `be48148bec57df7324e39dcb2e2ddd372bb8057cc524283116f4034d66af134f` | ☐ | ☐ | ☐ | À lire ; aucune validation héritée |
| `MacDown/Code/Document/MPPreviewInlineTransaction.h` | `5a2879fb31bf6e66f93cc7f17a0d80b8a674b0e06ec63b9ed32f1b6aec5bfe98` | ☑ | ☑ | ☐ | [Analyse et seconde passe](preuves/squashed-inline-count.md) ; intégration finale attendue |
| `MacDown/Code/Document/MPRenderer.h` | `897256ea8bb4616dec80592c49c7e02c82bc1ad42f3a43f7c34cc23f213cba6d` | ☑ | ☑ | ☐ | [Analyse et seconde passe](preuves/squashed-renderer.md) ; suite native finale attendue |
| `MacDown/Code/Document/MPRenderer.m` | `cd6b9a332b52f2a160d9c530d59c1fae3246642fa01679953d8c827cafb418e2` | ☑ | ☑ | ☐ | [Analyse et seconde passe](preuves/squashed-renderer.md) ; suite native finale attendue |
| `MacDown/Resources/Extensions/preview-edit.js` | `b6123ca35e435cacdfa966ee008e50ea0036766ce84d400952020056e12867ce` | ☑ | ☑ | ☐ | [Analyse et seconde passe](preuves/squashed-js.md) ; contrôles finaux attendus |

| `MacDown/Code/Extension/DOMNode+Text.m` | `1595fa2638565bbf1af3d46d22ebc7d47cec468a55c7802d715b8877550d3218` | ☑ | ☑ | ☐ | [Analyse et seconde passe](preuves/squashed-inline-count.md) ; régression WebView verte, suite finale attendue |

### Parcours et invariants à vérifier

- A1 : souris/clavier → plage DOM → fragments source prouvés → état commun et panneau ; absence de mise en forme pendant le geste.
- A2 : panneau/barre native → jeton, source et bornes → transaction Markdown → parseur réel → aperçu, sélection et voisins préservés.
- A3 : édition littérale → brouillon → sauvegarde/fermeture/export/impression → document réellement consommé ; refus sans perte de texte.
- A4 : rendu différé/rechargement/préférences → restauration → commandes en attente ; annuler si la source ou la sélection change.
- A5 : volumes et source hostile → sondes/provenance/sérialisation bornées, CSP et navigation ; aucun HTML nouveau dans la source.

### Défauts, contrôles et seconde passe

À renseigner avec des preuves actuelles. Les anciennes suites du rapport de feature sont historiques jusqu’à comparaison des empreintes et vérifications requises.

### Reprise

Six fichiers source recensés ; cinq versions finales entièrement lues et analysées, zéro certifiée avant les suites finales. Document lu intégralement avant correction, relecture finale encore nécessaire. Manifeste CocoaPods, schémas XCTest/XCUITest, workflow natif et coffre d’isolation lus. Corrections déjà commitées séparément : erreurs attachées à la sélection, bouton Fermer retiré, conversion des seules lignes sélectionnées, compteur sans contrôles, couleurs historiques voisines préservées.

## Nouvelle lecture complète du code fusionné — passe indépendante demandée le 9 octobre

Statut : **prêt à livrer dans le périmètre vérifié**. **8 sources intégralement lues, 8 analysées, 8 validées** (9 453 lignes). Aucun défaut confirmé ni hypothèse déterminante ouverts. Huit sources : cinq fichiers applicatifs du commit `dbc6b23`, le compteur DOM et NSTextView+Autocomplete h/m, dépendances directes nécessaires. Chaque version finale a été relue entièrement après correction, sans héritage de certification. Les tests et les quatre documents/artifact du commit sont examinés séparément. Les inventaires précédents restent historiques.

| Chemin | SHA-256 final relu | Lu | Analysé | Validé | Preuve |
| --- | --- | --- | --- | --- | --- |
| `MacDown/Code/Document/MPDocument.m` | `f2a130c74ff27e646ebe6ec665285e756539aef5442b26b43f99ea66ab7d9fc6` | ☑ | ☑ | ☑ | [Lecture intégrale et analyse](preuves/squashed-document-pass2.md) |
| `MacDown/Code/Document/MPPreviewInlineTransaction.h` | `618db0c670ad51b85755258eb1cc27dfdc49f8facd64f060be05cca31434c039` | ☑ | ☑ | ☑ | [Lecture intégrale et analyse](preuves/squashed-inline-count-pass2.md) |
| `MacDown/Code/Document/MPRenderer.h` | `897256ea8bb4616dec80592c49c7e02c82bc1ad42f3a43f7c34cc23f213cba6d` | ☑ | ☑ | ☑ | [Lecture intégrale et analyse](preuves/squashed-renderer-pass2.md) |
| `MacDown/Code/Document/MPRenderer.m` | `cd6b9a332b52f2a160d9c530d59c1fae3246642fa01679953d8c827cafb418e2` | ☑ | ☑ | ☑ | [Lecture intégrale et analyse](preuves/squashed-renderer-pass2.md) |
| `MacDown/Resources/Extensions/preview-edit.js` | `72bb762a66c365f6ea8895882fea2f560a731aa7a8eddb6308a202605bcf7cf0` | ☑ | ☑ | ☑ | [Lecture intégrale et analyse](preuves/squashed-js-pass2.md) |
| `MacDown/Code/Extension/DOMNode+Text.m` | `1595fa2638565bbf1af3d46d22ebc7d47cec468a55c7802d715b8877550d3218` | ☑ | ☑ | ☑ | [Lecture intégrale et analyse](preuves/squashed-inline-count-pass2.md) |
| `MacDown/Code/Extension/NSTextView+Autocomplete.h` | `9412de885b8ff167500177ee83787e485eed5cd4d1ea2de781f4ea3d15ef40e2` | ☑ | ☑ | ☑ | [Lecture intégrale et analyse](preuves/squashed-source-heading.md) |
| `MacDown/Code/Extension/NSTextView+Autocomplete.m` | `2e6d7472c314e9f24f4236f1f5398cb92e2e3021e8f7162e5767af209c07da4f` | ☑ | ☑ | ☑ | [Lecture intégrale et analyse](preuves/squashed-source-heading.md) |

### Contrôles finaux

Les huit fichiers ont été intégralement relus après leur dernière modification. **1 471 XCTest, 13 XCUITest et 65 contrats CLI réussis, zéro échec** ; aucun test ignoré dans les deux suites complètes. Syntaxe JS correcte. Release universel arm64/x86_64 compilé ; signature locale vérifiée et script embarqué identique. Les deux suites ont restauré et vérifié les préférences. Rapprochement final : sources identiques aux versions relues/testées/commitées, aucun fichier actif du périmètre omis. Chaque correction a son commit ; aucune installation ni publication.

Parcours : sélection souris/clavier et styles communs ; source Markdown unique et renderer réel ; restauration/queue commune popup et barre native ; brouillon/sauvegarde/export ; tokens/identité DOM/navigation ; wrappers historiques/UTF-16/volumes. Les preuves individuelles contiennent les registres de fonctions et branches, phases rouges/vertes et secondes passes.

L'ancienne fixture checkbox sans rendererFlags était incorrecte : elle n'est pas utilisée comme preuve de défaut. Une reproduction avec les options réelles démontre le clic non consommé avant correction des collisions d'identité. Le scénario source avec hashes suivis d'espaces a été aligné sur le comportement réel de Hoedown, sans modifier artificiellement sa grammaire.

Extension justifiée : le bouton natif du code fusionné délègue à NSTextView+Autocomplete. Toutes les lignes de cette catégorie h/m sont relues ; les sept consommateurs utilisent désormais les options réelles du renderer du document. L'ancienne API interne a été supprimée après migration et recherche des usages statiques, dynamiques et nib/resources.

[Clôture et résultats](preuves/squashed-cloture.md), [commandes, résultats et empreintes](preuves/squashed-verification.json). Validation locale sur macOS26.6.2/arm64 ; les limites Intel, matrice macOS et distribution sont explicites dans la clôture. Aucun déploiement ni push prévu.


## Nouvelle lecture indépendante — passe 3 du 9 octobre 2026

Statut : **terminé dans le périmètre vérifié**, baseline `17dbbb9ba39746b4c216278b764b2d95fe1ce801`, arbre initial propre. Nouvelle demande après clôture précédente : aucune case Lu/Analysé/Validé héritée. Même périmètre : cinq sources du squash dbc6b23 et trois dépendances directes nécessaires, huit sources actives. Tests/documents hors compteur. Anciennes lectures conservées comme historiques. Aucune installation ni publication.

| Chemin | SHA-256 final relu | Lu | Analysé | Validé | Preuve |
| --- | --- | --- | --- | --- | --- |
| `MacDown/Code/Document/MPDocument.m` | `9c8d4034063cce472c12ba667a81bdcf8c81d013a08dfea61f34763d556cc481` | ☑ | ☑ | ☑ | [Lecture, analyse et seconde passe](preuves/squashed-pass3-document.md) |
| `MacDown/Code/Document/MPPreviewInlineTransaction.h` | `618db0c670ad51b85755258eb1cc27dfdc49f8facd64f060be05cca31434c039` | ☑ | ☑ | ☑ | [Lecture, analyse et seconde passe](preuves/squashed-pass3-inline.md) |
| `MacDown/Code/Document/MPRenderer.h` | `897256ea8bb4616dec80592c49c7e02c82bc1ad42f3a43f7c34cc23f213cba6d` | ☑ | ☑ | ☑ | [Lecture, analyse et seconde passe](preuves/squashed-pass3-renderer.md) |
| `MacDown/Code/Document/MPRenderer.m` | `cd6b9a332b52f2a160d9c530d59c1fae3246642fa01679953d8c827cafb418e2` | ☑ | ☑ | ☑ | [Lecture, analyse et seconde passe](preuves/squashed-pass3-renderer.md) |
| `MacDown/Resources/Extensions/preview-edit.js` | `72bb762a66c365f6ea8895882fea2f560a731aa7a8eddb6308a202605bcf7cf0` | ☑ | ☑ | ☑ | [Lecture, analyse et seconde passe](preuves/squashed-pass3-js.md) |
| `MacDown/Code/Extension/DOMNode+Text.m` | `012b469069e5ba220c530ae1de0df9811585ceca7628330da984723139b56b8d` | ☑ | ☑ | ☑ | [Lecture, analyse et seconde passe](preuves/squashed-pass3-js.md) |
| `MacDown/Code/Extension/NSTextView+Autocomplete.h` | `9412de885b8ff167500177ee83787e485eed5cd4d1ea2de781f4ea3d15ef40e2` | ☑ | ☑ | ☑ | [Lecture, analyse et seconde passe](preuves/squashed-pass3-renderer.md) |
| `MacDown/Code/Extension/NSTextView+Autocomplete.m` | `d836b8efb5885b462a142166998b8541e1db51bc22f5eb75796e5817a81c5d6b` | ☑ | ☑ | ☑ | [Lecture, analyse et seconde passe](preuves/squashed-pass3-renderer.md) |

Lecture complète finale : **8/8 lus, 8/8 analysés, 8/8 validés — 9 501 lignes**. Quatre défauts confirmés et corrigés dans quatre commits séparés : `4929c78` (Setext et voisins), `55629e7` (compteur et styles inline), `cc358cb` (refus impression/PDF), `8c694d7` (CSS export Intel). Les fichiers modifiés sont intégralement relus après leur dernier changement et leurs consommateurs réexaminés. Aucun défaut confirmé non corrigé ni hypothèse déterminante ouverte dans les parcours étudiés.

Contrôles finaux : **1 476 XCTest complets en Intel/Rosetta, 13 XCUITest en ARM et 65 contrats CLI, zéro échec** ; zéro test ignoré dans les suites complètes. Test HTML final ciblé Intel puis ARM réussi après ajout d’une assertion de completion, sans changement applicatif (versions de test explicites). Syntaxe JS correcte. Release universel arm64/x86_64 compilé, signature locale valide et script embarqué identique. Préférences restaurées et vérifiées à chaque session.

Rapprochement complet : cinq sources du squash et trois dépendances directes, aucun fichier actif oublié ; 12 auxiliaires hors compteur. Les SHA relus/testés/commités concordent. Les preuves antérieures restent historiques, aucune validation héritée. Seconde passe terminée ; limites Rosetta/macOS/distribution et confiance envers scripts locaux explicites. Aucune installation ni publication.

[Clôture de cette passe](preuves/squashed-pass3-cloture.md), [commandes, résultats et empreintes](preuves/squashed-pass3-verification.json).
