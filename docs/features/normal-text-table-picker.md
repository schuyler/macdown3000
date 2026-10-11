# Texte normal et sélection de dimensions d’un tableau

Le bouton Texte normal est déplacé du groupe de titres vers le groupe de code, immédiatement après Bloc de code. Les identifiants des groupes restent inchangés afin que ce déplacement soit appliqué aux barres personnalisées déjà enregistrées. L’action convertit le passage en paragraphe puis retire les styles avec la transaction de mise en forme existante. Avec un curseur sans sélection dans la source, elle traite la ligne courante ; dans le visualiseur, la sélection restaurée permet de chaîner la suppression des styles après la conversion.

Le bouton Tableau possède son infobulle française. Il ouvre une grille de 8 colonnes et 8 lignes. Le survol colorie le rectangle des dimensions choisies ; cliquer sur une case ferme le panneau et insère un tableau Markdown. Les cases possèdent des libellés d’accessibilité et sont utilisables au clavier par les contrôles natifs. Un clic extérieur ferme le panneau sans insertion.

Le nombre de lignes comprend l’en-tête Markdown : 3 × 4 produit trois colonnes, une ligne d’en-tête et trois lignes de contenu. La ligne séparatrice Markdown ne compte pas comme ligne affichée. L’ancien menu d’insertion conserve son format par défaut de trois colonnes et deux lignes affichées ; les deux parcours utilisent le même générateur et la même mutation annulable. Les dimensions hors de 1–8 sont refusées avant toute mutation.

## Vérifications exécutées

- 64 dimensions et refus des valeurs hors limites dans le générateur Markdown.
- 64 choix et rectangles de survol dans les contrôles natifs ; ouverture et dispatch du vrai bouton.
- 32 combinaisons de gras, italique, souligné, barré et code en ligne, chacune avec sélection entière, mot sélectionné ou curseur seul (96 cas).
- Conversion et suppression des styles sur une sélection du vrai visualiseur, puis restauration de la sélection.
- Suites existantes de la barre d’outils, de l’insertion de tableau et de la modale du visualiseur.

Résultat : **101 tests réussis, aucun échec** : 69 tests de barre d’outils, 11 tests d’insertion de tableau, 20 tests du visualiseur et une matrice de 96 cas de remise en texte normal. La session et les préférences utilisateur ont été isolées puis restaurées. Preuve : `docs/audits/deep-audit/preuves/texte-normal-grille-tableau-final.log`. Cette correction ciblée ne certifie pas un nouvel audit exhaustif du dépôt.
