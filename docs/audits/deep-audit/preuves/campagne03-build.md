# Campagne 03 — build, CLI, YAML et PEG

Nouvelle lecture intégrale des 71 fichiers depuis `895d6c9`, plus le nouveau helper B03-02 : 72 fichiers lus, analysés et validés techniquement après décision de clôture root. Chaque état et SHA sont dans le JSON compagnon. Aucune preuve antérieure réutilisée.

## Défaut B03-01

Upload du DMG et checksum réussi puis échec des notes : retry refuse ticket déjà agrafé. Notes réussies puis échec publication : UUID perdu dans le nouveau body. Correctif autorisé root : réutiliser un ticket validé, répéter toutes vérifications, préserver UUID dans notes. Régression réellement exécutée : mêmes scripts shell, données persistées privées, shasum réel, frontières gh/Apple simulées et aucun effet externe. Échec avant correction, succès après ; quatre refus avant upload vérifiés. Trois fichiers source/test constituent ce seul correctif, commit94de1a9.

## Parcours et preuves

Queue : entrée CLI -> schema/lock privé -> plist atomique -> MainController migration/drain -> documents. Stdin binaire/vide preservé, 320 requêtes concurrentes consommées exactement une fois pendant fixture, FIFO/corruption/symlink/permissions refusés sans perte. Pas de garantie exactement une fois après crash entre drain et document.

YAML : front matter NSString -> graph borné -> Foundation/M13 -> title consumer ; graph aliases/depth/scalars/cycles et collections clés/mutables exercés. Écrivain générique sans consumer applicatif confirmé, API conservée.

PEG : greg.g/bootstrap/compile/tree -> pmh grammar/head/core/foot -> parser/styleparser -> highlighter UTF16 -> ranges NSTextView. Générateur recompilé sous UBSan, identifiers1023–2048/profondeur1100/200variables, parse/sort/free/liens Unicode/styles1000 consommés. Consumers setupEditor relus : deactivate avant extensions/styles puis activate. Tests natifs HG restent root.

Version : Git isolé -> header compiled literal quotes/%n/dev/post -> own target processed plist -> signed extension copy -> parent app. Mtime stable, source/signature embarquée inchangées, CI override cohérent, provenance tag/HEAD/ancestry testée.

Release : native/UI gates -> source tag exacte -> archive -> signature inside-out -> draft notary -> checksum/signature/ticket/Accepted -> app/QL/Sparkle vérification -> upload -> notes -> publication -> site. Fixture ne certifie pas les services Apple ni upload GitHub réels. B03-02 assure maintenant la reprise draft d’un upload DMG/checksum partiel sur hashes persistés avant remplacement ; published et provenance inconnue restent refusés.

## Vérifications fraîches

- `python3 MacDownTests/BuildTools/peg_contracts.py` : PASS.
- `python3 MacDownTests/BuildTools/yaml_graph_tests.py` : PASS.
- `python3 MacDownTests/BuildTools/command_queue_tests.py` : PASS.
- `python3 MacDownTests/BuildTools/version_tests.py` : PASS.
- `python3 MacDownTests/BuildTools/packaging_version_tests.py` : PASS.
- `python3 MacDownTests/BuildTools/release_identity_tests.py` : PASS.
- `python3 MacDownTests/BuildTools/scripts_tests.py` : PASS.
- `python3 MacDownTests/BuildTools/staple_resume_tests.py` : PASS.

## Inventaire individuel

