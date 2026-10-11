# Sélection à la souris dans l’aperçu — 10 octobre 2026

## Défaut et correction

Après un double-clic, WebKit conserve la sélection du mot au nouvel appui pour préparer un glissement du texte sélectionné. Cela donne l’impression que le mot est sélectionné immédiatement, avant le déplacement voulu. Le scénario avec sélection préalable reproduit le défaut sur `318fe85` ; le premier appui sur un paragraphe sans sélection préalable ne le reproduit pas sur cette machine.

Un clic simple sans touche modificatrice sur un passage source-prouvé efface désormais l’ancienne plage avant le traitement natif. WebKit reste responsable du placement du curseur, du glissement, du défilement et de la sélection de caractères. Aucun gestionnaire de déplacement personnalisé ni conversion HTML vers Markdown n’est ajouté.

Les double/triple clics, clics avec Shift/Command/Control/Option, clic droit, liens, contrôles, passages non mappés et édition explicite du texte gardent leur gestion existante. Le panneau reste caché pendant le maintien et s’ouvre après le relâchement d’une sélection valide.

## Contrôles

Le test physique UI observe la sélection pendant le maintien par un script local de fixture conforme à la CSP ; il ne modifie pas la sélection. Il exerce paragraphes, citations et titres : appui seul, double-clic, nouvel appui sur le mot sélectionné, glissement de quelques lettres, gras sur ces lettres et annulation exacte. Des événements DOM distincts couvrent les exceptions de boutons/modificateurs et l’édition explicite ; ils ne remplacent pas le test du geste natif.

Correction : `fdf48aa`. Sur macOS 26.6.2 / Xcode 26.2 :

- **7/7 tests natifs** du menu et de ses consommateurs réussis, dont 36 cas du nouveau test (12 gestes × paragraphes/citations/titres). [Preuve native](../audits/deep-audit/preuves/souris-native.log).
- **3/3 tests physiques UI** réussis : nouveau parcours souris sur les trois types de contenu, sélection et formats successifs dans les citations multilignes, exclusivité des sélections source/aperçu. [Preuve UI](../audits/deep-audit/preuves/souris-ui.log).
- Régression avec sélection préalable : échec avant correction, réussite après correction. L’essai initial avec script inline bloqué par la CSP n’est pas compté comme preuve du défaut. [Preuve avant correction](../audits/deep-audit/preuves/souris-red.log).
- Syntaxe JavaScript et `git diff --check` valides. Compilation native de tests pour arm64 et x86_64 ; exécution sur arm64 en Debug. Les suites complètes antérieures restent des preuves de leurs versions précédentes, sans revendication de nouvelle exécution intégrale.
- Préférences et sessions utilisateur isolées et restauration vérifiée après chaque run. Journaux intégraux et résultats `.xcresult` conservés dans `build/AuditCampaign03` ; les extraits versionnés portent leurs SHA-256. Cette correction est une revue ciblée du parcours souris, sans nouvelle certification de lecture intégrale du projet.
