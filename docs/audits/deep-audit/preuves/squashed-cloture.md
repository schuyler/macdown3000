# Clôture — nouvelle lecture complète du code fusionné

Date : 9 octobre 2026. **Prêt à livrer dans le périmètre vérifié : huit sources lues, analysées et validées ; aucun défaut confirmé ni hypothèse déterminante ouverts.** Révision applicative finale `bcb6c5bcb521865e33fb994a85a06dfef4ee0556`. Le commit de preuves suivant n'altère pas ces sources.

## Périmètre et lectures

Le squash `dbc6b23` contient cinq sources applicatives, cinq fichiers de tests et quatre documents/artifact image. Relecture intégrale des cinq sources, puis de trois dépendances directes nécessaires : DOMNode+Text.m et NSTextView+Autocomplete.h/.m. Total **huit sources**. Chaque version finale a été lue du début à la fin après sa dernière modification, sans reprendre une case historique. Journaux de plages, empreintes, fonctions et branches dans les preuves individuelles liées par [le suivi](../suivi.md). Tests/docs hors compteur ; les tests Lifecycle/Rendering/Utility/SelectionCount, le runner Hoedown et le Swift UI sont entièrement lus. La capture historique a été inspectée et son bouton Fermer supprimé depuis est expliqué dans le guide.

Rapprochement initial `git diff --name-status dbc6b23^ dbc6b23` : quatorze chemins. Les sources cachées/ignorées/liens des racines ciblées ont été inventoriées ; vingt fichiers physiques, aucun ignoré ni lien, autres fichiers hors squash uniquement dépendances examinées si nécessaires. Le snapshot final de vérification conserve SHA-256, lignes et statut des huit sources et des tests/docs. Pods/Prism/Hoedown = fournisseurs consultés pour les contrats ; build/.git = artefacts/métadonnées, pas de certification de leurs sources. Les 483 validations de campagne03 sont historiques et ne certifient pas cette nouvelle passe.

## Corrections et origine

| Commit distinct | Cause et résultat |
| --- | --- |
| 7219b60 | Erreurs attachées à leur sélection, désélection réelle ferme le panneau. |
| 98966d7 | Bouton Fermer retiré à la demande utilisateur. |
| 3bb46bd | Conversion limitée aux lignes réellement sélectionnées ; blancs et source intermédiaire inchangés. |
| 9ea74f0 | Compteur exclut seulement les contrôles de l'aperçu propriétaire. |
| 7456e72 | Voisins avec anciennes couleurs conservés byte pour byte. |
| adf7eed | Soulignement Setext réellement associé au bloc consommé. |
| 2625d6e | Complète la conservation des couleurs : appartenances imbriquées non prouvées refusées sans mutation. |
| 1a4d560 | Sérialisation des suites de blancs linéaire ; 12k espaces mesurés 1,660382 → 0,040059 s. |
| 076d78c | Corrige la régression intermédiaire adf7eed : ATX + === ne prouve pas un Setext. |
| 0aad66f | Identité privée des contrôles ; HTML rédigé conservé, globals nommés typés avant appel. |
| 85ef5c4 | Préfixes de blocs suivent le renderer réel et préservent le texte visible/les règles voisines. |
| 321a54a | Bornes de sélection transportées à travers conversions multibloc/Setext/wrappers. |
| e86f108 | Queue commune popup et barre native ; clics rapprochés tous consommés après rendu courant. |
| ee253cc | Boutons source H1–H6/Texte normal utilisent le renderer réel, Setext/ATX/CRLF/voisins/undo. |
| bcb6c5b | Brouillon flushé avant newline et bookkeeping de sauvegarde ; refus sans mutation et reprise possible. |

Les preuves détaillent les phases rouges puis vertes avec des effets consommés : vrai WebView/source/selection/popup, fichier réellement écrit, rendu Hoedown complet, export/ressources inchangés. Les défauts de queue, brouillon/newline, blancs et wrappers existaient dans le code fusionné. La conversion source de titres est un défaut antérieur dans le consommateur. Le garde ATX/Setext corrige une régression introduite par notre correction intermédiaire ; ce n'est pas attribué à la baseline. Le premier correctif couleurs était incomplet et a été complété. Le cas HTML littéral de la nouvelle conversion source a été corrigé avant commit, puis relu/testé.

