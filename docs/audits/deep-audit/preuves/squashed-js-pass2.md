# Nouvelle lecture complète — lot JS et interface

Nouvelle passe demandée le 9 octobre 2026. Cette lecture repart de zéro : aucune case de validation de la première passe n’est reconduite. Référence observée : `adf7eed9dfc874490a9823e6518d732e286d044b`, avec corrections locales d’identité DOM encore non commitées. Aucun fichier applicatif ni index Git modifié pendant cette passe.

| Fichier | SHA-256 réellement relu | Plages de cette nouvelle lecture | État |
| --- | --- | --- | --- |
| `MacDown/Resources/Extensions/preview-edit.js` | `72bb762a66c365f6ea8895882fea2f560a731aa7a8eddb6308a202605bcf7cf0` | 1–292, sortie complète non tronquée | Lu et analysé ; hypothèse de commandes rapides à confirmer, gates finales en attente. |
| `MacDownUITests/MacDownUITests.swift` | `19556d94b2a70aeb7bf3a4c15fe9a7930103f95572c5c5177748aa51b736dfed` | 1–230 puis 231–452, aucune ligne manquante | Lecture et analyse auxiliaires achevées ; tests UI de cette livraison à exécuter par le parent. |

La version des interactions natives lue est `MPDocument.m`, SHA-256 `348bd793cca1fa106fc9357d953c30fb9fa276ea1abb43189b4976a08df9aa77` (empreinte identique aux deux vérifications pendant et en fin de lecture). Plages relues : 2150–2177, 2625–2660, 5385–5439, puis 5440–5469, 5469–5594, 5595–5738, 5739–5960, 5961–6020 et 6020–6090. Elles couvrent intégralement l’installation du mapping, la restauration, la validation des sélections, les transactions, la queue, les transports et les consommateurs sauvegarde/fermeture. Le fichier natif complet relève du lot Document ; ces lectures ne prétendent pas le valider intégralement.

## Invariants et branches réexaminés

1. **Identité réelle des nœuds.** Initialisation et rétention ne reposent plus sur un ID rédigé : anciennes méthodes `elements` et `destroy` typées, références privées panneau/style/erreur et tableau de spans créés. `mappedSpan` et `currentSelection` excluent les nœuds détachés. Le scanner natif exclut les références propriétaires connectées, et les sondes hors DOM ne traitent pas les attributs rédigés comme des preuves internes. Les nouvelles classes CSS sont dérivées du jeton natif UUID et affectées seulement aux éléments créés.
2. **Sélection source prouvée.** Sélection réduite/absente ou édition active refusée ; frontières éléments et texte résolues en offsets ; runs ordonnés ; caractères non mappés refusés hormis séparateurs interblocs entre blocs distincts ; texte envoyé et recalculé nativement concordant ; bornes UTF-16 et surrogates validés ; pas de run touché manquant. Les boutons ne choisissent jamais le curseur indépendant de l’éditeur source.
3. **Styles communs.** Tous les runs admissibles doivent avoir les ancêtres de style attendus pour afficher le bleu ; seuls les espaces du code disposent de l’exception contractuelle. Le type de bloc n’est actif que s’il est commun. Les blocs H5/H6 sont reconnus mais sans option correspondante dans le menu H1–H4, conforme au périmètre de ce menu. Ces indications visuelles ne remplacent pas la vérification du renderer.
4. **Cycle du panneau.** `selectionchange` temporisé, verrou souris jusqu’à `mouseup`, nettoyage lors de blur pendant déplacement, scroll/resize bornés ; aucune ouverture tant que la sélection souris est en cours. Le focus interne retient la sélection. Une erreur est rattachée à sa sélection et supprimée uniquement lorsqu’elle change ; un brouillon actif reste récupérable. La désélection réelle ferme le panneau sans bouton Fermer.
5. **Brouillon et Markdown.** Remplacement direct explicite du fragment entier ; un seul run hors code ; multiligne expliqué et refusé ; Escape restaure puis demande le rendu, Enter/blur valident ; composition IME n’est pas interceptée ; `beforeinput` de format refusé ; collage texte brut avec retours aplatis ; drop refusé. Le transport JSON encode le texte et le jeton ; le backend échappe la saisie et refuse contrôles, retours, UTF-8 invalide et trop grand texte. Save/Save As/fermeture passent par `flushPreviewEditor` ; refus conservant le brouillon et interdisant sauvegarde/fermeture.
6. **Commandes et options.** Listes de tâches, barré, code et math dépendent des préférences vérifiées aussi nativement ; valeur block autorisée explicitement ; URL validée par le moteur source ; aucune commande de couleur ni HTML ajouté. Chaque action en ligne ordinaire consomme la même transaction native ; math possède sa variation de délimiteurs et les domaines générés restent non éditables.
7. **Restauration et état périmé.** `prepareForRender` conserve sélection et verrouille ; remplacement body garde les références ; nouvel install remappe source courante et reconstruit le panneau ; `restoreSelection` exige ordre, bornes et texte normalisé concordants. Tokens/source périmés refusés. La queue native annule si nouvelle sélection ou absence de preuve ; une continuation ne réutilise pas un jeton obsolète.
8. **Cleanup.** Timers annulés, tous les listeners enregistrés retirés ; destruction conditionnelle du panneau/style propres ; variables temporaires de configuration et liste de nœuds supprimées ; aucune écriture HTML issue de saisie utilisateur dans l’éditeur Markdown.