| Fichier | Lecture/analyse | Garantie et branches examinées |
|---|---|---|
| `.envrc.example` | intégrale / analysé | Exemple d'environnement Apple : placeholders seuls, aucun secret; direnv explicite et jamais exécuté ici. |
| `.github/actions/build-macdown/action.yml` | intégrale / analysé | Action build : archive/export explicites, versions release transmises au header et targets, préserver environnement CI. |
| `.github/actions/setup-macdown/action.yml` | intégrale / analysé | Action setup : Node 22, Ruby/Bundler/CocoaPods et sous-module; installation déterministe sans scripts npm. |
| `.github/dependabot.yml` | intégrale / analysé | Dependabot : groupes manifests/actions et cadence; aucune exécution applicative ou secret. |
| `.github/workflows/build-release.yml` | intégrale / analysé | Build release : entrée manuelle/tag, artefacts zip/app, action centrale réutilisée; aucune publication implicite. |
| `.github/workflows/markdownlint.yml` | intégrale / analysé | Markdownlint : déclencheurs et chemins, Node/action, contraintes documentation; aucune gate native prétendue. |
| `.github/workflows/release.yml` | intégrale / analysé | Release : secrets/provenance commit-tag/branches, tests avant build, inside-out signatures, DMG/notary/draft; frontières externes non exercées. |
| `.github/workflows/smoke-test.yml` | intégrale / analysé | Smoke workflow : runner CI, diagnostic cleanup/launch et artefact, source smoke script garde GITHUB_ACTIONS. |
| `.github/workflows/staple-release.yml` | intégrale / analysé | Staple : info UUID/Accepted, checksum/signature/ticket/Gatekeeper/app/QL/Sparkle puis upload-notes-publication; B03-01 corrigé et testé sur reprise. |
| `.github/workflows/test.yml` | intégrale / analysé | Tests : matrice macOS, timeout par étape, contrats réels puis XCTest, erreurs/stalls observables; régression reprise ajoutée. |
| `.github/workflows/update-website.yml` | intégrale / analysé | Website : releases API paginées, filtrage stable/RC, assets DMG/checksum, JSON/Jekyll, branche site et push borné; aucun effet externe exécuté. |
| `.gitignore` | intégrale / analysé | Ignore : générés/binaries/prefs/Pods/build/secrets exclus, exceptions Podfile.lock/Gemfile.lock, sources cachées inventoriées. |
| `.gitmodules` | intégrale / analysé | Sous-module Prism actif consommé par resources target; pas legacy supprimable. |
| `.markdownlint.json` | intégrale / analysé | Règles markdownlint : JSON cohérent avec workflow, aucune règle de code natif. |
| `Dependency/YAML-framework/YAMLSerialization.h` | intégrale / analysé | API YAML : options mutabilité/scalars et stream/string/data/single/multi, deprecated wrappers conservés car contrats publics. |
| `Dependency/YAML-framework/YAMLSerialization.m` | intégrale / analysé | YAML : graph memo depth/nodes/bytes/cycles, copies keys M13, stream read/write partial/error, ownership manuel et dump; front matter consommé NSString+Lookup. |
| `Dependency/peg-markdown-highlight/HGMarkdownHighlighter.h` | intégrale / analysé | API highlighter : target/defaultStyles/autoparse/extensions, notifications et accès main thread; consumers setupEditor observés. |
| `Dependency/peg-markdown-highlight/HGMarkdownHighlighter.m` | intégrale / analysé | Highlighter : génération async/cancel, offsets Unicode, visible ranges, font/style parse, observers et deactivate/free; setupEditor désactive avant extensions. |
| `Dependency/peg-markdown-highlight/HGMarkdownHighlightingStyle.h` | intégrale / analysé | API style : keys traits/color/font/background et range application, copy/default constructors. |
| `Dependency/peg-markdown-highlight/HGMarkdownHighlightingStyle.m` | intégrale / analysé | Style : attributed dictionary clamped font traits, mutable defaults et runtime keys; utilisée seulement par highlighter actif. |
| `Dependency/peg-markdown-highlight/Makefile` | intégrale / analysé | Make PEG : graphe source->greg->core->combined, clean/install, output généré utilisé par Xcode. |
| `Dependency/peg-markdown-highlight/greg/Makefile` | intégrale / analysé | Make greg : bootstrap greg.c et compile/tree objects, flags sanitizers propagés, capacité génération reconstruite en temp. |
| `Dependency/peg-markdown-highlight/greg/compile.c` | intégrale / analysé | Compile greg : code runtime/preamble/footer, node generation, charclasses/actions/thunks/variables, realloc stack; generated 200-variable parser réellement consommé. |
| `Dependency/peg-markdown-highlight/greg/greg.c` | intégrale / analysé | Bootstrap greg : runtime 37 règles/main/getopt/header/trailer, source g active; intégralité 1153 lignes relue, generation reconstruite UBSan. |
| `Dependency/peg-markdown-highlight/greg/greg.g` | intégrale / analysé | Grammaire greg : lexing/comments/identifiers/rules/actions/predicates/trailer/main, conventions trusted grammar; noms longs et profondeur1100 testés. |
| `Dependency/peg-markdown-highlight/greg/greg.h` | intégrale / analysé | Types greg : unions nodes/flags/references/stacks/API coherent compile/tree consumers. |
| `Dependency/peg-markdown-highlight/greg/tree.c` | intégrale / analysé | Tree greg : every constructor/action/rule/stack/realloc/list/print, trusted grammar storage and ownership; dynamic node stack utilisé par génération. |
| `Dependency/peg-markdown-highlight/peg-markdown-highlight.xcodeproj/project.pbxproj` | intégrale / analysé | Projet PEG : PBXLegacyTarget make ACTION, configuration debug/release et graphe targets; pas pipeline alternatif runtime. |
| `Dependency/peg-markdown-highlight/peg-markdown-highlight.xcodeproj/project.xcworkspace/contents.xcworkspacedata` | intégrale / analysé | Workspace PEG : self project reference XML uniquement. |
| `Dependency/peg-markdown-highlight/pmh_definitions.h` | intégrale / analysé | Définitions PEG : types/dummy/raw/style, extensions et lang count, tables name-index cohérentes avec C/highlighter. |
| `Dependency/peg-markdown-highlight/pmh_grammar.leg` | intégrale / analysé | Grammaire Markdown : Doc/blocks/RAW/list/quote/link/ref/inline/HTML/fence/math/note/UTF8 actions, second pass references et offsets. |
| `Dependency/peg-markdown-highlight/pmh_parser.h` | intégrale / analysé | API parser : parse/sort/free et name/type enumeration, allocation contract exact avec highlighter. |
| `Dependency/peg-markdown-highlight/pmh_parser_foot.c` | intégrale / analysé | Parser foot : wrapper parse Doc et result lists, coopération ownership head/core. |
| `Dependency/peg-markdown-highlight/pmh_parser_head.c` | intégrale / analysé | Parser head : UTF8 preformat/BOM/offsets/RAW spans/ref/intermediate queues, two passes, public sort/free; Unicode et liens réellement consommés. |
| `Dependency/peg-markdown-highlight/pmh_styleparser.c` | intégrale / analysé | Styleparser : lignes/tokens/ranges/default/theme, couleurs/font/options/errors, remplacement et libération chaque attribut; 1000 styles et familles vides UBSan. |
| `Dependency/peg-markdown-highlight/pmh_styleparser.h` | intégrale / analysé | API styleparser : enums/collection ownership/callbacks coherent HG consumer. |
| `Dependency/peg-markdown-highlight/tools/combine_parser_files.sh` | intégrale / analysé | Combiner : extraction marqueur core, head+core+foot atomique tempfile/rename, failfast si source incorrecte. |
| `Dependency/version/Makefile` | intégrale / analysé | Make version : FORCE sans mutation mtime si contenu identique, install/clean actifs; header réellement compilé dans fixture. |
| `Dependency/version/version.xcodeproj/project.pbxproj` | intégrale / analysé | Projet version : legacy make ACTION transmet settings au seul générateur central; aucune version dupliquée. |
| `Gemfile` | intégrale / analysé | Gemfile : CocoaPods toolchain seule, versions contraintes et source registry connue. |
| `Gemfile.lock` | intégrale / analysé | Gem lock : dépendances CocoaPods/ffi/xcodeproj actives, versions/platforms/Bundler vérifiées contre setup. |
| `MacDown 3000.xcodeproj/project.pbxproj` | intégrale / analysé | Projet principal : chaque entrée 2909 lignes, targets/resources/CLI/Core/QL, build phases versions/plist/sign/order/Pods, source sharing légitime; packaging ad-hoc vérifié. |
| `MacDown 3000.xcodeproj/project.xcworkspace/contents.xcworkspacedata` | intégrale / analysé | Workspace interne principal : self XML uniquement. |
| `MacDown 3000.xcodeproj/xcshareddata/xcschemes/MacDown.xcscheme` | intégrale / analysé | Scheme app : target ID/host/unit tests/Debug launch/Release archive cohérents projet; XCTest encore requis root. |
| `MacDown 3000.xcodeproj/xcshareddata/xcschemes/MacDownUITests.xcscheme` | intégrale / analysé | Scheme UI : target UI ID/host app/Debug lancement/Release configuration; UI réel encore requis root. |
| `MacDown 3000.xcworkspace/contents.xcworkspacedata` | intégrale / analysé | Workspace : main project + Pods project, chemins existants et graphe source unique. |
| `MacDown 3000.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` | intégrale / analysé | IDE checks : indicateur calcul avertissement32bits, aucune exécution. |
| `MacDown 3000.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings` | intégrale / analysé | Workspace settings : legacy Original build system historique; pas suppression speculative, actual build root requis. |
| `Podfile` | intégrale / analysé | Podfile : targets Core/QL/app/tests/CLI, pinned dependencies, deployment11 et flags post_install, ressources uniques. |
| `Podfile.lock` | intégrale / analysé | Pod lock : versions 2.9.5 Sparkle/LibYAML/M13/Hoedown exactes, checksum/source et target contracts; vendor internals non certifiés. |
| `Tools/GitHub-style-generator/.gitignore` | intégrale / analysé | Ignore generator : node_modules installé seul, manifestes/lock restés source. |
| `Tools/GitHub-style-generator/Makefile` | intégrale / analysé | Make Sass : npm sass local, temp transformation markdown-body->body, atomic rename/preserve existing on failure; fixture rouge/vert exécutée. |
| `Tools/GitHub-style-generator/index.sass` | intégrale / analysé | Sass : imports tokens primitives light/base Markdown requis pour standalone HTML; intégration template hors lot à lire rendering. |
| `Tools/GitHub-style-generator/package-lock.json` | intégrale / analysé | Npm lock : chaque package/provenance/integrity/optional watcher/engines20.19+, aucune publication; npm scripts volontairement ignorés. |
| `Tools/GitHub-style-generator/package.json` | intégrale / analysé | Npm manifest : Primer/Sass locaux, engines>=20.19; setup/workflows Node22 cohérents. |
| `Tools/compat.py` | intégrale / analysé | Compat : Python2/3 url helpers public tools adapter; zéro consumer actuel trouvé hors vendors/docs, absence seule insuffisante pour supprimer. |
| `Tools/generate_version_header.sh` | intégrale / analysé | Generate header : explicit release overrides validated together, escaping C literals, tmp comparison stablemtime; compiled literal quote/%n consumer. |
| `Tools/macdown_utils.py` | intégrale / analysé | Python utils : repository/default prefs paths/version helpers; aucun consumer local trouvé, conservation faute preuve déploiement. |
| `Tools/repro-stall.sh` | intégrale / analysé | Stall runner : QoS timeout/name and run/pass/fail/NORUN/WEDGE, nombre tests non vide, log guard; scénarios fixture0/65/vide passés. |
| `Tools/sign_sparkle.sh` | intégrale / analysé | Sign Sparkle :Refus Pods, layout version2.9.5 exact5MachO, nested IDs/entitlements/runtime/timestamp signing, retries bornés. |
| `Tools/smoke_launch.sh` | intégrale / analysé | Smoke script : CI-only preflight, suite deletion uniquement CI, PID cleanup, legacy migration sentinel et duration observation; jamais exécuté localement. |
| `Tools/update_build_number.sh` | intégrale / analysé | Build number : processed plist propre target-local, CI préserve valeurs, erreur visible; embedded signature ad-hoc intacte après parent phase. |
| `Tools/utils.sh` | intégrale / analysé | Utils shell : git tag/rev-count/plain/dev/post versions, quoting et static bundle IDs; git isolé utilisé. |
| `Tools/verify_sparkle_signature.sh` | intégrale / analysé | Verify Sparkle : layout exact composants, DeveloperID/team/runtime/timestamp et codesign strict; native release certificate non testé ici. |
| `macdown-cmd/MPArgumentProcessor.h` | intégrale / analysé | API argument processor : flags/args/help/version interface correspond impl/CLI entry. |
| `macdown-cmd/MPArgumentProcessor.m` | intégrale / analysé | Argument processor : GBCli register/options/error/help/version, cwd/files filtering, immutable arguments; parsing boundary seul substitué dans CLI fixture. |
| `macdown-cmd/MPCommandInput.h` | intégrale / analysé | Command input : stdin terminal/pipe/empty/binary/EINTR et absolute cwd/tilde URLs; pipe bytes NUL preservés. |
| `macdown-cmd/MPCommandQueue.h` | intégrale / analysé | Command queue : schema bounded32MiB, owner/mode/nlink/regular/no-follow/lock/atomic fsync/enqueue/read/drain; 320 producteurs/consumers et corrupt/symlink/FIFO/permissions testés. |
| `macdown-cmd/main.m` | intégrale / analysé | CLI main : options early exits, classification/dedup files/folders/stdin, enqueue then launch preserving work on error; complete CLI source fixture consumed. |
| `scripts/regenerate-golden-files.sh` | intégrale / analysé | Golden regen : preflight three defines, trap restoration, red generated fixtures copy and second verification; successes/failures restored and observed. |
| `setup.sh` | intégrale / analysé | Setup : requirements Git/Ruby/Node, bundle/pods/version/PEG/Sass pipeline unique, npm pinned --ignore-scripts, failfast. |

