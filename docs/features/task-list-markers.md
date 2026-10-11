# Marqueurs des listes de tâches — 9 octobre 2026

Défaut confirmé : les tâches `- [ ] texte` produisaient à la fois une puce de liste et une case à cocher. Les tâches ordonnées conservaient également un numéro. La classe `task-list-item` était bien produite, mais aucune règle commune ne neutralisait son marqueur.

Correction : le style partagé `li.task-list-item { list-style-type: none !important; }` est incorporé dans le visualiseur, les exports HTML avec ou sans thème et Quick Look. La case remplace le marqueur de liste ; les listes ordinaires, y compris imbriquées dans une tâche, conservent leurs puces et numéros. La source Markdown, les états cochés et le pont de clic ne changent pas.

Validation : le test dans une vraie WebView reprend les trois tâches signalées, ajoute une tâche cochée, une liste ordinaire imbriquée et une liste numérotée mixte, avec les styles GitHub2 et GitHub Tomorrow. Avant correction, les marqueurs calculés étaient `disc` et `decimal` au lieu de `none` : deux assertions métier en échec. Le premier montage de test avait également une hypothèse incorrecte de parent direct des cases dans une liste lâche ; elle a été corrigée pour compter les cases réelles. Un premier essai de compilation avait utilisé une méthode de préférences non déclarée ; il ne constitue pas une preuve métier.

Après correction : **148 tests, zéro échec** — suites `MPMarkdownRenderingTests` (82) et `MPQuickLookRendererTests` (66). Les tests ajoutés vérifient aussi le style structurel des exports avec/sans thème et sa présence dans le HTML Quick Look. Les préférences/session ont été restaurées et vérifiées.

Commande : `python3 /tmp/macdown-campaign03-xctest-vault.py --execute --timeout 900 -- xcodebuild test -workspace 'MacDown 3000.xcworkspace' -scheme MacDown -derivedDataPath build/AuditCampaign03 -destination 'platform=macOS,arch=arm64' 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- -only-testing:MacDownTests/MPMarkdownRenderingTests -only-testing:MacDownTests/MPQuickLookRendererTests`.

Journaux locaux : `build/TaskListMarkerFix/red-business.log` et `build/TaskListMarkerFix/green.log`. Résultat final : `build/AuditCampaign03/Logs/Test/Test-MacDown-2026.10.09_12-20-33-+0200.xcresult`. Le visualiseur est vérifié dans une vraie WebView ; Quick Look est vérifié via le renderer réel, sans nouvelle certification visuelle du panneau Finder.
