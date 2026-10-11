# Corrections Document — preuves ciblées

Ces preuves ne remplacent pas la nouvelle lecture intégrale finale demandée le 9 octobre 2026.

## Garde Setext après ATX

La première correction Setext `adf7eed` utilisait un oracle trop permissif : Hoedown rend `# Title\n===` comme un seul titre, en ignorant la seconde ligne. Ce résultat ne prouve pas que cette ligne appartenait au titre. La correction intermédiaire pouvait donc supprimer `===` lors d'une conversion.

Le candidat précédent doit désormais produire, seul, un paragraphe et produire avec l'underline un titre. Le test autonome `testPreviewSetextProofDoesNotConsumeUnderlineAfterATX` protège les octets voisins ; les deux parcours (underline suivante et interne) partagent cette preuve. Test vert réel dans `build/SquashedPreviewAudit/popup-queue-red-setext-green.log`. Il s'agit d'une régression de notre correction intermédiaire, pas d'un défaut attribué au code initial.

## Identité DOM des contrôles

Les IDs et attributs rédigés dans le Markdown ne sont pas une preuve d'identité des contrôles injectés. La référence privée JS `elements()` fournit panneau, style et spans possédés ; le scanner et le remplacement du body utilisent ces seules références. Les éléments détachés sont filtrés une fois, avant la marche DOM. Les propriétés globales nommées par un ID HTML doivent également exposer la fonction attendue avant son appel.

La régression WebView conserve les div/style/panneau/erreur/attribut run de l'auteur, applique du gras, conserve la sélection et vérifie un remplacement rapide par sentinelle. Elle vérifie aussi une vraie case de tâche, puis son clic et la mutation `[x]` du Markdown. Avec les flags de renderer réellement activés, ce dernier clic échoue avant les gardes Prism/MathJax : `real-fixtures-collision-red.log` ; après correction les 11 scénarios passent dans `targets-real-fixtures-green.log` (73,826 s). Les fixtures antérieures sans `rendererFlags` corrects ne sont pas retenues comme preuve de ce défaut. Le jeton assure fraîcheur/provenance, pas une frontière d'autorisation contre du JavaScript déjà exécuté dans le même contexte.

## Préfixes des blocs et texte visible

Les préfixes réellement reconnus par Hoedown sont retirés d'après la hiérarchie DOM originale (citations imbriquées, listes, titres). `2026) year` et `[x]` avec l'option tâches désactivée restent du texte. Les hashes de fermeture ATX sont reconnus par le même renderer. La sortie doit produire le bloc demandé et le même texte visible ; un marqueur littéral n'est échappé que si la première sortie ne préserve pas ce texte. Un cas non prouvé refuse toute mutation.

Retirer un titre devant `---` ou `===` ajoute la séparation nécessaire sans supprimer la ligne voisine. Les clones DOM de comparaison normalisent seulement l'espace du séparateur de checkbox généré. Les tests couvrent titres, règles voisines, literal `>`, citations imbriquées et options réelles ; les fixtures assignent `rendererFlags` avant de parser. Rouge confirmé dans `final-context-red.log` / `tasks-consumption-red.log` pour les préfixes, puis vert réel dans `targets-real-fixtures-green.log` (ne pas utiliser les anciennes assertions de tâche sans flags comme preuve).

## Restauration après conversion de plusieurs blocs

Une union de texte source recherchée telle quelle dans le remplacement ne survit pas aux préfixes insérés au milieu, ni à l'underline Setext retirée. Les bornes sont désormais transportées pendant la construction ligne par ligne, puis décalées pour l'encadré/menu dépliant et son titre. Le parcours en ligne conserve son invariant propre ; on ne réutilise pas les anciens nœuds DOM.

Rouge réel dans `native-stage-3.log` pour plusieurs paragraphes et `wrapper-restore-red.log` pour Setext + second paragraphe. Le test d'intégration vérifie la sélection entière et l'italique sans re-sélection ; le test compact vérifie callout/toggle/toggle-h2, ouvre manuellement le corps replié, puis met en gras la même sélection sans toucher le voisin. Les sorties code/math restent générées et non éditables. Les 11 scénarios finaux sont verts dans `targets-real-fixtures-green.log`. L'assertion de comparaison source du test wrapper utilise une copie de chaîne, pour ne pas comparer deux vues du même stockage mutable.

## File commune pour popup et barre d'outils

Le popup appelait directement la transaction, alors que la barre d'outils mettait les clics en attente pendant la restauration. Deux clics popup Gras puis Italique avant le nouveau rendu refusaient le second : source `**Selected**` et bouton Italique inactif. Ce défaut préexistait dans le squash, confirmé par `popup-queue-red-setext-green.log` (deux assertions réelles).

Un seul helper de continuation est appelé par les deux adaptateurs. Il vérifie forme/types, état fermé/impression, ancien token exact et whitelist de mise en forme ; le remplacement de texte et refresh ne sont jamais enqueued. Il vérifie la sélection source de l'ancien DOM puis le replay repasse par la transaction avec la sélection et le token frais. Un changement de passage annule la continuation.

Test WebView réel : popup Gras puis Italique avec parser arrière-plan temporairement suspendu, reprise et résultat `***Selected***`, même sélection et deux boutons actifs. Les requêtes avec token périmé, action replace ou valeur numérique ne mutent ni la source ni la continuation. Test vert final 5,245 s dans `queue-boundaries-green-source-headings-red.log` (les échecs voisins de ce journal concernent exclusivement le nouvel audit des commandes source, pas la queue). Relecture indépendante JS agent : aucun autre défaut confirmé du nouveau helper/replay.

## Brouillon visuel avant normalisation de sauvegarde

Le chemin direct writeToURL ajoutait le newline avant que dataOfType ne flushe le brouillon. La source normalisée ne correspondait donc plus à la preuve du draft et le save était refusé. Défaut préexistant dans le code fusionné, découvert dans la nouvelle lecture complète. Rouge réel : `source-headings-final-green-autosave-red.log`, cinq assertions du test WebView.

Le helper commun flushPreviewEditorForSaveWithError est désormais appelé avant toute mutation source ou état isSelfSaving/génération ; dataOfType partage la même erreur et synchronisation main. Un refus garde la saisie récupérable et ne crée pas de fichier. Le test réel vérifie cette frontière avec un draft périmé, puis restaure la source compatible et écrit `Changed text\n`. Vert : `pass2-final-targets-green.log`, 7 tests sans échec (2,217 s), préférences restaurées. Après ce correctif, MPDocument (6556 lignes) et Lifecycle (2687 lignes) ont tous deux été à nouveau intégralement relus, empreintes et registres dans `squashed-document-pass2.md`.
