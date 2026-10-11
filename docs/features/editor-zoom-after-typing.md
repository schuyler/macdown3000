# Zoom conservé après la frappe

Après une ouverture à un zoom mémorisé de 150 %, un passage à 100 % ajustait la police visible mais conservait l’ancienne taille dans le moteur de coloration. Sa prochaine remise à zéro des attributs réappliquait alors la police de 21 points, au lieu de la base à 14 points. Le niveau de zoom enregistré n’était pas responsable de ce retour visuel.

`applyCurrentZoom` emprunte maintenant le parcours existant de changement de police de base : désactivation de la coloration, application de la police et des tabulations au zoom courant, mise à jour de sa référence de texte normal, reconstruction des polices du thème, mise à jour du visualiseur et réactivation. Les polices du thème et les attributs de frappe utilisent ainsi le zoom courant. La police de base enregistrée reste inchangée.

## Validation

Le test de régression échoue avant correction avec une taille de 21 points après le retour à 100 %, puis passe après correction. Un second test parcourt tous les niveaux de zoom et un retour à 100 %, avec la coloration par défaut et GitHub Dark Default (20 scénarios). Il vérifie les polices du texte normal, du gras et de frappe après coloration, ainsi que le maintien du niveau choisi et de la police de base enregistrée.

**85 tests réussis, aucun échec** : 28 tests de zoom du document, 8 tests des niveaux de zoom, 47 tests du moteur de coloration et 2 tests de taille de la modale du visualiseur. Les préférences utilisateur ont été isolées et restaurées.

Preuves : `docs/audits/deep-audit/preuves/zoom-frappe-red.log` et `docs/audits/deep-audit/preuves/zoom-frappe-final.log`. Cette correction ciblée ne constitue pas une nouvelle relecture intégrale des fichiers.
