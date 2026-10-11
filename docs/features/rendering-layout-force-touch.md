# Réglages Compilation et clic du trackpad — 10 octobre 2026

## Réglages Compilation

Le contrôle de coloration syntaxique et les options qui suivent étaient reliés au bas du panneau sans être reliés à la ligne CSS située au-dessus. Auto Layout pouvait donc placer les deux groupes sur les mêmes coordonnées, notamment après chargement des noms de thèmes. La fenêtre réelle en français montre le défaut ; un test avec menus effectivement chargés échoue avec six intersections de contrôles sur le code antérieur.

La case de coloration syntaxique est maintenant placée sous le sélecteur CSS avec un espacement de 12 points. Cette relation complète la chaîne verticale et permet au calcul de hauteur existant de réserver la place nécessaire. Les liaisons de préférences, les actions et les traductions sont conservées.

Le nouveau test natif contrôle toutes les paires de contrôles distincts, avec la hauteur réellement imposée par le contrôleur et les menus peuplés. Le test UI français contrôle les cases et les menus dans la vraie fenêtre. Le premier essai qui retirait la hauteur imposée, et le premier test UI limité aux paires de cases, ne démontraient pas l’absence de défaut : leurs passes ne sont pas utilisées comme validation de la correction.

## Clic du trackpad

L’enregistrement utilisateur montre un mot entier surligné temporairement au premier clic sur un texte sans style. Les clics ordinaires automatisés ne reproduisent pas ce surlignage sur les paragraphes et citations du thème `Github2 (dark)`. Le premier essai de titre visait l’espace entre ses deux lignes et ne touchait pas le texte ; sa coordonnée a été corrigée.

Le parcours natif Force Touch est distinct du `mousedown` JavaScript : WebKit peut préparer sa recherche de mot avant ce dernier. [Apple documente `webkitmouseforcewillbegin` et l’annulation de cette action par `preventDefault()`](https://developer.apple.com/library/archive/documentation/AppleApplications/Conceptual/SafariJSProgTopics/RespondingtoForceTouchEventsfromJavaScript.html).

Le script annule désormais cette préparation sur les portions de texte mappées de l’aperçu. Il ne bloque pas les événements normaux de clic/glissement et conserve les actions Force Touch des liens, des contrôles, du texte non mappé et de l’édition explicite. Aucun réglage global du trackpad ou du système n’est modifié. L’hypothèse Force Touch est fondée sur la vidéo et ce parcours documenté ; la pression physique du trackpad utilisateur ne peut pas être certifiée par les événements souris du runner XCTest.

## Validation et limites

- Suite native ciblée : **40/40 tests réussis**, dont 32 tests de réglages et 8 du menu de mise en forme. Le nouveau contrat Force Touch couvre 36 décisions d’annulation/conservation sur deux thèmes et trois types de contenu. Les événements DOM de ce contrat prouvent l’interception et ses exclusions, sans simuler une pression matérielle.
- Tests UI finaux : **3/3 réussis dans une même exécution**. Ils couvrent le clic ordinaire, ses premières 650 ms, le double-clic, le maintien/glissement et le gras/annulation sur paragraphes/citations/titres avec `Github2 (dark)`, ainsi que les intersections de contrôles dans les réglages français.
- La syntaxe JavaScript et `git diff --check` passent. Les tests natifs sont compilés pour arm64 et x86_64 et exécutés sur arm64 en Debug.
- Les préférences et sessions utilisateur sont isolées puis leur restauration est vérifiée. Il s’agit d’une revue ciblée, sans nouvelle exécution de la totalité des suites ni nouvelle certification exhaustive des fichiers.

Le premier passage UI a échoué sur un glissement dans une citation sombre (sélection vide). Le scénario repasse seul, puis les trois tests repassent ensemble sans modification du correctif. Cet échec intermittent est conservé dans les preuves, sans cause matérielle affirmée.

Corrections : `18384da6` (Compilation) et `ae5566e4` (Force Touch). Les extraits fidèles des logs, leurs empreintes et les chemins des résultats XCTest sont conservés dans [les preuves](../audits/deep-audit/preuves/compilation-force-ui-verified.log), avec [les tests natifs](../audits/deep-audit/preuves/compilation-force-native.log), [l’échec initial UI](../audits/deep-audit/preuves/compilation-force-ui-first.log) et [sa vérification isolée](../audits/deep-audit/preuves/compilation-force-drag-recheck.log).

Le comportement du clic physique du trackpad reste à confirmer par l’utilisateur après installation ; le défaut visuel des réglages possède une reproduction et une vérification automatiques.
