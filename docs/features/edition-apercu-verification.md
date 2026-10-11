# Vérification de l’édition de l’aperçu — 8 octobre 2026

Ce rapport est historique : les commits de fonctionnalité cités ont été fusionnés dans `dbc6b23`. Il ne certifie pas les corrections suivantes. La lecture actuelle et ses contrôles sont consignés dans [le suivi deep-audit](../audits/deep-audit/suivi.md).

L’ajout fournit une édition visuelle partielle, liée à des plages Markdown vérifiées, et un panneau de mise en forme sur sélection. Les options et restrictions sont décrites dans [le guide](edition-apercu.md). Le bouton « Texte normal » est livré séparément dans le commit `28bebab`, l’édition de l’aperçu dans `95b9a78`.

## Relecture et corrections

Les nouvelles méthodes de MPDocument, le script preview-edit.js, l’API d’analyse de snapshot du renderer et leurs tests ont été relus. Les consommateurs examinés comprennent le chargement/remplacement du DOM, les notifications d’édition et de préférences, la fermeture, la sauvegarde, l’annulation, les exports et l’impression.

| Risque examiné | Traitement et preuve |
| --- | --- |
| Occurrence source située dans une URL ou un attribut, plutôt que dans le texte rendu | Vérification par marqueurs temporaires dans le même pipeline de rendu ; test avec un libellé décodé dont la seule occurrence littérale est dans l’URL, et avec un attribut HTML similaire. Aucun de ces passages ne reçoit de plage d’édition. |
| Correspondances ambiguës ou requêtes périmées | Sondes prouvant la position exacte dans le DOM, jeton de génération, source immuable comparée et plages bornées. Une occurrence répétée est admissible si elle est prouvée individuellement ; les ambiguïtés, faux jetons, identifiants invalides et transactions périmées sont refusés. |
| Injection par lien ou texte saisi | URL HTTP/HTTPS/mailto seulement ; commandes de couleur/surlignage refusées ; échappement du texte brut ; contrôle des caractères et de l’encodage. Les tests refusent javascript: et les commandes de couleur et de surlignage, et préservent le sens littéral de crochets et de HTML saisi. |
| Perte de saisie au moment de sauvegarder | ⌘S applique la saisie active ; la production des données, la fermeture et les opérations nécessitant un rendu passent aussi par cette application. Un brouillon invalide reste visible pour récupération. Test de sauvegarde native et lecture du vrai fichier après ⌘S dans l’aperçu. |
| Modification des voisins ou absence d’annulation | Tests comparant le Markdown avant/après et son voisin intact, plus ⌘Z depuis l’aperçu. Tests H1–H3, ligne voisine, Unicode, sélection et annuler/rétablir pour « Texte normal ». |
| Titre dépliant doublant le marqueur d’un titre existant | Retrait du marqueur existant avant conversion ; test du Markdown et du rendu details. |
| Panneau dépassant la fenêtre | Défaut constaté sur capture réelle. Correction séparée : calcul de largeur incluant bordure et padding, largeur plafonnée et défilement interne sur petite fenêtre ; assertion native des quatre limites du panneau. |
| Contrôles d’édition exportés | Installation uniquement dans le DOM de l’aperçu, après publication HTML ; le HTML exporté ne contient pas le panneau. Le CSS masque le panneau à l’impression. |

L’analyse de snapshot appelle le pipeline de parsing existant sans publier le résultat : elle ne remplace ni le jeton, ni le HTML, ni les ressources du renderer vivant. L’édition passe par NSTextView et son mécanisme d’annulation natif. Aucun pipeline HTML vers Markdown n’a été ajouté.

## Tests exécutés

Sur macOS 26.6.2, Apple Silicon, Xcode 26.2 : **1 450 XCTest et 12 XCUITest sans échec dans les suites complètes initiales**, avant la correction Markdown uniquement. Les reprises ciblées couvrent ensuite la restauration des préférences de test, les limites du panneau et le parcours de sélection à la souris. Elles complètent ces suites ; elles ne sont pas comptées comme de nouveaux tests distincts.

Le test natif d’intégration charge un véritable WebView. Il contrôle le panneau, les conversions H4/liste/tâches/citation/encadré/dépliant, le gras, le soulignement, le retrait des styles et le refus des commandes de couleur et de surlignage ; il vérifie le Markdown, le rendu et le voisin préservé. Les options d’équations et les autres niveaux de titre partagent les opérations contrôlées, mais n’ont pas chacune un parcours XCUITest individuel.

Le test d’interface modifie le texte par double-clic, sauvegarde avant Entrée, lit le fichier sur disque, annule depuis l’aperçu, sélectionne à la souris, ouvre le panneau, applique Gras et conserve le lien voisin. Les captures ne contiennent que le document de test.

