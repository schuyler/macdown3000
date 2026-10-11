# Clôture de la nouvelle lecture complète — passe 3

Le 9 octobre2026, nouvelle lecture indépendante après17dbbb9, sans hériter de validation précédente. Version finale applicative : `8c694d7ba9b34c414b1c32ce582fbd177e3650a0`. Les modifications suivantes de cette clôture portent seulement sur les preuves.

## Périmètre effectivement examiné

**8 fichiers source / 9 501 lignes : tous intégralement lus, analysés et validés.** Les cinq sources du squash dbc6b23 et les trois dépendances directes compteur/Autocomplete sont toutes incluses. Les quatre documents/artefacts d’origine, les cinq tests d’origine et trois autres tests nécessaires sont examinés séparément :12 auxiliaires, hors compteur source. Les autres dépendances et configurations sont tracées dans les notes individuelles. Il ne s’agit pas d’un nouvel audit de tous les483 fichiers du dépôt.

Rapprochement frais Git/système de fichiers :14 chemins du squash initial, aucune source initiale omise ; toutes les modifications applicatives depuis17dbbb9 appartiennent aux huit sources. Racines physiques Document9, Extension21, Resources/Extensions11 : aucun fichier caché, ignoré/non suivi ou lien symbolique trouvé. Leurs autres sources restent hors de la cible fusionnée sauf dépendances nécessaires examinées dans les notes. Fournisseurs Pods, sorties build et fichiers générés exclus du compteur, leurs contrats/source de génération examinés lorsque nécessaires. Aucun fichier source ajouté/supprimé dans cette passe.

Chaque version finale modifiée a été intégralement relue, avec plages contiguës et reprise explicite de toute sortie tronquée. Notes et registres : [Document et consommateurs](squashed-pass3-document.md), [transaction inline et contrats](squashed-pass3-inline.md), [renderer et conversion source](squashed-pass3-renderer.md), [JS/UI et compteur](squashed-pass3-js.md). Les SHA de ces versions correspondent aux sources testées et commitées.

## Quatre défauts confirmés, quatre commits

| Défaut et effet observable | Commit | Preuve rouge/verte et cause |
| --- | --- | --- |
| Texte normal d’un titre Setext laisse un délimiteur voisin recréer un titre ou perturbe le probe source | `4929c78` | [Setext](squashed-pass3-setext-fix.md) ; garder les délimiteurs intacts et protéger le premier voisin effectivement restant ; consommateurs source et aperçu corrigés ensemble |
| Gras/italique/lien au milieu d’un mot augmentent le nombre de mots affiché | `55629e7` | [Compteur](squashed-pass3-count-fix.md) ; segmenter le texte inline continu, conserver frontières de blocs et contrats CODE/PRE |
| Export PDF refusé par brouillon périmé laisse le slot occupé et ne termine pas la demande d’impression | `cc358cb` | [PDF/print](squashed-pass3-print-fix.md) ; acceptation explicite puis unique completion/cleanup existant sur refus |
| Export HTML Intel peut omettre la CSS du thème actif selon l’adresse de la chaîne | `8c694d7` | [Styles HTML](squashed-pass3-html-style-fix.md) ; comparaison explicite à nil, consommation par vrai checkbox/XIB/renderer/fichier |

Origine vérifiée : la régression de contexte Setext vient des corrections antérieures ee253cc/source et adf7eed/aperçu. Compteur, refus print et cast HTML préexistaient ; leurs provenances sont consignées dans les preuves. La simple insertion des spans de mapping n’est pas la cause du compteur ; cette hypothèse initiale a été réfutée avant correction. Aucun code legacy supprimé sans preuve, aucune grammaire parallèle ajoutée, aucun doublon de pipeline incohérent laissé dans les parcours étudiés.

## Contrôles exécutés sur le résultat final

- **1 476 XCTest / zéro échec / zéro ignoré**, suite complète forcée Intel sous Rosetta,139,038s. Architecture effective attestée par binaire x86_64 seul et diagnostic du test.
- Test export HTML final relancé sur Intel puis ARM :1 test sans échec à chaque fois, après ajout d’une assertion explicite de completion. La suite complète précédente utilise le même code applicatif final ; seul ce renforcement du test est postérieur, versions SHA distinctes enregistrées. Les résultats ne sont pas gonflés par ces doubles exécutions.
- **13 XCUITest / zéro échec / zéro ignoré**,223,415s, sur ARM, après le dernier correctif. Édition aperçu, styles mixtes successifs/sélection/voisin, undo, titres/texte normal, Find, lecteur/progress, préférences et restauration de documents exercés.
- **65 contrats CLI réussis** avec vrai Hoedown ; syntaxe JS correcte. Helper/JS inchangés depuis leur exécution fraîche de cette passe.
- **Release universel arm64/x86_64 compilé**, signature locale `codesign --verify --deep --strict` valide ; preview-edit.js embarqué identique à la version relue.
- Chaque session native/UI a restauré et vérifié les préférences. Toutes exécutions partageant ressources/app/prefs sont sérialisées ; coffre isolé et fichiers de test propres.

Les phases rouges, vertes, commandes, logs, xcresult, empreintes et versions de tests sont conservées dans [le manifeste des preuves](squashed-pass3-verification.json). Les premières suites ARM1475/UI13 et le premier Release de cette passe restent historiques et ne remplacent pas les gates finales. Le premier test fat à destination x86 ayant passé n’est pas décrit comme un RED ou une preuve d’architecture effective ; l’échec réel Intel forcé est distinct.

## Seconde passe et limites

Seconde passe complète des contrats source unique/renderer, payloads/UTF16/provenance, styles communs/mixed, retenue et replay de sélection, mouse-up/IME/brouillons, save/close/export, callbacks/générations/queue, identité DOM, options parsing, comptage, voisins non sélectionnés et volumes bornés. Aucun défaut confirmé non corrigé ni hypothèse déterminante ouverte ne subsiste dans ces parcours. Aucun code caché/obfusqué découvert dans les sources lues ; les chaînes JS embarquées ont été examinées comme code.

Piste didFailLoad/print investiguée sans chaîne applicative atteignable établie : rendu propre via loadHTMLString, erreurs subresources et provisoires distinctes ; aucun delegate artificiellement invoqué pour inventer un bug. La confiance envers les scripts locaux déjà exécutés dans le même WebView reste une frontière historique explicite, sans nouvelle promesse d’isolation adversariale.

Validation locale sur macOS26.6.2/25G83, Xcode26.2/17C52, matériel ARM et exécution Intel sous Rosetta ; pas de matériel Intel physique ni matrice d’autres macOS testés. Release conserve des warnings d’API WebView/DOM dépréciées, prototypes anciens, variable inutilisée et phases build/signature ; ils ne sont pas assimilés à une suite sans avertissements. Le cast fonctionnel à risque identifié est corrigé. La signature est locale, sans validation DeveloperID/notarisation. Aucune installation ni publication effectuée.

**Verdict : prêt dans le périmètre local vérifié**, avec les limites ci-dessus ; pas de garantie d’absence absolue de bugs ni de certification du dépôt entier.
