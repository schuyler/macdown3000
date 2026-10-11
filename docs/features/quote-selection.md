# Sélection et mise en forme des citations dans l’aperçu

Correction du signalement du 10 octobre 2026, à partir de `3050a58`.

## Causes et corrections

1. Le moteur Markdown rassemble plusieurs lignes de citation dans un même nœud texte, sans les préfixes `>` des lignes suivantes. La recherche d’une sous-chaîne source continue ne pouvait donc pas prouver ce nœud. Le parcours commun découpe désormais les retours de ligne des citations avant les preuves du DOM vivant, des occurrences répétées et des restaurations de sélection. Chaque portion conserve une preuve par le moteur Markdown ; aucun intervalle fourni par la page n’est accepté directement.
2. Les transactions en ligne ne retiraient qu’un préfixe de citation avant leur oracle de rendu. Les préfixes imbriqués, puis les titres/listes qu’ils contiennent, sont conservés séparément du texte modifiable. L’empreinte sémantique du document complet reste obligatoire.
3. Une ligne vide `>` entre deux paragraphes n’a aucun caractère à mettre en forme. Elle est ignorée comme portion de texte seulement si son rendu ne contient aucun token textuel. L’empreinte finale doit toujours conserver la structure et le contenu voisins.

Les retours souples entre deux portions prouvées du même paragraphe sont admis dans la sélection. Les caractères visibles sans preuve et les séparateurs de blocs de code restent refusés. Le plan de découpage est limité à 4 000 coupures avant toute mutation du DOM. Le mapping conserve sa limite de 2 000 portions modifiables.

## Couverture ajoutée

- 14 documents réels : citation simple, texte normal après du gras, deux et trois niveaux de citation, CRLF imbriqué, titre et liste dans une citation, espaces après `>`, saut dur, ligne vide `>`, occurrences répétées dedans/dehors, première ligne en italique, Unicode. Sélection d’un mot, gras, puis sélection traversant les lignes et italique ; restauration de sélection et conservation des voisins.
- 64 combinaisons dans un vrai WebView : les 32 sous-ensembles de gras/italique/souligné/barré/code en ligne, en LF et CRLF. Vérification des styles effectivement rendus, des états communs du panneau, de la sélection persistante, des préfixes et des voisins.
- 130 cas de préfixes dans le chemin source : 13 préfixes × 2 fins de ligne × 5 actions, avec ajout et retrait. Citation, imbrication, indentation, titres, listes à puces, numérotées et de tâches.
- 4 contrôles de protection : texte décodé ayant un homonyme dans un attribut HTML ou une URL ; citation de 2 100 lignes dépassant le budget sans mutation partielle du DOM ; paragraphe ordinaire de même taille conservant son mapping continu. Jeton falsifié rejeté et source intacte.
- Un test XCTest UI avec deux documents : vrai double-clic sur le mot normal de la seconde ligne, ouverture du panneau, gras puis italique sans nouvelle sélection, deux annulations.

Ces 212 scénarios natifs et 2 scénarios UI complètent les tests existants ; ils ne constituent pas une énumération de tous les documents Markdown possibles.

## Exécution

Code final : `7d5f2f5` (trois corrections, chacune dans son propre commit : `0396e11`, `ca553b8`, `7d5f2f5`).

- Suite native complète : **1 553 tests exécutés, 1 552 réussis, 1 échec** dans `MPZoomTests/testZoomChangeInDocAPropagatesToDocB` (deux notifications KVO reçues, une attendue). Les quatre nouveaux tests, leurs 212 scénarios, et les matrices de conversion existantes passent. [Résultats natifs](../audits/deep-audit/preuves/citations-native.log).
- Contrôle du zoom : **26/26 tests réussis** isolément, puis **520/520** sur 20 répétitions de cette suite. Ce résultat ne supprime pas l’échec initial ; sa cause reste à qualifier. Le test n’a pas été assoupli ou masqué et le code de zoom n’a pas été modifié. [Contrôle isolé](../audits/deep-audit/preuves/citations-zoom-recheck.log), [20 répétitions](../audits/deep-audit/preuves/citations-zoom-repeat.log).
- Suite UI complète : **18/18 tests réussis**, notamment le nouveau test avec deux citations et deux mises en forme successives. [Résultats UI](../audits/deep-audit/preuves/citations-ui.log).
- Le scénario de régression échoue sur les fichiers de production du parent `3050a58`, avec une vraie fenêtre/WebView ; il passe après correction. [Régression avant correction](../audits/deep-audit/preuves/citations-red.log).

Compilation de tests pour arm64 et x86_64 ; exécution sur arm64. La validation couvre le mode Debug. Les journaux intégraux et les bundles `.xcresult` sont conservés localement dans `build/AuditCampaign03` et les chemins indiqués dans les extraits. Chaque extrait porte le SHA-256 du journal intégral. Aucune nouvelle relecture exhaustive du projet n’est revendiquée.

Le test de régression, avec WebView attaché à une fenêtre et URL de document réelle, échoue sur le code antérieur. Les préférences et les états utilisateur sont isolés et leur restauration est vérifiée après chaque exécution.
