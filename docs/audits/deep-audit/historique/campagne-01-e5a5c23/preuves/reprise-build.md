# Reprise outils, CI et CLI — 2026-10-07

Preuve complémentaire du suivi principal, sans nouveau périmètre ni certification automatique. Tous les fichiers source ci-dessous ont été relus intégralement et leurs fonctions/branches examinées ; leurs empreintes représentent le contenu relu. Aucune case `Validé` globale : build/signature/CLI-app/CI/notarisation restent des gates du responsable principal.

## Découvertes corrigées pendant la reprise

- **RB-01** : `Tools/repro-stall.sh` considérait un résumé `Executed 0 tests` exit0 comme `ok`. Test `stall_empty_suite_tests.py` rouge exécuté (runner exit0, assertion échouée), condition NORUN étendue, puis vert ; suites voisines restent vertes. Aucun vrai Xcode lancé par cet agent.
- **RB-02** : `update_build_number.sh` ne protégeait pas le langage de commande PlistBuddy, distinct de la citation shell. Avec le vrai tag Git `v1.2.3"%n`, script exit0 mais clé CFBundleShortVersionString absente ; lecture PlistBuddy échouée dans version_tests.py. Échappement backslash/guillemet et value citée corrigent le consommateur. Test rouge puis vert exécuté avec vrai Git/make/clang/PlistBuddy isolés.

## Contrôles exécutés

- `python3 MacDownTests/BuildTools/scripts_tests.py` : exit0, sept scénarios golden failure/verify failure/success, CSS compiler failure/success atomic et stall status. Mocks du build externe, vrai shell/make/storage.
- `python3 MacDownTests/BuildTools/stall_empty_suite_tests.py` : exit0 après échec rouge constaté ; suite vide NORUN/exit nonzero.
- `python3 MacDownTests/BuildTools/version_tests.py` : exit0 ; vrai repo Git synthétique, header no-tag/tag/post consommé par C compilé, mtime stable, vrai PlistBuddy ajoute clés et préserve guillemet/%n, missing plist nonzero.
- `ruby MacDownTests/Tools/WorkflowContracts.rb` : exit0, neuf fichiers YAML/52 blocs shell syntax, version input valide/malveillant, paramètres array espaces, grammar long identifier2048, garde CI.
- `ruby MacDownTests/Tools/WebsiteContracts.rb` : exit0 ; bloc extraction complet exécuté, jq réel sur pages synthétiques, JSON consommé, metadata apostrophe+commande conservée sans exécution, prerelease plus ancien que stable retrouvé et draft ignoré. GitHub API est fake.
- `clang -fobjc-arc -fblocks -framework Foundation MacDownTests/CLI/input_tests.m -o /tmp/macdown-audit-cli-input-tests && /tmp/macdown-audit-cli-input-tests` : exit0 ; vrai pipe à producteur différé, erreur EBADF et chars spéciaux filenames Foundation. L'app GUI n'est pas lancée.
- Chaque script `.sh` Tools (sept) + scripts/regenerate + setup a été contrôlé par invocation `bash -n <path>` distincte : neuf scripts syntaxe réussie.
- `plutil -lint Dependency/version/version.xcodeproj/project.pbxproj` : exit0.

La phase rouge historique des corrections déjà présentes n'a pas été recréée ; les preuves initiales sont conservées dans les anciennes notes. Aucun stage/commit effectué par cet agent.

## Fichiers source relus et analysés