## Exclusions requalifiées du lot

- `Dependency/peg-markdown-highlight/greg/compile.o` : Artefact Mach-O compilé arm64, identifié par file; source générateur fraîche et reconstruction UBSan testée; binaire local hors validation source.
- `Dependency/peg-markdown-highlight/greg/greg` : Artefact Mach-O compilé arm64, identifié par file; source générateur fraîche et reconstruction UBSan testée; binaire local hors validation source.
- `Dependency/peg-markdown-highlight/greg/greg.o` : Artefact Mach-O compilé arm64, identifié par file; source générateur fraîche et reconstruction UBSan testée; binaire local hors validation source.
- `Dependency/peg-markdown-highlight/greg/tree.o` : Artefact Mach-O compilé arm64, identifié par file; source générateur fraîche et reconstruction UBSan testée; binaire local hors validation source.
- `Dependency/peg-markdown-highlight/pmh_parser.c` : Source générée : entrées/générateur lus intégralement; génération et consommation en fixture fraîche; sortie locale non certifiée ligne par ligne.
- `Dependency/peg-markdown-highlight/pmh_parser_core.c` : Source générée : entrées/générateur lus intégralement; génération et consommation en fixture fraîche; sortie locale non certifiée ligne par ligne.
- `Dependency/version/version.h` : Source générée : entrées/générateur lus intégralement; génération et consommation en fixture fraîche; sortie locale non certifiée ligne par ligne.
- `MacDown 3000.xcworkspace/xcshareddata/MacDown.xccheckout` : Métadonnées SCM XML/JSON entièrement lues; URLs historiques IDE seulement, aucun effet build/publish source.
- `MacDown 3000.xcworkspace/xcshareddata/MacDown.xcscmblueprint` : Métadonnées SCM XML/JSON entièrement lues; URLs historiques IDE seulement, aucun effet build/publish source.
- `Tools/GitHub-style-generator/README.md` : Documentation README générateur lue, contrat Node20.19/pinned Primer/Sass confirmé par manifests/setup.

