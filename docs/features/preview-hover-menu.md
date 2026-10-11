# Menu de mise en forme au survol

La barre du visualiseur conserve exactement ses commandes et ses deux groupes existants. Aucun choix supplémentaire n’est ajouté.

Chaque nouvelle sélection et chaque réapparition de la barre ferment le menu précédent. Le survol du sélecteur ouvre une surface distincte, accolé à droite lorsque la largeur le permet. La barre courte conserve sa hauteur. Le menu reste ouvert pendant le passage de la souris du sélecteur à ses options ; quitter ces deux surfaces le ferme après 150 ms. Le clic sur le sélecteur et la navigation clavier restent disponibles.

Le positionnement tient compte des bords : largeur du menu ajustée, placement à gauche si nécessaire, puis au-dessous ou au-dessus sur les fenêtres trop étroites. Les options défilent dans leur propre surface. Les boutons conservent la sélection même lorsque le clic touche leur libellé.

## Validation

Le test de réouverture reproduit deux assertions en échec avant correction : menu encore visible et `aria-expanded=true` après une nouvelle sélection.

Les tests dans une vraie WebView couvrent la réouverture compacte, le survol, la hauteur inchangée, les largeurs 900/600/300 pixels, le contact entre surfaces, la conservation de toutes les options, la sélection conservée, la fermeture au départ du pointeur, Échap et une conversion en titre après clic sur le libellé. Les autres tests du composant vérifient les parcours Markdown et les mises en forme successives.

Cette intervention est une correction ciblée ; elle ne certifie pas un nouvel audit exhaustif du dépôt.

Résultat : 17 tests du composant réussis, puis 3 tests ciblés réussis sur la dernière version du positionnement (barre immobile au survol, menu contigu à 900/600 pixels et sans recouvrement à 300 pixels). Les préférences utilisateur ont été isolées puis restaurées par le lanceur. Les preuves se trouvent dans `docs/audits/deep-audit/preuves/menu-survol-{red,final,positionnement}.log`.

## Lisibilité du sélecteur

Le texte du sélecteur de la barre courte utilise maintenant 16 px au lieu de 13 px. Le bouton conserve sa hauteur de 36 px et sa largeur existante ; sa ligne de texte utilise 22 px, sans retour à la ligne. Un libellé exceptionnellement long est abrégé par une ellipse.

Validation de cet ajustement : les 3 tests existants du positionnement, du plafond de zoom et des commandes du menu réussissent. Journal local : `/tmp/macdown-selector-font-tests.log`.

Le sélecteur affiche maintenant un chevron orienté à droite, aligné au bord droit du bouton. Le libellé et le chevron sont indépendants : un libellé long est abrégé sans masquer la flèche. Les dimensions du bouton et la taille du texte restent inchangées.

Le bord droit du sélecteur est désormais aligné sur le bord droit des boutons d’action visibles. La largeur est adaptée à leur géométrie réelle, au zoom et aux retours à la ligne dans un visualiseur étroit, sans agrandir les boutons. Le test existant de géométrie vérifie cet alignement aux largeurs 900/600/300 pixels.
