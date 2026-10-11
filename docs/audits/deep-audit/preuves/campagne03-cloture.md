# Clôture campagne 03

Audit repris de zéro depuis 895d6c9 ; dernière correction source c0cd3a1. **483/483 fichiers propres entièrement lus, analysés et validés techniquement**, sans défaut confirmé ouvert. Les états individuels, SHA finaux, symboles/branches et consommateurs sont dans les quatre preuves JSON et l’inventaire central. Une empreinte identique n’a jamais servi de preuve de lecture. Validation décidée après analyse manuelle et gates pertinentes.

## Corrections

Sept défauts, sept commits séparés : B03-01 94de1a9, D03-01 4d9966c, B03-02 ef1aa63, D03-02 1122e1d, U03-01 43c2781, U03-02 d3b4712, U03-03 c0cd3a1. Tableau détaillé dans ../commits.md. Reproductions rouges et régressions vertes documentées ; les deux traductions corrigées sont vérifiées dans le vrai bundle et liées à leurs préférences.

## Gates actuelles

| Contrat | Résultat réel | Preuves |
| --- | --- | --- |
| Compilation et consommateurs natifs après dernière correction | 1437 tests, zéro échec ; 4 tests UI, zéro échec ; préférences restaurées et vérifiées après chaque tentative | build/AuditCampaign03/native-final.log, ui-final.log et leurs xcresult |
| Debug et Release | app/CLI/Core/Quick Look arm64 et x86_64 ; Release signature ad-hoc deep strict vérifiée | campagne03-final-build.json ; release-final.log |
| Build/CLI/parser/YAML/version/publication | Toutes les22 commandes de contrats de test.yml réussies dans cette campagne ; commandes inchangées non répétées sans motif. Fixtures release conservent les refus signature/ticket/checksum/provenance et les frontières externes simulées | campagne03-build.json, campagne03-ci-build-gates.json ; staple-resume-final.log, staple-partial-final.log |
| Édition automatique | 6 cas rouges baseline, 12 contrôles AppKit verts : texte, sélection, notifications, veto et undo | autocomplete-final-red.log, autocomplete-final-green.log |
| Défilement après fin | Rouge dans un vrai NSScrollView ; vert répétitions, contenu long/court, disable/re-enable ; appel fautif remonte au commit6ab550b5 de2014 | geometry-final-red.log, geometry-final-green.log |
| HTML/Hoedown/styles/print | Cinq suites de consommateurs WebKit réelles ; huit combinaisons thèmes/numérotation et six PDF imprimés ; scénarios JS frais | *_tests.log, preuves render/build |
| Export PDF et retour à l’éditeur | 12 contrôles, deux impressions réelles, fichier sauvé et rouvert, destination exacte, 1294016octets RGBA identiques, DOM/CSSOM/session restaurés | pdf-consumer.log et dossier consumer manifest/report |
| Bundles et localisations | 5184 entrées réelles, 26 locales, 8 nibs présents, 42 imageset chargeables + icône ; export réel/bindings cliqués/0 overflow en Debug et Release | ui-layout-final.log, ui-layout-release.log, bundle-is.log |
| Pluriels | 126 +360 contrats spécifiques, 3120 contrôles techniques nombres/formats sur26locales | preuve UI |
| Sandbox | Préférences UUID denied/granted/read-only ; vrais CSS utilisateur/bundle et chemins hors-scope/écritures interdits | campagne03-ci-build-gates.json, sandbox-assets.log |
| Quick Look système final | Provider UUID réellement exécuté, host exit0, captures compositor6s/12s examinées : titre, gras, code et tableau rendus. Provider arrêté/désenregistré | campagne03-quicklook-native.json, quicklook-final/report.json |
| Documentation publique | Cinq documents configurés passent markdownlint | markdownlint.log |
| Inventaire physique final | 483 sources,120 exclusions individuelles requalifiées, aucune source inconnue ni symlink non résolu | campagne03-final-reconcile.json |

## Seconde passe

- Publication : relecture après correctifs, reprise après notes/publication ou upload checksum partiel, provenance inconnue refusée ; relance published valide conserve les octets et les notes. La restriction draft initialement proposée aurait cassé cette relance ; elle a été corrigée avant commit et caractérisée.
- Édition : toutes trois suppressions automatiques convergent vers le contrat public insertText ; veto ne produit ni mutation ni notification. Le résultat est consommable par la notification de document et les parcours natifs. Aucun contournement des assertions pour obtenir du vert.
- Géométrie : première sonde détachée n’exerçait pas le viewport ; version attachée a confirmé l’accumulation. Hauteur reconstruite depuis contenu/viewport, cohérente avec setupEditor ; les répétitions et changements long/court sont stables.
- Export : test de largeur non bornée de cellule a été rejeté comme faux positif quand AutoLayout replie réellement le texte ; mesure bornée, containment et absence de chevauchement passent26locales. Le crash initial de la sonde provenait de NSWindow releasedWhenClosed/ARC, corrigé uniquement dans le harness.
- Rendu : fastDOM et rechargement respectent base/head/assets/générations ; API sync/async partage parser ; app et QL partagent preprocessing/callbacks, avec variations sandbox/non-interactives justifiées. PDF transfère ses liens sans modifier les pixels et restaure l’état de l’éditeur.
- Legacy : aucun fichier supprimé sur la seule absence d’une référence textuelle. Compat/outils historiques, thème forest et alias conservés faute de preuve complète d’absence d’usage.

## Code et données cachés

Les deux archives embarquées ont été réellement décodées. data.map insère une image1500×1500 pour une expression spécifique ; treats.map ouvre trois messages Markdown selon le préfixe du nom utilisateur et des dates calendaires. Image, métadonnées, graphe et payloads examinés ; aucun programme exécutable dans ces payloads. Comportements historiques encore atteignables, documentés et conservés. Les deux PNG base64 du style GitHub2 ont aussi leurs structures/CRC vérifiés.

## Portée et limites

Validation locale macOS/Xcode26.2, exécution arm64 et compilation universelle. Pas d’exécution macOS14 distant/Intel, de certification exhaustive des fournisseurs ni d’inspection visuelle de chaque écran dans chaque langue. Réserve linguistique arabe facultative non confirmée : CLDR seul ne définit pas le contrat de libellé des compteurs ; formats/nombres/fallbacks vérifiés, aucune traduction inventée et aucune certification grammaticale générale.

Le build Release vérifié porte une signature **ad-hoc locale** ; Developer ID, notarisation Apple, Gatekeeper de distribution et publication GitHub réelle ne sont pas exercés. Leurs scripts/contrats sont analysés et les frontières simulées sont explicitement distinguées du fournisseur. L’audit ne constitue pas une autorisation de publier.

Les tests ont protégé puis restauré les préférences. Enregistrements LaunchServices des copies d’audit nettoyés, application installée réenregistrée. macOS conserve seulement les métadonnées protégées de quelques containers UUID synthétiques ; les providers sont désenregistrés, les suites de préférences supprimées et les fichiers CSS fixtures nettoyés. Le wrapper Quick Look retourne2 pour cette limite de cleanup, malgré host0 et peinture valide : ce code n’est pas présenté comme zéro échec global du wrapper. Aucun élargissement de permissions effectué.

La réconciliation finale ne trouve aucune source propre inconnue. Les preuves décrivent le périmètre local vérifié, sans promesse d’absence absolue de bugs.