| Chemin | SHA-256 | Lu | Analysé | Validé | Preuve spécifique |
| --- | --- | --- | --- | --- | --- |
| `.github/actions/build-macdown/action.yml` | 540cf0bfeb8abfbd0515bd61558ce3a2350940a98b8a8be234cae665522f079d | ☑ | ☑ | ☐ | Branches signature/non-signature, arguments array, archive/extraction, plist consommé ; EU-18, mock argv exécuté ; archive réel root. |
| `.github/actions/setup-macdown/action.yml` | 2c727a47459b0529027067a1f864964350c1f69f5ef0a0f3ff8edfc71c6aea64 | ☑ | ☑ | ☐ | Ordre Node/npmci/Ruby/Pods/PEG, lockfile et absence lifecycle scripts ; EU-21 ; installation réelle root. |
| `.github/dependabot.yml` | ae94084f7047315150685e16d7958a792d39bbc0c2525ef923fc3e8370b3d1df | ☑ | ☑ | ☐ | Bundler/npm chemins cohérents, calendrier et exceptions y18n anciennes sans effet runtime ; aucune suppression demandée. |
| `.github/workflows/build-release.yml` | 327c09e26f78e50a838c25174b85fbb67ff5a7500c5742c8f5133647ca77eff9 | ☑ | ☑ | ☐ | PR/manual, universal architectures, zip/artifact manual, logs failure ; vérification archive réelle root. |
| `.github/workflows/markdownlint.yml` | 1e8a20d34f808fcbf845de3dcf7fa0dc8c34c1a6b97a71cac061d1bb8a2ca343 | ☑ | ☑ | ☐ | Déclenchement documentation, install lint et chemins existants ; dépendances réseau CI non exercées. |
| `.github/workflows/release.yml` | a6ef9579101a06f9c382cff1a560e9a791be807b4d983539393ac40dde9ce926 | ☑ | ☑ | ☐ | Toutes 857 lignes et steps setup/tag/version/changelog/tests/smoke/keychain/cert/build/sign/DMG/notary/notes/draft/cleanup ; EU-18/19/21. Pas de signature/notarisation réelles. |
| `.github/workflows/smoke-test.yml` | 961d97bd49dbd36f97d97c22c735110191fbb81e95696dbfda1f109b007f2669 | ☑ | ☑ | ☐ | Jobs launch/UI, Debug exact path, helper commun, timeouts/artifacts ; test guard local exécuté, app CI non lancée. |
| `.github/workflows/staple-release.yml` | 6a61c84cc043a73cae825d1ac3e63e84067b6a4eec6fbe916e16985eca6ab43e | ☑ | ☑ | ☐ | Toutes 453 lignes : input/tag/checkout/release-info/poll statuses/download checksum/staple/final signature+entitlements/upload/notes/publish. Action distante non exécutée. |
| `.github/workflows/test.yml` | ff340a907ef3dc27cd7e4f80ec299f7f7a2424c6dd3a45361c188db75bdf953e | ☑ | ☑ | ☐ | Matrix/permissions/timeout/logs/status blocked/artifacts ; tests Xcode réels root. |
| `.github/workflows/update-website.yml` | a9ddacf84f11c3945de3f15c07ec7f7d22762848dc4e8aaa1e397e4fb8705874 | ☑ | ☑ | ☐ | Toutes 247 lignes : extraction metadata, latest prerelease pages/date, branches JSON stable/both/prerelease, commit/push retry. EU-20 ; nouveau WebsiteContracts exécute extraction/jq/JSON et données littérales. |
| `Dependency/version/Makefile` | a657c7f788cd96a745d8ce1d7f1034ab26b867eacb976941300af168e3bce5a4 | ☑ | ☑ | ☐ | FORCE rebuild, target stable mtime conservée par generator, clean/install ; vrai make isolated git exécuté. |
| `Dependency/version/version.xcodeproj/project.pbxproj` | 9b87d0ce64c70023ace152fe735d18f3db3715fd5c971aa59ebc75883aa5cb3a | ☑ | ☑ | ☐ | Legacy target est adaptateur make actuel, pas pipeline métier obsolète ; toutes configs/warnings/debug/release et invocation ACTION lus ; plutil réussi. |
| `Tools/GitHub-style-generator/.gitignore` | ca1838cde9e4cfb493f3ea87a08bf973a9d6102aac688fc8828107d5586042aa | ☑ | ☑ | ☐ | Exclusion node_modules fournisseur uniquement. |
| `Tools/GitHub-style-generator/Makefile` | 25ea97722bc0900df6871d8f4d5c2b532fee2c5ed30074ea3f9cc4ca92c5b31b | ☑ | ☑ | ☐ | Prerequis sass/lockfile/Makefile, staging temporary files, fail-fast compiler et atomic mv, suppression temporary ; fake compiler couvre failure/success. |
| `Tools/GitHub-style-generator/index.sass` | 10daab1c94e27a6752a86f26b1f9f6132dfa05eb82f42a86d96acc299e528940 | ☑ | ☑ | ☐ | Import Markdown Primer unique, wrapper CSS transforme markdown-body en body ; compiler consommateur réel root. |
| `Tools/GitHub-style-generator/package.json` | c40a49e1291c18b70b9d467927b87c8009c6f1f4b269f3e9f191797fd21144d2 | ☑ | ☑ | ☐ | Manifest sass/primer, caret constraints et lockfile exact ; repository metadata legacy ne change pas package runtime. |
| `Tools/GitHub-style-generator/package-lock.json` | e4e7fe566e705b52b2b702ddc25bb3daba883a2221ca89db47a6170dbf4709d9 | ☑ | ☑ | ☐ | Toutes 514 lignes en 1–270 et 271–514 ; intégrités/résolutions npm, engines Node20.19, optional platform watcher, peer primitives, graphe Sass/Primer cohérent ; internals fournisseurs exclus. |
| `Tools/compat.py` | 113a769af85a25898125b411f24ea5467b9787bfb064306beccf12400fbf0a0f | ☑ | ☑ | ☐ | Branche Python2 ConfigParser Safe/readfp contre Python3 alias ; usage externe non trouvé, preuve insuffisante pour suppression donc conservé. |
| `Tools/macdown_utils.py` | 2f02ee26ef7353c50373de5ca1e273db1b30078fb76c4452cfcb68baf444b141 | ☑ | ☑ | ☐ | execute argv sans shell, communicate drains stdout/stderr et returncode obligatoire, decode UTF8 ; constants paths/XLIFF. Aucun code caché ; pas suppression sans usages dynamiques établis. |
| `Tools/generate_version_header.sh` | 32e89e8f46e64e3679cb075b0b4285d42c32094311d7152f169efcc29b69e863 | ☑ | ☑ | ☐ | Source location chemins espaces, erreurs Git propagées, escaping C/printf constant, temp/mv et stable mtime ; version réelle compilée et consommée. |
| `Tools/repro-stall.sh` | a0ee310115f9a03e9bac31b73601043a5a0e9582d1d4d77c375dbcd3f09b2292 | ☑ | ☑ | ☐ | Parsing args, logs isolés, command status, watchdog, no-run, failure classification, exit aggregate ; nouveau RB-01 zero tests ; tests isolated taskpolicy exécutés. |
| `Tools/sign_sparkle.sh` | 63740bc01bd59bdf430dcc9b46d87d281bd530d3921cd8595ed45f4808e260c5 | ☑ | ☑ | ☐ | Args/layout/Pods source guard, cinq composants inside-out, count MachO, retry codesign errors/backoff et seal owner ; aucune signature utilisateur exécutée. |
| `Tools/smoke_launch.sh` | d8648538634cfc55ffb0a11f16c542824ffb669e7cc1f8e1dd4e51afa296b29c | ☑ | ☑ | ☐ | Garde CI avant defaults, plist executable, direct PID observation/early exit, bounded termination, cleanup preferences, migration values gate ; aucune donnée préférence locale touchée. |
| `Tools/update_build_number.sh` | 633982df9b4deac8de1361bc590a76c6f471ba9d09686b2e3e22f9d83165374c | ☑ | ☑ | ☐ | Skip CI avant source, git versions, Info.plist existence, Set/Add fallback pour clés absentes, RB-02 quoting du langage PlistBuddy ; vrai fichier isolé et missing failure vérifiés. |
| `Tools/utils.sh` | 6fa173ed0679ea1d15888e72323d025023e9b04e624020925b6cf819852df921 | ☑ | ☑ | ☐ | get_build_version/short_version/bundle_version : nearest vtag, absence tags, post-count, errors return nonzero et git absent fatal ; vrai repo isolated pour branches tag/no-tag/post. |
| `Tools/verify_sparkle_signature.sh` | dbf1db97d46bc941f89d7f50f16f6098a419f4fb0bc0428992bec5546648a03e | ☑ | ☑ | ☐ | Args/layout/MachO count, composants signature strict, identity/runtime/team/timestamp et agrégation erreurs ; signature notarisation distante non certifiée. |
| `macdown-cmd/MPArgumentProcessor.h` | bcb98b7454a3ec7abed3b8e6fdd1a538b7c79f505b22dbfe59be2d410a40e5fe | ☑ | ☑ | ☐ | Contrat help/version/arguments readonly et méthodes bool exit. |
| `macdown-cmd/MPArgumentProcessor.m` | cb12a2c3d28b4596fc9634cfd647d764de178eb830935838190238531fac0c92 | ☑ | ☑ | ☐ | Initialization parser/options/settings, callbacks versions, option short/long et help/header, accessors et exit ; aucune alternative pipeline observée. |
| `macdown-cmd/MPCommandInput.h` | 62aeaedd676d65ce603bed481be096b548f4ec5e52f2a7cc59921c92c14e1789 | ☑ | ☑ | ☐ | isatty no pipe, blocking read chunks/EINTR/EOF/error POSIX ; URL filesystem tilde/relative/standardisation et chars URL littéraux ; tests vrais pipe + Foundation. |
| `macdown-cmd/main.m` | 9da954efa58ccd5074ef025596eb3d094798ad269ec19375ae0c0e4d2d7b38a8 | ☑ | ☑ | ☐ | Help/version before input, stdin error, atomic temporary write, suites file/folder updates, launch status failure. Dépendances prefs/global/suite et consommation pending lues ; consommateur app complet root. |
| `scripts/regenerate-golden-files.sh` | 897f221ab3bb156febdb46e54523a2e6690a36b8e7bdceb5067fa6d378803887 | ☑ | ☑ | ☐ | Preflight tous fichiers avant mutation, restore EXIT/signals, unique DerivedData logs, PIPESTATUS regen expected failure, fixtures source/copy, definitions restored, verify pipefail ; tests builds simulés success/fail rendent erreurs visibles. |
| `setup.sh` | b6b594c02231ac4f58b86f2f840a591cdbf4e3c44fdea21a1c5a46c68781ec32 | ☑ | ☑ | ☐ | Projet root preflight, submodules/Bundler/Pods/PEG puis node version/npm ci ; aucune installation effectuée pour analyse ; guards et consumers CI lus. |

