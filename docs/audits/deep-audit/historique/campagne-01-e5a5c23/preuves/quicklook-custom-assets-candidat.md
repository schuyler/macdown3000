# QuickLook — accès aux styles et thèmes utilisateur

## Défaut confirmé, correction non appliquée

`MacDownCore/MPQuickLookRenderer.m:66–146` cherche les styles et thèmes Prism dans `NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES)` + `MacDown 3000/Styles` ou `MacDown 3000/Prism/themes`. La principale utilise le même domaine utilisateur puis le CFBundleName du produit (`MPUtilities.m:20–41`), qui vaut `MacDown 3000` en Release. Les noms configurés sont lus dans les préférences (`MPQuickLookPreferences.m:96–112`) puis consommés par `embeddedStyles` (`MPQuickLookRenderer.m:325–356`).

Un lecteur Foundation compilé et signé ad hoc avec **les véritables entitlements QuickLook inchangés** confirme deux causes distinctes :

1. Dans le sandbox, NSSearchPath et NSHomeDirectory retournent `~/Library/Containers/<fixture>/Data/...`. Le lookup effectué par les deux fonctions Core ne trouve pas les fichiers utilisateur externes.
2. Un chemin absolu vers ces mêmes fichiers externes ne suffit pas : NSString stringWithContentsOfFile refuse leur lecture avec NSCocoaErrorDomain257, sous-jacent NSPOSIXErrorDomain1 (EPERM). Le grant shared-preference corrige l'accès au nom choisi, pas l'accès au CSS choisi.

Les fixtures sont deux CSS `0600` aux noms UUID ne préexistant pas, placés dans les deux dossiers réellement utilisés. Hors sandbox, les deux lookup/lectures réussissent. Sandbox production : searchExists=false, canonicalContent vide, erreur permission pour les deux. `getpwuid(getuid())->pw_dir` donne le home réel `/Users/zydon`, tandis que NSHomeDirectory reste celui du container.

Contrôle expérimental : même policy production, augmentée **uniquement dans l'app fixture** d'un `com.apple.security.temporary-exception.files.home-relative-path.read-only` désignant les deux fichiers UUID exacts. La lecture absolue réelle réussit alors ; NSSearchPath continue de retourner le container et son lookup échoue toujours. Il faut donc corriger à la fois permission et résolution. Aucun entitlement production n'a été augmenté et aucun véritable CSS/préférence utilisateur n'a été consommé.

## Correction minimale proposée au coordinateur

Un seul parcours de résolution des assets avec priorité utilisateur → bundle, partagé entre app et Core : calculer la racine utilisateur réelle (API passwd ; version réentrante `getpwuid_r` à privilégier), puis les deux sous-répertoires déjà employés. Accorder à QuickLook uniquement la lecture de `/Library/Application Support/MacDown 3000/Styles/` et `/Library/Application Support/MacDown 3000/Prism/themes/` dans le home réel. Conserver l'exception shared-preference séparée ; ne pas accorder accès au home complet, à tous les fichiers ApplicationSupport ou écriture. L'autre architecture possible serait un App Group avec migration explicite des assets, plus large que ce défaut et non nécessaire pour prouver cette réparation.

Apple documente les exceptions home-relative read-only, impose slash initial et slash final pour un répertoire, et recommande la portée read-only quand suffisante : [Entitlement Key Reference — File Access Temporary Exceptions](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html). Cela documente le mécanisme, sans prétendre valider une future soumission App Store.

## Reproduction, lecture et limites

Harnais : `/tmp/macdown-asset-sandbox-contract.m`, pilote `/tmp/macdown-asset-sandbox-test.py` ; compilation Foundation, vrais bundles APPL Mach-O, codesign avec entitlements, chaque subprocess borné à20s. Test final exit0, fixtures CSS supprimées dans finally ; aucun Xcode, aucune production modifiée. Les deux helpers Core et tout le renderer ont été relus ; la preuve statique rattache le comportement Foundation reproduit au lookup réel. Le renderer complet n'a pas été chargé dans une extension QuickLook : ne pas prétendre un E2E Finder.

Le nettoyage des métadonnées ContainerManager est protégé par macOS ; aucune permission forcée. Restent uniquement les containers fixtures signalés :

- `/Users/zydon/Library/Containers/org.macdown.audit.assetreader.94b4dc209e57417c9eae88b472064075.production`
- `/Users/zydon/Library/Containers/org.macdown.audit.assetreader.94b4dc209e57417c9eae88b472064075.fixture-read-only`

Empreintes de la preuve : renderer intégralement relu SHA-256 `f7637311c6c552fe5e0143790a7a83c3b229ff03fe5d07adfb833071e99b4bd5` ; entitlements production intégralement relus `b625a38499d888ac947a33bfd66a2725aa6b4a766532cb4f9cca2b47b7eaf1b8` ; harness `fd6be02ececa73ec6a4881d539c3379054bdfd1789269ccc951b6a07535626fd` ; pilote `d1545a1f49b3dcc717c523f1594f06243373f4251c1f93053cefc490cd1d7426`.