Les racines tierces, générées, caches et métadonnées sont explicitement séparées dans le JSON ; aucune certification des internals fournisseurs par un hash ou un build seul.

## B03-02 — reprise après upload partiel

Confirmé : DMG uploadé, .sha256 upload échoué cinq fois, reprise refuse ancien checksum. Correctif distinct après commit B03-01 `94de1a9` : hashes original/agrafé persistés dans brouillon avant remplacement. Toute panne de cette écriture empêche upload. Réparation sidecar uniquement pour draft/tag/commit exacts, métadonnées uniques et bytes correspondant à hash connu préenregistré ; shasum, signature, ticket et toutes gates restent exécutés. Helper conservé RUNNER_TEMP avant checkout ancien tag. Nouvelle source `Tools/release_asset_checksums.py` lue/analysee intégralement, total 72 fichiers ; validation toujours ouverte. `staple_partial_upload_tests.py` PASS, rejoue pipeline réel et refus unknown/published/wrong tag/commit/no metadata/ambigu sans mutation. UUID conservé et B03-01 régression rejouée PASS. Aucune API externe ni native notarisation réellement utilisée.

Révision B03-02 après revue root : une release publiée dont checksum/signature/ticket sont valides poursuit toutes les vérifications en conservant les octets et les notes, sans edit/upload/staple. Fixture complète PASS, mismatch published avec hashes connus refusé. Workflow final intégral et fixture partielle finale relus.

B03-02 committé par root ef1aa63 après revue et replay des deux fixtures verts, logs build/AuditCampaign03/staple-*-final.log. Les gates globales de livraison restent distinctes; 72 lus/analysés, validation en attente.

Clôture root : les mentions de gates en attente dans les relevés initiaux sont soldées par FINAL1437+UI4, Debug/Release universels et signature ad-hoc locale stricte. Publication Apple/GitHub réelle non exercée, aucune certification externe. Voir campagne03-cloture.md.
