# Sélections mixtes dans l’aperçu — 10 octobre 2026

## Diagnostic démontré

Le test UI existant échouait sur `test **mot** selection` : « test mot » restait sélectionné, mais la modale ne s’affichait pas. La comparaison avec la version antérieure à la correction de sélection source reproduisait cet échec.

La cause est la vérification des correspondances DOM/Markdown lorsque `extensionIntraEmphasis` est désactivée. Le document visible rend correctement le gras. Pour vérifier ses fragments, l’application ajoutait des marqueurs privés avant et après chaque littéral dans une copie du Markdown. Le marqueur placé après l’espace de `test ` se retrouvait immédiatement avant `**mot**`. Il supprimait ainsi la séparation nécessaire au délimiteur, et le rendu de vérification ne conservait plus les mêmes fragments. Les trois portions de la phrase étaient rejetées ; seul le lien suivant restait mappé.

Un test avec un vrai WebView confirme cet état : avec l’option désactivée, seule la portion « Preserved link » est reconnue et la sélection mixte n’a pas de payload. Avec l’option activée, le même document fonctionne.

## Correction

Un helper commun place les marqueurs à l’intérieur des espaces de bord du littéral. Il est utilisé pour les vérifications groupées, les occurrences répétées et la restauration d’une sélection. Les espaces entourant les délimiteurs Markdown restent donc à leur position d’origine.

Les nœuds constitués uniquement d’espaces sont vérifiés entre leurs deux voisins prouvés, avec occurrence source unique, position DOM, nombre de nœuds et parent identiques. Le sondage double leur espace physique au lieu d’ajouter des marqueurs : le nœud affiché doit doubler lui aussi. Un espace dans un attribut HTML ne peut donc pas servir de preuve pour un espace rendu depuis une entité. Les budgets de sondage, refus de contenus non prouvés, identités des occurrences et contrôles de la source restent appliqués.

La préférence utilisateur n’est pas changée pour installer la correspondance. Le Markdown du document n’est pas modifié par les marqueurs de vérification.

## Matrices de validation

Les assertions portent sur le rendu et les effets observables, pas seulement sur les chaînes de marqueurs. Les cas paramétrés ne sont pas comptés comme des méthodes XCTest individuelles.

| Matrice | Cas | Contrôles |
| --- | ---: | --- |
| 64 sous-ensembles de styles × 11 types de ligne × 11 conteneurs | 7 744 | Sémantique rendue, conservation des voisins, texte unique, absence de HTML ajouté. |
| 11 lignes de départ × 11 destinations × 11 conteneurs | 1 331 | Conversion de ligne et conservation des six styles. |
| 11 conteneurs de départ × 11 destinations × 11 types de ligne | 1 331 | Remplacement/retrait du conteneur et conservation des styles/contenus. |
| Deux bascules × cinq styles × 64 sous-ensembles × 11 conteneurs | 7 040 | Activation/désactivation, conservation des quatre autres styles et du lien, retour à la composition initiale. |
| Tous les ordres des six styles | 720 | Même composition sémantique, malgré une sérialisation éventuellement différente. |
| 64 sous-ensembles × 11 conteneurs depuis l’éditeur natif | 704 | Titre, styles, composition sémantique et voisins. |
| 64 sous-ensembles × deux modes du parseur × deux thèmes dans une vraie WebView | 256 | Correspondances DOM/source, payload, états actifs des six boutons, préférence conservée, source inchangée. |
| Sept types de ligne × trois contextes de conteneur × LF/CRLF, avec emoji et accents décomposés | 42 | Gras appliqué à la sélection mixte, sélection restaurée, voisins et état déplié conservés. |
| Deux modes du parseur × trois types de ligne × trois sélections mixtes | 18 | Modale, payload, occurrence répétée, mise en forme, sélection et voisin. |
| Deux modes × quatre cas d’espaces physiques ou d’entités | 8 | Espaces simples/doubles prouvés ; attribut HTML ressemblant et tabulation normalisée refusés. |

Les matrices de conversion et d’ordre existaient déjà et sont relancées ; la matrice de 7 040 transitions de bascule est nouvelle. Les 324 cas des quatre dernières matrices étendent les tests avec le véritable DOM ; ils complètent les fixtures du moteur, qui fournissent leurs plages source et n’exercent pas des gestes de souris.

Les contrôles existants couvrent également annulation/rétablissement, refus atomiques des blocs de code, requêtes périmées ou falsifiées, budgets de correspondance, délimiteurs inclus dans la sélection et indépendance des panneaux. La conservation d’une sélection en ligne exclut volontairement ses espaces périphériques, conformément au contrat actuel ; les caractères choisis restent sélectionnés.

**Résultats natifs : 1 563 méthodes réussies sans échec (1 549 dans la suite élargie et 14 tests de menu séparés, sans doublon). **23 tests UI réussis sans échec**, y compris le test initialement en échec dans les deux modes du parseur.** Cette couverture parcourt intégralement les matrices finies décrites dans la table, pas pour tous les documents possibles, toutes les profondeurs d’imbrication ou tous les appareils.

Le test UI existant conserve ses assertions, gestes de sélection, commandes successives gras/italique, sauvegarde, annulation et protections des voisins. Il est étendu aux deux valeurs explicites de l’option, avec le thème sombre. La suite UI complète a été exécutée, avec les contrôles de sélection source, d’exclusivité des panneaux, de clics, de listes, de code, de réglages et de restauration après relance.

Cette revue est ciblée ; elle ne constitue pas une nouvelle certification exhaustive de `MPDocument.m`.

## Preuves et livraison

Correction : `0c7d9e2b`. Extension des transitions : `a62ffb66`. **7 364 nouveaux cas paramétrés** sont ajoutés ; ils font partie des 1 563 méthodes natives et ne sont pas additionnés à ce nombre. Les 14 contrôles de menu et les 1 549 autres contrôles natifs ont des identifiants disjoints, vérifiés dans leurs logs.

- [Régression avant correction](../audits/deep-audit/preuves/selection-mixte-red.log).
- [14 tests du menu et correspondances DOM](../audits/deep-audit/preuves/selection-mixte-menu.log).
- [1 549 autres tests natifs](../audits/deep-audit/preuves/selection-mixte-native.log).
- [23 tests UI complets](../audits/deep-audit/preuves/selection-mixte-ui.log).
- [Axes et nombre de cas ajoutés](../audits/deep-audit/preuves/selection-mixte-matrices.json).

Les essais intermédiaires restent conservés dans `build/AuditCampaign03/MixedMappingEvidence` : ils ont notamment permis de corriger l’attente des tests pour exiger un nouveau jeton de rendu, au lieu d’accepter prématurément l’ancien aperçu. Le lancement UI avec le schéma natif a été refusé avant exécution ; la suite réussie utilise le schéma `MacDownUITests`.

Les sessions utilisent le coffre de préférences réversible, avec restauration vérifiée. Exécution sur Apple Silicon ; configuration de livraison : Release, architectures Apple Silicon et Intel. Les tests ne certifient pas une exécution sur Intel ni les gestes physiques de tous les modèles de trackpad.
