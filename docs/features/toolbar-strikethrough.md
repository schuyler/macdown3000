# Bouton Barré dans la barre rapide

Le groupe de styles contient maintenant Gras, Italique, Souligné puis Barré. Le nouveau segment réutilise l’icône, la traduction et l’action `toggleStrikethrough:` déjà présentes. Les sélections dans la source et le visualiseur suivent donc leur pipeline existant, avec la syntaxe Markdown `~~texte~~`.

L’entrée autonome Barré reste disponible pour les personnalisations de barre déjà enregistrées. Le groupe conserve son identifiant afin que les barres personnalisées profitent également du nouveau segment. L’extension de rendu Barré conserve son réglage existant.

Le test de dispatch des groupes a été étendu au quatrième segment. La suite complète `MPToolbarControllerTests` réussit ; journal local : `/tmp/macdown-toolbar-strike-tests.log`. Cette intervention ciblée ne certifie pas un nouvel audit intégral du contrôleur.
