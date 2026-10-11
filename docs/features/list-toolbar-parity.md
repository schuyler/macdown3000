# Listes : barre rapide et menu du visualiseur — 9 octobre 2026

## Défaut et contrat

Les actions natives de liste ordonnée et non ordonnée appelaient `toggleBlockWithPattern`, qui ajoutait/retirait seulement un préfixe dans la sélection de l'éditeur. Elles ne consommaient pas la sélection active du visualiseur et pouvaient empiler des marqueurs (`- 1. texte`), conserver un titre/citation ou retirer la liste au second clic. Le menu du visualiseur appliquait déjà une conversion de bloc fondée sur le rendu réel.

Les boutons appliquent désormais les valeurs `unordered`, `ordered` et `tasks` au même moteur que le menu. Ce sont des conversions, pas des toggles retirant les listes. Les noms de sélecteurs existants sont conservés pour les menus/raccourcis et les identifiants de barre personnalisée.

## Implémentation

- Extraction exacte du traitement de bloc existant dans `applyBlockFormattingValue:selection:callouts:renderer:`. Le corps a été comparé byte pour byte après normalisation de l'indentation ; L'adaptation injecte l'oracle/ranges callout, permet l'insertion sur une ligne vide et préserve séparément les bornes du curseur source lors du retrait des enveloppes.
- La sélection du visualiseur continue de passer par son validateur, ses jetons et sa file d'actions. Aucun repli sur le curseur du volet source lorsque la sélection visuelle est refusée.
- La sélection native de l'éditeur fournit ses propres plages au même moteur. Un snapshot indépendant du renderer prouve la structure et les enveloppes callout, sans remplacer les métadonnées de la page visible. Les refus demeurent atomiques ; les préférences de syntaxe de tâches sont respectées.
- Les anciens appels de liste à `toggleBlockWithPattern` ont été retirés. La méthode générique reste utilisée par la commande citation : elle ne peut pas être supprimée comme legacy.
- Le groupe conserve ses identifiants et ajoute `task-list` après `ordered-list`, avec une icône template de cases/listes en 19/38 pixels et des libellés français/anglais. Son action appelle le même adaptateur de conversion.

## Scénarios

| Scénario | Preuve |
| --- | --- |
| Titre gras/citation → liste, conversion entre types, second clic idempotent | RED initial : un test, cinq assertions ; tests natifs après correction. |
| Boutons et menu produisent exactement le même Markdown sur la sélection du visualiseur, curseur source volontairement placé sur un voisin | Vraie WebView, bouton réel, pont natif, sélection conservée, voisin inchangé ; trois types. |
| Source vide, ligne vide, titre gras, CRLF, contenu callout → tâches ; syntaxe désactivée | Source exacte et bornes de sélection ; refus sans modification si syntaxe inactive. |
| Bouton de tâches placé après la liste ordonnée | Groupe/segments, image template, tooltips et dispatch avec le bon sender ; bouton réel. |

Le montage initial d'un test tentait de fixer `selectedSegment` hors d'un événement sur un contrôle momentané : il restait à `-1`. Ce n'était pas un défaut de conversion. Le test de parité utilise les vrais boutons des sous-items ; le test de dispatch du contrôle simule explicitement son segment actif pendant un événement. Le mode momentané de production est conservé. Un premier essai de compilation du snapshot appelait une API privée non déclarée ; elle a été remplacée par une API de snapshot sans publication.

Journaux locaux : `build/ListToolbarUnification/`. Commande native : `python3 /tmp/macdown-campaign03-xctest-vault.py --execute --timeout 1200 -- xcodebuild test -workspace 'MacDown 3000.xcworkspace' -scheme MacDown -derivedDataPath build/AuditCampaign03 -destination 'platform=macOS,arch=arm64' 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`. Les tests sont sérialisés dans le coffre de session/préférences avec restauration vérifiée.

## Régressions corrigées pendant la relecture