Les tests utilisent un coffre privé réversible pour les préférences, caches, état restauré et fichiers de support de l’application. Chaque exécution réussie confirme la restauration et la vérification des préférences. Les journaux bruts restent dans build/ReaderFeatures ; leurs empreintes et celles du code sont conservées dans [verification.json](edition-apercu-verification.json).

## Correction Markdown uniquement

Le signalement `t**est avec t**est` a été reproduit avec l’option d’emphase à l’intérieur des mots désactivée. Le nouveau test échouait avant correction. Les espaces finaux dans une sélection provoquaient également l’affichage des marqueurs.

La correction du HTML est isolée dans `c2daa93` : soulignement `_texte_` avec l’extension de rendu correspondante, suppression des commandes de couleur et de surlignage, échappement Markdown du texte saisi et retrait explicite possible des anciennes balises de style. La correction des sélections partielles est livrée séparément : espaces exclus des marqueurs, activation de l’option d’emphase à l’intérieur des mots lorsque nécessaire et vérification du HTML produit par le même parseur avant de modifier la source. Les préférences requises sont restaurées si la commande est refusée.

La validation compte les éléments de style dont le contenu correspond à la sélection, avant/après la modification proposée. L’analyse du HTML généré interdit le chargement d’entités externes. Ce HTML sert uniquement à vérifier le rendu ; il n’est jamais écrit dans le document Markdown. Le refus conserve l’aperçu et affiche une explication. L’option d’emphase activée par une commande est une préférence globale de rendu ; les documents déjà ouverts peuvent donc changer de rendu.

Après correction : **1 451 tests natifs sans échec**, dont le nouveau test des sélections intramots, des espaces et du refus de sélections incompatibles. Le test d’intégration dans un vrai WebView sélectionne `est avec t`, applique Gras, retrouve le fragment rendu, applique Souligné, puis vérifie `strong u`, le texte visible `test avec test` sans marqueurs et la source exacte `t**_est avec t_**est` sans HTML.

Le parcours XCUITest ciblé passe également : modification directe, sauvegarde réelle, annulation, sélection à la souris, Gras, nouvelle sélection dans le fragment rendu, Souligné, absence de marqueurs dans les éléments de texte accessibles et absence de balises de style dans la source. La capture du guide provient de cette exécution. Un premier contrôle d’accessibilité utilisait `CONTAINS` sur des valeurs de titres numériques ; il a été remplacé par une comparaison des valeurs de texte typées pour éviter une exception dans XCTAutomationSupport.

## Correction des sélections et de la barre d’outils

Trois corrections distinctes répondent au nouveau signalement :

- `382657f` conserve la sélection native d’un mot au double-clic. L’édition du passage devient une action explicite « Modifier le texte » ; elle ne se déclenche plus pendant une sélection destinée à la mise en forme.
- `d7efb2f` dirige les commandes de style et de titre de la barre d’outils vers la sélection du visualiseur lorsque celui-ci a le focus. Elles utilisent le même contrôle de plage, de source, de jeton et de rendu que le panneau flottant. Une sélection refusée ne provoque aucun repli sur le curseur de l’éditeur source.
- `b048280` résout les bornes de sélection placées par WebKit sur des éléments, notamment les titres. Le panneau et les boutons natifs utilisent cette même résolution. Le texte sélectionné doit correspondre exactement à un seul passage source vérifié ; les sélections ambiguës restent refusées.

Le test d’intégration charge un vrai WebView dans une fenêtre native. Pour H1 à H6, il sélectionne le contenu du titre avec des bornes d’éléments, contrôle l’ouverture du panneau, place le curseur source en fin de fichier puis appelle les commandes natives de gras, italique, soulignement et barré. Le titre rendu contient le style attendu et le paragraphe voisin reste inchangé. Une sélection repliée du visualiseur ne modifie pas le document. Le double-clic ne crée pas de passage contenteditable ; « Modifier le texte » applique toujours la saisie et la sauvegarde.

Le parcours XCUITest vérifie le double-clic réel, l’action explicite d’édition, la sauvegarde, l’annulation et le gras/soulignement par clic sur la barre d’outils après sélection dans le visualiseur. Les éléments de texte rendus ne contiennent pas les marqueurs de style, et le Markdown ne contient pas de balises de soulignement ou de couleur.

Après ces trois corrections : **1 451 tests natifs sans échec dans la suite complète et deux parcours XCUITest ciblés sans échec**. Le second parcours contrôle « Texte normal » depuis l’éditeur source, H1 à H3, les lignes voisines et l’annulation/rétablissement. Ces exécutions restaurent et vérifient les préférences via le coffre privé. Les 12 XCUITest de la suite complète initiale n’ont pas été réexécutés pour ces dernières corrections.

