# Commits campagne03

Un commit distinct par correction confirmée. Vérifications globales encore en cours.

| Finding | Commit | Correction | Preuve |
| --- | --- | --- | --- |
| B03-01 | `94de1a9` | Reprendre la publication d’un DMG déjà agrafé après échec notes/publication ; conserver UUID. | [build](preuves/campagne03-build.md), fixture reprise rouge/verte |
| D03-01 | `4d9966c` | Drainer stdout du processus Homebrew avant d’attendre sa terminaison. | [root](preuves/campagne03-root.md), fixture1MiB et 4XCTest |
| B03-02 | `ef1aa63` | Récupérer une paire DMG/checksum interrompue avec hashes persistés avant upload ; refus des octets/provenances inconnus. | [build](preuves/campagne03-build.md), fixtures partial upload/published |
| D03-02 | `1122e1d` | Unifier trois suppressions automatiques sur insertText pour notifier et respecter les délégués. | [root](preuves/campagne03-root.md), six cas rouges et 12contrats AppKit verts, native1437 |
| U03-01 | `43c2781` | Décrire le zoom par taille de police éditeur dans zh-Hant. | [UI](preuves/campagne03-ui.md), binding et vrai bundle rouge/vert |
| U03-02 | `d3b4712` | Corriger le terme islandais Superscript selon aide officielle LibreOffice. | [UI](preuves/campagne03-ui.md), binding et vrai bundle rouge/vert |
| U03-03 | `c0cd3a1` | Recalculer la hauteur naturelle avant l’ajout du défilement après fin, sans accumulation du padding. | [UI](preuves/campagne03-ui.md), viewport attaché rouge/vert, 30 répétitions et long/court/disable/re-enable |