Les helpers `listen`, `send`, `hide`, `draft`, `finish`, `commit`, `mappedSpan`, `currentSelection`, `selectionPayload`, `command`, `button`, `select`, `createPanel`, `begin`, `updateStyles`, `blockType`, `updatePanel`, `finishMouseSelection`, `showEditError`, `restoreSelection`, `normalizedSelectionText`, l’API publique et tous les listeners ont été réexaminés dans cette version. Les branches de refus et options désactivées sont incluses.

## Relecture des tests Swift

Les 13 méthodes de test et les trois fonctions de fixture (`setUpWithError`, `tearDownWithError`, `waitForEditor`) ont été relues intégralement : transferts du home isolé, lancement/arrêt, fichiers UUID temporaires supprimés, restauration du presse-papiers Find, récupération des documents, recherche source/aperçu, édition explicite et persistance, styles mélangés avec voisin lien intact et deux undo, Texte normal H1–H3 avec undo/redo, reader mode, pourcentage avec molette et préférences persistées. Les prédicats AX s’appliquent aux textViews/staticTexts appropriés ; les valeurs numériques des headings ne reçoivent pas `CONTAINS` à distance. Les contrôles à `aria-pressed` sont trouvés comme éléments AX quelconques par label. Aucun changement de tests ou affaiblissement d’assertions effectué.

## Hypothèse nouvelle P2-JS-01 — clics rapprochés du panneau

Chaîne relue : `command()` du panneau appelle le transport `handlePreviewEdit`, qui applique directement `applyPreviewEditPayload`. La queue de continuation se trouve uniquement dans `performPreviewFormattingAction`, utilisé par la barre native. Si le premier style modifie la source avant l’installation du nouveau rendu, le panneau reste présent et un second clic peut encore transporter l’ancien token ; `applyPreviewEditPayload` doit alors le refuser. La conservation du panneau/sélection rend ce scénario plausible, mais il faut le reproduire dans le vrai WebView et vérifier le contrat d’enchaînement du panneau avant de déclarer un défaut.

Scénario transmis au parent et au lot Document : sélectionner un passage, clic popup Gras puis Italique pendant l’attente du rendu ; résultat attendu si les deux commandes sont autorisées : source avec les deux styles, voisin intact, sélection restaurée, aucun refus erroné. Comparer avec le même enchaînement de barre native. **État : défaut confirmé par reproduction native, correction et gate vert en attente.**

## Seconde passe de cette nouvelle lecture

Les chaînes alternatives sont réexaminées : panneau URL contre barre native et leur traitement différent de l’attente (hypothèse ci-dessus), brouillon contre formatage, changement de passage pendant rendu, focus panneau contre vraie désélection, IDs/attributs rédigés contre références propriétaires, mapping d’espaces et séparateurs, retrait de métadonnées Setext et bornes de restauration, anciennes préférences/rendu et jeton courant. Aucun autre défaut confirmé n’est établi par cette lecture ; cela n’est pas une garantie d’absence de bugs.

La famille de noms globaux Prism/MathJax reste suivie dans le lot Document : elle n’est pas requalifiée ni déclarée corrigée ici sans les preuves de ce propriétaire. La ponctuation échappée peut rendre un fragment non littéralement mappable ; la limitation explicite des correspondances prouvées ne devient pas un bug de modification sans contre-exemple.

## Contrôles et clôture

- Nouveau contrôle exécuté pendant cette passe : `node --check MacDown/Resources/Extensions/preview-edit.js`, sortie 0.
- Lectures source/test et empreintes réalisées de nouveau ; aucun ancien résultat de suite reconduit comme validation de cette passe.
- Tests natifs/UI et build de livraison restent à exécuter et traiter par le parent dans le coffre de préférences sérialisé. Les résultats antérieurs figurent dans `squashed-js.md` comme historique uniquement.
- Statut : **lu et analysé, validation en attente**. P2-JS-01 confirmé, correction commune du pipeline native/popup et gate vert en attente ; identité DOM prête mais non commitée, gates finales requises. Aucun déploiement/push/test natif concurrent lancé.

