# Alignement des colonnes depuis le visualiseur

La modale conserve ses deux lignes existantes et affiche une troisième ligne lorsque tous les passages sélectionnés appartiennent au même tableau. Trois boutons à icônes proposent gauche, centré et droite, avec infobulles et libellés accessibles. L’alignement commun aux cellules sélectionnées apparaît en bleu. Une sélection sur plusieurs cellules applique le choix à toutes les colonnes touchées. Les sélections hors tableau ne présentent pas cette ligne.

La mutation utilise uniquement les marqueurs Markdown de la ligne séparatrice (`:---`, `:---:`, `---:`). Les colonnes sont déterminées depuis les feuilles du DOM dont la correspondance source est déjà vérifiée, sans accepter un indice fourni par la page. Avant toute mutation, un rendu de contrôle prouve que seule la propriété d’alignement des colonnes du tableau cible change dans le document complet. Les autres colonnes, tableaux, contenus et styles sont conservés. Les tableaux HTML sans séparateur Markdown sont refusés. La recherche de la bonne ligne est bornée à 64 sondages de candidats.

La sélection est restaurée après le rendu et les clics rapides empruntent la file de transactions existante. Les positions ouvertes ou fermées des menus dépliants sont conservées. Les fins de ligne CRLF et la longueur des séparateurs sont préservées (avec au moins trois tirets lors d’une modification).

## Vérifications exécutées

**37 tests réussis, aucun échec** : 29 tests du visualiseur et 8 tests de zoom, dans une session isolée dont les préférences ont été restaurées. Neuf nouveaux tests couvrent notamment :

- les 27 conversions entre les trois alignements sur chacune des trois colonnes ;
- les en-têtes, sélections partielles, styles imbriqués, code en ligne et pipes échappés ;
- les sélections sur plusieurs colonnes ou lignes et leur restauration ;
- les tableaux sans pipes extérieurs, dans une citation, un encadré ou un menu dépliant, et les fins de ligne CRLF ;
- les changements successifs et les clics rapides pendant un rendu ;
- le masquage de la troisième ligne hors tableau, l’option active en bleu, les valeurs invalides, jetons périmés, indices de colonne falsifiés et tableaux HTML.

Preuve : `docs/audits/deep-audit/preuves/alignement-tableau-final.log`. Cette évolution ciblée ne certifie pas une relecture intégrale des fichiers modifiés.