Deux faux positifs sont explicitement retirés : ancienne fixture de checkbox sans rendererFlags effectifs ; attente incorrecte sur hashes de fermeture suivis d'espaces contredite par Hoedown. Le problème réel de checkbox est reproduit avec flags corrects avant correction de collision. Aucun test n'est ignoré ni assertion affaiblie pour masquer un défaut. Deux snapshots index locaux plaçaient des tests dans une interface : les commits ont été réparés avant livraison, sans changer les sources applicatives ni leur working tree testé, puis Lifecycle entièrement relu. IDs actuels 076d78c/0aad66f.

## Parcours et seconde passe

Sélection souris/clavier → fragments et bornes UTF-16 prouvés → états communs/panneau ; popup/barre source → options/token/source → transaction unique → renderer réel → sélection et voisins restaurés ; brouillon → flush → sauvegarde/fermeture/export/impression ; rendu différé/génération → file commune ou abandon si état divergent ; comptage et identités propriétaires ; limites de sondes/volumes et source hostile/CSP/navigation.

Les variantes légitimes snapshot/publication, rendu body/reload, source/preview et math/code ne sont pas des pipelines concurrents cachés. Les conversions source consomment les mêmes options réelles du renderer du document, sans renderer de secours. Ancien sélecteur interne supprimé seulement après migration des sept callbacks et recherche statique/dynamique/nib. Compatibilité des anciens wrappers conservée ou refusée sans corruption ; aucune suppression de legacy supposé inutilisé.

Les protections token/source/bornes assurent fraîcheur/provenance ; elles ne constituent pas une autorisation contre du JS déjà exécuté dans le même WebView. Les snapshots ne publient pas de nouveau token/HTML/ressources. Le DOM n'est jamais reconverti en Markdown. La seconde passe a réexaminé état périmé, changements de sélection, deux clics, refus/reprise de save, atomes/liens/couleurs, prefix/Setext/CRLF, rendu réel/options et volumes.

## Contrôles

[Commandes, résultats, xcresult, SHA et manifeste final](squashed-verification.json) :

- Suite native complète : **1 471 tests réussis, zéro échec/ignoré**, 126,067 s. `pass2-native-full.log`, xcresult 01-09-31.
- Suite UI complète : **13 tests réussis, zéro échec/ignoré**, 224,141 s. `pass2-ui-full.log`, xcresult 01-11-52. Sélection réelle, édition/sauvegarde, styles successifs et mixtes, undo/redo et voisins, reader/find/progression/préférences et restauration untitled.
- Contrats du helper avec Hoedown réel : **65 PASS**, `pass2-inline-final.log`. Dernier batch source-titres/sauvegarde : **7 tests réussis**, 2,217 s.
- `node --check` : sortie 0.
- Release universel : **BUILD SUCCEEDED**, sortie 0 ; `lipo -archs` = x86_64 arm64. Signature ad hoc vérifiée `codesign --verify --deep --strict`, sortie 0. Script preview-edit.js embarqué identique à la source.
- Coffre de préférences : restauré et vérifié après chacune des deux suites complètes. Exécution sérialisée, données de fixtures uniquement.
- Rapprochement final : 8 sources/9 453 lignes, SHA identiques aux versions finales intégralement relues et au HEAD applicatif ; tests identiques aux versions exécutées. Les deux tests de caractérisation renderer sont ajoutés au commit final de preuves, sans nouvelle modification de production.

Chaque fichier est validé sur la base de son analyse complète, de ses corrections et des gates pertinentes ci-dessus, pas par automatisation des empreintes. Les journaux bruts locaux sont sous build/SquashedPreviewAudit et leurs empreintes conservées dans la preuve JSON. Aucune suite vide/interrompue/ignorée ne sert de validation. Aucun défaut confirmé restant dans le périmètre vérifié, sans garantie d'absence absolue de bugs.

## Limites de portée

Environnement : macOS 26.6.2 arm64, Xcode 26.2. Exécution native/UI arm64 ; Release construit pour arm64/x86_64. Pas d'exécution Intel ou de matrice macOS distante, pas de notarisation/Developer ID/distribution. Pas de certification de toutes les dépendances tierces ni de toute la grammaire Markdown. Les correspondances ambiguës, contenu généré et limites documentées peuvent être refusés sans mutation. Aucun déploiement, installation ou push dans cette passe.
