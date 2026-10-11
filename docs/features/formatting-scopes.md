# Mise en forme à trois portées — 9 octobre 2026

## Contrat

Les styles de caractères sont cumulables : gras, italique, souligné Markdown, barré, lien et code en ligne. Une sélection mixte reçoit le style sur tous ses caractères ; un style commun à toute la sélection peut être retiré. Les marqueurs d'emphase autour d'un code en ligne restent à l'extérieur des backticks.

Un menu unique réunit deux groupes séparés : le type des lignes (texte normal, H1 à H6, listes, citation, code, équation) et l'enveloppe (aucun encadré, cinq callouts, menu dépliant ou titre dépliant H1 à H4). Les choix sont exclusifs dans chaque groupe et indépendants entre groupes. Changer le type d'une ligne ne retire plus son encadré.

Un nouvel encadré possède son titre localisé, distinct du contenu sélectionné. Un H1 du contenu reste donc H1 même si le nouveau dépliant demande un titre H3. Remplacer une enveloppe existante conserve son titre personnalisé et son contenu ; un choix explicite de niveau de titre dépliant modifie son titre. « Aucun encadré » retire les délimiteurs et conserve les frontières des blocs voisins. L'enveloppe la plus intérieure est ciblée dans un document déjà imbriqué.

Les boutons rapides de titres, texte normal, listes et citation utilisent le même moteur que les sélecteurs. Les styles de la source et du visualiseur utilisent la même transaction inline, validée par le véritable moteur de rendu. Les modifications refusées ne basculent pas sur un autre algorithme. Les catégories ne produisent aucune balise HTML dans le Markdown.

Un bloc de code contient du texte littéral : ses styles inline sont indisponibles, mais ses sélecteurs permettent le retour en prose. Les contextes de code non représentables par une correspondance source/rendu sûre sont refusés sans mutation. L'équation est validée séparément ; son rendu généré n'est pas une sélection éditable de caractères Markdown.

## Défauts traités et vérifications

| Point | Cause corrigée | Vérification |
| --- | --- | --- |
| Portées indépendantes | Les conversions de lignes retiraient les délimiteurs des callouts | Produit des types, conteneurs et styles ; transitions dans les deux directions |
| Sélection mixte dans la source | Les boutons inline utilisaient une insertion de marqueurs distincte du visualiseur | Parité native, styles préexistants, voisins, undo/redo |
| État bleu des menus | Le placeholder vide était assimilé à une option commune | Vrai WebView : H1, callout, sélections mixtes et hors encadré |
| Métadonnées Setext | Le moteur inline tentait de mettre en forme l'underline d'un titre | Six styles traversant un titre Setext et le paragraphe suivant ; règle horizontale refusée |
| Code littéral dans la source | Une ligne de code était analysée comme un titre isolé | Preuve du contexte complet ; conservation du `#` et du contenu non sélectionné |
| Dépliant sans titre | Un changement vers un titre dépliant ne créait pas le titre demandé | Titre localisé H1, corps conservé |
| Paragraphe long | Une limite de 128 lignes pouvait tronquer le paragraphe | Paragraphe de 300 lignes ; recherche des frontières avec preuves logarithmiques |
| Retrait d'un encadré | La suppression des délimiteurs pouvait fusionner trois paragraphes | Voisins adjacents, LF, CRLF et fin de fichier |
| Lien de la barre rapide | L'action native utilisait la sélection source même lorsque le visualiseur était actif | Dialogue natif, annulation, URL dangereuse, href, sélection et scopes conservés |

## Matrice finie

| Famille | Cas |
| --- | ---: |
| 64 sous-ensembles des six styles × 11 types ordinaires × 11 états d'enveloppe | 7 744 |
| Toutes les transitions entre types ordinaires, avec chaque enveloppe et les six styles | 1 331 |
| Toutes les transitions entre enveloppes, avec chaque type ordinaire et les six styles | 1 331 |
| Tous les ordres d'application des six styles | 720 |
| Sous-ensembles inline via les commandes natives, H1 et chaque enveloppe | 704 |
| Chaque code clôturé vers chaque type ordinaire et chaque enveloppe | 121 |
| Chaque type ordinaire vers code puis texte normal, avec chaque enveloppe | 121 |
| Génération d'équation dans chaque enveloppe depuis chaque type ordinaire | 121 |

Ces cas vérifient le source et le DOM produit par MPRenderer, les marqueurs/style réellement rendus, l'unicité du texte sélectionné et les voisins. S'y ajoutent les refus inline dans le code, les sélections partielles/multiples, les enveloppes imbriquées, les identités périmées ou forgées et l'annulation/rétablissement. Les tests de menus utilisent un véritable WebView et ses événements de sélection, ainsi que les actions natives de la barre rapide.

