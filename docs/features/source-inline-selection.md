# Sélection du texte source après mise en forme — 10 octobre 2026

## Défaut et correction

La transaction en ligne calcule une plage de remplacement contenant la ligne et une plage retenue limitée au passage sélectionné. L’adaptateur source récupérait cette dernière dans `previewSelectionToRestore` après le remplacement. Or la notification native de changement de sélection, lorsque l’éditeur possède le focus, efface cet état pour annuler une restauration appartenant à l’ancien aperçu. Le remplacement pouvait donc laisser toute la ligne sélectionnée.

L’adaptateur source restaure maintenant la plage calculée par la transaction elle-même, traduite dans le document par la position du remplacement. Il ne dépend plus de l’état temporaire de sélection DOM. Le moteur de validation du Markdown et les transformations de ligne ou d’encadré ne sont pas modifiés.

## Régression et validation

Le nouveau test utilise un vrai éditeur et un vrai WebView, avec l’observateur `NSTextViewDidChangeSelectionNotification` utilisé par les fenêtres de document. Il vérifie la sélection immédiatement après la commande puis après le rendu de l’aperçu. Sept actions × quatre contextes donnent 28 combinaisons ; les cinq styles basculables sont réappliqués sur la sélection conservée, sans nouvelle sélection, dans chaque contexte. Un second mot identique reste hors de la sélection.

Sur le code antérieur, ce test échoue avec **48 assertions** : les 28 sélections initiales et les 20 réapplications ont conservé la ligne entière. Les échecs sont conservés, avec empreinte du log complet, comme preuve de régression.

**14 tests natifs réussis**. Les contrôles ciblés comprennent aussi l’annulation/rétablissement, les délimiteurs Markdown inclus dans une sélection, les styles mixtes, les refus dans les blocs de code et le fonctionnement du menu d’aperçu.

Le test UI applique le gras, le retire puis cumule gras et italique depuis les boutons rapides, sans refaire la sélection. Il remplace ensuite le passage sélectionné par saisie pour vérifier que seuls les caractères choisis sont remplacés, pas la phrase ni ses marqueurs.

Il s’agit d’une correction ciblée avec tests, sans nouvelle certification exhaustive du fichier `MPDocument.m` ni nouvelle exécution de l’ensemble du projet.

## Contrôle supplémentaire non résolu

`testPreviewMixedSelectionFormattingPreservesSelectionAndNeighbor` échoue avant la mise en forme : la sélection visuelle existe, mais le test ne retrouve pas la modale après le glissement. L’échec apparaît dans deux exécutions avec la correction et dans une comparaison avec `MPDocument.m` de `d78cd4c2`, sans la correction source. Le test n’a pas été assoupli ou supprimé. La cause de cet échec dans l’aperçu reste à diagnostiquer ; ces trois résultats ne sont pas présentés comme des suites entièrement réussies.

Le code corrigé a été restauré après comparaison, avec vérification de son empreinte. Les preuves conservent [l’échec UI initial](../audits/deep-audit/preuves/selection-source-ui-first.log), [sa répétition](../audits/deep-audit/preuves/selection-source-ui-recheck.log) et [la comparaison antérieure](../audits/deep-audit/preuves/selection-source-ui-baseline.log).

## Livraison ciblée

Les **2 tests UI ciblés réussissent ensemble** sur le code corrigé : commandes successives dans la sélection source, puis exclusivité des sélections et boutons rapides entre source et aperçu. [Log final UI](../audits/deep-audit/preuves/selection-source-ui-targeted.log), [14 tests natifs](../audits/deep-audit/preuves/selection-source-native.log) et [test de régression avant correction](../audits/deep-audit/preuves/selection-source-red.log). Les sessions et préférences utilisateur sont isolées puis restaurées avec vérification.

Commit de correction : `ea9f506d`. Compilation Release pour Intel et Apple Silicon ; tests exécutés sur Apple Silicon.

## Résolution ultérieure du contrôle d’aperçu

L’échec supplémentaire décrit plus haut est désormais corrigé par `0c7d9e2b`. Le sondage des littéraux altérait les espaces nécessaires aux délimiteurs de gras lorsque l’emphase à l’intérieur des mots était désactivée. Le test UI original passe maintenant dans les deux modes, sans suppression de ses assertions, parmi les 23 tests UI réussis. Voir [le diagnostic et les matrices élargies](preview-mixed-mapping.md). Les échecs historiques restent conservés comme preuve de reproduction.
