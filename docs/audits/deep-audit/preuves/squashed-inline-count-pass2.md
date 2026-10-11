# Nouvelle lecture intégrale — transactions inline et compteur

9 octobre 2026. Lecture refaite du début à la fin après les corrections de cette passe, sans reconduire la certification précédente. Helper : 559 lignes, plages 1–200, 201–240, 241–410, 411–559, toutes les fonctions et branches. DOMNode+Text.m : 1–164 ; .h et MPSelectionCountTests.m relus entièrement. Le contrat CLI .m/.py est relu entièrement.

| Source réellement relue | SHA-256 | État |
| --- | --- | --- |
| MPPreviewInlineTransaction.h | `618db0c670ad51b85755258eb1cc27dfdc49f8facd64f060be05cca31434c039` | Lu, analysé ; suites finales en attente |
| DOMNode+Text.m | `1595fa2638565bbf1af3d46d22ebc7d47cec468a55c7802d715b8877550d3218` | Lu, analysé ; suites finales en attente |

## Fonctions et invariants réexaminés

Collect/ParseHTML/InlineOracle : UTF-16 et strict inline, entités externes interdites, paragraphes multiples refusés. Provenance : chemin monotone unique, syntaxe seulement, limites 20k/1024/100k, ambiguïtés refusées. Marker/Serialize : styles imbriqués, ordre et spelling validés réellement, surrogates identiques, whitespace aux bords, liens et fence code. FingerprintNode/Fingerprint : texte, styles, liens/attributs et structure de tout le document ; seul le changement sélectionné est autorisé. LegacyColorOpenings/WithoutLegacyTags/MaskOpaque : palette ancienne explicite, pas de HTML nouveau ; sources opaque hors sélection conservées byte pour byte, clear complet seulement, refus lorsqu’une couleur imbriquée ou dans un lien réécrit n’a pas d’appartenance prouvée. SingleChange : validation action/URL/bornes, extraction ligne, mapping, changements styles/link, variantes oracle, restauration inverse des atomes, empreinte finale et bornes. Change : paragraphe soft-wrapped avant lignes, blancs, 128 lignes, mode commun add/remove, union des changements et contrôle global.

Compteur : Make/Zero/Add et String traitent nil/vide, ICU words et UTF-16/espaces selon contrat existant ; Children/Node suivent seulement les nœuds comptables et excluent script/style/head, code bloc. Un contrôle UI n’est exclu que si son token correspond au meta du head ; contenu rédigé avec mêmes IDs ou token différent reste comptable. Wrapper public et catégorie utilisent la même accumulation. Parcours réel du panneau visible/caché et contenu rédigé exercé via WebView, pas via mock.

## Défauts confirmés de cette nouvelle passe

**P2-INLINE-01** : la première conservation des anciens wrappers ne couvrait pas les spans imbriqués ni ceux dans le label d’un lien sélectionné. Deux appels acceptaient le changement tout en perdant une couleur hors sélection. Rouge `pass2-legacy-nested-red.log` : 2 échecs concrets. Correction `2625d6e` : vérifier chaque ouverture ancienne contre un atome effectivement protégé ; refuser sans mutation si l’appartenance n’est pas prouvée. Un lien entier hors sélection garde aussi ses couleurs imbriquées, test positif exact. Le défaut de conservation est présent dans le code fusionné ; le correctif initial 7456e72 ne le couvrait pas entièrement.

**P2-INLINE-02** : Serialize recalculait les deux bords de chaque suite de blancs pour chaque caractère. Benchmark du helper réel avec Hoedown, actions bold sur a+espaces+b : 1000/4000/12000 espaces, 0.046632/0.194247/1.660382 s avant. Correction `1a4d560` : calculer masque et borne une seule fois par suite ; mêmes règles de styles/code aux bords. Après : 0.007592/0.014059/0.040059 s. Logs `pass2-whitespace-before.log` et `pass2-whitespace-after.log`, programme `whitespace-benchmark.m` dans build/SquashedPreviewAudit. Mesures locales, aucun seuil temporel artificiel ni assertion timing fragile. Test exact de 12k espaces vérifie texte entier et marqueurs attendus. Défaut présent dans le commit fusionné.

## Contrôles actuels et seconde passe

`python3 MacDownTests/BuildTools/inline_transactions_tests.py` : sortie 0, 65 lignes PASS, log `pass2-inline-final.log`. Chaque cas garde Hoedown réel ; refus ne devient pas remplacement silencieux. Le benchmark n’abaisse pas les limites. Réexamen de frontières d’atomes/liens, ordre des deltas, espace entre styles différents, UTF-16, source répétée, marqueurs de blocs, URL et refus. Aucun autre défaut confirmé dans ces fichiers. Suites natives/UI et build de clôture restent requis ; ces lectures ne certifient pas encore le fichier Document ni une grammaire exhaustive de Markdown.


## Validation de livraison après les lectures

Les attentes de contrôles mentionnées plus haut décrivent l'état au moment des lectures. Clôture du parent : **1 471 XCTest, 13 XCUITest, 65 contrats CLI réussis**, syntaxe JS correcte et Release universel signé localement vérifié. Aucun changement de source depuis la version finale intégralement relue. Validation dans le périmètre vérifié, commandes/empreintes/limites dans [la clôture](squashed-cloture.md) et [verification.json](squashed-verification.json).
