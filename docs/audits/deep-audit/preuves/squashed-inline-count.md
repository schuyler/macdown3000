# Transaction inline et comptage — audit du commit dbc6b23

Lecture intégrale du helper avant correction puis de sa version finale, toutes fonctions comprises, et de DOMNode+Text.h/.m avec leurs tests. Les dépendances de rendu sont examinées dans les lots renderer/document. Les commandes natives sont centralisées dans le coffre de préférences ; aucun document utilisateur ne sert de fixture.

| Source finale lue | SHA-256 | Analyse | Validation |
| --- | --- | --- | --- |
| MPPreviewInlineTransaction.h | `5a2879fb31bf6e66f93cc7f17a0d80b8a674b0e06ec63b9ed32f1b6aec5bfe98` | Terminée, seconde passe effectuée | Contrats CLI réussis ; intégration native finale à terminer |
| DOMNode+Text.m | `1595fa2638565bbf1af3d46d22ebc7d47cec468a55c7802d715b8877550d3218` | Terminée, seconde passe effectuée | Régression WebView réussie ; suite finale à terminer |

## Fonctions et branches examinées

- Collecte et parse HTML : styles par caractère UTF-16, XML puis récupération HTML, entités externes interdites, refus des structures non inline et des paragraphes multiples. Aucun DOM vivant n'est reconverti en Markdown.
- Provenance : consommation monotone unique des caractères source, ambiguïtés refusées, échappements explicites, limites de 20 000 caractères, 1 024 états et 100 000 chemins. Une entrée trop grande est refusée avant invocation du renderer.
- Marqueurs et sérialisation : ordre des styles, liens et destinations, fences de code supérieures aux backticks présents, espaces aux frontières, différents styles dans les espaces, bornes retenues. Les variantes proposées sont validées par Hoedown réel, jamais acceptées uniquement par une regex.
- Empreinte globale : caractères, masques, balises structurelles, liens et attributs pertinents ; changement permis seulement sur les caractères sélectionnés. Les voisins et structures doivent conserver leur empreinte.
- Palette historique et masquage opaque : neuf wrappers connus, code et liens hors sélection conservés comme atomes uniques, positions source conservées, restauration depuis la fin et ajustement de la sélection. Une couleur historique intersectée n'est effaçable que si tout son contenu est sélectionné ; sinon refus sans mutation. Aucun HTML neuf produit.
- Transaction simple : validation des paramètres, action et URL, extraction du préfixe/fin de ligne, provenance et styles réels, bascule ou clear, liens scindés avec destinations voisines conservées, sondes de sérialisation, restauration des atomes puis comparaison sémantique du document entier.
- Transaction multiligne : essai paragraphe soft-wrapped avant découpage indépendant, blancs ignorés, maximum 128 lignes non vides, bascule commune puis fusion des modifications non contradictoires ; modification inverse des ranges et bornes finales ajustées.
- Comptage DOM : agrégation texte/espaces avec contrats ICU existants, script/style et bloc code exclus, code inline conservé ; contrôles internes exclus uniquement lorsque leur jeton correspond au nonce du head. Un ID ou attribut rédigé sans le nonce vivant reste du contenu comptable. Panneau visible et caché vérifiés.

## Défauts reproduits et corrigés

1. Les couleurs HTML historiques des voisins disparaissaient lors d'une mise en forme inline, parce que le filtre de tags retirait leurs wrappers et l'empreinte ne représentait pas les couleurs. Reproduction rouge `inline-legacy-red.log`, puis conservation byte pour byte des wrappers voisins et refus des sélections partielles impossibles en Markdown pur. Commit `7456e72` ; tests pour chaque couleur/fond, clear complet, clear partiel et sélection colorée refusée. Aucun HTML ajouté à la source.
2. Le compteur incluait les libellés du panneau même caché : 57 mots au lieu de 3 dans une WebView réelle. Rouge dans `native-stage-2.log`, vert dans `count-green.log` (1 test, 0 échec, préférences restaurées). Commit `9ea74f0` ; test visible/caché et contenu rédigé portant le même ID.

Les logs se trouvent sous `build/SquashedPreviewAudit`. Les suites historiques ne valident pas ces corrections.

## Seconde passe et limites

Réexamen des atomes imbriqués, voisins avant/après sélection, palette entière et partielle, ordre des remplacements, UTF-16, soft newlines, texte répété, styles mixtes, liens, bornes, volumes et nonce. Aucune suppression de legacy non prouvée : la compatibilité des anciens wrappers reste explicite. Les ambiguïtés et structures non représentables sont refusées plutôt que devinées ; la source reste intacte. Le helper et le renderer constituent un pipeline commun avec sondes locales, pas une conversion concurrente du DOM en Markdown. La validation finale dépend encore des suites natives/UI de cette campagne.