La sélection native distingue le curseur des plages de lignes utilisées pour prouver la conversion. Deux défauts de cette adaptation ont été reproduits avant correction : au début du document/à la fin sans saut de ligne, le curseur devenait une sélection de ligne ; dans un callout déballé, il devenait une sélection du contenu. Un test table de trois cas échoue sur les trois positions avant correction (`caret-red.log`), puis les quatre tests de conversion/parité passent (`caret-green.log`). Les bornes exactes de sélection sont désormais translatées indépendamment des plages analysées ; un curseur est admis aux deux extrémités d'une ligne.

La suite complète a d'abord rencontré un crash avec une pile de gestion des fenêtres macOS (cause non déterminée). Deux reprises sans crash ont exécuté 1501 puis 1502 tests, avec 11 assertions en échec dans les deux nouveaux tests de dispatch réel. Un sous-ensemble export/barre reproduit le problème et prouve qu'un `NSSavePanel` modal reste ouvert (`modal-red.log` : 85 tests, 12 assertions dont celle sur `NSApp.modalWindow`). Les anciens tests d'export ouvraient effectivement de vrais panneaux sans les terminer. Leurs fixtures simulent maintenant uniquement la présentation et l'annulation ; elles vérifient qu'aucun rendu/écriture n'est mis en attente et que l'annulation libère le créneau PDF. Les assertions de dispatch réel sont conservées et les contrôles possèdent une fenêtre dans leur fixture. Le même sous-ensemble passe avec 85 tests sans échec (`modal-green.log`).

## Validation finale

- Suite native complète : **1502 tests, 0 échec**, `native-verified.log`, `TEST SUCCEEDED`. Les deux tests de dispatch réel passent dans la suite complète.
- Tests ciblés de conversion/sélection : **4 tests, 0 échec**, `caret-green.log` ; export/dispatch : **85 tests, 0 échec**, `modal-green.log`.
- Contrats JavaScript de mise en forme : **65 contrats réussis**, `inline-contracts.log`. Les fichiers de traduction français/anglais passent `plutil -lint` ; `git diff --check` passe.
- Les sessions XCTest sont exécutées dans le coffre isolé ; chaque session terminée indique `RESTORED and preferences verified`.

- Interface réelle : le nouveau test `testListToolbarConvertsExistingBlockAndSupportsUndo` passe (`ui-verified.log`, 9,571 s) : clic sur les trois segments du groupe `list-group`, conversion exacte sans toucher au voisin, annuler/rétablir. AppKit expose les icônes comme des boutons sans nom ; la première recherche par libellé était une erreur de fixture corrigée, les libellés/ordre étant vérifiés par les tests natifs. Les scénarios « Texte normal » et citation → code passent également (`ui-acceptance.log`).
- **Limite ouverte :** le test d'interface existant `testPreviewMixedSelectionFormattingPreservesSelectionAndNeighbor` échoue sur l'apparition du panneau « Gras » après son glisser de sélection (`ui-acceptance.log`, `ui-verified.log`). Un essai en donnant d'abord le focus au visualiseur échoue aussi (`ui-mixed-focus.log`) ; cette modification sans effet a été retirée. L'échec précède tout appel au moteur extrait. Le JavaScript de sélection n'a pas été modifié par cette livraison. La cause exacte n'est pas établie : ce test n'est pas annoncé comme validé. Les scénarios natifs/WebView de sélection mixte passent dans la suite complète ; cela ne remplace pas ce scénario d'interface en échec.

## Commits

- `1127636` : unification des conversions de listes entre boutons et menu.
- `3b1bce3` : bouton de tâches, icône et traductions.
- `9d75861` : conservation du curseur aux bornes et dans les callouts.
- `611ba70` : isolation des panneaux d'export dans les tests natifs.

L'installation locale utilise une compilation Release universelle arm64/x86_64, une signature ad hoc vérifiée, une copie temporaire et un remplacement avec restauration de l'ancienne app en cas d'échec. Les fichiers du bundle copié sont comparés au build. La preuve locale est `build/ListToolbarUnification/installation.json`. Aucune préférence ni aucun document utilisateur n'est modifié par l'installation. Aucun push n'est effectué pour cette demande.