## Maintien de la sélection pendant les réglages successifs

La perte de sélection venait du remplacement du DOM après chaque modification. Le document conserve désormais la plage source du passage sélectionné et la retrouve dans le rendu suivant. Le script rétablit la sélection et le panneau sur les nouveaux nœuds, avec le nouveau jeton. Les clics natifs rapprochés attendent ce rendu ; changer de sélection annule la continuation.

Lorsqu’un style isole un mot présent plusieurs fois, sa correspondance est vérifiée par une sonde unique sur sa plage source et une comparaison ordonnée de tous les nœuds de texte admissibles et de leurs éléments parents. Seul le nœud prouvé reçoit cette correspondance supplémentaire. Les autres ambiguïtés restent refusées. Une modification de la source ou une impossibilité de vérifier la nouvelle plage annule la restauration et les commandes en attente.

Le test a également révélé que la commande Italique pouvait traiter une étoile du marqueur Gras comme un style à retirer. Une correction distincte reconnaît les marqueurs doubles et recherche le style demandé parmi les styles entourant la sélection. Retirer un style conserve les autres.

Le test natif enchaîne les commandes sans nouvelle sélection, y compris des appels immédiats Gras → Italique → Souligné sur la première occurrence de `test avec test`, puis H1. Il vérifie les styles rendus, la sélection `test`, la seconde occurrence intacte et le paragraphe voisin. Un autre scénario sélectionne la seconde occurrence pendant le rendu : la commande en attente n’altère aucun des deux passages. Les tests de parsing vérifient aussi l’ajout/retrait d’italique sur du gras et le retrait du soulignement autour d’un passage gras.

Le parcours XCUITest enchaîne les boutons natifs Gras → Souligner → Italique sans redéfinir la sélection. Il contrôle la source et l’absence de marqueurs dans le texte rendu.

Résultat après ces corrections : **1 451 tests natifs sans échec dans la suite complète et un parcours XCUITest ciblé sans échec**. La correction des styles imbriqués est isolée dans `31c9e19` ; le maintien et la vérification de la sélection sont livrés séparément. Les autres parcours d’interface n’ont pas été réexécutés pour ce dernier changement.

## Stabilité du panneau pendant la mise en forme

Le clic de mise en forme ne masque plus le panneau. Pendant un remplacement du corps HTML, le même élément de panneau et sa feuille de style sont conservés ; leurs anciens écouteurs sont libérés et les commandes sont réinstallées avec le nouveau jeton. La vérification de sélection reprend immédiatement après la restauration, sans attendre le délai des sélections utilisateur. Le panneau se ferme si la sélection devient vide ou inadmissible.

Le test WebView clique sur Gras puis Souligné dans le panneau. Il contrôle également l’identité du panneau et son affichage à chaque frame pendant une conversion en H1 : aucune frame masquée. Retirer la sélection ferme effectivement le panneau.

## Indication des styles actifs

Les boutons Gras, Italique, Souligné, Barré et Lien vérifient les ancêtres du passage sélectionné dans le rendu. Leur état est exposé par `aria-pressed` et leur texte actif utilise exactement `#2784DE`. Le sélecteur de blocs affiche le type reconnu : paragraphe, titre, liste, tâches, citation, encadré ou dépliant. Cette indication ne modifie pas le Markdown.

Le test WebView contrôle les trois boutons simultanément actifs sur un passage gras/italique/souligné, leur couleur calculée `rgb(39, 132, 222)`, le titre H1 actif et le bouton Barré inactif. Les sélections de fragments non admissibles gardent les limites existantes.

Après ces changements : **1 451 tests natifs et un parcours XCUITest ciblé sans échec**. Le parcours à la souris conserve la sauvegarde, l’annulation, la sélection et l’enchaînement des styles sans nouvelle sélection. Sa recherche des commandes utilise leur libellé pour couvrir les contrôles à état exposés par `aria-pressed` ; la première recherche limitée aux boutons simples échouait. Les autres parcours d’interface n’ont pas été relancés. Les préférences ont été restaurées et vérifiées après chaque exécution.

## Sélections mixtes et fin du geste de sélection

Le commit `33dd544` masque le panneau pendant que le bouton principal de la souris est enfoncé et le calcule après relâchement. Le test WebView maintient le geste pendant 250 ms, vérifie le panneau masqué, puis vérifie son ouverture à mouseup.

