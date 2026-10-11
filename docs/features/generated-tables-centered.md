# Tableaux générés centrés par défaut

Le générateur partagé par la grille de dimensions et l’action d’insertion standard utilise désormais `:---:` pour chaque colonne. Tous les en-têtes et cellules de contenu sont donc centrés dès la création, en Markdown uniquement. Le réglage concerne les nouvelles insertions ; les tableaux déjà présents conservent leur alignement. L’alignement peut ensuite être modifié depuis la troisième ligne de la modale du visualiseur.

## Validation

**82 tests réussis, aucun échec** : 12 tests d’insertion, 69 tests de barre d’outils et le test des 27 conversions d’alignement dans le vrai visualiseur. Les tests d’insertion vérifient les 64 dimensions de 1 × 1 à 8 × 8, puis le rendu de chaque cellule, en-tête compris, avec `text-align: center`. Les séparations de blocs, le curseur et les insertions répétées restent vérifiés. Préférences utilisateur isolées puis restaurées.

Preuve : `docs/audits/deep-audit/preuves/tableaux-centres-final.log`. Cette modification ciblée ne certifie pas une nouvelle lecture intégrale des fichiers.