Il s'agit d'une couverture exhaustive de ces produits finis, pas d'une preuve de toutes les entrées Markdown arbitraires ni de tous les gestes physiques possibles. Le visualiseur conserve la sélection lors des commandes successives et l'état ouvert/fermé des dépliants pendant les rafraîchissements ordinaires.

## Reproductibilité et limites

Les tests natifs sont dans `MacDownTests/MPFormattingScopeMatrixTests.m` et `MacDownTests/MPFormattingScopeMenuTests.m`. La matrice utilise le véritable parseur et les transactions du document, avec un adaptateur de correspondance source/rendu et un ordonnancement synchrone pour les fixtures sans visualiseur. Les tests de menu gardent le renderer asynchrone et un véritable WebView. Le nettoyage attend explicitement les tâches main queue après chaque dataset ; le thème de ces tests est fixé à un thème local.

Des exécutions complètes ont d'abord révélé un retard du premier chargement WebView après la matrice. L'isolation du seul renderer n'a pas suffi. Le drainage explicite du nettoyage AppKit a permis aux 29 tests de matrice et de menu de passer ensemble, sans allonger le délai de chargement ni supprimer d'assertion. La validation complète finale est consignée ci-dessous.

Deux tests lancés sur le code antérieur ont produit 12 échecs : ils démontrent les régressions corrigées autour des paragraphes à retours souples et du retrait d'encadré. Les suites d'automatisation physique `MacDownUITests` ne sont pas revendiquées comme exécutées. Les tests WebView utilisent des événements DOM et les commandes natives, notamment le dialogue de lien.

## Résultats et livraison

- Suite native complète : **1 538 tests, 0 échec**, incluant les 24 méthodes de matrice et les cinq méthodes de menu/WebView. Journal : `build/ListToolbarUnification/formatting-scopes-native-verified.log`.
- Moteur inline autonome : **72 cas, 0 échec**. Journal : `build/ListToolbarUnification/formatting-scopes-inline.log`.
- Contrôles : syntaxe JavaScript, projet Xcode, traductions anglaises/françaises et `git diff --check` réussis.
- Compilation Release universelle **arm64 + x86_64** réussie. Journal : `build/ListToolbarUnification/formatting-scopes-release.log`.
- Application cible : `/Applications/MacDown 3000.app`. La procédure d'installation vérifie la signature ad hoc et compare chaque entrée du bundle compilé à la copie installée ; sa preuve horodatable est enregistrée dans `build/ListToolbarUnification/installation.json` avec le commit, les architectures et le SHA-256 du binaire.
- Changements enregistrés séparément : correction Setext, refonte des portées, correction du lien natif, puis ce rapport. Aucun push effectué pour cette demande.

La suite complète termine par `TEST SUCCEEDED` et la restauration vérifiée des préférences. Les avertissements de dépréciation WebKit/AppKit existants restent présents ; cette refonte ne migre pas le moteur WebView historique.

## Révision du menu déroulant et des icônes

Les deux sélecteurs sont réunis dans un menu déroulant à lignes avec leurs libellés et un séparateur entre les deux portées. Le bouton d'ouverture affiche le type de ligne commun à la sélection. Seules les actions gras, italique, souligné, barré, code en ligne, effacement des styles, lien et modification du texte sont des boutons à icône sans libellé visible ; leur nom reste accessible et apparaît dans une infobulle native au survol prolongé. L'équation en ligne, lorsqu'elle est disponible, figure dans le menu. Les états communs restent bleus dans chaque groupe. Le menu conserve la sélection, propose une navigation au clavier et se repositionne à l'ouverture pour rester dans la fenêtre.

Validation ciblée : 95 tests de cycle de vie et de menu examinés. Le premier lancement a passé 94 tests ; une assertion visant l'ancien élément `select` a ensuite été adaptée à la nouvelle option active et vérifiée dans une relance de sept tests, sans échec. Les six tests du menu ont été relancés après l'ajustement final de positionnement. Journaux : `icon-menu-tests.log`, `icon-menu-confirmation.log` et `icon-menu-final.log` dans `build/ListToolbarUnification`. La suite complète de 1 538 tests ci-dessus correspond à la refonte précédente ; elle n'a pas été intégralement relancée pour cette modification d'interface.

La présentation initiale sous forme de grille de pictogrammes a été corrigée après clarification : les choix structurels affichent toujours leur texte dans le menu déroulant. Les six tests WebView ont été relancés pour vérifier les libellés, les icônes inline, les états communs, le clavier et la conservation de la sélection (`build/ListToolbarUnification/text-dropdown-tests.log`).
