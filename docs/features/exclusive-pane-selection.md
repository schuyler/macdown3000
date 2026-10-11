# Sélection exclusive entre source et visualiseur — 9 octobre 2026

## Comportement corrigé

Une sélection dans le visualiseur conservait la surbrillance de la source. Une sélection dans la source pouvait conserver la sélection DOM et le panneau du visualiseur, ainsi que sa sélection mémorisée pour les commandes rapides. Les deux passages semblaient donc actifs simultanément.

Le délégué de sélection WebView réduit désormais la sélection source à son curseur, sans déplacer ce curseur. Lorsque la source reçoit une sélection avec le focus, elle efface la sélection DOM, la sélection mémorisée, le panneau et ses erreurs, puis annule la restauration et les commandes du visualiseur encore en attente de rendu. Les boutons rapides conservent leur routage existant selon le volet actif.

Les changements de plage source provoqués par une mise en forme du visualiseur ne doivent pas voler sa sélection. Ils sont réduits à un curseur sans annuler sa continuation. Ils ne transfèrent pas non plus l'indicateur de progression au volet source et ne déclenchent pas de synchronisation vers l'ancien curseur. L'effacement de sélection JavaScript ne supprime pas le brouillon d'édition.

## Vérifications

- Régression reproduite avant correction dans une vraie WebView : quatre assertions en échec (`selection-exclusive-red.log`).
- Après correction : trois tests ciblés réussis (`selection-exclusive-targeted.log`), dont la sélection exclusive et la matrice de 736 conversions de blocs.
- Le nouveau test natif applique les commandes rapides dans les deux volets, vérifie le Markdown exact, la conservation de sélection après rendu et l'annulation d'une commande en attente lors du changement de volet.
- 65 contrats de mise en forme JavaScript réussis (`selection-inline-contracts.log`), syntaxe JavaScript vérifiée avec `node --check`.
- Suite native complète : **1 507 tests, aucun échec**, `TEST SUCCEEDED` (`selection-exclusive-native-full.log`).
- Le nouveau test d'interface `testQuickFormattingFollowsExclusiveSelectionAcrossPanes` compile, mais n'a pas pu démarrer : le runner expire en activant l'automatisation macOS (`Timed out while enabling automation mode`, `selection-exclusive-ui.log`). Le scénario de clics réels n'est donc pas déclaré validé. L'ancien échec documenté du test de sélection mixte par glisser n'a pas été réévalué.

Les journaux sont dans `build/ListToolbarUnification/`. Les sessions XCTest utilisent le coffre isolé, avec restauration vérifiée des préférences et fichiers utilisateur après chaque session terminée.

La livraison locale utilise une compilation Release universelle arm64/x86_64 et une signature ad hoc vérifiée. Le remplacement dans `/Applications` vérifie le contenu du bundle et restaure l'ancienne application si l'installation échoue ; sa preuve est enregistrée dans `build/ListToolbarUnification/installation.json`. Aucun push n'est effectué pour cette demande.