## Tests relus, hors inventaire source principal

- `MacDownTests/BuildTools/scripts_tests.py` : SHA-256 `83a89584b91a57e9700baada438f54c6ddf20da1bcfbd23b3a996ccf2b433875` ; lu intégralement, assertions/mocks/isolation analysés, exécuté avec succès.
- `MacDownTests/BuildTools/stall_empty_suite_tests.py` : SHA-256 `5abb764c88daac9bd56cec8c4c072b18362779ee51b67b7e804a3522080e8e24` ; lu intégralement, assertions/mocks/isolation analysés, exécuté avec succès.
- `MacDownTests/BuildTools/version_tests.py` : SHA-256 `683b9d56c221512b4ecaaaa5a1684976ccd9600e6f8f6fc2b0c8f48ed68e3865` ; lu intégralement, assertions/mocks/isolation analysés, exécuté avec succès.
- `MacDownTests/Tools/WorkflowContracts.rb` : SHA-256 `599506dc08c084b2b7ee03c7423cc38c59d0ab83e1bc4047359150c45e15ee24` ; lu intégralement, assertions/mocks/isolation analysés, exécuté avec succès.
- `MacDownTests/Tools/WebsiteContracts.rb` : SHA-256 `41b7f8811e377f50489db020b5f712ed9a2b3e750e47389256ed1877ae551fdd` ; lu intégralement, assertions/mocks/isolation analysés, exécuté avec succès.
- `MacDownTests/CLI/input_tests.m` : SHA-256 `dbf86538517f58b7733b57a08cb0dbc982562dca79bd0cccaceae5613a4d8d97` ; lu intégralement, assertions/mocks/isolation analysés, exécuté avec succès.

## Seconde passe et limites

Recontrôle du consommateur réel C et plist après version generation ; zéro tests constitue une classe distincte du résumé absent ; no-run avec watchdog reste WEDGE, priorité conservée. Les parcours release/smoke convergent vers le même helper, inputs externes sont séparés de code shell, tableaux d’arguments préservent settings espaces. Pas de retrait du legacy : adaptateurs make/Python2 conservés faute de preuve de retrait dynamique. Les modes signed/unsigned build sont des variations légitimes du packaging. Les entitlements/signatures/notarisation Apple et GUI réelles nécessitent des gates séparées ; aucun accès réseau Apple/GitHub de release ni changement de préférences utilisateur effectué.