La résolution accepte maintenant une suite ordonnée de fragments dont les plages source sont indépendamment prouvées. Elle vérifie le texte sélectionné, les bornes UTF-16, les fragments manquants, leur ordre et le jeton. Les espaces entre fragments sont reliés à leurs voisins prouvés. Les occurrences répétées sont testées sur la totalité du DOM ordonné, avec une limite de 64 occurrences par texte et 128 sondes supplémentaires par rendu.

Le panneau calcule l’intersection des styles des fragments. Une sélection `st mo` dans `test **mot** selection` ouvre le panneau avec Gras inactif ; Gras produit `te**st mot** selection`, conserve la sélection `st mo` et affiche Gras actif. La réécriture préserve les styles extérieurs à la sélection, les autres styles présents, les destinations des liens et les blocs voisins. Les styles en ligne, le code, les liens et le retrait des styles passent par une seule transaction source. Le HTML produit par le parseur sert de preuve de texte, de style et de structure pour tout le document candidat ; aucun HTML n’est créé dans la source.

La capture du guide provient du nouveau parcours XCUITest : sélection initialement mixte, puis Gras → Italique, deux boutons bleus et sélection encore visible. La source sauvegardée est comparée exactement, puis deux annulations restaurent successivement le gras seul et le document initial.

Les tests natifs comparent dix résultats Markdown exacts, dont des sélections à gauche et à droite d’un marqueur, les quatre styles, les styles imbriqués, les espaces, un emoji et le retrait partiel d’un style. Les requêtes incomplètes, désordonnées, hors limites ou portant un faux texte sont refusées. Le vrai WebView vérifie aussi des espaces répétés entre mots gras et une sélection entre paragraphes : le gras s’impose à tous les fragments, puis se retire au clic suivant, sans perdre la sélection.

Le banc isolé compile la transaction avec le véritable Hoedown : 46 scénarios de sélections, liens, code, Unicode et retours à la ligne, plus un refus de paragraphe volumineux avant tout appel au moteur de rendu, ainsi que deux assertions supplémentaires de source exacte. La correspondance unique des caractères et le nombre de candidats sont bornés pour éviter une explosion de coût sur une source ambiguë.

| Point | État et preuve |
| --- | --- |
| Panneau affiché pendant le geste | Corrigé : test de maintien souris puis relâchement dans WebView. |
| Sélection mélangeant des styles refusée | Corrigé : sélection multi-fragments prouvée, test natif et glisser réel dans XCUITest. |
| Styles actifs calculés sur un seul fragment | Corrigé : intersection sur tous les fragments ; assertions avant/après Gras, puis capture Gras + Italique. |
| Marqueurs à déplacer aux limites de sélection | Corrigé : source exacte sur dix scénarios, vérification sémantique du document entier et voisins intacts. |
| Perte de sélection après réécriture | Corrigé : restauration de plusieurs fragments et enchaînement de styles sans nouvelle sélection. |
| Multiplication des sondes sur texte répété | Bornée : plafond par texte et par rendu ; les occurrences sans preuve restent non modifiables. |


Résultat final : **1 452 tests natifs sans échec dans la suite complète, deux parcours XCUITest ciblés sans échec, 47 cas Hoedown et deux assertions de source supplémentaires sans échec**. Les autres parcours XCUITest n’ont pas été relancés. Le premier passage complet avait un échec indépendant sur le nombre de notifications de zoom ; le passage final réussit ce même test sans modification du code de zoom ni de son assertion. Les premières assertions d’interface ont été adaptées à une imbrication Markdown équivalente et aux valeurs de texte exposées par WebKit. Les sources exactes, l’annulation et la préservation des voisins restent contrôlées. Tous les coffres de test ont restauré et vérifié les préférences.

La dernière protection de taille intervient avant le rendu et l’allocation des styles, au lieu d’attendre la recherche de provenance. Après cet ajout, le test natif des dix sources mixtes exactes et les 47 contrats Hoedown repassent. Les suites complètes et les deux parcours d’interface ci-dessus ont été exécutés avant cet ajout isolé ; le code des événements et du panneau n’a pas changé.

## Limites et livraison

Les transformations de texte et les structures non vérifiées peuvent exiger l’éditeur source. Les sélections mixtes et les occurrences répétées dont la plage est prouvée sont prises en charge. Les passages sur plusieurs lignes source ne se modifient pas directement. Les documents dépassant 2 000 nœuds admissibles conservent leur lecture et leur édition source. Il n’y a pas de pages, sous-pages, commentaires, IA ou colonnes Notion dans cette version.

La compilation locale utilise Release universel arm64/x86_64 et une signature ad hoc. La preuve de compilation et d’installation locale est consignée séparément dans build/ReaderFeatures/preview-local-install.json après contrôle de la signature et comparaison du bundle. Cette vérification locale ne constitue pas une signature Developer ID ou une notarisation de distribution.