## Confirmation P2-JS-01 et origine

Le parent a exécuté `testPreviewPopupQueuesRapidFormattingWithoutReselecting` dans le coffre sérialisé ; preuve `build/SquashedPreviewAudit/popup-queue-red-setext-green.log`, XCTest 00:51:43. Les deux seules assertions métier en échec : source réelle `**Selected** passage` au lieu de `***Selected*** passage`, puis absence du style Italique actif. La première mutation, la conservation du token ancien, le panneau et la sélection sont vérifiés avant le second clic. Le test Setext indépendant du même batch passe. Il ne s’agit ni d’un timeout de fixture ni d’une reproduction uniquement simulée : boutons JS, policyDelegate, fenêtre/focus, parseur et application du premier style sont réels. La queue du parseur est temporairement suspendue, puis reprise dans `finally`, pour garder l’intervalle source nouvelle/DOM ancien de façon déterministe.

Origine vérifiée directement dans `git show dbc6b23:MacDown/Code/Document/MPDocument.m`, fonctions `performPreviewFormattingAction` (5859–5895) et `handlePreviewEdit` (5897–5918) : le même écart existe déjà dans le code fusionné de référence, file d’attente dans le parcours natif et application directe dans le parcours popup. Ce défaut n’est donc pas introduit par les corrections de cet audit. La correction commune est propriété du lot Document ; aucune modification production faite par ce lot JS pour le masquer. Relecture de la frontière modifiée et résultat vert encore attendus.

## Relecture de la correction commune du pipeline

Version native relue après signal du propriétaire : SHA-256 `ca3fd5400d5b0bff446534efa149bcfac05be6aa6732ed6038654ff9926ec412`, `queuePendingPreviewFormattingPayload`, `performPreviewFormattingAction`, `handlePreviewEdit` (6055–6140), et replay dans `installPreviewEditor` (5622–5638). Le helper partagé valide dictionnaire, document ouvert/non printing, jeton ancien courant typé, action de formatage autorisée et value typée. La preuve de sélection est reconstruite depuis les runs de l’ancien DOM ; un changement de passage annule la continuation ; seules action/value rejoignent la queue. Au replay, la sélection restaurée est récupérée et la mutation revalide jeton/source/options sur le rendu neuf. `replace` et `refresh` ne peuvent rejoindre la queue. Aucun défaut supplémentaire confirmé par cette relecture ; gate vert avec requêtes invalides reste à consigner par le parent.

L’identité DOM a été commitée conjointement dans `b37e772`, JS inchangé SHA `72bb762…`. **Contrôle postcommit a révélé une erreur de snapshot index Lifecycle** : les fonctions Setext (`f3208f9`) et collision ont été insérées avant le premier `@end`, dans une interface, alors que les fichiers working tree testés les placent correctement. Parent et propriétaire Document avertis immédiatement. Les résultats working tree ne certifient donc pas encore ces snapshots committés ; réparation et contrôle du contenu Git requis avant livraison.


## Disposition après correction et réparation des commits

P2-JS-01 corrigé dans `e86f108` : le test de popup et les refus token/action/value passent dans `queue-boundaries-green-source-headings-red.log` (5,245 s pour ce test). Les échecs du même batch appartiennent exclusivement aux commandes source de titres, ensuite corrigées dans `ee253cc`. Le contenu JS est inchangé depuis cette lecture intégrale.

L'erreur de snapshot index, concernant uniquement la place des méthodes de tests dans les commits locaux, a été réparée avant livraison : `f3208f9` remplacé par `076d78c`, `b37e772` par `0aad66f`. Sources applicatives inchangées ; tests placés dans leur implémentation et relus entièrement par le lot Document. Les anciens identifiants ci-dessus sont historiques. Aucune certification ne repose sur leur snapshot incorrect. Les suites finales utilisent le contenu corrigé actuel.


## Validation de livraison après les lectures

Les attentes de contrôles mentionnées plus haut décrivent l'état au moment des lectures. Clôture du parent : **1 471 XCTest, 13 XCUITest, 65 contrats CLI réussis**, syntaxe JS correcte et Release universel signé localement vérifié. Aucun changement de source depuis la version finale intégralement relue. Validation dans le périmètre vérifié, commandes/empreintes/limites dans [la clôture](squashed-cloture.md) et [verification.json](squashed-verification.json).
