# Plafond de taille de la barre de mise en forme

Le zoom de la page agrandissait également la barre de sélection et son menu. À 300 %, les boutons et les libellés occupaient plusieurs fois leur taille habituelle et provoquaient le retour à la ligne des icônes.

La taille affichée des contrôles est maintenant plafonnée à celle de 100 % : barre de 344 points au maximum et menu de 260 points au maximum, réduits si le visualiseur est trop étroit. À 50 %, leur réduction reste cohérente avec le zoom. Le document conserve son zoom demandé, ses styles et sa source Markdown.

Le facteur réel du visualiseur est transmis au chargement de la passerelle et lors des changements de zoom. Une transformation de la seule interface compense son agrandissement au-delà de 100 %. Le menu utilise le même repère que la barre ; son placement et ses limites tiennent compte du facteur de compensation. La sélection, les options et le comportement au survol sont conservés.

## Validation

Un test dans une vraie WebView reproduit le défaut avant correction. Les nouveaux tests couvrent les transitions 100/150/200/300/50/300/100 %, le chargement initial à 300 % combiné à une police relative de 21 points (facteur effectif 4,5), les dimensions affichées, le placement du menu dans le visualiseur, ses zones cliquables et une mise en gras suivie de la restauration de la sélection à 300 %.

Cette correction ciblée ne constitue pas une nouvelle validation exhaustive de tous les fichiers.

Résultat : **53 tests réussis, aucun échec** (19 tests du menu de mise en forme, 8 tests de zoom du visualiseur et 26 tests de zoom du document). Les préférences et la session utilisateur ont été isolées puis restaurées. Preuves : `docs/audits/deep-audit/preuves/modale-zoom-{red,final}.log`.
