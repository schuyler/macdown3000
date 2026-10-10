# En-têtes de tableaux dans la langue de l’application

Le générateur commun à la grille de dimensions et à l’insertion standard utilise maintenant la traduction `Column %lu` de la langue active de MacDown. En français, il insère « Colonne 1 », « Colonne 2 », etc. La clé existe dans les 26 langues disponibles, avec l’anglais comme texte de référence. La langue suit les réglages macOS de l’application.

Cette évolution concerne les nouveaux tableaux ; les cellules restent du contenu Markdown éditable, et les tableaux existants ne sont pas réécrits. Les séparateurs centrés `:---:` et le calcul du curseur sont conservés.

## Validation

**97 exécutions de tests réussies, aucun échec** : 83 en anglais (14 tests d’insertion et 69 tests de barre d’outils), puis les 14 tests d’insertion en français. Les journaux confirment les langues actives `en` et `fr`. Les deux exécutions vérifient les 64 dimensions possibles et le centrage de chaque cellule rendue, les positions du curseur, les insertions répétées et les remplacements de sélection. Les traductions des 26 langues sont chargées depuis les ressources compilées ; leur paramètre numérique est vérifié et les résultats anglais, français, allemand et espagnol sont contrôlés explicitement. Les 26 fichiers de traduction passent aussi `plutil -lint`. Les préférences utilisateur ont été isolées puis restaurées.

Preuves : `docs/audits/deep-audit/preuves/tableau-langue-en.log` et `docs/audits/deep-audit/preuves/tableau-langue-fr.log`. Cette correction ciblée ne constitue pas une relecture intégrale des fichiers modifiés.
